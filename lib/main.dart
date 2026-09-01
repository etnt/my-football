import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'dev/live_simulator.dart';
import 'features/reminders/reminder_store.dart';
import 'providers/app_providers.dart';

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
        // No-op unless launched with --dart-define=SIMULATE_LIVE=true.
        ...liveSimulationOverrides(),
      ],
      child: const MyFootballApp(),
    ),
  );
}
