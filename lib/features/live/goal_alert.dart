import '../../models/fixture.dart';

/// A score increase detected between two live-score snapshots.
class GoalAlert {
  const GoalAlert({
    required this.fixture,
    required this.homeDelta,
    required this.awayDelta,
  });

  /// The match after the score changed.
  final Fixture fixture;

  /// How many extra home goals appeared since the last snapshot.
  final int homeDelta;

  /// How many extra away goals appeared since the last snapshot.
  final int awayDelta;

  int get totalGoals => homeDelta + awayDelta;

  /// Short heads-up title.
  String get title => totalGoals > 1 ? 'GOALS!' : 'GOAL!';

  /// Body naming the scoring side(s) and the new scoreline.
  String get body {
    final score =
        '${fixture.homeName} ${fixture.homeGoals ?? 0}-${fixture.awayGoals ?? 0} ${fixture.awayName}';
    if (homeDelta > 0 && awayDelta == 0) {
      return '${fixture.homeName} score — $score';
    }
    if (awayDelta > 0 && homeDelta == 0) {
      return '${fixture.awayName} score — $score';
    }
    return score;
  }
}

/// Compares two livescore snapshots and returns one alert per match whose
/// score went up. New matches (not in [previous]) are ignored so we don't
/// fire for games that were already 1-0 when polling started. Score
/// decreases (e.g. a disallowed goal) are ignored.
List<GoalAlert> detectScoreIncreases(
  List<Fixture> previous,
  List<Fixture> current,
) {
  final prevById = {for (final fixture in previous) fixture.id: fixture};
  final alerts = <GoalAlert>[];

  for (final match in current) {
    final before = prevById[match.id];
    if (before == null) continue;

    final homeDelta = (match.homeGoals ?? 0) - (before.homeGoals ?? 0);
    final awayDelta = (match.awayGoals ?? 0) - (before.awayGoals ?? 0);
    if (homeDelta <= 0 && awayDelta <= 0) continue;

    alerts.add(
      GoalAlert(
        fixture: match,
        homeDelta: homeDelta > 0 ? homeDelta : 0,
        awayDelta: awayDelta > 0 ? awayDelta : 0,
      ),
    );
  }
  return alerts;
}

/// Remembers the last livescore snapshot so we can emit [GoalAlert]s on
/// subsequent polls. The first [ingest] only sets the baseline.
class LiveGoalMonitor {
  List<Fixture>? _baseline;

  /// Ingest a new snapshot. Returns alerts for score increases since the
  /// previous call, or an empty list on the first snapshot / after [reset].
  List<GoalAlert> ingest(List<Fixture> matches) {
    final previous = _baseline;
    _baseline = List<Fixture>.unmodifiable(matches);
    if (previous == null) return const [];
    return detectScoreIncreases(previous, matches);
  }

  /// Drop the baseline (e.g. when the selected league changes).
  void reset() => _baseline = null;
}
