// Pure-Dart back-test logic for the prediction formula (plan §4.7, TASK-024).
//
// No Flutter imports: this file is compiled by the plain Dart CLI in
// `tool/predictions_backtest.dart` (`dart compile exe`), so every import must
// resolve without `package:flutter` or `dart:ui`. Tests live in
// `test/tool/predictions_backtest_test.dart`.

import 'package:my_football/features/predictions/prediction_calculator.dart';
import 'package:my_football/features/predictions/prediction_input.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/features/predictions/team_form.dart';
import 'package:my_football/models/fixture.dart';

/// Below this many scored predictions the report is flagged as too small to
/// support a tuning decision. The threshold counts scored predictions, not
/// rounds, so it does not depend on `intRound`, which can be null or
/// non-contiguous.
const int minMeaningfulSample = 30;

/// One league-table row rebuilt from finished season events at a point in
/// time. Mirrors what `TeamStanding` carries, plus goals for (needed for the
/// deterministic tie-break that `TeamStanding` alone cannot express).
class BacktestStanding {
  const BacktestStanding({
    required this.teamId,
    required this.name,
    required this.rank,
    required this.played,
    required this.win,
    required this.draw,
    required this.lose,
    required this.goalsFor,
    required this.goalsAgainst,
  });

  final int teamId;
  final String name;

  /// 1-based table position at the rebuilt moment.
  final int rank;
  final int played;
  final int win;
  final int draw;
  final int lose;
  final int goalsFor;
  final int goalsAgainst;

  int get points => 3 * win + draw;
  int get goalsDiff => goalsFor - goalsAgainst;
}

/// A league table rebuilt from the finished, scored fixtures that kicked off
/// strictly before a cutoff instant.
class BacktestTable {
  const BacktestTable(Map<int, BacktestStanding> rows) : _rows = rows;

  final Map<int, BacktestStanding> _rows;

  /// Null when the team has not played any scored fixture before the cutoff.
  BacktestStanding? rowFor(int teamId) => _rows[teamId];

  int get teamCount => _rows.length;

  /// Average points per game over the rows that have played. 0 when no team
  /// has played (the calculator then falls back to its constant).
  double get leagueAvgPpg {
    var games = 0;
    var points = 0;
    for (final row in _rows.values) {
      games += row.played;
      points += row.points;
    }
    if (games == 0) return 0;
    return points / games;
  }
}

/// Rebuilds the league table from [events] using only finished fixtures with
/// a score that kicked off **strictly before** [before] (no look-ahead; a
/// result at exactly the cutoff is excluded). When [before] is null every
/// finished, scored fixture counts.
///
/// Rows are ranked points → goal difference → goals for → name → team id, so
/// the rank is fully deterministic even for teams identical on every metric.
BacktestTable buildTable(List<Fixture> events, {DateTime? before}) {
  final cutoff = before?.toUtc();
  final acc = <int, _RowAcc>{};
  for (final f in events) {
    if (cutoff != null && !f.dateUtc.isBefore(cutoff)) continue;
    if (!f.isFinished || !f.hasScore) continue;
    final home = _acc(acc, f.homeId, f.homeName);
    final away = _acc(acc, f.awayId, f.awayName);
    final hg = f.homeGoals!;
    final ag = f.awayGoals!;
    home.played++;
    home.goalsFor += hg;
    home.goalsAgainst += ag;
    away.played++;
    away.goalsFor += ag;
    away.goalsAgainst += hg;
    if (hg > ag) {
      home.win++;
      away.lose++;
    } else if (hg < ag) {
      away.win++;
      home.lose++;
    } else {
      home.draw++;
      away.draw++;
    }
  }
  final rows = acc.values.toList()
    ..sort((a, b) {
      var by = _desc(a.points, b.points);
      if (by != 0) return by;
      by = _desc(a.goalsFor - a.goalsAgainst, b.goalsFor - b.goalsAgainst);
      if (by != 0) return by;
      by = _desc(a.goalsFor, b.goalsFor);
      if (by != 0) return by;
      by = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (by != 0) return by;
      return a.teamId.compareTo(b.teamId);
    });
  final table = <int, BacktestStanding>{
    for (var i = 0; i < rows.length; i++)
      rows[i].teamId: BacktestStanding(
        teamId: rows[i].teamId,
        name: rows[i].name,
        rank: i + 1,
        played: rows[i].played,
        win: rows[i].win,
        draw: rows[i].draw,
        lose: rows[i].lose,
        goalsFor: rows[i].goalsFor,
        goalsAgainst: rows[i].goalsAgainst,
      ),
  };
  return BacktestTable(table);
}

