/// One row on a leaderboard: a player and their tally.
class StatLine {
  const StatLine(
    this.player,
    this.value, {
    this.penalties = 0,
    this.yellows = 0,
    this.reds = 0,
    this.team,
  });

  /// Player name (as reported by the timeline feed).
  final String player;

  /// The counted stat — goals, assists or total cards depending on the board.
  final int value;

  /// How many of [value] were penalties (top-scorers board only).
  final int penalties;

  /// Yellow cards (cards board only).
  final int yellows;

  /// Red cards (cards board only).
  final int reds;

  /// The player's team (most recently seen), shown in small print.
  final String? team;
}

/// The leaderboards produced from a season's finished matches.
class Leaderboards {
  const Leaderboards({
    this.scorers = const [],
    this.assists = const [],
    this.cards = const [],
  });

  final List<StatLine> scorers;
  final List<StatLine> assists;
  final List<StatLine> cards;

  static const empty = Leaderboards();
}

/// Where the aggregation currently is.
enum StatsPhase { building, done, error, premiumRequired }

/// Immutable snapshot of the stats build: the (possibly partial) leaderboards
/// plus progress so the UI can show "Analyzed X of Y matches".
class StatsState {
  const StatsState({
    required this.phase,
    this.board = Leaderboards.empty,
    this.processed = 0,
    this.total = 0,
    this.error,
  });

  final StatsPhase phase;
  final Leaderboards board;
  final int processed;
  final int total;
  final Object? error;

  bool get isBuilding => phase == StatsPhase.building;

  StatsState copyWith({
    StatsPhase? phase,
    Leaderboards? board,
    int? processed,
    int? total,
    Object? error,
  }) =>
      StatsState(
        phase: phase ?? this.phase,
        board: board ?? this.board,
        processed: processed ?? this.processed,
        total: total ?? this.total,
        error: error,
      );

  static const premiumRequired = StatsState(phase: StatsPhase.premiumRequired);
}
