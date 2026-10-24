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

  final android = _FakeAndroidPlugin();
  Object? initializeError;

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() {
    if (T == AndroidFlutterLocalNotificationsPlugin) {
      return android as T;
    }
    return null;
  }

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback?
        onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    if (initializeError != null) throw initializeError!;
    return true;
  }

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

/// The Android side of the plugin fake: permission probes and channel state.
///
/// `implements` (not `extends`) so unimplemented members fall through to
/// [noSuchMethod].
class _FakeAndroidPlugin implements AndroidFlutterLocalNotificationsPlugin {
  /// Results for the permission probes; `null` means the method is not
  /// stubbed and falls through to [noSuchMethod].
  ///
  /// [areNotificationsEnabledResults] is consumed one entry per call; the
  /// last entry repeats, so `[false, true]` models a prompt that granted
  /// permission after an initial "off" reading.
  final areNotificationsEnabledResults = <bool?>[];
  bool? requestNotificationsPermissionResult;
  List<AndroidNotificationChannel>? channels;
  final createdChannels = <AndroidNotificationChannel>[];
  int areNotificationsEnabledCalls = 0;
  int requestPermissionCalls = 0;

  @override
  Future<bool?> areNotificationsEnabled() async {
    areNotificationsEnabledCalls++;
    if (areNotificationsEnabledResults.isEmpty) return null;
    final i = areNotificationsEnabledCalls - 1;
    return areNotificationsEnabledResults[
        i >= areNotificationsEnabledResults.length
            ? areNotificationsEnabledResults.length - 1
            : i];
  }

  @override
  Future<bool?> requestNotificationsPermission() async {
    requestPermissionCalls++;
    return requestNotificationsPermissionResult;
  }

  @override
  Future<void> createNotificationChannel(
    AndroidNotificationChannel notificationChannel,
  ) async {
    createdChannels.add(notificationChannel);
  }

  @override
  Future<List<AndroidNotificationChannel>?> getNotificationChannels() async =>
      channels;

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

    final result =
        await service.schedule(_reminder(kickoffUtc: kickoff, lead: 15));

    expect(result, ReminderScheduleResult.scheduled);
    expect(plugin.scheduled.keys, [100042]);
    final scheduledAt = plugin.scheduled[100042]!;
    expect(
      scheduledAt.toUtc().isAtSameMomentAs(
            kickoff.subtract(const Duration(minutes: 15)),
          ),
      isTrue,
    );
  });

  test('schedule reports alreadyPassed when the fire time is in the past',
      () async {
    final plugin = _FakePlugin();
    final service = ReminderNotificationService(plugin: plugin);
    final kickoff = DateTime.now().toUtc().add(const Duration(minutes: 5));

    // Lead of 15 minutes means the notification would fire in the past.
    final result =
        await service.schedule(_reminder(kickoffUtc: kickoff, lead: 15));

    expect(result, ReminderScheduleResult.alreadyPassed);
    expect(plugin.scheduled, isEmpty);
  });

  test('cancel targets the derived notification id', () async {
    final plugin = _FakePlugin();
    final service = ReminderNotificationService(plugin: plugin);

    await service.cancel(42);

    expect(plugin.cancelled, [100042]);
  });

  test('ensureReady: already-enabled notifications skip the prompt and grant',
      () async {
    final plugin = _FakePlugin()
      ..android.areNotificationsEnabledResults.addAll([true])
      ..android.channels = [
        const AndroidNotificationChannel(
          'match_reminders',
          'Match reminders',
          importance: Importance.high,
        ),
      ];
    final service = ReminderNotificationService(plugin: plugin);

    expect(await service.ensureReady(), ReminderPermissionStatus.granted);
    expect(plugin.android.requestPermissionCalls, 0);
    expect(plugin.android.createdChannels.map((c) => c.id), ['match_reminders']);
  });

  test('ensureReady: disabled notifications prompt, grant, and verify channel',
      () async {
    final plugin = _FakePlugin()
      ..android.areNotificationsEnabledResults.addAll([false])
      ..android.requestNotificationsPermissionResult = true
      ..android.channels = [
        const AndroidNotificationChannel(
          'match_reminders',
          'Match reminders',
          importance: Importance.high,
        ),
      ];
    final service = ReminderNotificationService(plugin: plugin);

    expect(await service.ensureReady(), ReminderPermissionStatus.granted);
    expect(plugin.android.requestPermissionCalls, 1);
  });

  test('ensureReady: a denied prompt reports notificationsDenied', () async {
    final plugin = _FakePlugin()
      ..android.areNotificationsEnabledResults.addAll([false])
      ..android.requestNotificationsPermissionResult = false;
    final service = ReminderNotificationService(plugin: plugin);

    expect(
      await service.ensureReady(),
      ReminderPermissionStatus.notificationsDenied,
    );
  });

  test('ensureReady: a null prompt answer re-checks the toggle', () async {
    // Some devices return null when no dialog is shown. The toggle is
    // re-read: still off means denied, back on means granted.
    final plugin = _FakePlugin()
      ..android.areNotificationsEnabledResults.addAll([false, true])
      ..android.requestNotificationsPermissionResult = null;
    final service = ReminderNotificationService(plugin: plugin);

    expect(await service.ensureReady(), ReminderPermissionStatus.granted);
    expect(plugin.android.areNotificationsEnabledCalls, 2);
  });

  test('ensureReady: a null prompt answer with a still-off toggle is denied',
      () async {
    final plugin = _FakePlugin()
      ..android.areNotificationsEnabledResults.addAll([false, false])
      ..android.requestNotificationsPermissionResult = null;
    final service = ReminderNotificationService(plugin: plugin);

    expect(
      await service.ensureReady(),
      ReminderPermissionStatus.notificationsDenied,
    );
  });

  test('ensureReady: a null enabled answer does not block scheduling',
      () async {
    // Empty result queue -> areNotificationsEnabled() returns null.
    final plugin = _FakePlugin();
    final service = ReminderNotificationService(plugin: plugin);

    expect(await service.ensureReady(), ReminderPermissionStatus.granted);
    expect(plugin.android.requestPermissionCalls, 0);
  });

  test('ensureReady: a channel with no importance reports channelBlocked',
      () async {
    final plugin = _FakePlugin()
      ..android.areNotificationsEnabledResults.addAll([true])
      ..android.channels = [
        const AndroidNotificationChannel(
          'match_reminders',
          'Match reminders',
          importance: Importance.none,
        ),
      ];
    final service = ReminderNotificationService(plugin: plugin);

    expect(await service.ensureReady(), ReminderPermissionStatus.channelBlocked);
  });

  test('ensureReady: a missing channel still reports granted', () async {
    final plugin = _FakePlugin()
      ..android.areNotificationsEnabledResults.addAll([true])
      ..android.channels = [];
    final service = ReminderNotificationService(plugin: plugin);

    expect(await service.ensureReady(), ReminderPermissionStatus.granted);
  });

  test('ensureReady: a plugin failure reports error instead of throwing',
      () async {
    final plugin = _FakePlugin()..initializeError = Exception('boom');
    final service = ReminderNotificationService(plugin: plugin);

    expect(await service.ensureReady(), ReminderPermissionStatus.error);
  });
}