class _RowAcc {
  _RowAcc(this.teamId, this.name);

  final int teamId;
  String name = '';
  int played = 0;
  int win = 0;
  int draw = 0;
  int lose = 0;
  int goalsFor = 0;
  int goalsAgainst = 0;

  int get points => 3 * win + draw;
  int get goalsDiff => goalsFor - goalsAgainst;
}

_RowAcc _acc(Map<int, _RowAcc> acc, int teamId, String name) =>
    acc.putIfAbsent(teamId, () => _RowAcc(teamId, name));

int _desc(int a, int b) => b.compareTo(a);

/// Builds the calculator input for [fixture] as it looked at kickoff: table
/// from [table] (already rebuilt at the fixture's kickoff) and recent form
/// from [events] strictly before the same instant. Returns null when either
/// team has no table row yet (round 1, or a team absent so far) — the caller
/// skips such fixtures instead of inventing zero-game rows.
PredictionInput? buildInput(
  Fixture fixture,
  List<Fixture> events,
  BacktestTable table,
) {
  final home = table.rowFor(fixture.homeId);
  final away = table.rowFor(fixture.awayId);
  if (home == null || away == null) return null;
  // Season-event form: the order is always known (fixture dates, plan §4.1),
  // so `formOrdered` is true and the recency weighting applies when it is on.
  TeamFactors factors(BacktestStanding s) {
    return TeamFactors(
      teamId: s.teamId,
      name: s.name,
      rank: s.rank,
      played: s.played,
      points: s.points,
      goalsDiff: s.goalsDiff,
      form: recentForm(s.teamId, events, before: fixture.dateUtc),
      formOrdered: true,
      formSource: FormSource.seasonEvents,
    );
  }

  return PredictionInput(
    fixture: fixture,
    home: factors(home),
    away: factors(away),
    leagueAvgPpg: table.leagueAvgPpg,
  );
}

/// The actual outcome of a finished, scored fixture.
Outcome outcomeOf(Fixture fixture) {
  final hg = fixture.homeGoals!;
  final ag = fixture.awayGoals!;
  if (hg > ag) return Outcome.home;
  if (hg < ag) return Outcome.away;
  return Outcome.draw;
}

/// The prediction's argmax outcome. Ties break home → draw → away, matching
/// the verdict rule's reading order; ties are exact doubles and are only
/// expected at the extremes (e.g. pDraw clamped to 0).
Outcome argmaxOutcome({
  required double pHome,
  required double pDraw,
  required double pAway,
}) {
  if (pHome >= pDraw && pHome >= pAway) return Outcome.home;
  if (pDraw >= pAway) return Outcome.draw;
  return Outcome.away;
}

/// Multiclass Brier score for one fixture: the summed squared error over the
/// three outcomes (0 = perfect, 2 = worst possible single fixture).
double brierScore({
  required double pHome,
  required double pDraw,
  required double pAway,
  required Outcome actual,
}) {
  double sq(double p, bool hit) {
    final y = hit ? 1.0 : 0.0;
    final d = p - y;
    return d * d;
  }

  return sq(pHome, actual == Outcome.home) +
      sq(pDraw, actual == Outcome.draw) +
      sq(pAway, actual == Outcome.away);
}

