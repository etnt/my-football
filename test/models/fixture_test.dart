import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/models/fixture.dart';

Fixture _finished({
  required int homeId,
  required int awayId,
  required int homeGoals,
  required int awayGoals,
}) {
  return Fixture.fromJson({
    'fixture': {
      'id': 1,
      'date': '2023-08-11T19:00:00+00:00',
      'status': {'short': 'FT', 'long': 'Match Finished', 'elapsed': 90},
    },
    'teams': {
      'home': {'id': homeId, 'name': 'Home', 'logo': ''},
      'away': {'id': awayId, 'name': 'Away', 'logo': ''},
    },
    'goals': {'home': homeGoals, 'away': awayGoals},
  });
}

void main() {
  group('Fixture.resultFor', () {
    test('win/draw/loss from the home team perspective', () {
      final win = _finished(homeId: 10, awayId: 20, homeGoals: 2, awayGoals: 0);
      final draw = _finished(homeId: 10, awayId: 20, homeGoals: 1, awayGoals: 1);
      final loss = _finished(homeId: 10, awayId: 20, homeGoals: 0, awayGoals: 3);

      expect(win.resultFor(10), 'W');
      expect(draw.resultFor(10), 'D');
      expect(loss.resultFor(10), 'L');
    });

    test('is inverted for the away team', () {
      final f = _finished(homeId: 10, awayId: 20, homeGoals: 2, awayGoals: 0);

      expect(f.resultFor(20), 'L');
    });

    test('returns null for unfinished matches', () {
      final upcoming = Fixture.fromJson({
        'fixture': {
          'id': 2,
          'date': '2023-08-19T14:00:00+00:00',
          'status': {'short': 'NS', 'long': 'Not Started', 'elapsed': null},
        },
        'teams': {
          'home': {'id': 10, 'name': 'Home', 'logo': ''},
          'away': {'id': 20, 'name': 'Away', 'logo': ''},
        },
        'goals': {'home': null, 'away': null},
      });

      expect(upcoming.resultFor(10), isNull);
    });

    test('survives a cache round-trip', () {
      final original =
          _finished(homeId: 10, awayId: 20, homeGoals: 3, awayGoals: 1);
      final restored = Fixture.fromJson(original.toJson());

      expect(restored.homeId, 10);
      expect(restored.awayId, 20);
      expect(restored.resultFor(10), 'W');
    });
  });
}
