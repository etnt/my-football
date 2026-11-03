import 'dart:math' as math;

import 'prediction_input.dart';
import 'prediction_result.dart';
import 'team_form.dart';

/// Recency weights for the newest-first form list (see plan §4.1). Only the
/// first `n` are used for `n` results.
const List<double> defaultRecencyWeights = [1.0, 0.9, 0.8, 0.7, 0.6];

/// Constants for the prediction formula (plan §4). Versioned so they can be
/// tuned and back-tested (TASK-024).
///
/// The defaults are formula v1.2 (plan §4.10): the v1.1 constants (§4.8,
/// fitted on 12 league seasons and checked on 12 later ones) plus a small,
/// opponent-adjusted form term. The back-test found no accuracy gain from
/// form, so its weight is kept small enough to cost none either.
class PredictionWeights {
  const PredictionWeights({
    this.shrinkageK = 3,
    this.goalDiffWeight = 0.25,
    this.formWeight = 0.10,
    this.opponentAdjustedForm = true,
    this.recencyWeights = defaultRecencyWeights,
    this.recencyWeighting = true,
    this.homeAdvantage = 0.40,
    this.logisticScale = 0.80,
    this.drawCenter = 0.57,
    this.leagueAvgPpgFallback = 1.37,
    this.version = 'v1.2',
  });

  /// Formula v1.1 (plan §4.8): the table only, form is context only. Kept so
  /// the back-test can compare against it.
  const PredictionWeights.v1_1()
    : shrinkageK = 3,
      goalDiffWeight = 0.25,
      formWeight = 0,
      opponentAdjustedForm = false,
      recencyWeights = defaultRecencyWeights,
      recencyWeighting = true,
      homeAdvantage = 0.40,
      logisticScale = 0.80,
      drawCenter = 0.57,
      leagueAvgPpgFallback = 1.37,
      version = 'v1.1';

  /// The original v1 starting constants (plan §4.1–4.3), kept so the
  /// back-test can compare against them.
  const PredictionWeights.v1({this.recencyWeighting = true})
    : shrinkageK = 3,
      goalDiffWeight = 0.25,
      formWeight = 0.35,
      opponentAdjustedForm = false,
      recencyWeights = defaultRecencyWeights,
      homeAdvantage = 0.20,
      logisticScale = 1.6,
      drawCenter = 0.55,
      leagueAvgPpgFallback = 1.37,
      version = 'v1';

  /// Small-sample shrinkage constant: `ppg = (points + k·L) / (played + k)`.
  final int shrinkageK;
  final double goalDiffWeight;

  /// Weight of the form term in the strength. 0 makes recent form
  /// context-only: it is still shown, but does not change the estimate.
  final double formWeight;

  /// Whether recent form changes the estimate.
  bool get formAffectsEstimate => formWeight != 0;

  /// When true, each recent result is compared with the points expected
  /// against that opponent at that venue (plan §4.10), so a loss to a much
  /// stronger side counts less than a loss to a much weaker one. Needs
  /// [TeamFactors.formMatches] and [PredictionInput.table]; without them the
  /// form is compared with the team's own season average (v1 behaviour).
  final bool opponentAdjustedForm;
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

/// Pure, deterministic prediction calculation (plan §4; formula version in
/// [PredictionWeights.version]).
class PredictionCalculator {
  const PredictionCalculator({this.weights = const PredictionWeights()});

  final PredictionWeights weights;

  PredictionResult calculate(PredictionInput input) {
    final league = input.leagueAvgPpg > 0
        ? input.leagueAvgPpg
        : weights.leagueAvgPpgFallback;

    final home = _factors(input.home, league, input.table, isHomeSide: true);
    final away = _factors(input.away, league, input.table, isHomeSide: false);

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
      // Neither side is clearly ahead: too close to call (tip 1X2). The draw
      // is never the most likely single outcome, so it is not named as the
      // verdict (plan §4.4, §4.9). isSlight stays false: no favourite here.
      verdict = Verdict.tooClose;
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

  /// Table strength: shrunk ppg plus weighted, shrunk goal difference per
  /// game (plan §4.1–4.2).
  double _tableStrength(int points, int played, int goalsDiff, double league) {
    final k = weights.shrinkageK;
    final ppg = (points + k * league) / (played + k);
    return ppg + weights.goalDiffWeight * goalsDiff / (played + k);
  }

  /// Opponent-adjusted form (plan §4.10): for each recent result, the points
  /// taken minus the points expected against that opponent at that venue,
  /// from both table strengths and the home advantage. Recency-weighted and
  /// shrunk by `n / (n + 2)` like the plain form. Null when the opponents
  /// are unknown or any of them is missing from [table]: a partial list
  /// would quote points over a different set of matches than the form.
  ({double residual, double expected})? _opponentAdjusted(
    TeamFactors team,
    double ownStrength,
    double league,
    Map<int, TeamRecord> table,
  ) {
    final matches = team.formMatches;
    if (!weights.opponentAdjustedForm || matches.isEmpty) return null;
    final a = weights.logisticScale;
    final c = weights.drawCenter;
    final useRecency = team.formOrdered && weights.recencyWeighting;
    var weighted = 0.0;
    var weightSum = 0.0;
    var expectedTotal = 0.0;
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final opp = table[m.opponentId];
      if (opp == null) return null;
      final oppStrength = _tableStrength(
        opp.points,
        opp.played,
        opp.goalsDiff,
        league,
      );
      final dd =
          ownStrength -
          oppStrength +
          (m.atHome ? weights.homeAdvantage : -weights.homeAdvantage);
      final pWin = _sigmoid(a * dd - c);
      final pLoss = _sigmoid(-a * dd - c);
      final pDraw = math.max(0.0, 1 - pWin - pLoss);
      final expected = 3 * pWin + pDraw;
      expectedTotal += expected;
      final w = useRecency && i < weights.recencyWeights.length
          ? weights.recencyWeights[i]
          : 1.0;
      weighted += w * (_points(m.result) - expected);
      weightSum += w;
    }
    final n = matches.length;
    return (
      residual: weighted / weightSum * n / (n + 2),
      expected: expectedTotal,
    );
  }

