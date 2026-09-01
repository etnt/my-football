import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/live/goal_alert.dart';
import 'package:my_football/models/fixture.dart';

Fixture _live({
  required int id,
  required int homeGoals,
  required int awayGoals,
  String home = 'Arsenal',
  String away = 'Chelsea',
}) {
  return Fixture.fromV2Json({
    'idEvent': '$id',
    'strTimestamp': '2026-08-06T19:00:00',
    'strStatus': '2H',
    'strProgress': '67',
    'idHomeTeam': '40',
    'strHomeTeam': home,
    'strHomeTeamBadge': '',
    'idAwayTeam': '34',
    'strAwayTeam': away,
    'strAwayTeamBadge': '',
    'intHomeScore': '$homeGoals',
    'intAwayScore': '$awayGoals',
  });
}

void main() {
  group('detectScoreIncreases', () {
    test('returns nothing when scores are unchanged', () {
      final previous = [_live(id: 1, homeGoals: 1, awayGoals: 0)];
      final current = [_live(id: 1, homeGoals: 1, awayGoals: 0)];

      expect(detectScoreIncreases(previous, current), isEmpty);
    });

    test('detects a home goal', () {
      final previous = [_live(id: 1, homeGoals: 0, awayGoals: 0)];
      final current = [_live(id: 1, homeGoals: 1, awayGoals: 0)];

      final alerts = detectScoreIncreases(previous, current);
      expect(alerts, hasLength(1));
      expect(alerts.single.homeDelta, 1);
      expect(alerts.single.awayDelta, 0);
      expect(alerts.single.title, 'GOAL!');
      expect(alerts.single.body, 'Arsenal score — Arsenal 1-0 Chelsea');
    });

    test('detects an away goal', () {
      final previous = [_live(id: 1, homeGoals: 1, awayGoals: 0)];
      final current = [_live(id: 1, homeGoals: 1, awayGoals: 1)];

      final alerts = detectScoreIncreases(previous, current);
      expect(alerts.single.awayDelta, 1);
      expect(alerts.single.body, 'Chelsea score — Arsenal 1-1 Chelsea');
    });

    test('treats a jump of two goals as one multi-goal alert', () {
      final previous = [_live(id: 1, homeGoals: 0, awayGoals: 0)];
      final current = [_live(id: 1, homeGoals: 2, awayGoals: 0)];

      final alerts = detectScoreIncreases(previous, current);
      expect(alerts.single.homeDelta, 2);
      expect(alerts.single.title, 'GOALS!');
    });

    test('ignores a match that was not in the previous snapshot', () {
      final previous = [_live(id: 1, homeGoals: 0, awayGoals: 0)];
      final current = [
        _live(id: 1, homeGoals: 0, awayGoals: 0),
        _live(
            id: 2,
            homeGoals: 1,
            awayGoals: 0,
            home: 'Liverpool',
            away: 'Everton'),
      ];

      expect(detectScoreIncreases(previous, current), isEmpty);
    });

    test('ignores a score decrease (e.g. disallowed goal)', () {
      final previous = [_live(id: 1, homeGoals: 1, awayGoals: 0)];
      final current = [_live(id: 1, homeGoals: 0, awayGoals: 0)];

      expect(detectScoreIncreases(previous, current), isEmpty);
    });

    test('emits one alert per match that scored', () {
      final previous = [
        _live(id: 1, homeGoals: 0, awayGoals: 0),
        _live(
            id: 2,
            homeGoals: 1,
            awayGoals: 1,
            home: 'Liverpool',
            away: 'Everton'),
      ];
      final current = [
        _live(id: 1, homeGoals: 1, awayGoals: 0),
        _live(
            id: 2,
            homeGoals: 1,
            awayGoals: 2,
            home: 'Liverpool',
            away: 'Everton'),
      ];

      final alerts = detectScoreIncreases(previous, current);
      expect(alerts, hasLength(2));
      expect(alerts.map((a) => a.fixture.id), [1, 2]);
    });
  });

  group('LiveGoalMonitor', () {
    test('the first snapshot is a baseline and never alerts', () {
      final monitor = LiveGoalMonitor();
      final first = monitor.ingest([_live(id: 1, homeGoals: 2, awayGoals: 1)]);

      expect(first, isEmpty);
    });

    test('alerts on a later score increase', () {
      final monitor = LiveGoalMonitor();
      monitor.ingest([_live(id: 1, homeGoals: 0, awayGoals: 0)]);
      final alerts = monitor.ingest([_live(id: 1, homeGoals: 1, awayGoals: 0)]);

      expect(alerts, hasLength(1));
      expect(alerts.single.homeDelta, 1);
    });

    test('reset drops the baseline so the next snapshot is quiet', () {
      final monitor = LiveGoalMonitor();
      monitor.ingest([_live(id: 1, homeGoals: 0, awayGoals: 0)]);
      monitor.reset();
      final afterReset =
          monitor.ingest([_live(id: 9, homeGoals: 3, awayGoals: 1)]);

      expect(afterReset, isEmpty);
    });

    test('an empty snapshot keeps the baseline so later goals still alert', () {
      final monitor = LiveGoalMonitor();
      monitor.ingest([_live(id: 1, homeGoals: 0, awayGoals: 0)]);

      // Feed hiccup: an empty poll must not be treated as a new baseline.
      expect(monitor.ingest(const []), isEmpty);
      expect(monitor.ingest([_live(id: 1, homeGoals: 1, awayGoals: 0)]),
          hasLength(1));
    });

    test('an empty first snapshot is still a valid baseline', () {
      final monitor = LiveGoalMonitor();
      // No baseline yet: an empty snapshot sets it, so the next real snapshot
      // is "new matches" and stays quiet (first-snapshot behaviour).
      expect(monitor.ingest(const []), isEmpty);
      expect(monitor.ingest([_live(id: 1, homeGoals: 4, awayGoals: 0)]),
          isEmpty);
    });
  });
}
