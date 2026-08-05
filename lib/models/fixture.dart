/// A single match (event) from TheSportsDB `events`/`eventsseason` endpoints.
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
    this.postponed = false,
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
  final bool postponed;

  static const _finished = {'FT', 'AET', 'PEN', 'Match Finished'};
  static const _live = {'1H', '2H', 'HT', 'ET', 'BT', 'P', 'INT', 'LIVE'};

  bool get isLive => _live.contains(statusShort);
  bool get hasScore => homeGoals != null && awayGoals != null;
  bool get isFinished =>
      !postponed &&
      !isLive &&
      (_finished.contains(statusShort) || hasScore);

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
    final status = (json['strStatus'] as String?)?.trim();
    return Fixture(
      id: _asInt(json['idEvent']),
      dateUtc: _parseDate(json),
      statusShort: (status == null || status.isEmpty) ? 'NS' : status,
      statusLong: '',
      elapsed: null,
      postponed:
          ((json['strPostponed'] as String?) ?? 'no').toLowerCase() == 'yes',
      homeId: _asInt(json['idHomeTeam']),
      homeName: (json['strHomeTeam'] as String?) ?? '',
      homeLogo: (json['strHomeTeamBadge'] as String?) ?? '',
      awayId: _asInt(json['idAwayTeam']),
      awayName: (json['strAwayTeam'] as String?) ?? '',
      awayLogo: (json['strAwayTeamBadge'] as String?) ?? '',
      homeGoals: _asIntOrNull(json['intHomeScore']),
      awayGoals: _asIntOrNull(json['intAwayScore']),
    );
  }

  /// Compact representation used for local caching. Uses TheSportsDB event keys
  /// so [fromJson] round-trips cleanly.
  Map<String, dynamic> toJson() => {
        'idEvent': id,
        'strTimestamp': dateUtc.toIso8601String(),
        'strStatus': statusShort,
        'strPostponed': postponed ? 'yes' : 'no',
        'idHomeTeam': homeId,
        'strHomeTeam': homeName,
        'strHomeTeamBadge': homeLogo,
        'idAwayTeam': awayId,
        'strAwayTeam': awayName,
        'strAwayTeamBadge': awayLogo,
        'intHomeScore': homeGoals,
        'intAwayScore': awayGoals,
      };

  /// TheSportsDB timestamps are UTC but carry no timezone suffix. Prefer
  /// `strTimestamp`, falling back to `dateEvent` + `strTime`.
  static DateTime _parseDate(Map<String, dynamic> json) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final ts = (json['strTimestamp'] as String?)?.trim();
    if (ts != null && ts.isNotEmpty) {
      final normalized = ts.endsWith('Z') ? ts : '${ts}Z';
      final parsed = DateTime.tryParse(normalized);
      if (parsed != null) return parsed.toUtc();
    }
    final date = (json['dateEvent'] as String?)?.trim();
    if (date != null && date.isNotEmpty) {
      final time = (json['strTime'] as String?)?.trim();
      final t = (time == null || time.isEmpty) ? '00:00:00' : time;
      final parsed = DateTime.tryParse('${date}T${t}Z');
      if (parsed != null) return parsed.toUtc();
    }
    return epoch;
  }

  static int _asInt(Object? value) => _asIntOrNull(value) ?? 0;

  static int? _asIntOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