  _TeamMath _factors(
    TeamFactors team,
    double league,
    Map<int, TeamRecord> table, {
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
    final tablePart = ppg + weights.goalDiffWeight * gdpg;
    final adjusted = hasForm
        ? _opponentAdjusted(team, tablePart, league, table)
        : null;
    final formTerm = !hasForm
        ? 0.0
        : weights.formWeight * (adjusted?.residual ?? (formAdj - ppg));

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
      formExpected: adjusted?.expected,
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
    if (!weights.formAffectsEstimate) {
      // v1.1: form is context only (plan §4.8). The line must say so, and
      // it quotes raw points only, so `favours` follows the raw points.
      final context = _formContextReason(home, away);
      if (context != null) reasons.add(_Weighted(context, 0));
    } else if (home.isOpponentAdjusted || away.isOpponentAdjusted) {
      reasons.add(
        _Weighted(_adjustedFormReason(home, away, formGap), formGap.abs()),
      );
    } else if (home.hasForm && away.hasForm) {
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

    // Streak lines: display only (contribution 0). With a form weight the
    // streak is already part of the weighted form; without one (v1.1) form
    // does not enter d at all.
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
    // counts the same. This changes how d is computed, hence a reason. When
    // form does not affect the estimate the note would be noise.
    if (weights.formAffectsEstimate &&
        (home.usesUnorderedStandingForm || away.usesUnorderedStandingForm)) {
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

  /// The form line when at least one side's form is opponent-adjusted
  /// (plan §4.10). Each side quotes its points and, when adjusted, the
  /// points expected against those opponents, so a side can be favoured
  /// with fewer raw points without the text contradicting itself.
  PredictionReason _adjustedFormReason(
    _TeamMath home,
    _TeamMath away,
    double formGap,
  ) {
    String part(_TeamMath side) {
      final points = _totalPoints(side.factors.form);
      final max = 3 * side.factors.form.length;
      final expected = side.formExpected;
      return expected != null
          ? '${side.factors.name} took $points of $max points where '
                '${expected.toStringAsFixed(1)} were expected'
          : '${side.factors.name} took $points of $max points (opponents '
                'unknown, compared with their season average)';
    }

    final sides = [if (home.hasForm) home, if (away.hasForm) away];
    final weighted =
        weights.recencyWeighting && sides.every((s) => s.factors.formOrdered);
    final clause = weighted ? ', with recent matches counting more' : '';
    final favours = formGap > 0
        ? PredictionFavour.home
        : formGap < 0
        ? PredictionFavour.away
        : PredictionFavour.none;
    double round1(double v) => double.parse(v.toStringAsFixed(1));
    return PredictionReason(
      factor: 'form',
      favours: favours,
      text:
          'Recent form against the opponents faced: '
          '${sides.map(part).join('; ')}$clause.',
      numbers: {
        'homeFormPoints': _totalPoints(home.factors.form),
        'awayFormPoints': _totalPoints(away.factors.form),
        if (home.formExpected != null)
          'homeFormExpected': round1(home.formExpected!),
        if (away.formExpected != null)
          'awayFormExpected': round1(away.formExpected!),
      },
    );
  }

  /// The context-only form line (form weight 0). Null when neither team has
  /// form; a single missing side is already covered by the missing notes.
  PredictionReason? _formContextReason(_TeamMath home, _TeamMath away) {
    if (!home.hasForm && !away.hasForm) return null;
    String part(_TeamMath side) {
      final points = _totalPoints(side.factors.form);
      return '${side.factors.name} took $points of '
          '${3 * side.factors.form.length} points';
    }

    final parts = [if (home.hasForm) part(home), if (away.hasForm) part(away)];
    var favours = PredictionFavour.none;
    if (home.hasForm && away.hasForm) {
      // Compare as points per match: the two lists can differ in length.
      final h = _totalPoints(home.factors.form) / home.factors.form.length;
      final a = _totalPoints(away.factors.form) / away.factors.form.length;
      favours = h > a
          ? PredictionFavour.home
          : h < a
          ? PredictionFavour.away
          : PredictionFavour.none;
    }
    return PredictionReason(
      factor: 'form',
      favours: favours,
      text:
          'Recent form, shown for context and not used in the estimate: '
          '${parts.join(', ')}.',
      numbers: {
        'homeFormPoints': _totalPoints(home.factors.form),
        'awayFormPoints': _totalPoints(away.factors.form),
      },
    );
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
    this.formExpected,
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

  /// Points expected over the recent matches against those opponents;
  /// null when the form is not opponent-adjusted.
  final double? formExpected;

  bool get hasForm => factors.form.isNotEmpty;

  bool get isOpponentAdjusted => formExpected != null;

  bool get usesUnorderedStandingForm =>
      factors.formSource == FormSource.standingsForm && !factors.formOrdered;
}

class _Weighted {
  const _Weighted(this.reason, this.contribution);

  final PredictionReason reason;
  final double contribution;
}
