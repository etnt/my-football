import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import '../../providers/app_providers.dart';
import 'match_reminder.dart';
import 'reminder_notification_service.dart';
import 'reminder_store.dart';

final reminderStoreProvider = Provider<ReminderStore>((ref) {
  return ReminderStore(ref.watch(sharedPreferencesProvider));
});

final reminderNotificationServiceProvider = Provider<ReminderNotificationService>((
  ref,
) {
  return ReminderNotificationService();
});

/// All saved reminders, loaded once and updated after every change.
final remindersProvider =
    AsyncNotifierProvider<RemindersNotifier, List<MatchReminder>>(
      RemindersNotifier.new,
    );

class RemindersNotifier extends AsyncNotifier<List<MatchReminder>> {
  @override
  Future<List<MatchReminder>> build() {
    return ref.watch(reminderStoreProvider).load();
  }

  /// Persists the reminder for [fixture]; `null` lead minutes means "Off".
  ///
  /// Returns the resulting list so callers can react without re-reading.
  Future<List<MatchReminder>> setLead(Fixture fixture, int? leadMinutes) async {
    final store = ref.watch(reminderStoreProvider);
    if (leadMinutes == null) {
      await store.remove(fixture.id);
    } else {
      await store.upsert(
        MatchReminder(
          fixtureId: fixture.id,
          kickoffUtc: fixture.dateUtc,
          homeName: fixture.homeName,
          awayName: fixture.awayName,
          leadMinutes: leadMinutes,
        ),
      );
    }
    final all = await store.load();
    state = AsyncData(all);
    return all;
  }
}
