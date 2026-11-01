import 'dart:math' as math;

import 'prediction_input.dart';
import 'prediction_result.dart';
import 'team_form.dart';

/// Recency weights for the newest-first form list (see plan §4.1). Only the
/// first `n` are used for `n` results.
const List<double> defaultRecencyWeights = [1.0, 0.9, 0.8, 0.7, 0.6];

/// Starting constants for the prediction formula (plan §4). All heuristic;
/// versioned so they can be tuned and back-tested (TASK-024).
class PredictionWeights {
  const PredictionWeights({
    this.shrinkageK = 3,
    this.goalDiffWeight = 0.25,
    this.formWeight = 0.35,
    this.recencyWeights = defaultRecencyWeights,
    this.recencyWeighting = true,
    this.homeAdvantage = 0.20,
    this.logisticScale = 1.6,
    this.drawCenter = 0.55,
    this.leagueAvgPpgFallback = 1.37,
    this.version = 'v1',
  });

  /// Small-sample shrinkage constant: `ppg = (points + k·L) / (played + k)`.
  final int shrinkageK;
  final double goalDiffWeight;
  final double formWeight;
  final List<double> recencyWeights;

  /// Switch for the recency weighting so the back-test can compare weighted
  /// form with plain counts. When false (or the order is unknown) every
  /// match counts the same.
  final bool recencyWeighting;

  /// Fixed home advantage in points per game.
  final double homeAdvantage;

  /// Ordered-logistic scale `a` and draw centre `c` (plan §4.3).
  final double logisticScale;
  final double drawCenter;

  /// League average ppg used when the table has no games played.
  final double leagueAvgPpgFallback;

  final String version;
}

int _points(String result) => switch (result) {
  'W' => 3,
  'D' => 1,
  _ => 0,
};

/// Points per result for a newest-first form list. When [ordered] and
/// [recencyWeighting] are both true the results are weighted newest-first
/// with [weights]; otherwise every match counts the same (plain average).
double formPpg(
  List<String> form, {
  required bool ordered,
  required bool recencyWeighting,
  List<double> weights = defaultRecencyWeights,
}) {
  if (form.isEmpty) return 0;
  final points = [for (final r in form) _points(r)];
  if (!(ordered && recencyWeighting)) {
    var total = 0;
    for (final p in points) {
      total += p;
    }
    return total / points.length;
  }
  var weighted = 0.0;
  var weightSum = 0.0;
  for (var i = 0; i < points.length; i++) {
    final w = i < weights.length ? weights[i] : 1.0;
    weighted += w * points[i];
    weightSum += w;
  }
  return weighted / weightSum;
}

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

double _sigmoid(double x) => 1 / (1 + math.exp(-x));

/// Pure, deterministic prediction calculation (formula v1, plan §4).
class PredictionCalculator {
  const PredictionCalculator({this.weights = const PredictionWeights()});

  final PredictionWeights weights;

  PredictionResult calculate(PredictionInput input) {
    final league = input.leagueAvgPpg > 0
        ? input.leagueAvgPpg
        : weights.leagueAvgPpgFallback;

    final home = _factors(input.home, league, isHomeSide: true);
    final away = _factors(input.away, league, isHomeSide: false);

    final d = home.strength - away.strength + weights.homeAdvantage;

    final a = weights.logisticScale;
    final c = weights.drawCenter;
    final pHome = _sigmoid(a * d - c);
    final pAway = _sigmoid(-a * d - c);
    var pDraw = 1 - pHome - pAway;
    if (pDraw < 0) pDraw = 0;

    final percents = _displayPercents(pHome, pDraw, pAway);

    final gap = (pHome - pAway).abs();
    final Verdict verdict;
    final bool isSlight;
    if (gap < 0.10) {
      // A plain "highest probability" rule would almost never pick a draw
      // (plan §4.4). isSlight stays false: there is no favourite side here.
      verdict = Verdict.closeDrawLikely;
      isSlight = false;
    } else if (pHome > pAway) {
      verdict = Verdict.homeWin;
      isSlight = gap < 0.20;
    } else {
      verdict = Verdict.awayWin;
      isSlight = gap < 0.20;
    }

    final (:reasons, notes: missingNotes, :completeness) = _explain(
      input,
      home,
      away,
      league,
    );

    return PredictionResult(
      pHome: pHome,
      pDraw: pDraw,
      pAway: pAway,
      displayPercents: percents,
      verdict: verdict,
      isSlight: isSlight,
      reasons: reasons,
      missingNotes: missingNotes,
      completeness: completeness,
      formulaVersion: weights.version,
    );
  }

