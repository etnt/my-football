import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import '../../models/match_timeline.dart';
import '../../providers/app_providers.dart';
import '../standings/standings_providers.dart' show selectedLeagueProvider;
import 'goal_notification_service.dart';

/// How often to poll the livescore feed while the Live tab is visible.
/// Overridden in tests to make polling fast.
final livePollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

/// How many consecutive failed polls before the stream gives up and surfaces
/// the error (the UI shows it and pull-to-refresh restarts polling). A smaller
/// number of transient failures is retried silently instead, so one flaky
/// request can no longer kill goal alerts for the whole session.
const _maxConsecutiveFailures = 3;

/// Local-notification helper used to alert on goals. Overridden in tests.
final goalNotificationServiceProvider = Provider<GoalNotificationService>((
  ref,
) {
  return GoalNotificationService();
});

/// Streams live matches for the selected league, re-polling on a timer.
///
/// This is `autoDispose`, so polling stops automatically when the Live tab is
/// swapped out. It only emits when a Premium (v2) client is available.
///
/// Transient poll failures (rate limits, timeouts) are retried after the
/// normal interval — the UI keeps showing the last good snapshot and goal
/// alerting continues. Only after several consecutive failures does the
/// stream surface the error, so one flaky request can't silence alerts.
final liveScoresProvider = StreamProvider.autoDispose<List<Fixture>>((ref) async* {
  final client = ref.watch(sportsDbV2ClientProvider);
  if (client == null) {
    yield const [];
    return;
  }
  final league = ref.watch(selectedLeagueProvider);
  final interval = ref.watch(livePollIntervalProvider);

  var failures = 0;
  while (true) {
    try {
      yield await client.getLiveScores(leagueId: league.id);
      failures = 0;
    } catch (error) {
      failures++;
      if (failures >= _maxConsecutiveFailures) rethrow;
    }
    await Future<void>.delayed(interval);
  }
});

/// Goal and card events for one match, fetched only when its live row is
/// opened. Timeline coverage varies by competition, so an empty result is
/// valid even when the livescore feed has a score.
final matchTimelineProvider = FutureProvider.autoDispose
    .family<MatchTimeline, int>((ref, eventId) async {
      final client = ref.watch(sportsDbV2ClientProvider);
      if (client == null) return const MatchTimeline();
      return client.getEventTimeline(eventId: eventId);
    });
