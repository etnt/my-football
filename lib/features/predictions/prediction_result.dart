/// The three match outcomes.
enum Outcome { home, draw, away }

/// The verdict shown in the sheet.
enum Verdict { homeWin, awayWin, tooClose }

/// The verdict as a 1/X/2 tip: `1` home win, `X` draw, `2` away win. A
/// slight favourite gets a double tip that adds the draw, and a match that
/// is too close to call gets `1X2`. A lone `X` is never given: the draw is
/// never the most likely single outcome in this model (plan §4.9).
enum MatchTip {
  home('1', 'Home win'),
  homeOrDraw('1X', 'Home win or draw'),
  open('1X2', 'Any result'),
  drawOrAway('X2', 'Draw or away win'),
  away('2', 'Away win');

  const MatchTip(this.code, this.description);

  /// The short code, e.g. `1X`.
  final String code;

  /// Plain words for the code, for tooltips and screen readers.
  final String description;
}

/// Which side a reason factor favours.
enum PredictionFavour { home, away, none }

/// How complete the input data was.
enum Completeness { full, partial, tableOnly }

/// One line in the "Why this estimate?" list. [text] quotes only numbers
/// from the prediction inputs (REQ-005).
class PredictionReason {
  const PredictionReason({
    required this.factor,
    required this.favours,
    required this.text,
    this.numbers = const {},
  });

  /// Which factor this explains: `table`, `form`, `streak`, `home` or
  /// `formOrder`.
  final String factor;
  final PredictionFavour favours;
  final String text;

  /// The raw input numbers behind [text], e.g. `{'homePpg': 2.1}`.
  final Map<String, num> numbers;
}

/// The deterministic outcome of the prediction calculation.
class PredictionResult {
  const PredictionResult({
    required this.pHome,
    required this.pDraw,
    required this.pAway,
    required this.displayPercents,
    required this.verdict,
    required this.isSlight,
    required this.reasons,
    required this.missingNotes,
    required this.completeness,
    required this.formulaVersion,
  });

  final double pHome;
  final double pDraw;
  final double pAway;

  /// The three percentages as shown, summing to exactly 100 (REQ-003).
  final Map<Outcome, int> displayPercents;

  final Verdict verdict;

  /// True when the winning side is only a slight favourite (gap < 0.20).
  /// Always false for `Verdict.tooClose`.
  final bool isSlight;

  /// The verdict as a 1/X/2 tip. Derived from [verdict] and [isSlight] only,
  /// so the tip and the verdict text can never disagree.
  MatchTip get tip => switch (verdict) {
    Verdict.homeWin => isSlight ? MatchTip.homeOrDraw : MatchTip.home,
    Verdict.awayWin => isSlight ? MatchTip.drawOrAway : MatchTip.away,
    Verdict.tooClose => MatchTip.open,
  };

  /// Reasons sorted by their contribution to the strength difference,
  /// largest first.
  final List<PredictionReason> reasons;

  /// Notes on missing or partial data (missing form, early season).
  final List<String> missingNotes;

  final Completeness completeness;

  /// Version of the weights/formula that produced this result.
  final String formulaVersion;
}

/// Thrown when a prediction cannot be built, e.g. a team is not in the
/// selected league table (REQ-007). The sheet shows the reason as a message.
class PredictionUnavailable implements Exception {
  const PredictionUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'PredictionUnavailable: $reason';
}
