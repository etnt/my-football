import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/recap/fact_sheet.dart';
import 'package:my_football/models/card_event.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/models/goal_event.dart';
import 'package:my_football/models/match_timeline.dart';

import '../../support/fixture_helpers.dart';

void main() {
  group('FactSheet.build', () {
    test('full timeline: goals sorted by minute, extras carried through', () {
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: fullTimeline(),
      );

      expect(facts.homeGoals, 2);
      expect(facts.awayGoals, 1);
      expect(
        facts.goals.map((g) => g.minute),
        [12, 34, 77],
        reason: 'goals must be ordered by minute',
      );
      expect(facts.cards.length, 2);
      expect(facts.cards.where((c) => c.red).length, 1);
      expect(facts.dateLocal.isUtc, isFalse);
    });

    test('missing timeline: score-only, eventsComplete false above 0–0', () {
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: emptyTimeline,
      );

      expect(facts.goals, isEmpty);
      expect(facts.cards, isEmpty);
      expect(facts.homeGoals, 2);
      expect(facts.awayGoals, 1);
      expect(facts.eventsComplete, isFalse);
    });

    test('0–0 with an empty timeline counts as complete', () {
      final facts = FactSheet.build(
        fixture: fixtureZeroNil(),
        timeline: emptyTimeline,
      );

      expect(facts.eventsComplete, isTrue);
      expect(facts.goals, isEmpty);
    });

    test('null goals are treated as 0', () {
      final facts = FactSheet.build(
        fixture: fixtureNullScore(),
        timeline: emptyTimeline,
      );

      expect(facts.homeGoals, 0);
      expect(facts.awayGoals, 0);
      expect(facts.eventsComplete, isTrue);
    });

    test('date is converted to local time', () {
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: emptyTimeline,
      );
      expect(facts.dateLocal, fixtureFinished().dateUtc.toLocal());
    });
  });

  group('toFactLines', () {
    test('lists match, score, date, round and every goal with details', () {
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: fullTimeline(),
        competition: 'Premier League',
      );
      final lines = facts.toFactLines();

      expect(lines.first, 'Match: Arsenal 2–1 Chelsea');
      // Build the expected date from dateLocal so the test does not depend
      // on the machine's timezone.
      final date = facts.dateLocal;
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      expect(
        lines,
        contains('Date: ${date.day} ${months[date.month - 1]} ${date.year}'),
      );
      expect(lines, contains('Competition: Premier League'));
      expect(lines, contains('Round: 3'));
      expect(
        lines,
        contains("Goal: 12' Saka (Arsenal)"),
      );
      expect(
        lines,
        contains("Goal: 34' Palmer (Chelsea) – assist Neto"),
      );
      expect(
        lines,
        contains("Goal: 77' Gabriel (Arsenal) – penalty"),
      );
      expect(
        lines,
        contains('Card: Jackson (Chelsea) – red card'),
      );
    });

    test('cards show player, team and colour only', () {
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: fullTimeline(),
      );
      final cardLines =
          facts.toFactLines().where((l) => l.startsWith('Card:')).toList();

      expect(cardLines, hasLength(2));
      expect(cardLines, contains('Card: Caicedo (Chelsea) – yellow card'));
      expect(
        cardLines.any((l) => RegExp(r'\d').hasMatch(l)),
        isFalse,
        reason: 'CardEvent has no minute, so no numbers may appear',
      );
    });
  });

  group('allowedNumbers / allowedNameTokens', () {
    test('numbers cover score, minutes, round, date and counts', () {
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: fullTimeline(),
        competition: 'Premier League',
      );
      final numbers = facts.allowedNumbers;

      expect(
        numbers,
        containsAll(
          ['2', '1', '3', '12', '34', '77', '15', '2026'],
        ),
      );
      expect(numbers, contains('2'));
      expect(numbers.contains('99'), isFalse);
    });

    test('name tokens are accent-folded and lowercase', () {
      final facts = FactSheet.build(
        fixture: fixtureFinishedAccent(),
        timeline: MatchTimeline(
          goals: const [
            GoalEvent(
              scorer: 'Nkúnku',
              minute: 5,
              team: 'Chelsea',
              assist: 'Mudryk',
            ),
          ],
          cards: const [
            CardEvent(player: 'Thiago Silva', team: 'Chelsea'),
          ],
        ),
        competition: 'Ligue 1',
      );

      final tokens = facts.allowedNameTokens;
      expect(tokens, containsAll(['arsenal', 'chelsea', 'nkunku', 'mudryk',
        'thiago', 'silva', 'ligue']));
      expect(tokens.contains('Nkunku'), isFalse);
      expect(tokens.contains('Nkúnku'), isFalse);
    });
  });
}

/// A finished fixture with null score fields, so the FactSheet must treat
/// nulls as 0.
Fixture fixtureNullScore() => Fixture.fromJson(const {
      'idEvent': '2053460',
      'strTimestamp': '2026-08-15T14:00:00',
      'strStatus': 'Match Finished',
      'idHomeTeam': '40',
      'strHomeTeam': 'Everton',
      'strHomeTeamBadge': '',
      'idAwayTeam': '34',
      'strAwayTeam': 'Brighton',
      'strAwayTeamBadge': '',
      'intRound': '3',
    });

/// A finished 0–0 fixture.
Fixture fixtureZeroNil() => Fixture.fromJson(const {
      'idEvent': '2053458',
      'strTimestamp': '2026-08-15T14:00:00',
      'strStatus': 'Match Finished',
      'intHomeScore': '0',
      'intAwayScore': '0',
      'idHomeTeam': '40',
      'strHomeTeam': 'Everton',
      'strHomeTeamBadge': '',
      'idAwayTeam': '34',
      'strAwayTeam': 'Brighton',
      'strAwayTeamBadge': '',
      'intRound': '3',
    });

/// A finished fixture where the away team name has accents, for the
/// accent-fold tests.
Fixture fixtureFinishedAccent() => Fixture.fromJson(const {
      'idEvent': '2053459',
      'strTimestamp': '2026-08-15T14:00:00',
      'strStatus': 'Match Finished',
      'intHomeScore': '1',
      'intAwayScore': '0',
      'idHomeTeam': '40',
      'strHomeTeam': 'Arsenal',
      'strHomeTeamBadge': '',
      'idAwayTeam': '34',
      'strAwayTeam': 'Chelsea',
      'strAwayTeamBadge': '',
      'intRound': '3',
    });
