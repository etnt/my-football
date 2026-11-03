import '../../models/fixture.dart';
import 'prediction_input.dart';

/// How the letters in `TeamStanding.form` (`strForm`) are ordered.
enum FormOrder { newestFirst, oldestFirst, unknown }

/// The order of the `strForm` letters for TheSportsDB standings.
///
/// TASK-019 (2026-11-03): **newest first**. Evidence on a Premium key:
/// `strForm` compared with the derived last 5 results for 114 teams in 6
/// tables (EPL and La Liga 2025-26 and 2026-27, Bundesliga 2026-27,
/// Allsvenskan 2026): 99 match newest first, 0 oldest first, 13 read the
/// same both ways, and 1 matches neither because its table row was one
/// match behind the season events. Details in
/// `plan/feature-match-predictions-1.md` (TASK-019).
///
/// The test in `test/features/predictions/team_form_test.dart` pins this
/// value on purpose: a wrong order silently reverses the form curve
/// (RISK-006), so any change needs new evidence in the same change.
const FormOrder standingsFormOrder = FormOrder.newestFirst;

/// The last [limit] results for [teamId] as `W`/`D`/`L`, **newest first**,
/// from finished fixtures with a score in [events].
///
/// When [before] is given, only fixtures that kicked off strictly before
/// that instant (compared in UTC) count, so a cached later result cannot
/// leak into a pre-match calculation. Fixtures with the same kick-off time
/// are ordered by fixture id, newest first.
List<String> recentForm(
  int teamId,
  Iterable<Fixture> events, {
  DateTime? before,
  int limit = 5,
}) => [
  for (final f in recentMatches(teamId, events, before: before, limit: limit))
    f.resultFor(teamId)!,
];

/// The last [limit] finished, scored fixtures for [teamId], **newest
/// first**, with the same cutoff and ordering rules as [recentForm]. Used
/// where the opponent and venue of each result matter (opponent-adjusted
/// form, plan §4.10).
List<Fixture> recentMatches(
  int teamId,
  Iterable<Fixture> events, {
  DateTime? before,
  int limit = 5,
}) {
  final cutoff = before?.toUtc();
  final played =
      <Fixture>[
        for (final e in events)
          if (e.resultFor(teamId) != null &&
              (cutoff == null || e.dateUtc.isBefore(cutoff)))
            e,
      ]..sort((a, b) {
        final byDate = b.dateUtc.compareTo(a.dateUtc);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
  return played.take(limit).toList();
}

/// The [FormMatch] list for [teamId] from [matches] (newest first, as
/// returned by [recentMatches]).
List<FormMatch> formMatchesFor(int teamId, List<Fixture> matches) => [
  for (final f in matches)
    FormMatch(
      result: f.resultFor(teamId)!,
      atHome: f.homeId == teamId,
      opponentId: f.homeId == teamId ? f.awayId : f.homeId,
    ),
];

/// Parses a `strForm` value (`TeamStanding.form`) into W/D/L results.
///
/// Other characters are ignored and case does not matter, but at least one
/// and at most five W/D/L letters must remain; anything else returns null
/// (REQ-006: invalid data is never treated as results).
///
/// When [standingsFormOrder] is known the results are normalized to newest
/// first and `ordered` is true. While it is [FormOrder.unknown] the letters
/// are returned as they appear and `ordered` is false, so callers must not
/// use the sequence.
({List<String> results, bool ordered})? parseStandingForm(String raw) {
  final cleaned = raw.toUpperCase().replaceAll(RegExp('[^WDL]'), '');
  if (cleaned.isEmpty || cleaned.length > 5) return null;
  final results = cleaned.split('');
  return switch (standingsFormOrder) {
    FormOrder.newestFirst => (results: results, ordered: true),
    FormOrder.oldestFirst => (
      results: results.reversed.toList(),
      ordered: true,
    ),
    FormOrder.unknown => (results: results, ordered: false),
  };
}

/// Length of the leading run in a newest-first result list (the current
/// streak). Returns 0 for runs shorter than 2 and for an empty list.
int currentStreak(List<String> newestFirst) {
  if (newestFirst.isEmpty) return 0;
  final first = newestFirst.first;
  var run = 0;
  for (final result in newestFirst) {
    if (result != first) break;
    run++;
  }
  return run >= 2 ? run : 0;
}