  _TeamMath _factors(
    TeamFactors team,
    double league, {
    required bool isHomeSide,
  }) {
    final k = weights.shrinkageK;
    // Shrunk points per game: with few games, pulled toward the league.
    final ppg = (team.points + k * league) / (team.played + k);
    // Goal difference per game, shrunk toward 0.
    final gdpg = team.goalsDiff / (team.played + k);

    final hasForm = team.form.isNotEmpty;
    final fPpg = hasForm
        ? formPpg(
            team.form,
            ordered: team.formOrdered,
            recencyWeighting: weights.recencyWeighting,
            weights: weights.recencyWeights,
          )
        : null;
    // Shrink form toward the team's ppg for small samples. Missing form
    // leaves the form term at exactly zero (REQ-006: never a loss).
    final formAdj = hasForm
        ? (team.form.length * fPpg! + 2 * ppg) / (team.form.length + 2)
        : ppg;
    final formTerm = hasForm ? weights.formWeight * (formAdj - ppg) : 0.0;
    final tablePart = ppg + weights.goalDiffWeight * gdpg;

    return _TeamMath(
      factors: team,
      isHomeSide: isHomeSide,
      ppg: ppg,
      gdpg: gdpg,
      formPpg: fPpg,
      formAdj: formAdj,
      strength: tablePart + formTerm,
      tablePart: tablePart,
      formTerm: formTerm,
    );
  }

