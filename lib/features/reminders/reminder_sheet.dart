import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import 'match_reminder.dart';
import 'reminder_store.dart';
import 'reminders_providers.dart';

/// Opens the reminder configuration sheet for [fixture].
///
/// The sheet pre-selects the stored reminder, defaulting to 15 minutes before
/// kick-off, and offers Off / 15 / 30 / 60 / 120 minutes. Saving persists the
/// choice, schedules (or cancels) the OS notification, and confirms with a
/// snackbar.
Future<void> showReminderSheet(
  BuildContext context,
  WidgetRef ref,
  Fixture fixture,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ReminderSheet(fixture: fixture),
  );
}

class _ReminderSheet extends ConsumerStatefulWidget {
  const _ReminderSheet({required this.fixture});

  final Fixture fixture;

  @override
  ConsumerState<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends ConsumerState<_ReminderSheet> {
  /// `null` means Off.
  int? _lead;
  bool _userAdjusted = false;

  @override
  void initState() {
    super.initState();
    // Optimistic default while the stored list loads; _loadStored() applies
    // the persisted choice once available.
    _lead = MatchReminder.defaultLeadMinutes;
    _loadStored();
  }

  Future<void> _loadStored() async {
    final reminders = await ref.read(remindersProvider.future);
    if (!mounted || _userAdjusted) return;
    setState(() {
      _lead = ReminderStore.forFixture(reminders, widget.fixture.id)
              ?.leadMinutes ??
          MatchReminder.defaultLeadMinutes;
    });
  }

  void _select(int? lead) {
    _userAdjusted = true;
    setState(() => _lead = lead);
  }

  Future<void> _save() async {
    // Capture these before popping: the sheet's context dies with the route.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final lead = _lead;
    final fixture = widget.fixture;

    await ref.read(remindersProvider.notifier).setLead(fixture, lead);
    final service = ref.read(reminderNotificationServiceProvider);

    if (lead == null) {
      await service.cancel(fixture.id);
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Reminder off')),
      );
      return;
    }

    // Persist and schedule even if the permission prompt fails (TASK-015):
    // the choice survives restarts; the notification just stays silent until
    // notifications are enabled in system settings.
    final allowed = await service.ensureReady();
    await service.schedule(
      MatchReminder(
        fixtureId: fixture.id,
        kickoffUtc: fixture.dateUtc,
        homeName: fixture.homeName,
        awayName: fixture.awayName,
        leadMinutes: lead,
      ),
    );
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          allowed
              ? 'Reminder set: ${_leadLabel(lead)} before kick-off'
              : 'Reminder saved, but notifications are turned off in system '
                  'settings, so it will stay silent.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fixture = widget.fixture;
    final kickoff = fixture.dateUtc.toLocal();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${fixture.homeName} vs ${fixture.awayName}',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Text(
              'Kick-off ${_formatDate(kickoff)} at ${_formatTime(kickoff)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // Scrollable so the sheet stays usable on small screens.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReminderTile(
                      label: 'Off',
                      selected: _lead == null,
                      onTap: () => _select(null),
                    ),
                    for (final minutes in MatchReminder.allowedLeadMinutes)
                      _ReminderTile(
                        label: _leadLabel(minutes),
                        selected: _lead == minutes,
                        onTap: () => _select(minutes),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable lead-time row styled like a radio option.
class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(label),
      onTap: onTap,
    );
  }
}

String _leadLabel(int minutes) => '$minutes min before';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String _formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
