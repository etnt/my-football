import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/live/goal_alert.dart';
import 'package:my_football/features/live/goal_notification_service.dart';
import 'package:my_football/features/live/live_providers.dart';
import 'package:my_football/features/live/live_scores_view.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/models/goal_event.dart';
import 'package:my_football/models/league.dart';
import 'package:my_football/models/match_timeline.dart';
import 'package:my_football/features/standings/standings_providers.dart';

Fixture _live({
  required int id,
  required int homeGoals,
  required int awayGoals,
}) {
  return Fixture.fromV2Json({
    'idEvent': '$id',
    'strTimestamp': '2026-08-06T19:00:00',
    'strStatus': '2H',
    'strProgress': '67',
    'idHomeTeam': '40',
    'strHomeTeam': 'Arsenal',
    'strHomeTeamBadge': '',
    'idAwayTeam': '34',
    'strAwayTeam': 'Chelsea',
    'strAwayTeamBadge': '',
    'intHomeScore': '$homeGoals',
    'intAwayScore': '$awayGoals',
  });
}

class _FakeNotifications extends GoalNotificationService {
  _FakeNotifications() : super();

  final shown = <GoalAlert>[];
  bool allowed = true;

  @override
  Future<bool> ensureReady() async => allowed;

  @override
  Future<void> showGoal(GoalAlert alert) async {
    shown.add(alert);
  }
}

void main() {
  testWidgets('fires a notification when a live score increases', (
    tester,
  ) async {
    final controller = StreamController<List<Fixture>>();
    final notifications = _FakeNotifications();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          liveScoresProvider.overrideWith((ref) => controller.stream),
          goalNotificationServiceProvider.overrideWithValue(notifications),
        ],
        child: const MaterialApp(home: Scaffold(body: LiveScoresView())),
      ),
    );

    controller.add([_live(id: 1, homeGoals: 0, awayGoals: 0)]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Arsenal'), findsOneWidget);
    expect(notifications.shown, isEmpty);

    controller.add([_live(id: 1, homeGoals: 1, awayGoals: 0)]);
    await tester.pump();
    await tester.pump();

    expect(notifications.shown, hasLength(1));
    expect(notifications.shown.single.title, 'GOAL!');
    expect(notifications.shown.single.body, contains('Arsenal 1-0 Chelsea'));
  });

  testWidgets('does not notify after switching league until a new goal', (
    tester,
  ) async {
    final controller = StreamController<List<Fixture>>();
    final notifications = _FakeNotifications();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          liveScoresProvider.overrideWith((ref) => controller.stream),
          goalNotificationServiceProvider.overrideWithValue(notifications),
        ],
        child: const MaterialApp(home: Scaffold(body: LiveScoresView())),
      ),
    );

    controller.add([_live(id: 1, homeGoals: 0, awayGoals: 0)]);
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LiveScoresView)),
    );
    container.read(selectedLeagueProvider.notifier).state = League.laLiga;
    await tester.pump();

    // First snapshot of the new league already has a score — baseline only.
    controller.add([_live(id: 99, homeGoals: 2, awayGoals: 1)]);
    await tester.pump();
    await tester.pump();

    expect(notifications.shown, isEmpty);
  });

  testWidgets('shows scorer and minute when a live match is tapped', (
    tester,
  ) async {
    final notifications = _FakeNotifications();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          liveScoresProvider.overrideWith(
            (ref) => Stream.value([_live(id: 1, homeGoals: 1, awayGoals: 0)]),
          ),
          matchTimelineProvider.overrideWith(
            (ref, eventId) async => const MatchTimeline(
              goals: [
                GoalEvent(
                  scorer: 'Bukayo Saka',
                  minute: 23,
                  assist: 'Martin Ødegaard',
                  team: 'Arsenal',
                ),
              ],
            ),
          ),
          goalNotificationServiceProvider.overrideWithValue(notifications),
        ],
        child: const MaterialApp(home: Scaffold(body: LiveScoresView())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Arsenal'));
    await tester.pumpAndSettle();

    expect(find.text('Goals'), findsOneWidget);
    expect(find.text("23'"), findsOneWidget);
    expect(find.text('Bukayo Saka'), findsOneWidget);
    expect(find.textContaining('Assist: Martin Ødegaard'), findsOneWidget);
  });
}
