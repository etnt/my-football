import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/models/account_status.dart';
import 'package:my_football/models/team_standing.dart';

void main() {
  group('TeamStanding.fromJson', () {
    final json = {
      'rank': 1,
      'team': {'id': 50, 'name': 'Manchester City', 'logo': 'city.png'},
      'points': 89,
      'goalsDiff': 61,
      'form': 'WWDWW',
      'all': {
        'played': 38,
        'win': 28,
        'draw': 5,
        'lose': 5,
        'goals': {'for': 94, 'against': 33},
      },
    };

    test('maps all fields', () {
      final standing = TeamStanding.fromJson(json);

      expect(standing.rank, 1);
      expect(standing.teamId, 50);
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
      final standing = TeamStanding.fromJson({'rank': 3});

      expect(standing.rank, 3);
      expect(standing.teamName, '');
      expect(standing.points, 0);
      expect(standing.played, 0);
      expect(standing.form, '');
    });

    test('coerces numeric strings to ints', () {
      final standing = TeamStanding.fromJson({
        'rank': '7',
        'points': '42',
        'all': {'played': '30'},
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

  group('AccountStatus.fromJson', () {
    test('maps plan and request counters', () {
      final status = AccountStatus.fromJson({
        'subscription': {'plan': 'Free', 'active': true},
        'requests': {'current': 12, 'limit_day': 100},
      });

      expect(status.plan, 'Free');
      expect(status.active, true);
      expect(status.requestsToday, 12);
      expect(status.dailyLimit, 100);
      expect(status.remainingToday, 88);
    });

    test('remainingToday never goes negative', () {
      final status = AccountStatus.fromJson({
        'requests': {'current': 150, 'limit_day': 100},
      });

      expect(status.remainingToday, 0);
    });

    test('falls back gracefully on empty payload', () {
      final status = AccountStatus.fromJson({});

      expect(status.plan, 'Unknown');
      expect(status.active, false);
      expect(status.dailyLimit, 0);
    });
  });
}
