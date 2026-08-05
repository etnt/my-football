import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../models/account_status.dart';
import '../../providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _checking = false;
  AccountStatus? _status;
  String? _statusError;
  bool _prefilled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    await ref.read(apiKeyProvider.notifier).setKey(key);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key saved.')),
      );
    }
  }

  Future<void> _clear() async {
    await ref.read(apiKeyProvider.notifier).clear();
    _controller.clear();
    setState(() {
      _status = null;
      _statusError = null;
    });
  }

  Future<void> _checkStatus() async {
    setState(() {
      _checking = true;
      _status = null;
      _statusError = null;
    });
    try {
      final status = await ref.read(footballApiClientProvider).getStatus();
      setState(() => _status = status);
    } on ApiException catch (e) {
      setState(() => _statusError = e.message);
    } catch (e) {
      setState(() => _statusError = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyState = ref.watch(apiKeyProvider);
    // Prefill the field once with the stored key (masked by the obscure toggle).
    final storedKey = keyState.valueOrNull;
    if (!_prefilled && storedKey != null) {
      _controller.text = storedKey;
      _prefilled = true;
    }
    final hasKey = (storedKey ?? '').isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('API-Football key',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Get a free key at api-football.com. It is stored securely on this '
            'device only.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: hasKey ? _clear : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear'),
              ),
            ],
          ),
          const Divider(height: 32),
          Text('Account status',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Checks your plan and how many of today\'s requests are left. '
            'This uses one API request.',
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _checking || !hasKey ? null : _checkStatus,
            icon: _checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: const Text('Check account status'),
          ),
          const SizedBox(height: 16),
          if (_statusError != null)
            Text(
              _statusError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_status != null) _StatusCard(status: _status!),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final AccountStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Plan', status.plan),
            _row('Active', status.active ? 'Yes' : 'No'),
            _row('Used today', '${status.requestsToday}/${status.dailyLimit}'),
            _row('Remaining today', '${status.remainingToday}'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
