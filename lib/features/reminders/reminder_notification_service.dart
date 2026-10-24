import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'match_reminder.dart';

/// Why [ReminderNotificationService.ensureReady] may not be able to show a
/// reminder notification.
enum ReminderPermissionStatus {
  /// Notifications are allowed and the 'Match reminders' channel is on.
  granted,

  /// Notifications are turned off for the whole app in system settings.
  notificationsDenied,

  /// Notifications are allowed, but the 'Match reminders' channel is turned
  /// off in system settings. Android will silently drop anything posted to a
  /// blocked channel, and the app cannot re-enable it — only the user can,
  /// under Settings → Apps → this app → Notifications → Match reminders.
  channelBlocked,

  /// Talking to the notification plugin failed. The cause is logged; the
  /// reminder is still saved and can fire once the problem goes away.
  error,
}

/// Outcome of [ReminderNotificationService.schedule].
enum ReminderScheduleResult {
  /// The OS accepted the alarm for the reminder's fire time.
  scheduled,

  /// The fire time was already in the past, so no alarm was set and none
  /// will fire. The saved choice is still recorded, but the user must save
  /// the reminder again (before an earlier lead time) to get an alert.
  alreadyPassed,
}

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

  /// Initialise the plugin, timezone database, channel, and permission.
  ///
  /// Safe to call more than once. Returns a [ReminderPermissionStatus]
  /// describing whether reminders can actually be shown, so the UI can tell
  /// the user *why* a reminder would stay silent instead of blaming system
  /// settings for every failure.
  Future<ReminderPermissionStatus> ensureReady() async {
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
      final status = await _checkPermission();
      if (status != ReminderPermissionStatus.granted) return status;
      return await _ensureChannel();
    } catch (e) {
      // One concise log for the failure case only — this method runs on every
      // reminder save, so nothing is logged on the success path.
      debugPrint('ReminderNotificationService.ensureReady failed: $e');
      return ReminderPermissionStatus.error;
    }
  }

  /// Checks notification permission without muddling the cause.
  ///
  /// Android first: `areNotificationsEnabled()` is the authoritative answer
  /// for the app-level toggle, so it is used directly when notifications are
  /// already on. The runtime prompt is only raised when the toggle is off.
  /// A `null` result is treated as "cannot tell", never as "denied" — some
  /// devices return null when no dialog is shown, and reporting that as
  /// "turned off in system settings" is exactly the false warning we are
  /// fixing here.
  Future<ReminderPermissionStatus> _checkPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final enabled = await android.areNotificationsEnabled();
      if (enabled == true) return ReminderPermissionStatus.granted;
      // Null means the plugin could not tell (e.g. no dialog was shown on
      // some devices). Treating it as granted is deliberate: claiming "off in
      // system settings" would be a false warning, and the OS simply drops
      // the notification if we guess wrong.
      if (enabled == null) return ReminderPermissionStatus.granted;

      // Explicitly off: offer the Android 13+ runtime prompt, then re-check.
      final granted = await android.requestNotificationsPermission();
      if (granted == null) {
        final recheck = await android.areNotificationsEnabled();
        return recheck == false
            ? ReminderPermissionStatus.notificationsDenied
            : ReminderPermissionStatus.granted;
      }
      return granted
          ? ReminderPermissionStatus.granted
          : ReminderPermissionStatus.notificationsDenied;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      // Null here means "cannot tell", not "denied" — some devices return
      // null when no dialog is presented. Treating it as granted is a
      // deliberate decision: a false denial warning is worse than a silent
      // drop, and the OS discards the notification if we guessed wrong.
      if (granted == false) return ReminderPermissionStatus.notificationsDenied;
      return ReminderPermissionStatus.granted;
    }

    return ReminderPermissionStatus.granted;
  }

  /// Creates the reminder channel if needed and verifies it is not blocked.
  ///
  /// The plugin also creates the channel when a notification is posted, but
  /// creating it up front lets us detect the one state the app cannot fix
  /// itself: a channel the user (or an OEM default) switched to "none" in
  /// system settings. Re-creating a channel never re-enables it, so the only
  /// remedy is telling the user where the switch lives.
  Future<ReminderPermissionStatus> _ensureChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      // iOS/macOS have no channels; permission was already checked.
      return ReminderPermissionStatus.granted;
    }

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    final channels = await android.getNotificationChannels();
    final match = channels
        ?.where((channel) => channel.id == _channelId)
        .toList(growable: false);
    if (match == null || match.isEmpty) {
      // Cannot verify — assume the channel is fine rather than blocking.
      return ReminderPermissionStatus.granted;
    }
    return match.first.importance == Importance.none
        ? ReminderPermissionStatus.channelBlocked
        : ReminderPermissionStatus.granted;
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
  /// Returns [ReminderScheduleResult.alreadyPassed] when the fire time is
  /// already in the past (e.g. the user saved a reminder for a match that
  /// kicked off while the sheet was open); nothing is scheduled in that
  /// case, so the UI must not claim a reminder was set. Uses inexact
  /// scheduling so no Android 12+ exact-alarm permission is needed; a
  /// kick-off reminder tolerates minute-level drift.
  Future<ReminderScheduleResult> schedule(MatchReminder reminder) async {
    // `tz.local` throws until the timezone database is initialised, so make
    // sure it is even when schedule() is called without ensureReady() first.
    await _initTimeZones();
    final scheduled = tz.TZDateTime.from(reminder.notifyAtUtc, tz.local);
    if (scheduled.isBefore(DateTime.now())) {
      return ReminderScheduleResult.alreadyPassed;
    }

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
    return ReminderScheduleResult.scheduled;
  }

  /// Cancels the scheduled notification for [fixtureId] (no-op when none).
  Future<void> cancel(int fixtureId) {
    return _plugin.cancel(id: notificationId(fixtureId));
  }
}
