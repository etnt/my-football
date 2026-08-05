/// A single row in a league standings table.
class TeamStanding {
  const TeamStanding({
    required this.rank,
    required this.teamId,
    required this.teamName,
    required this.teamLogo,
    required this.points,
    required this.goalsDiff,
    required this.played,
    required this.win,
    required this.draw,
    required this.lose,
    required this.form,
  });

  final int rank;
  final int teamId;
  final String teamName;
  final String teamLogo;
  final int points;
  final int goalsDiff;
  final int played;
  final int win;
  final int draw;
  final int lose;
  final String form;

  factory TeamStanding.fromJson(Map<String, dynamic> json) {
    return TeamStanding(
      rank: _asInt(json['intRank']),
      teamId: _asInt(json['idTeam']),
      teamName: (json['strTeam'] as String?) ?? '',
      teamLogo: (json['strBadge'] as String?) ?? '',
      points: _asInt(json['intPoints']),
      goalsDiff: _asInt(json['intGoalDifference']),
      played: _asInt(json['intPlayed']),
      win: _asInt(json['intWin']),
      draw: _asInt(json['intDraw']),
      lose: _asInt(json['intLoss']),
      form: (json['strForm'] as String?) ?? '',
    );
  }

  /// Compact representation used for local caching. Uses the same keys as the
  /// TheSportsDB `lookuptable` response so [fromJson] round-trips cleanly.
  Map<String, dynamic> toJson() => {
        'intRank': rank,
        'idTeam': teamId,
        'strTeam': teamName,
        'strBadge': teamLogo,
        'intPoints': points,
        'intGoalDifference': goalsDiff,
        'intPlayed': played,
        'intWin': win,
        'intDraw': draw,
        'intLoss': lose,
        'strForm': form,
      };

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
