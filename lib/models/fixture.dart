/// A single match (fixture) from the API-Football `/fixtures` endpoint.
class Fixture {
  const Fixture({
    required this.id,
    required this.dateUtc,
    required this.statusShort,
    required this.statusLong,
    required this.elapsed,
    required this.homeId,
    required this.homeName,
    required this.homeLogo,
    required this.awayId,
    required this.awayName,
    required this.awayLogo,
    required this.homeGoals,
    required this.awayGoals,
  });

  final int id;
  final DateTime dateUtc;
  final String statusShort;
  final String statusLong;
  final int? elapsed;
  final int homeId;
  final String homeName;
  final String homeLogo;
  final int awayId;
  final String awayName;
  final String awayLogo;
  final int? homeGoals;
  final int? awayGoals;

  static const _finished = {'FT', 'AET', 'PEN'};
  static const _live = {'1H', '2H', 'HT', 'ET', 'BT', 'P', 'INT', 'LIVE'};

  bool get isFinished => _finished.contains(statusShort);
  bool get isLive => _live.contains(statusShort);
  bool get hasScore => homeGoals != null && awayGoals != null;

  bool isHome(int teamId) => homeId == teamId;

  /// 'W', 'D' or 'L' for [teamId] when finished with a score; otherwise null.
  String? resultFor(int teamId) {
    if (!isFinished || !hasScore) return null;
    final home = isHome(teamId);
    final scored = home ? homeGoals! : awayGoals!;
    final conceded = home ? awayGoals! : homeGoals!;
    if (scored > conceded) return 'W';
    if (scored < conceded) return 'L';
    return 'D';
  }

  factory Fixture.fromJson(Map<String, dynamic> json) {
    final fixture = (json['fixture'] as Map<String, dynamic>?) ?? const {};
    final status = (fixture['status'] as Map<String, dynamic>?) ?? const {};
    final teams = (json['teams'] as Map<String, dynamic>?) ?? const {};
    final home = (teams['home'] as Map<String, dynamic>?) ?? const {};
    final away = (teams['away'] as Map<String, dynamic>?) ?? const {};
    final goals = (json['goals'] as Map<String, dynamic>?) ?? const {};

    return Fixture(
      id: _asInt(fixture['id']),
      dateUtc: DateTime.tryParse((fixture['date'] as String?) ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      statusShort: (status['short'] as String?) ?? 'NS',
      statusLong: (status['long'] as String?) ?? '',
      elapsed: _asIntOrNull(status['elapsed']),
      homeId: _asInt(home['id']),
      homeName: (home['name'] as String?) ?? '',
      homeLogo: (home['logo'] as String?) ?? '',
      awayId: _asInt(away['id']),
      awayName: (away['name'] as String?) ?? '',
      awayLogo: (away['logo'] as String?) ?? '',
      homeGoals: _asIntOrNull(goals['home']),
      awayGoals: _asIntOrNull(goals['away']),
    );
  }

  /// Compact representation used for local caching.
  Map<String, dynamic> toJson() => {
        'fixture': {
          'id': id,
          'date': dateUtc.toIso8601String(),
          'status': {'short': statusShort, 'long': statusLong, 'elapsed': elapsed},
        },
        'teams': {
          'home': {'id': homeId, 'name': homeName, 'logo': homeLogo},
          'away': {'id': awayId, 'name': awayName, 'logo': awayLogo},
        },
        'goals': {'home': homeGoals, 'away': awayGoals},
      };

  static int _asInt(Object? value) => _asIntOrNull(value) ?? 0;

  static int? _asIntOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
