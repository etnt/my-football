/// The three match outcomes.
enum Outcome { home, draw, away }

/// The verdict shown in the sheet.
enum Verdict { homeWin, awayWin, closeDrawLikely }

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
  /// Always false for `Verdict.closeDrawLikely`.
  final bool isSlight;

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
