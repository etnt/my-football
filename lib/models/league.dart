/// A football league, identified by its TheSportsDB league ID.
///
/// Originally a fixed enum of four leagues; now a data class so the user can
/// follow any league from TheSportsDB's full catalogue (browsed by country in
/// Settings). The four original leagues remain available as named constants
/// for sensible first-run defaults.
class League {
  const League({required this.id, required this.name, this.country});

  /// TheSportsDB league ID (e.g. Premier League = 4328).
  final int id;

  /// Display name (`strLeague`), e.g. "Premier League".
  final String name;

  /// Owning country (`strCountry`), when known, e.g. "England".
  final String? country;

  /// Name used throughout the UI. Kept as a getter for backwards
  /// compatibility with call sites that used the old enum's `label`.
  String get label => name;

  /// Parses a league from `search_all_leagues.php` / `all_leagues.php` JSON,
  /// returning `null` when required fields are missing or malformed.
  static League? fromApiJson(Map<String, dynamic> json) {
    final rawId = json['idLeague'];
    final id = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
    final name = (json['strLeague'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return null;
    final country = (json['strCountry'] as String?)?.trim();
    return League(
      id: id,
      name: name,
      country: (country == null || country.isEmpty) ? null : country,
    );
  }

  /// Serialises this league for storage (followed leagues, catalogue cache).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (country != null) 'country': country,
      };

  factory League.fromJson(Map<String, dynamic> json) => League(
        id: json['id'] as int,
        name: json['name'] as String,
        country: json['country'] as String?,
      );

  // Leagues are considered equal when they share the same TheSportsDB ID, so
  // they behave well in Sets, dropdowns and `contains` checks.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is League && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'League($id, $name)';

  // ---- Default leagues (the original MVP set) --------------------------------

  static const premierLeague =
      League(id: 4328, name: 'Premier League', country: 'England');
  static const laLiga = League(id: 4335, name: 'La Liga', country: 'Spain');
  static const serieA = League(id: 4332, name: 'Serie A', country: 'Italy');
  static const bundesliga =
      League(id: 4331, name: 'Bundesliga', country: 'Germany');

  /// Followed by default on first run.
  static const defaults = [premierLeague, laLiga, serieA, bundesliga];
}

/// Converts a season's starting year to TheSportsDB's `YYYY-YYYY` format
/// (e.g. `2024` -> `2024-2025`).
String apiSeason(int startYear) => '$startYear-${startYear + 1}';