  ({
    List<PredictionReason> reasons,
    List<String> notes,
    Completeness completeness,
  })
  _explain(
    PredictionInput input,
    _TeamMath home,
    _TeamMath away,
    double league,
  ) {
    final reasons = <_Weighted>[];

    // Table factor: rank is display only; ppg (and goal difference) carry
    // the signal and handle different games played (plan ALT-003).
    final tableGap = home.tablePart - away.tablePart;
    final tableFavours = tableGap > 0
        ? PredictionFavour.home
        : tableGap < 0
        ? PredictionFavour.away
        : PredictionFavour.none;
    reasons.add(
      _Weighted(
        PredictionReason(
          factor: 'table',
          favours: tableFavours,
          text:
              '${home.factors.name} are ${_ordinal(home.factors.rank)}, '
              '${away.factors.name} are ${_ordinal(away.factors.rank)} '
              '(${home.ppg.toStringAsFixed(1)} vs '
              '${away.ppg.toStringAsFixed(1)} points per game).',
          numbers: {'homePpg': home.ppg, 'awayPpg': away.ppg},
        ),
        tableGap.abs(),
      ),
    );

    // Form factor. Only comparative when both teams have form; when one is
    // missing the missing note explains it (navigator decision: missing
    // data lives in missingNotes, not here).
    final formGap = home.formTerm - away.formTerm;
    if (home.hasForm && away.hasForm) {
      final favours = formGap > 0
          ? PredictionFavour.home
          : formGap < 0
          ? PredictionFavour.away
          : PredictionFavour.none;
      // The weighting clause is only truthful when BOTH lists are newest
      // first; a mixed pair (one unordered `strForm`) must not claim it.
      final weighted =
          home.factors.formOrdered &&
          away.factors.formOrdered &&
          weights.recencyWeighting;
      final hPoints = _totalPoints(home.factors.form);
      final aPoints = _totalPoints(away.factors.form);
      final clause = weighted ? ', with recent matches counting more' : '';
      // `formGap` is the difference of the season-ppg-relative form terms,
      // not of the raw points, so the text must not claim "better form"
      // while quoting raw points that can say the opposite. It states which
      // side has the higher (more favourable) form term after adjustment.
      final lead = formGap == 0
          ? 'Both teams’ recent form has a similar effect after adjustment'
          : '${_betterName(home, away, formGap)}’s recent form has the more '
                'favourable form adjustment';
      reasons.add(
        _Weighted(
          PredictionReason(
            factor: 'form',
            favours: favours,
            text:
                '$lead: $hPoints of ${3 * home.factors.form.length} points '
                'vs $aPoints of ${3 * away.factors.form.length} points'
                '$clause.',
            numbers: {'homeFormPoints': hPoints, 'awayFormPoints': aPoints},
          ),
          formGap.abs(),
        ),
      );
    } else if (home.hasForm || away.hasForm) {
      final withForm = home.hasForm ? home : away;
      final without = home.hasForm ? away : home;
      final favours = formGap > 0
          ? PredictionFavour.home
          : formGap < 0
          ? PredictionFavour.away
          : PredictionFavour.none;
      reasons.add(
        _Weighted(
          PredictionReason(
            factor: 'form',
            favours: favours,
            text:
                '${withForm.factors.name} have recent form data; '
                '${without.factors.name} do not.',
            numbers: {
              'homeFormPoints': _totalPoints(home.factors.form),
              'awayFormPoints': _totalPoints(away.factors.form),
            },
          ),
          formGap.abs(),
        ),
      );
    }

    // Streak lines: display only, the streak is already part of the
    // weighted form, so it adds nothing to d (contribution 0).
    for (final side in [home, away]) {
      if (!side.hasForm) continue;
      // With an unknown `strForm` order the list is not newest first, so a
      // "last N" streak would be a guess (plan §4.1, RISK-006).
      if (!side.factors.formOrdered) continue;
      final streak = currentStreak(side.factors.form);
      if (streak == 0) continue;
      final result = side.factors.form.first;
      final PredictionFavour favours;
      final verb = switch (result) {
        'W' => 'won',
        'L' => 'lost',
        _ => 'drawn',
      };
      if (result == 'W') {
        favours = side.isHomeSide
            ? PredictionFavour.home
            : PredictionFavour.away;
      } else if (result == 'L') {
        favours = side.isHomeSide
            ? PredictionFavour.away
            : PredictionFavour.home;
      } else {
        favours = PredictionFavour.none;
      }
      reasons.add(
        _Weighted(
          PredictionReason(
            factor: 'streak',
            favours: favours,
            text: '${side.factors.name} have $verb their last $streak.',
            numbers: {'streak': streak},
          ),
          0,
        ),
      );
    }

    // Unknown strForm order: the sequence is not used, so every match
    // counts the same. This changes how d is computed, hence a reason.
    if ((home.usesUnorderedStandingForm || away.usesUnorderedStandingForm)) {
      reasons.add(
        _Weighted(
          const PredictionReason(
            factor: 'formOrder',
            favours: PredictionFavour.none,
            text:
                'Recent form order is unknown for this league, so every '
                'match counts the same.',
          ),
          0,
        ),
      );
    }

    // Home advantage is a fixed documented constant (plan §4.2).
    reasons.add(
      _Weighted(
        const PredictionReason(
          factor: 'home',
          favours: PredictionFavour.home,
          text: 'Home advantage is included as a fixed factor.',
        ),
        weights.homeAdvantage,
      ),
    );

    // Missing-data notes (navigator decision: never inside reasons).
    final notes = <String>[
      if (!home.hasForm) 'Recent form is missing for ${home.factors.name}.',
      if (!away.hasForm) 'Recent form is missing for ${away.factors.name}.',
      if (home.factors.played < 3 || away.factors.played < 3)
        'Early in the season – low confidence.',
    ];

    final completeness = _completeness(home, away);

    // Sort by contribution to d, largest first; ties keep insertion order
    // (Dart's sort is not stable, hence the explicit index tie-break).
    final sorted = [...reasons.asMap().entries]
      ..sort((x, y) {
        final byContribution = y.value.contribution.compareTo(
          x.value.contribution,
        );
        return byContribution != 0 ? byContribution : x.key.compareTo(y.key);
      });
    return (
      reasons: [for (final entry in sorted) entry.value.reason],
      notes: notes,
      completeness: completeness,
    );
  }

