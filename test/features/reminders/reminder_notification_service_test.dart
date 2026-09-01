import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/reminders/match_reminder.dart';
import 'package:my_football/features/reminders/reminder_notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// Records scheduled/cancelled notifications instead of touching the OS.
///
/// `implements` (not `extends`) because the plugin class only exposes a
/// factory constructor; unimplemented members fall through to [noSuchMethod].
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final scheduled = <int, DateTime>{};
  final cancelled = <int>[];

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduled[id] = scheduledDate;
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelled.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

MatchReminder _reminder({required DateTime kickoffUtc, int lead = 15}) {
  return MatchReminder(
    fixtureId: 42,
    kickoffUtc: kickoffUtc,
    homeName: 'Arsenal',
    awayName: 'Chelsea',
    leadMinutes: lead,
  );
}

void main() {
  test('notificationId namespaces reminders away from other notifications', () {
    expect(ReminderNotificationService.notificationId(42), 100042);
  });

  test('schedule fires at kick-off minus the lead time with the derived id',
      () async {
    final plugin = _FakePlugin();
    final service = ReminderNotificationService(plugin: plugin);
    final kickoff = DateTime.now().toUtc().add(const Duration(hours: 2));

    await service.schedule(_reminder(kickoffUtc: kickoff, lead: 15));

    expect(plugin.scheduled.keys, [100042]);
    final scheduledAt = plugin.scheduled[100042]!;
    expect(
      scheduledAt.toUtc().isAtSameMomentAs(
            kickoff.subtract(const Duration(minutes: 15)),
          ),
      isTrue,
    );
  });

  test('schedule is a no-op when the fire time is already in the past',
      () async {
    final plugin = _FakePlugin();
    final service = ReminderNotificationService(plugin: plugin);
    final kickoff = DateTime.now().toUtc().add(const Duration(minutes: 5));

    // Lead of 15 minutes means the notification would fire in the past.
    await service.schedule(_reminder(kickoffUtc: kickoff, lead: 15));

    expect(plugin.scheduled, isEmpty);
  });

  test('cancel targets the derived notification id', () async {
    final plugin = _FakePlugin();
    final service = ReminderNotificationService(plugin: plugin);

    await service.cancel(42);

    expect(plugin.cancelled, [100042]);
  });
}
