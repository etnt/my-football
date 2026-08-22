import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'goal_alert.dart';

/// Shows a local notification for a [GoalAlert].
///
/// Thin wrapper so the Live tab can be tested without the plugin, and so
/// plugin initialisation / permission prompts stay in one place.
class GoalNotificationService {
  GoalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'live_goals';
  static const _channelName = 'Live goals';
  static const _channelDescription =
      'Alerts when a goal is scored in a live match.';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  int _nextId = 1;

  /// Initialise the plugin and ask for notification permission.
  ///
  /// Safe to call more than once. Returns whether notifications are allowed.
  Future<bool> ensureReady() async {
    try {
      if (!_ready) {
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
              alert: true, badge: true, sound: true) ??
          false;
    }

    final macos = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (macos != null) {
      return await macos.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return true;
  }

  Future<void> showGoal(GoalAlert alert) async {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.event,
      ticker: 'Goal',
    );
    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
    );
    await _plugin.show(
      id: _nextId++,
      title: alert.title,
      body: alert.body,
      notificationDetails: const NotificationDetails(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
    );
  }
}
