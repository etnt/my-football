/// One player row in a match line-up (`lookuplineup.php`). The response holds
/// both teams' rows in one list, distinguished by [isHome].
class LineupPlayer {
  const LineupPlayer({
    required this.playerId,
    required this.name,
    required this.teamId,
    required this.teamName,
    required this.position,
    required this.squadNumber,
    required this.isHome,
    required this.isSubstitute,
    required this.imageUrl,
  });

  final int playerId;
  final String name;
  final int teamId;
  final String teamName;

  /// Named position in this match, e.g. "Goalkeeper" / "Right Winger".
  final String position;

  /// Shirt number as reported (`intSquadNumber`), empty when unknown.
  final String squadNumber;

  final bool isHome;
  final bool isSubstitute;

  /// Player cutout, falling back to the thumbnail; empty when unknown.
  final String imageUrl;

  static LineupPlayer? fromApiJson(Map<String, dynamic> json) {
    final rawId = json['idPlayer'];
    final playerId = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
    final name = (json['strPlayer'] as String?)?.trim();
    if (playerId == null || name == null || name.isEmpty) return null;
    final cutout = (json['strCutout'] as String?)?.trim() ?? '';
    final thumb = (json['strThumb'] as String?)?.trim() ?? '';
    return LineupPlayer(
      playerId: playerId,
      name: name,
      teamId: int.tryParse('${json['idTeam'] ?? ''}') ?? 0,
      teamName: (json['strTeam'] as String?)?.trim() ?? '',
      position: (json['strPosition'] as String?)?.trim() ?? '',
      squadNumber: (json['intSquadNumber'] as String?)?.trim() ?? '',
      isHome: ((json['strHome'] as String?) ?? '').toLowerCase() == 'yes',
      isSubstitute:
          ((json['strSubstitute'] as String?) ?? '').toLowerCase() == 'yes',
      imageUrl: cutout.isNotEmpty ? cutout : thumb,
    );
  }

  /// Compact form persisted in the cache; [fromJson] round-trips it.
  Map<String, dynamic> toJson() => {
        'idPlayer': playerId,
        'strPlayer': name,
        'idTeam': teamId,
        'strTeam': teamName,
        'strPosition': position,
        'intSquadNumber': squadNumber,
        'strHome': isHome ? 'Yes' : 'No',
        'strSubstitute': isSubstitute ? 'Yes' : 'No',
        'strCutout': imageUrl,
      };

  factory LineupPlayer.fromJson(Map<String, dynamic> json) {
    final player = LineupPlayer.fromApiJson(json);
    if (player == null) {
      throw const FormatException('Invalid line-up payload.');
    }
    return player;
  }
}
