import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fixture.dart';
import '../../models/match_timeline.dart';
import '../../providers/app_providers.dart';
import '../standings/standings_providers.dart' show selectedLeagueProvider;
import 'goal_notification_service.dart';

/// How often to poll the livescore feed while the Live tab is visible.
const _livePollInterval = Duration(seconds: 30);

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
final liveScoresProvider = StreamProvider.autoDispose<List<Fixture>>((
  ref,
) async* {
  final client = ref.watch(sportsDbV2ClientProvider);
  if (client == null) {
    yield const [];
    return;
  }
  final league = ref.watch(selectedLeagueProvider);

  while (true) {
    yield await client.getLiveScores(leagueId: league.id);
    await Future<void>.delayed(_livePollInterval);
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
