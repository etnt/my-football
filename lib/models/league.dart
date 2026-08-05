/// The leagues supported in the MVP, with their TheSportsDB league IDs.
enum League {
  premierLeague(4328, 'Premier League'),
  laLiga(4335, 'La Liga'),
  serieA(4332, 'Serie A'),
  bundesliga(4331, 'Bundesliga');

  const League(this.id, this.label);

  final int id;
  final String label;
}

/// Converts a season's starting year to TheSportsDB's `YYYY-YYYY` format
/// (e.g. `2024` -> `2024-2025`).
String apiSeason(int startYear) => '$startYear-${startYear + 1}';
