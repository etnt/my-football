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
    final team = (json['team'] as Map<String, dynamic>?) ?? const {};
    final all = (json['all'] as Map<String, dynamic>?) ?? const {};
    return TeamStanding(
      rank: _asInt(json['rank']),
      teamId: _asInt(team['id']),
      teamName: (team['name'] as String?) ?? '',
      teamLogo: (team['logo'] as String?) ?? '',
      points: _asInt(json['points']),
      goalsDiff: _asInt(json['goalsDiff']),
      played: _asInt(all['played']),
      win: _asInt(all['win']),
      draw: _asInt(all['draw']),
      lose: _asInt(all['lose']),
      form: (json['form'] as String?) ?? '',
    );
  }

  /// Compact representation used for local caching.
  Map<String, dynamic> toJson() => {
        'rank': rank,
        'team': {'id': teamId, 'name': teamName, 'logo': teamLogo},
        'points': points,
        'goalsDiff': goalsDiff,
        'all': {'played': played, 'win': win, 'draw': draw, 'lose': lose},
        'form': form,
      };

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
