import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/live/live_match_goals_sheet.dart';
import 'package:my_football/features/live/live_providers.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/models/goal_event.dart';
import 'package:my_football/models/match_timeline.dart';

Fixture _live() {
  return Fixture.fromV2Json({
    'idEvent': '1',
    'strTimestamp': '2026-08-06T19:00:00',
    'strStatus': '2H',
    'strProgress': '67',
    'idHomeTeam': '40',
    'strHomeTeam': 'Arsenal',
    'strHomeTeamBadge': '',
    'idAwayTeam': '34',
    'strAwayTeam': 'Chelsea',
    'strAwayTeamBadge': '',
    'intHomeScore': '4',
    'intAwayScore': '4',
  });
}

List<GoalEvent> _goals(int count) => List.generate(
      count,
      (i) => GoalEvent(
        scorer: 'Player ${i + 1}',
        minute: i + 1,
        assist: 'Assister ${i + 1}',
        team: 'Arsenal',
      ),
    );

/// Opens [LiveMatchGoalsSheet] exactly like [LiveScoresView] does and returns
/// the rendered height of the sheet content.
Future<double> _openSheet(WidgetTester tester, MatchTimeline timeline) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchTimelineProvider.overrideWith((ref, eventId) async => timeline),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => LiveMatchGoalsSheet(fixture: _live()),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  return tester.getSize(find.byType(LiveMatchGoalsSheet)).height;
}

void main() {
  testWidgets('shows every goal — the last ones after scrolling', (
    tester,
  ) async {
    final height = await _openSheet(
      tester,
      MatchTimeline(goals: _goals(8)),
    );

    // Sanity: the sheet is capped well below full height.
    expect(height, lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio));

    // Only the first few rows fit; the rest are below the fold…
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('Player 7'), findsNothing);
    expect(find.text('Player 8'), findsNothing);

    // …but are reachable by scrolling the list.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.text('Player 7'), findsOneWidget);
    expect(find.text('Player 8'), findsOneWidget);
  });

  testWidgets('sheet height adapts to the number of goals', (tester) async {
    final twoGoals = await _openSheet(
      tester,
      MatchTimeline(goals: _goals(2)),
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    final eightGoals = await _openSheet(
      tester,
      MatchTimeline(goals: _goals(8)),
    );

    expect(eightGoals, greaterThan(twoGoals));
    // Old behaviour was a fixed 55% height no matter what — now an 8-goal
    // match grows well beyond what 2 goals need (but stays capped).
    expect(eightGoals, greaterThan(twoGoals * 1.5));
    expect(eightGoals, lessThanOrEqualTo(420.0)); // 0.7 × 600 test surface
  });

  testWidgets('shows an empty state when no goals are recorded', (
    tester,
  ) async {
    await _openSheet(tester, const MatchTimeline());

    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Goal details aren’t available yet.'), findsOneWidget);
  });

  testWidgets('shows an error with retry when the timeline fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchTimelineProvider.overrideWith((ref, eventId) async {
            throw Exception('boom');
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => LiveMatchGoalsSheet(fixture: _live()),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t load goal details.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
