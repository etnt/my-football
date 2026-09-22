/// A player profile returned by TheSportsDB's player search, optionally
/// enriched from the full `lookupplayer.php` profile (which carries several
/// fields the name search omits — see issue #7).
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
    this.number = '',
    this.status = '',
    this.signing = '',
    this.wage = '',
    this.preferredFoot = '',
    this.nationalTeam = '',
    this.alternateName = '',
    this.instagram = '',
    this.twitter = '',
    this.website = '',
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

  /// Shirt number (`strNumber`), empty when unknown — the name search omits it.
  final String number;

  /// Contract status (`strStatus`), e.g. "Active" / "Retired".
  final String status;

  /// Transfer/signing fee (`strSigning`, falling back to `strSign`).
  final String signing;

  /// Salary (`strWage`), e.g. "£525,000 per week".
  final String wage;

  /// Preferred foot (`strSide`), e.g. "Left" / "Right".
  final String preferredFoot;

  /// National team (`strTeam2`), e.g. "Norway".
  final String nationalTeam;

  /// Alternate spelling of the name (`strPlayerAlternate`).
  final String alternateName;

  /// Social/website URLs as raw strings, empty when unknown.
  final String instagram;
  final String twitter;
  final String website;

  String get imageUrl => cutoutUrl.isNotEmpty ? cutoutUrl : thumbUrl;

  /// This profile with every empty field filled from [fallback] (the sparser
  /// search-result profile), so the richest known value for each field wins.
  PlayerDetails mergeFallback(PlayerDetails fallback) => PlayerDetails(
        id: id,
        name: name.isNotEmpty ? name : fallback.name,
        team: team.isNotEmpty ? team : fallback.team,
        sport: sport.isNotEmpty ? sport : fallback.sport,
        position: position.isNotEmpty ? position : fallback.position,
        nationality: nationality.isNotEmpty ? nationality : fallback.nationality,
        dateBorn: dateBorn.isNotEmpty ? dateBorn : fallback.dateBorn,
        birthLocation:
            birthLocation.isNotEmpty ? birthLocation : fallback.birthLocation,
        height: height.isNotEmpty ? height : fallback.height,
        weight: weight.isNotEmpty ? weight : fallback.weight,
        thumbUrl: thumbUrl.isNotEmpty ? thumbUrl : fallback.thumbUrl,
        cutoutUrl: cutoutUrl.isNotEmpty ? cutoutUrl : fallback.cutoutUrl,
        description:
            description.isNotEmpty ? description : fallback.description,
        number: number.isNotEmpty ? number : fallback.number,
        status: status.isNotEmpty ? status : fallback.status,
        signing: signing.isNotEmpty ? signing : fallback.signing,
        wage: wage.isNotEmpty ? wage : fallback.wage,
        preferredFoot:
            preferredFoot.isNotEmpty ? preferredFoot : fallback.preferredFoot,
        nationalTeam:
            nationalTeam.isNotEmpty ? nationalTeam : fallback.nationalTeam,
        alternateName:
            alternateName.isNotEmpty ? alternateName : fallback.alternateName,
        instagram: instagram.isNotEmpty ? instagram : fallback.instagram,
        twitter: twitter.isNotEmpty ? twitter : fallback.twitter,
        website: website.isNotEmpty ? website : fallback.website,
      );

  static PlayerDetails? fromApiJson(Map<String, dynamic> json) {
    final rawId = json['idPlayer'];
    final id = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
    final name = (json['strPlayer'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return null;
    final signing = (json['strSigning'] as String?)?.trim() ?? '';
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
      number: (json['strNumber'] as String?)?.trim() ?? '',
      status: (json['strStatus'] as String?)?.trim() ?? '',
      signing:
          signing.isNotEmpty ? signing : ((json['strSign'] as String?)?.trim() ?? ''),
      wage: (json['strWage'] as String?)?.trim() ?? '',
      preferredFoot: (json['strSide'] as String?)?.trim() ?? '',
      nationalTeam: (json['strTeam2'] as String?)?.trim() ?? '',
      alternateName: (json['strPlayerAlternate'] as String?)?.trim() ?? '',
      instagram: (json['strInstagram'] as String?)?.trim() ?? '',
      twitter: (json['strTwitter'] as String?)?.trim() ?? '',
      website: (json['strWebsite'] as String?)?.trim() ?? '',
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
        'strNumber': number,
        'strStatus': status,
        'strSigning': signing,
        'strWage': wage,
        'strSide': preferredFoot,
        'strTeam2': nationalTeam,
        'strPlayerAlternate': alternateName,
        'strInstagram': instagram,
        'strTwitter': twitter,
        'strWebsite': website,
      };

  factory PlayerDetails.fromJson(Map<String, dynamic> json) {
    final player = PlayerDetails.fromApiJson(json);
    if (player == null) {
      throw const FormatException('Invalid player details payload.');
    }
    return player;
  }
}
