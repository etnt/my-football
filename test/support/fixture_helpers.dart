import 'package:my_football/models/card_event.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/models/goal_event.dart';
import 'package:my_football/models/match_timeline.dart';

/// A finished fixture used by the recap tests. `strTimestamp` has no
/// timezone suffix, so it is parsed as UTC and `FactSheet` must convert it
/// with `toLocal()`.
Fixture fixtureFinished() => Fixture.fromJson(const {
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
      'intRound': '3',
    });

Fixture fixtureUpcoming() => Fixture.fromJson(const {
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

/// Timeline for [fixtureFinished]: 3 goal rows for the 2–1 score (one from
/// an assist), so `eventsComplete` is true.
MatchTimeline fullTimeline() => MatchTimeline(
      goals: const [
        GoalEvent(scorer: 'Saka', minute: 12, team: 'Arsenal'),
        GoalEvent(
          scorer: 'Palmer',
          minute: 34,
          team: 'Chelsea',
          assist: 'Neto',
        ),
        GoalEvent(
          scorer: 'Gabriel',
          minute: 77,
          team: 'Arsenal',
          penalty: true,
        ),
      ],
      cards: const [
        CardEvent(player: 'Caicedo', team: 'Chelsea'),
        CardEvent(player: 'Jackson', team: 'Chelsea', red: true),
      ],
    );

/// Complete timeline for [fixtureFinished]: 3 goal rows for the 2–1 score
/// (one an own goal), so `eventsComplete` is true.
MatchTimeline completeTimeline() => MatchTimeline(
      goals: const [
        GoalEvent(scorer: 'Saka', minute: 12, team: 'Arsenal'),
        GoalEvent(
          scorer: 'Palmer',
          minute: 34,
          team: 'Chelsea',
          ownGoal: true,
        ),
        GoalEvent(
          scorer: 'Gabriel',
          minute: 77,
          team: 'Arsenal',
          penalty: true,
        ),
      ],
    );

/// [completeTimeline] plus a red card, so the template recap has a card
/// clause as well and `eventsComplete` is still true.
MatchTimeline completeTimelineRed() => MatchTimeline(
      goals: const [
        GoalEvent(scorer: 'Saka', minute: 12, team: 'Arsenal'),
        GoalEvent(
          scorer: 'Palmer',
          minute: 34,
          team: 'Chelsea',
          ownGoal: true,
        ),
        GoalEvent(
          scorer: 'Gabriel',
          minute: 77,
          team: 'Arsenal',
          penalty: true,
        ),
      ],
      cards: const [
        CardEvent(player: 'Jackson', team: 'Chelsea', red: true),
      ],
    );

/// Timeline with nothing in it — the recap must stay score-only.
const MatchTimeline emptyTimeline = MatchTimeline();
