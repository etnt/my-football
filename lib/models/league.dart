/// The leagues supported in the MVP, with their API-Football league IDs.
enum League {
  premierLeague(39, 'Premier League'),
  laLiga(140, 'La Liga'),
  serieA(135, 'Serie A'),
  bundesliga(78, 'Bundesliga');

  const League(this.id, this.label);

  final int id;
  final String label;
}
