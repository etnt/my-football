/// Debug-only live-score simulator.
///
/// Feeds synthetic, score-incrementing livescore snapshots into the *real*
/// `liveScoresProvider` seam so the whole goal-alert pipeline
/// (`LiveGoalMonitor` → `GoalNotificationService` → OS notification) can be
/// exercised on an emulator without a Premium key or an actual live match.
///
/// Enable it by passing a compile-time flag at run time:
///
/// ```bash
/// flutter run --dart-define=SIMULATE_LIVE=true
/// ```
///
/// This has no effect on normal builds: when the flag is absent
/// [liveSimulationOverrides] returns an empty list.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/live/live_providers.dart';
import '../models/fixture.dart';
import '../providers/app_providers.dart';

/// True when the app was launched with `--dart-define=SIMULATE_LIVE=true`.
const bool simulateLive = bool.fromEnvironment('SIMULATE_LIVE');

/// How long to wait between simulated goals.
const _goalInterval = Duration(seconds: 5);

/// Provider overrides that turn on the live simulation.
///
/// Returns an empty list unless [simulateLive] is set, so it is safe to spread
/// unconditionally into a `ProviderScope`.
List<Override> liveSimulationOverrides() {
  if (!simulateLive) return const [];
  return [
    // Unlock the Premium-only Live tab without a stored API key.
    isPremiumProvider.overrideWithValue(true),
    // Replace the network poll with a scripted stream of goals.
    liveScoresProvider.overrideWith((ref) => _simulatedLiveScores()),
  ];
}

/// Emits an initial 0-0 baseline, then adds one goal every [_goalInterval]
/// following a short script. The first emit sets the monitor baseline and
/// (by design) fires no alert; each later emit bumps one team's score, so a
/// notification fires per goal.
Stream<List<Fixture>> _simulatedLiveScores() async* {
  var homeA = 0, awayA = 0; // Match 1: Arsenal vs Chelsea
  var homeB = 0, awayB = 0; // Match 2: Spurs vs Liverpool
  var minute = 45;

  List<Fixture> snapshot() => [
        _live(
          id: 1,
          home: 'Arsenal',
          away: 'Chelsea',
          homeGoals: homeA,
          awayGoals: awayA,
          minute: minute,
        ),
        _live(
          id: 2,
          home: 'Spurs',
          away: 'Liverpool',
          homeGoals: homeB,
          awayGoals: awayB,
          minute: minute,
        ),
      ];

  // Baseline snapshot — establishes the score the monitor diffs against.
  yield snapshot();

  // Each step mutates the running score; the resulting emit fires an alert.
  final script = <void Function()>[
    () => homeA++, // Arsenal score
    () => awayB++, // Liverpool score
    () => awayA++, // Chelsea equalise
    () => homeA++, // Arsenal retake the lead
  ];

  for (final scoreGoal in script) {
    await Future<void>.delayed(_goalInterval);
    scoreGoal();
    minute += 3;
    yield snapshot();
  }
}

/// Builds a live [Fixture] in its second half with the given scoreline.
Fixture _live({
  required int id,
  required String home,
  required String away,
  required int homeGoals,
  required int awayGoals,
  required int minute,
}) {
  return Fixture(
    id: id,
    dateUtc: DateTime.now().toUtc(),
    statusShort: '2H',
    statusLong: 'Second Half',
    elapsed: minute,
    homeId: id * 100,
    homeName: home,
    homeLogo: '',
    awayId: id * 100 + 1,
    awayName: away,
    awayLogo: '',
    homeGoals: homeGoals,
    awayGoals: awayGoals,
    progress: "$minute'",
  );
}
