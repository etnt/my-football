/// A player profile returned by TheSportsDB's player search.
class PlayerDetails {
  const PlayerDetails({
    required this.id,
    required this.name,
    required this.team,
    required this.sport,
    required this.position,
    required this.nationality,
    required this.dateBorn,
    required this.birthLocation,
    required this.height,
    required this.weight,
    required this.thumbUrl,
    required this.cutoutUrl,
    required this.description,
  });

  final int id;
  final String name;
  final String team;
  final String sport;
  final String position;
  final String nationality;
  final String dateBorn;
  final String birthLocation;
  final String height;
  final String weight;
  final String thumbUrl;
  final String cutoutUrl;
  final String description;

  String get imageUrl => cutoutUrl.isNotEmpty ? cutoutUrl : thumbUrl;

  static PlayerDetails? fromApiJson(Map<String, dynamic> json) {
    final rawId = json['idPlayer'];
    final id = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
    final name = (json['strPlayer'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return null;
    return PlayerDetails(
      id: id,
      name: name,
      team: (json['strTeam'] as String?)?.trim() ?? '',
      sport: (json['strSport'] as String?)?.trim() ?? '',
      position: (json['strPosition'] as String?)?.trim() ?? '',
      nationality: (json['strNationality'] as String?)?.trim() ?? '',
      dateBorn: (json['dateBorn'] as String?)?.trim() ?? '',
      birthLocation: (json['strBirthLocation'] as String?)?.trim() ?? '',
      height: (json['strHeight'] as String?)?.trim() ?? '',
      weight: (json['strWeight'] as String?)?.trim() ?? '',
      thumbUrl: (json['strThumb'] as String?)?.trim() ?? '',
      cutoutUrl: (json['strCutout'] as String?)?.trim() ?? '',
      description: (json['strDescriptionEN'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'idPlayer': id,
        'strPlayer': name,
        'strTeam': team,
        'strSport': sport,
        'strPosition': position,
        'strNationality': nationality,
        'dateBorn': dateBorn,
        'strBirthLocation': birthLocation,
        'strHeight': height,
        'strWeight': weight,
        'strThumb': thumbUrl,
        'strCutout': cutoutUrl,
        'strDescriptionEN': description,
      };

  factory PlayerDetails.fromJson(Map<String, dynamic> json) {
    final player = PlayerDetails.fromApiJson(json);
    if (player == null) {
      throw const FormatException('Invalid player details payload.');
    }
    return player;
  }
}
