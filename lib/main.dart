import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'config/app_version.dart';
import 'dev/live_simulator.dart';
import 'features/reminders/reminder_store.dart';
import 'providers/app_providers.dart';
import 'providers/update_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Drop reminders whose match already kicked off; already-fired alarms are
  // dropped by the OS anyway, this just keeps the stored list tidy.
  await ReminderStore(prefs).removeExpired();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        releaseCheckerProvider.overrideWithValue(
          ReleaseChecker(
            owner: 'etnt',
            repo: 'my-football',
            currentVersion: appVersion,
            // Avoid a GitHub request on every launch; successful checks are
            // throttled across restarts, while errors remain retryable.
            checkStore: SharedPrefsUpdateCheckStore(prefs),
          ),
        ),
        // No-op unless launched with --dart-define=SIMULATE_LIVE=true.
        ...liveSimulationOverrides(),
      ],
      child: const MyFootballApp(),
    ),
  );
}
