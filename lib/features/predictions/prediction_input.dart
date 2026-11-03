import '../../models/fixture.dart';

/// Where a team's recent form came from.
enum FormSource { seasonEvents, standingsForm, none }

/// One recent result with its context: who the opponent was and where it
/// was played. Lets the calculator compare the result with what was expected
/// against that opponent (opponent-adjusted form, plan §4.10).
class FormMatch {
  const FormMatch({
    required this.result,
    required this.atHome,
    required this.opponentId,
  });

  /// `W`, `D` or `L` for the team.
  final String result;
  final bool atHome;
  final int opponentId;
}

/// A team's league-table record, used to rate the opponents in
/// [TeamFactors.formMatches].
class TeamRecord {
  const TeamRecord({
    required this.played,
    required this.points,
    required this.goalsDiff,
  });

  final int played;
  final int points;
  final int goalsDiff;
}

/// The per-team factors the prediction formula uses. `form` is W/D/L,
/// **newest first**, and empty when form is missing (REQ-006: missing data
/// is never treated as a zero or a loss).
class TeamFactors {
  const TeamFactors({
    required this.teamId,
    required this.name,
    required this.rank,
    required this.played,
    required this.points,
    required this.goalsDiff,
    required this.form,
    required this.formOrdered,
    required this.formSource,
    this.formMatches = const [],
  });

  final int teamId;
  final String name;

  /// Table position (`TeamStanding.rank`).
  final int rank;

  /// League games played.
  final int played;

  /// League points.
  final int points;

  /// Goal difference (the table does not carry goals for/against).
  final int goalsDiff;

  /// Up to 5 recent results, newest first; empty when form is missing.
  final List<String> form;

  /// Whether the order of [form] is known (fixture dates or a confirmed
  /// `strForm` order). When false the calculator uses plain counts.
  final bool formOrdered;

  final FormSource formSource;

  /// The same recent results as [form] with opponent and venue, newest
  /// first. Empty when that context is unknown (`strForm` has none); the
  /// calculator then compares form with the team's own season average.
  final List<FormMatch> formMatches;
}

/// Everything the calculator needs for one fixture.
class PredictionInput {
  const PredictionInput({
    required this.fixture,
    required this.home,
    required this.away,
    required this.leagueAvgPpg,
    this.sameGroup = true,
    this.table = const {},
  });

  final Fixture fixture;
  final TeamFactors home;
  final TeamFactors away;

  /// League average points per game from the table. When the table has no
  /// games played (or the value is not positive) the calculator falls back
  /// to its `leagueAvgPpgFallback` constant.
  final double leagueAvgPpg;

  /// Whether both teams come from the same table group. `TeamStanding` has
  /// no group field, so this is always true today; kept so a multi-group
  /// table can later suppress rank-based reasoning without a schema change.
  final bool sameGroup;

  /// Every team's table record by team id, to rate the opponents in the
  /// recent form. Empty means form cannot be adjusted for opponents.
  final Map<int, TeamRecord> table;
}
