import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/football_api_client.dart';
import '../../models/league.dart';
import '../../providers/app_providers.dart';
import '../standings/standings_providers.dart';
import 'league_catalog_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

/// Outcome of checking a key against the standings endpoint.
enum _KeyStatus { premium, limited, free, invalid }

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _prefilled = false;
  bool _validating = false;
  _KeyStatus? _status;

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
        const SnackBar(content: Text('Premium key saved.')),
      );
    }
  }

  Future<void> _clear() async {
    await ref.read(apiKeyProvider.notifier).clear();
    _controller.clear();
    setState(() => _status = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reverted to the free key.')),
      );
    }
  }

  /// Probes the standings endpoint: a Premium key returns the full table
  /// (>5 rows), the free key is capped at 5, and a bad key errors out.
  Future<void> _validate() async {
    final key = _controller.text.trim();
    setState(() {
      _validating = true;
      _status = null;
    });

    final client = FootballApiClient(apiKey: key.isEmpty ? null : key);
    _KeyStatus result;
    try {
      final rows = await client.getStandings(
        leagueId: 4328,
        season: apiSeason(2025),
      );
      if (key.isEmpty) {
        result = _KeyStatus.free;
      } else if (rows.length > 5) {
        result = _KeyStatus.premium;
      } else {
        result = _KeyStatus.limited;
      }
    } catch (_) {
      result = _KeyStatus.invalid;
    } finally {
      client.close();
    }

    if (mounted) {
      setState(() {
        _validating = false;
        _status = result;
      });
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
    final isPremium = ref.watch(isPremiumProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _FollowedLeaguesSection(),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text('TheSportsDB Premium key',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              _ModeChip(isPremium: isPremium),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "By default the app uses TheSportsDB's free test key, which fully "
            'supports league tables but limits fixtures to the first few '
            'matches of a season.\n\n'
            'Optionally add a Premium key (from thesportsdb.com) to unlock full '
            'schedules. It is stored securely on this device only.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Premium API key (optional)',
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
                label: const Text('Use free key'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _validating ? null : _validate,
            icon: _validating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_outlined),
            label: Text(_validating ? 'Checking…' : 'Validate key'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            _StatusBanner(status: _status!),
          ],
        ],
      ),
    );
  }
}

/// Small pill showing whether the app is currently in Premium or Free mode.
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.isPremium});

  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, label) = isPremium
        ? (scheme.primaryContainer, scheme.onPrimaryContainer, 'Premium')
        : (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, 'Free');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

/// Result of a key validation probe.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final _KeyStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color, String text) = switch (status) {
      _KeyStatus.premium => (
          Icons.check_circle,
          scheme.primary,
          'Premium active — full tables, fixtures and live scores unlocked.',
        ),
      _KeyStatus.free => (
          Icons.info_outline,
          scheme.outline,
          'Free key in use — tables are limited to 5 rows.',
        ),
      _KeyStatus.limited => (
          Icons.warning_amber,
          scheme.tertiary,
          'Key works but returned a limited table. It may not be a Premium key.',
        ),
      _KeyStatus.invalid => (
          Icons.error_outline,
          scheme.error,
          'That key was rejected. Check it and try again.',
        ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color)),
        ),
      ],
    );
  }
}

/// Lets the user browse TheSportsDB's catalogue by country and tick the
/// leagues they want to follow. Followed leagues appear in the app's top
/// dropdown and are persisted across launches.
class _FollowedLeaguesSection extends ConsumerStatefulWidget {
  const _FollowedLeaguesSection();

  @override
  ConsumerState<_FollowedLeaguesSection> createState() =>
      _FollowedLeaguesSectionState();
}

class _FollowedLeaguesSectionState
    extends ConsumerState<_FollowedLeaguesSection> {
  String? _country;

  @override
  Widget build(BuildContext context) {
    final followed = ref.watch(followedLeaguesProvider);
    final countriesAsync = ref.watch(countriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Followed leagues',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Pick a country, then tick the leagues you want to follow. They '
          'appear in the dropdown at the top of the app. At least one league '
          'must stay followed.',
        ),
        const SizedBox(height: 12),
        if (followed.isEmpty)
          const Text('No leagues followed yet.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final league in followed)
                InputChip(
                  label: Text(league.country == null
                      ? league.name
                      : '${league.name} · ${league.country}'),
                  onDeleted: followed.length == 1
                      ? null
                      : () => ref
                          .read(followedLeaguesProvider.notifier)
                          .toggle(league),
                ),
            ],
          ),
        const SizedBox(height: 16),
        countriesAsync.when(
          data: (countries) => DropdownMenu<String>(
            initialSelection: _country,
            enableFilter: true,
            requestFocusOnTap: true,
            label: const Text('Country'),
            expandedInsets: EdgeInsets.zero,
            menuHeight: 320,
            dropdownMenuEntries: [
              for (final c in countries) DropdownMenuEntry(value: c, label: c),
            ],
            onSelected: (c) => setState(() => _country = c),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
          error: (_, _) => _CatalogError(
            message: 'Could not load countries.',
            onRetry: () => ref.invalidate(countriesProvider),
          ),
        ),
        const SizedBox(height: 8),
        if (_country != null) _LeaguesForCountry(country: _country!),
      ],
    );
  }
}

/// The soccer leagues for a country, each with a follow checkbox.
class _LeaguesForCountry extends ConsumerWidget {
  const _LeaguesForCountry({required this.country});

  final String country;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaguesAsync = ref.watch(leaguesByCountryProvider(country));
    final followed = ref.watch(followedLeaguesProvider);

    return leaguesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _CatalogError(
        message: 'Could not load leagues for $country.',
        onRetry: () => ref.invalidate(leaguesByCountryProvider(country)),
      ),
      data: (leagues) {
        if (leagues.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No soccer leagues found for $country.'),
          );
        }
        return Column(
          children: [
            for (final league in leagues)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(league.name),
                value: followed.any((l) => l.id == league.id),
                onChanged: (_) {
                  final isLastFollowed = followed.length == 1 &&
                      followed.any((l) => l.id == league.id);
                  // Keep at least one league followed.
                  if (isLastFollowed) return;
                  ref.read(followedLeaguesProvider.notifier).toggle(league);
                },
              ),
          ],
        );
      },
    );
  }
}

/// Inline error with a retry button for catalogue loads.
class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.error_outline, color: scheme.error, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.error)),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

