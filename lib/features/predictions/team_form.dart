import '../../models/fixture.dart';

/// How the letters in `TeamStanding.form` (`strForm`) are ordered.
enum FormOrder { newestFirst, oldestFirst, unknown }

/// The order of the `strForm` letters for TheSportsDB standings.
///
/// TASK-019: set this to [FormOrder.newestFirst] or [FormOrder.oldestFirst]
/// only after comparing `strForm` with derived recent form for at least 5
/// teams in 2 leagues on a Premium key, and record the evidence in
/// `plan/feature-match-predictions-1.md`. While it is [FormOrder.unknown]
/// the letter order is not used: `parseStandingForm` reports the results as
/// unordered and the calculator falls back to plain counts.
///
/// The test in `test/features/predictions/team_form_test.dart` pins this
/// value on purpose: if TASK-019 changes it, that test (and the plan note)
/// must be updated with the evidence in the same change.
const FormOrder standingsFormOrder = FormOrder.unknown;

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
  return [for (final f in played.take(limit)) f.resultFor(teamId)!];
}

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
