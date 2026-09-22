import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/fixtures/fixtures_providers.dart';
import 'package:my_football/features/fixtures/fixtures_view.dart';
import 'package:my_football/features/live/live_providers.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/models/goal_event.dart';
import 'package:my_football/models/match_timeline.dart';

/// Issue #5 — from the Matches/Results page, tapping a finished match opens
/// the same goals sheet as the Live tab, showing who scored.
void main() {
  testWidgets('tapping a finished match opens the goals sheet with scorers',
      (tester) async {
    var timelineCalls = 0;
    await _pumpView(
      tester,
      fixtures: [_finished(), _upcoming()],
      timelineFor: (eventId) {
        timelineCalls++;
        return MatchTimeline(goals: _goals());
      },
    );

    await tester.tap(find.text('Arsenal'));
    // onTap is delayed by the double-tap window (the finished row also
    // double-taps into the line-up sheet, issue #8) — flush it.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // The sheet header repeats the match with its score…
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Arsenal 2–1 Chelsea'), findsOneWidget);

    // …and the goal rows carry the scorers.
    expect(find.text('Scorer One'), findsOneWidget);
    expect(find.text('Scorer Two'), findsOneWidget);
    expect(find.textContaining('Assist: Assister'), findsOneWidget);
    expect(find.textContaining('Penalty'), findsOneWidget);
    expect(timelineCalls, 1);
  });

  testWidgets('tapping an upcoming match opens nothing', (tester) async {
    var timelineCalls = 0;
    await _pumpView(
      tester,
      fixtures: [_finished(), _upcoming()],
      timelineFor: (eventId) {
        timelineCalls++;
        return const MatchTimeline();
      },
    );

    await tester.tap(find.text('Liverpool'));
    await tester.pumpAndSettle();

    expect(find.text('Goals'), findsNothing);
    expect(timelineCalls, 0);
  });

  testWidgets('a finished match without timeline data explains itself',
      (tester) async {
    await _pumpView(tester, fixtures: [_finished(), _upcoming()]);

    await tester.tap(find.text('Arsenal'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // Finished matches must not use the live-oriented "yet" wording.
    expect(
      find.text('Goal details aren’t available for this match.'),
      findsOneWidget,
    );
  });
}

Fixture _finished() => Fixture.fromJson(const {
      'idEvent': '2053456',
      'strTimestamp': '2026-08-15T14:00:00',
      'strStatus': 'Match Finished',
      'intHomeScore': '2',
      'intAwayScore': '1',
      'idHomeTeam': '40',
      'strHomeTeam': 'Arsenal',
      'strHomeTeamBadge': '',
      'idAwayTeam': '34',
      'strAwayTeam': 'Chelsea',
      'strAwayTeamBadge': '',
      'intRound': '1',
    });

Fixture _upcoming() => Fixture.fromJson(const {
      'idEvent': '2053457',
      'strTimestamp': '2026-12-01T20:00:00',
      'strStatus': 'NS',
      'idHomeTeam': '45',
      'strHomeTeam': 'Liverpool',
      'strHomeTeamBadge': '',
      'idAwayTeam': '34',
      'strAwayTeam': 'Chelsea',
      'strAwayTeamBadge': '',
      'intRound': '1',
    });

List<GoalEvent> _goals() => const [
      GoalEvent(scorer: 'Scorer One', minute: 12, team: 'Arsenal'),
      GoalEvent(
        scorer: 'Scorer Two',
        minute: 55,
        team: 'Chelsea',
        assist: 'Assister',
        penalty: true,
      ),
    ];

/// Renders [FixturesView] with a canned fixture list and a canned match
/// timeline, exactly the providers the real screens pull from.
Future<void> _pumpView(
  WidgetTester tester, {
  required List<Fixture> fixtures,
  MatchTimeline Function(int eventId)? timelineFor,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fixturesProvider.overrideWith(
          () => _FakeFixturesNotifier(fixtures),
        ),
        matchTimelineProvider.overrideWith(
          (ref, eventId) async =>
              timelineFor?.call(eventId) ?? const MatchTimeline(),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: FixturesView())),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeFixturesNotifier extends FixturesNotifier {
  _FakeFixturesNotifier(this.fixtures);

  final List<Fixture> fixtures;

  @override
  Future<List<Fixture>> build() => Future.value(fixtures);
}