/// The baseline from plan §4.7, computed **in sample** from the same
/// scored fixtures the predictions cover (never from all events): the league's
/// home/draw/away rates on that set, the argmax accuracy of always picking
/// the most frequent outcome (same home → draw → away tie order), and the
/// Brier score of that rate triple.
({double home, double draw, double away, double accuracy, double brier})
computeBaseline(List<Outcome> outcomes) {
  if (outcomes.isEmpty) {
    return (home: 0.0, draw: 0.0, away: 0.0, accuracy: 0.0, brier: 0.0);
  }
  final homes = outcomes.where((o) => o == Outcome.home).length;
  final draws = outcomes.where((o) => o == Outcome.draw).length;
  final aways = outcomes.where((o) => o == Outcome.away).length;
  final n = outcomes.length;
  final home = homes / n;
  final draw = draws / n;
  final away = aways / n;
  final top = argmaxOutcome(pHome: home, pDraw: draw, pAway: away);
  final accuracy = switch (top) {
    Outcome.home => home,
    Outcome.draw => draw,
    Outcome.away => away,
  };
  var brierSum = 0.0;
  for (final o in outcomes) {
    brierSum += brierScore(pHome: home, pDraw: draw, pAway: away, actual: o);
  }
  return (
    home: home,
    draw: draw,
    away: away,
    accuracy: accuracy,
    brier: brierSum / n,
  );
}

/// Aggregate result of one back-test pass. Counts and aggregate metrics only
/// (CON-003): no team names, fixture ids or per-match lines ever enter a
/// [BacktestReport].
class BacktestReport {
  const BacktestReport({
    required this.n,
    required this.skipped,
    required this.correct,
    required this.accuracy,
    required this.brier,
    required this.baselineHomeRate,
    required this.baselineDrawRate,
    required this.baselineAwayRate,
    required this.baselineAccuracy,
    required this.baselineBrier,
    required this.formAffectsEstimate,
    required this.recencyWeighting,
    required this.formulaVersion,
  });

  /// Fixtures actually scored (both teams had a table row at kickoff).
  final int n;

  /// Finished, scored fixtures skipped because a team had no table row yet.
  final int skipped;
  final int correct;

  /// Argmax accuracy, 0 when [n] == 0 (never NaN).
  final double accuracy;

  /// Mean multiclass Brier score, 0 when [n] == 0 (never NaN).
  final double brier;

  /// In-sample outcome rates of the same [n] fixtures.
  final double baselineHomeRate;
  final double baselineDrawRate;
  final double baselineAwayRate;
  final double baselineAccuracy;
  final double baselineBrier;

  /// Whether recent form changed the estimate (form weight not 0). When
  /// false, [recencyWeighting] has no effect and is not reported.
  final bool formAffectsEstimate;
  final bool recencyWeighting;
  final String formulaVersion;
}

/// Runs the back-test over one league season: every finished, scored fixture
/// is predicted with the table and form as they stood at its own kickoff
/// (strict `isBefore` cutoff in both places), then scored against its actual
/// outcome. Fixtures are processed in kickoff order (ties by fixture id) so
/// the report is deterministic regardless of the API's event order.
/// [weights] defaults to the shipped formula.
BacktestReport runBacktest({
  required List<Fixture> events,
  PredictionWeights weights = const PredictionWeights(),
}) {
  final ordered = [...events]..sort(_byKickoff);
  final calculator = PredictionCalculator(weights: weights);
  var n = 0;
  var skipped = 0;
  var correct = 0;
  var brierSum = 0.0;
  final outcomes = <Outcome>[];
  for (final f in ordered) {
    if (!f.isFinished || !f.hasScore) continue;
    final table = buildTable(ordered, before: f.dateUtc);
    final input = buildInput(f, ordered, table);
    if (input == null) {
      skipped++;
      continue;
    }
    final result = calculator.calculate(input);
    final predicted = argmaxOutcome(
      pHome: result.pHome,
      pDraw: result.pDraw,
      pAway: result.pAway,
    );
    final actual = outcomeOf(f);
    outcomes.add(actual);
    n++;
    if (predicted == actual) correct++;
    brierSum += brierScore(
      pHome: result.pHome,
      pDraw: result.pDraw,
      pAway: result.pAway,
      actual: actual,
    );
  }
  final baseline = computeBaseline(outcomes);
  return BacktestReport(
    n: n,
    skipped: skipped,
    correct: correct,
    accuracy: n == 0 ? 0 : correct / n,
    brier: n == 0 ? 0 : brierSum / n,
    baselineHomeRate: baseline.home,
    baselineDrawRate: baseline.draw,
    baselineAwayRate: baseline.away,
    baselineAccuracy: baseline.accuracy,
    baselineBrier: baseline.brier,
    formAffectsEstimate: weights.formAffectsEstimate,
    recencyWeighting: weights.recencyWeighting,
    formulaVersion: weights.version,
  );
}

