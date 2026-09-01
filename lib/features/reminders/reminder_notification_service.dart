import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'match_reminder.dart';

/// Schedules and cancels kick-off reminder notifications.
///
/// Thin wrapper so the reminder feature can be tested without the plugin,
/// and so plugin initialisation / permission prompts stay in one place —
/// the same pattern as `GoalNotificationService` in the Live feature.
class ReminderNotificationService {
  ReminderNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'match_reminders';
  static const _channelName = 'Match reminders';
  static const _channelDescription = 'Alerts before a match kicks off.';

  /// Reminder notification ids are namespaced away from other notification
  /// users (live goal alerts count up from 1) by offsetting the fixture id.
  static int notificationId(int fixtureId) => 100000 + fixtureId;

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  bool _timeZonesReady = false;

  /// Initialise the plugin, timezone database, and permission prompt.
  ///
  /// Safe to call more than once. Returns whether notifications are allowed.
  Future<bool> ensureReady() async {
    try {
      if (!_ready) {
        await _initTimeZones();
        const android = AndroidInitializationSettings('@drawable/ic_stat_goal');
        const darwin = DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
        const settings = InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        );
        await _plugin.initialize(settings: settings);
        _ready = true;
      }
      return await _requestPermission();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return true;
  }

  /// Initialises the timezone database and the device's local zone (once).
  ///
  /// `zonedSchedule` needs a `tz.TZDateTime`; converting the UTC kick-off
  /// through `tz.local` keeps the alarm on the right wall-clock instant. If
  /// the device zone can't be resolved we fall back to UTC — converting a
  /// UTC instant through any zone labels the alarm correctly even if the
  /// zone's offset metadata is imperfect for the user's location.
  Future<void> _initTimeZones() async {
    if (_timeZonesReady) return;
    tzdata.initializeTimeZones();
    String name;
    try {
      name = await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      name = 'UTC';
    }
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    _timeZonesReady = true;
  }

  /// Schedules the kick-off notification for [reminder].
  ///
  /// A no-op when the fire time is already in the past (e.g. the user saved
  /// a reminder for a match that kicked off while the sheet was open). Uses
  /// inexact scheduling so no Android 12+ exact-alarm permission is needed;
  /// a kick-off reminder tolerates minute-level drift.
  Future<void> schedule(MatchReminder reminder) async {
    // `tz.local` throws until the timezone database is initialised, so make
    // sure it is even when schedule() is called without ensureReady() first.
    await _initTimeZones();
    final scheduled = tz.TZDateTime.from(reminder.notifyAtUtc, tz.local);
    if (scheduled.isBefore(DateTime.now())) return;

    final android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Kick-off reminder',
    );
    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
    );

    await _plugin.zonedSchedule(
      id: notificationId(reminder.fixtureId),
      title: '${reminder.homeName} vs ${reminder.awayName}',
      body: 'Kick-off in ${reminder.leadMinutes} minutes',
      scheduledDate: scheduled,
      notificationDetails: NotificationDetails(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Cancels the scheduled notification for [fixtureId] (no-op when none).
  Future<void> cancel(int fixtureId) {
    return _plugin.cancel(id: notificationId(fixtureId));
  }
}
