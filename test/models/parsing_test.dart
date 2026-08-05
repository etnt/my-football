import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/models/team_standing.dart';

void main() {
  group('TeamStanding.fromJson', () {
    final json = {
      'intRank': '1',
      'idTeam': '133613',
      'strTeam': 'Manchester City',
      'strBadge': 'city.png',
      'intPoints': '89',
      'intGoalDifference': '61',
      'strForm': 'WWDWW',
      'intPlayed': '38',
      'intWin': '28',
      'intDraw': '5',
      'intLoss': '5',
      'intGoalsFor': '94',
      'intGoalsAgainst': '33',
    };

    test('maps all fields', () {
      final standing = TeamStanding.fromJson(json);

      expect(standing.rank, 1);
      expect(standing.teamId, 133613);
      expect(standing.teamName, 'Manchester City');
      expect(standing.teamLogo, 'city.png');
      expect(standing.points, 89);
      expect(standing.goalsDiff, 61);
      expect(standing.played, 38);
      expect(standing.win, 28);
      expect(standing.draw, 5);
      expect(standing.lose, 5);
      expect(standing.form, 'WWDWW');
    });

    test('tolerates missing/partial data', () {
      final standing = TeamStanding.fromJson({'intRank': '3'});

      expect(standing.rank, 3);
      expect(standing.teamName, '');
      expect(standing.points, 0);
      expect(standing.played, 0);
      expect(standing.form, '');
    });

    test('coerces numeric strings to ints', () {
      final standing = TeamStanding.fromJson({
        'intRank': '7',
        'intPoints': '42',
        'intPlayed': '30',
      });

      expect(standing.rank, 7);
      expect(standing.points, 42);
      expect(standing.played, 30);
    });

    test('round-trips through toJson', () {
      final original = TeamStanding.fromJson(json);
      final restored = TeamStanding.fromJson(original.toJson());

      expect(restored.rank, original.rank);
      expect(restored.teamName, original.teamName);
      expect(restored.teamLogo, original.teamLogo);
      expect(restored.points, original.points);
      expect(restored.goalsDiff, original.goalsDiff);
      expect(restored.played, original.played);
      expect(restored.win, original.win);
      expect(restored.form, original.form);
    });
  });
}