/// Runs the comparison on the same season: the shipped formula against the
/// original v1 constants (plan §4.8), so a regression shows up at once.
({BacktestReport current, BacktestReport v1}) compareBacktests(
  List<Fixture> events,
) => (
  current: runBacktest(events: events),
  v1: runBacktest(events: events, weights: const PredictionWeights.v1()),
);

int _byKickoff(Fixture a, Fixture b) {
  final byDate = a.dateUtc.compareTo(b.dateUtc);
  return byDate != 0 ? byDate : a.id.compareTo(b.id);
}

/// Human-readable aggregate report. Pure string formatting so the empty and
/// small-sample paths are testable without running `main`. Output contains
/// counts and aggregate metrics only (CON-003).
String formatReport(BacktestReport r) {
  final b = StringBuffer()
    ..write(
      r.formAffectsEstimate
          ? 'formula ${r.formulaVersion}, '
                'recencyWeighting = ${r.recencyWeighting}\n'
          : 'formula ${r.formulaVersion}, form is context only\n',
    );
  if (r.n == 0) {
    b.write(
      '  not enough data: no scored predictions (n = 0, ${r.skipped} '
      'finished fixtures skipped). No metrics.\n',
    );
    return b.toString();
  }
  b
    ..write(
      '  scored predictions: n = ${r.n} (${r.skipped} finished fixtures '
      'skipped: a team had no table row yet)\n',
    )
    ..write(
      '  argmax accuracy: ${r.accuracy.toStringAsFixed(3)} '
      '(${r.correct} of ${r.n})\n',
    )
    ..write('  Brier score: ${r.brier.toStringAsFixed(4)} (lower is better)\n')
    ..write(
      '  in-sample baseline over the same ${r.n} fixtures: '
      '${(r.baselineHomeRate * 100).round()}% / '
      '${(r.baselineDrawRate * 100).round()}% / '
      '${(r.baselineAwayRate * 100).round()}% home-draw-away\n',
    )
    ..write(
      '  baseline argmax accuracy: ${r.baselineAccuracy.toStringAsFixed(3)}; '
      'baseline Brier: ${r.baselineBrier.toStringAsFixed(4)}\n',
    );
  if (r.n < minMeaningfulSample) {
    b.write(
      '  warning: n = ${r.n} is too small to support a tuning decision.\n',
    );
  }
  return b.toString();
}

/// Command-line arguments for the back-test tool, with the API key read from
/// the environment (never from a file). Pure so it is testable without
/// `dart:io` side effects.
class BacktestArgs {
  const BacktestArgs({
    this.leagueId,
    this.season,
    this.apiKey,
    this.help = false,
  });

  final int? leagueId;
  final String? season;

  /// From `SPORTSDB_API_KEY`, trimmed; null when unset or blank.
  final String? apiKey;
  final bool help;
}

/// Environment variable carrying the API key. Env only: the tool never reads
/// `API-KEY.txt` or any other key file.
const String apiKeyEnvVar = 'SPORTSDB_API_KEY';

/// Parses CLI arguments. Throws [ArgumentError] for unknown arguments or
/// malformed values; missing `--league`/`--season`/key are reported as null
/// fields for the caller to turn into a usage error.
BacktestArgs parseArgs(List<String> arguments, Map<String, String> env) {
  int? leagueId;
  String? season;
  var help = false;
  for (final arg in arguments) {
    if (arg == '--help' || arg == '-h') {
      help = true;
      continue;
    }
    if (arg.startsWith('--league=')) {
      final value = arg.substring('--league='.length);
      final id = int.tryParse(value);
      if (id == null || id <= 0) {
        throw ArgumentError.value(value, '--league', 'must be a positive id');
      }
      leagueId = id;
      continue;
    }
    if (arg.startsWith('--season=')) {
      final value = arg.substring('--season='.length).trim();
      if (value.isEmpty) {
        throw ArgumentError.value(value, '--season', 'must not be empty');
      }
      season = value;
      continue;
    }
    throw ArgumentError.value(arg, 'argument', 'unknown argument; see --help');
  }
  final key = (env[apiKeyEnvVar] ?? '').trim();
  return BacktestArgs(
    leagueId: leagueId,
    season: season,
    apiKey: key.isEmpty ? null : key,
    help: help,
  );
}