  Completeness _completeness(_TeamMath home, _TeamMath away) {
    final bothFull = home.hasForm && away.hasForm;
    if (bothFull &&
        home.factors.form.length >= 3 &&
        away.factors.form.length >= 3) {
      return Completeness.full;
    }
    if (home.hasForm || away.hasForm) return Completeness.partial;
    return Completeness.tableOnly;
  }

  String _betterName(_TeamMath home, _TeamMath away, double formGap) {
    if (formGap < 0) return away.factors.name;
    return home.factors.name;
  }

  /// Largest-remainder rounding so the shown percentages sum to exactly 100
  /// (REQ-003). Remainder ties go to the outcome order (home, draw, away)
  /// and no percentage is ever negative.
  Map<Outcome, int> _displayPercents(double pHome, double pDraw, double pAway) {
    final raw = {
      Outcome.home: pHome.clamp(0.0, 1.0) * 100,
      Outcome.draw: pDraw.clamp(0.0, 1.0) * 100,
      Outcome.away: pAway.clamp(0.0, 1.0) * 100,
    };
    final floors = <Outcome, int>{};
    final fractions = <Outcome, double>{};
    var used = 0;
    for (final outcome in Outcome.values) {
      final value = raw[outcome]!;
      final floor = value.floor();
      floors[outcome] = floor;
      fractions[outcome] = value - floor;
      used += floor;
    }
    var left = 100 - used;
    // Outcomes sorted by largest fractional part, ties by outcome order.
    final order = [...Outcome.values]
      ..sort((x, y) {
        final byFraction = fractions[y]!.compareTo(fractions[x]!);
        return byFraction != 0
            ? byFraction
            : Outcome.values.indexOf(x).compareTo(Outcome.values.indexOf(y));
      });
    while (left > 0) {
      for (final outcome in order) {
        if (left == 0) break;
        floors[outcome] = floors[outcome]! + 1;
        left--;
      }
      // With three outcomes left is at most 2, so one pass suffices; the
      // guard only prevents an infinite loop if that ever changes.
      if (order.isEmpty) break;
    }
    return {
      Outcome.home: floors[Outcome.home]!,
      Outcome.draw: floors[Outcome.draw]!,
      Outcome.away: floors[Outcome.away]!,
    };
  }
}

int _totalPoints(List<String> form) =>
    form.fold(0, (sum, r) => sum + _points(r));

class _TeamMath {
  const _TeamMath({
    required this.factors,
    required this.isHomeSide,
    required this.ppg,
    required this.gdpg,
    required this.formPpg,
    required this.formAdj,
    required this.strength,
    required this.tablePart,
    required this.formTerm,
  });

  final TeamFactors factors;
  final bool isHomeSide;
  final double ppg;
  final double gdpg;
  final double? formPpg;
  final double formAdj;
  final double strength;
  final double tablePart;
  final double formTerm;

  bool get hasForm => factors.form.isNotEmpty;

  bool get usesUnorderedStandingForm =>
      factors.formSource == FormSource.standingsForm && !factors.formOrdered;
}

class _Weighted {
  const _Weighted(this.reason, this.contribution);

  final PredictionReason reason;
  final double contribution;
}
