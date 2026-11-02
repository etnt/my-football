// Tests for the pure-Dart back-test logic (plan §4.7, TASK-024).
//
// The Brier and baseline expectations below are hand-computed; see the
// comments on each test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/predictions/prediction_calculator.dart';
import 'package:my_football/features/predictions/prediction_input.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/models/fixture.dart';

import '../../tool/src/backtest.dart';

Fixture fx(
  int id,
  String day,
  int home,
  int away, {
  int? homeGoals,
  int? awayGoals,
  String? homeName,
  String? awayName,
}) => Fixture(
  id: id,
  dateUtc: DateTime.parse('${day}T15:00:00Z'),
  statusShort: 'FT',
  statusLong: '',
  elapsed: null,
  homeId: home,
  homeName: homeName ?? 'T$home',
  homeLogo: '',
  awayId: away,
  awayName: awayName ?? 'T$away',
  awayLogo: '',
  homeGoals: homeGoals,
  awayGoals: awayGoals,
);

/// Season 1: four teams, two rounds. Round 1 (day 1): A 3-0 B, C 3-0 D.
/// Round 2 (day 8): B 0-3 A, D 0-3 C — both upsets against the argmax pick.
List<Fixture> simpleSeason() => [
  fx(1, '2026-01-01', 1, 2, homeGoals: 3, awayGoals: 0),
  fx(2, '2026-01-01', 3, 4, homeGoals: 3, awayGoals: 0),
  fx(3, '2026-01-08', 2, 1, homeGoals: 0, awayGoals: 3),
  fx(4, '2026-01-08', 4, 3, homeGoals: 0, awayGoals: 3),
];

/// Season 2: crafted so teams 1 and 2 enter the decisive fixture (day 30)
/// with identical points and mirrored form sequences:
/// team 1 newest first W W W L L (rising), team 2 L L W W W (falling).
/// With recency weighting their form terms differ; without it they are equal.
List<Fixture> recencySeason() => [
  // Day 5: team 2 beats team 1 (team 1's oldest L, team 2's oldest W).
  fx(1, '2026-01-05', 2, 1, homeGoals: 1, awayGoals: 0),
  fx(2, '2026-01-05', 3, 4, homeGoals: 1, awayGoals: 0),
  // Day 10: team 1 loses again, team 2 wins again.
  fx(3, '2026-01-10', 1, 3, homeGoals: 0, awayGoals: 1),
  fx(4, '2026-01-10', 2, 4, homeGoals: 2, awayGoals: 0),
  // Day 15: team 1 starts winning, team 2 keeps winning.
  fx(5, '2026-01-15', 1, 4, homeGoals: 3, awayGoals: 0),
  fx(6, '2026-01-15', 3, 2, homeGoals: 0, awayGoals: 1),
  // Day 20: team 1 wins again, team 2 loses its first.
  fx(7, '2026-01-20', 1, 3, homeGoals: 2, awayGoals: 0),
  fx(8, '2026-01-20', 4, 2, homeGoals: 0, awayGoals: 1),
  // Day 25: team 1 completes W W W, team 2 completes L L.
  fx(9, '2026-01-25', 1, 2, homeGoals: 1, awayGoals: 0),
  fx(10, '2026-01-25', 4, 3, homeGoals: 1, awayGoals: 0),
  // Day 30, the decisive fixture: team 1 hosts team 2 and loses 0-1.
  fx(11, '2026-01-30', 1, 2, homeGoals: 0, awayGoals: 1),
];

void main() {
  group('buildTable', () {
    test('accumulates W/D/L, points, goals and ranks deterministically', () {
      final events = [
        fx(1, '2026-01-01', 1, 5, homeGoals: 2, awayGoals: 0),
        fx(2, '2026-01-01', 3, 6, homeGoals: 4, awayGoals: 2),
        // Team 10 and team 20 are identical on every metric, including the
        // name — only the team id breaks the tie.
        fx(3, '2026-01-01', 10, 7, homeGoals: 1, awayGoals: 0,
          homeName: 'Team A'),
        fx(4, '2026-01-01', 20, 8, homeGoals: 1, awayGoals: 0,
          homeName: 'Team A'),
        // A drawn game for variety.
        fx(5, '2026-01-02', 5, 6, homeGoals: 1, awayGoals: 1),
      ];
      final table = buildTable(events);

      expect(table.teamCount, 8);
      // T3: 3 pts, gd +2, gf 4 — beats T1 (3 pts, gd +2, gf 2) on goals for.
      expect(table.rowFor(3)!.rank, 1);
      expect(table.rowFor(1)!.rank, 2);
      // Identical rows: id 10 before id 20.
      expect(table.rowFor(10)!.rank, 3);
      expect(table.rowFor(20)!.rank, 4);
      // T6: 0 pts, gd -2, gf 3 — beats T5 (gf 1) and T7 (gf 0) on goals for.
      expect(table.rowFor(6)!.rank, 5);
      expect(table.rowFor(5)!.rank, 6);
      expect(table.rowFor(7)!.rank, 7);
      expect(table.rowFor(8)!.rank, 8);

      final t1 = table.rowFor(1)!;
      expect(t1.played, 1);
      expect(t1.win, 1);
      expect(t1.draw, 0);
      expect(t1.lose, 0);
      expect(t1.points, 3);
      expect(t1.goalsFor, 2);
      expect(t1.goalsAgainst, 0);
      expect(t1.goalsDiff, 2);

      final t5 = table.rowFor(5)!;
      expect(t5.played, 2);
      expect(t5.lose, 1);
      expect(t5.draw, 1);
      expect(t5.points, 1);
      expect(t5.goalsFor, 1);
      expect(t5.goalsAgainst, 3);

      // League average ppg: points T1 3, T3 3, T10 3, T20 3, T5 1, T6 1,
      // T7 0, T8 0 = 14 over 10 team-games (2 per fixture, 5 fixtures).
      expect(table.leagueAvgPpg, closeTo(14 / 10, 1e-9));
    });

    test('strict cutoff: fixtures at or after the cutoff are excluded', () {
      final target = DateTime.parse('2026-01-08T15:00:00Z');
      final events = [
        fx(1, '2026-01-01', 1, 2, homeGoals: 3, awayGoals: 0),
        // Same instant as the target fixture: must stay out (strict isBefore).
        fx(2, '2026-01-08', 1, 4, homeGoals: 2, awayGoals: 1),
        // After the target fixture: must stay out.
        fx(3, '2026-01-09', 1, 4, homeGoals: 5, awayGoals: 0),
      ];
      final table = buildTable(events, before: target);

      final a = table.rowFor(1)!;
      expect(a.played, 1, reason: 'only the day-1 fixture may count');
      expect(a.win, 1);
      expect(a.goalsFor, 3);
      expect(a.goalsAgainst, 0);
      // Teams 3 and 4 have no finished fixture before the cutoff.
      expect(table.rowFor(4), isNull);
      expect(table.rowFor(3), isNull);
    });
  });

  group('buildInput', () {
    test('round 1: both teams have no table row, so the input is null', () {
      final events = simpleSeason();
      final table = buildTable(events, before: events.first.dateUtc);
      expect(buildInput(events.first, events, table), isNull);
    });

    test('a team absent from the rebuilt table makes the input null', () {
      final events = simpleSeason();
      final table = buildTable(events, before: events[2].dateUtc);
      // Team 9 has not played yet, so it has no table row.
      final ghost = fx(99, '2026-01-08', 1, 9, homeGoals: 0, awayGoals: 0);
      expect(buildInput(ghost, events, table), isNull);
    });

    test('factors come from the table and the season-event form', () {
      final events = simpleSeason();
      final round2 = events[2]; // B 0-3 A on day 8.
      final table = buildTable(events, before: round2.dateUtc);
      final input = buildInput(round2, events, table)!;

      // Table before round 2: T1/T3 on 3 pts (T1 first by name), T2/T4 on 0.
      expect(input.home.teamId, 2);
      expect(input.home.rank, 3);
      expect(input.home.played, 1);
      expect(input.home.points, 0);
      expect(input.home.goalsDiff, -3);
      expect(input.home.form, ['L']);
      expect(input.home.formOrdered, isTrue);
      expect(input.home.formSource, FormSource.seasonEvents);

      expect(input.away.teamId, 1);
      expect(input.away.rank, 1);
      expect(input.away.points, 3);
      expect(input.away.goalsDiff, 3);
      expect(input.away.form, ['W']);

      // Total points 6 over 4 games.
      expect(input.leagueAvgPpg, closeTo(1.5, 1e-9));
    });
  });

  group('metrics (hand-computed)', () {
    test('brierScore', () {
      expect(
        brierScore(
          pHome: 0.5,
          pDraw: 0.25,
          pAway: 0.25,
          actual: Outcome.home,
        ),
        closeTo(0.375, 1e-9), // 0.25 + 0.0625 + 0.0625
      );
      expect(
        brierScore(
          pHome: 0.5,
          pDraw: 0.25,
          pAway: 0.25,
          actual: Outcome.draw,
        ),
        closeTo(0.875, 1e-9), // 0.25 + 0.5625 + 0.0625
      );
      expect(
        brierScore(pHome: 1, pDraw: 0, pAway: 0, actual: Outcome.home),
        closeTo(0, 1e-9),
      );
    });

    test('argmax breaks ties home -> draw -> away', () {
      expect(
        argmaxOutcome(pHome: 0.4, pDraw: 0.4, pAway: 0.2),
        Outcome.home,
      );
      expect(
        argmaxOutcome(pHome: 0.2, pDraw: 0.4, pAway: 0.4),
        Outcome.draw,
      );
      expect(
        argmaxOutcome(pHome: 0.2, pDraw: 0.3, pAway: 0.5),
        Outcome.away,
      );
      expect(
        argmaxOutcome(pHome: 0.3, pDraw: 0.3, pAway: 0.3),
        Outcome.home,
      );
    });

    test('computeBaseline on four outcomes', () {
      final b = computeBaseline([
        Outcome.home,
        Outcome.home,
        Outcome.draw,
        Outcome.away,
      ]);
      expect(b.home, closeTo(0.5, 1e-9));
      expect(b.draw, closeTo(0.25, 1e-9));
      expect(b.away, closeTo(0.25, 1e-9));
      expect(b.accuracy, closeTo(0.5, 1e-9));
      // Home fixture: 0.375; draw and away fixtures: 0.875 each.
      // Mean = (0.375 + 0.375 + 0.875 + 0.875) / 4 = 0.625.
      expect(b.brier, closeTo(0.625, 1e-9));
    });

    test('computeBaseline on an empty set stays finite', () {
      final b = computeBaseline([]);
      expect(b.home, 0);
      expect(b.draw, 0);
      expect(b.away, 0);
      expect(b.accuracy, 0);
      expect(b.brier, 0);
      expect(b.brier.isNaN, isFalse);
    });
  });

  group('runBacktest', () {
    test('round 1 is skipped, round 2 is scored, baseline uses the scored set',
        () {
      final report = runBacktest(events: simpleSeason());

      expect(report.n, 2);
      expect(report.skipped, 2);
      // The strong team is away in both round-2 fixtures, so the argmax pick
      // is the away win and both predictions are right (the tiny set is
      // rigged; the point is that the plumbing scores it correctly).
      expect(report.correct, 2);
      expect(report.accuracy, 1);
      expect(report.brier, greaterThan(0));
      // v1.1 is deliberately less confident than v1 (plan §4.8), so even two
      // right calls keep a clearly non-zero Brier; well under the 0.667 of a
      // uniform 1/3 guess.
      expect(report.brier, lessThan(0.5));
      // The scored set holds two away wins, so the in-sample baseline
      // ("always away") is perfect here — exactly why it is labelled
      // in-sample and computed on the same scored set, not all events.
      expect(report.baselineHomeRate, 0);
      expect(report.baselineDrawRate, 0);
      expect(report.baselineAwayRate, 1);
      expect(report.baselineAccuracy, 1);
      expect(report.baselineBrier, 0);
      expect(report.formulaVersion, 'v1.1');
    });

    test('an empty season gives n = 0 and no NaN', () {
      final report = runBacktest(events: const []);
      expect(report.n, 0);
      expect(report.skipped, 0);
      expect(report.accuracy.isNaN, isFalse);
      expect(report.brier.isNaN, isFalse);
      expect(report.baselineBrier.isNaN, isFalse);
    });

    test('recency weighting changes the Brier score on a crafted season', () {
      final events = recencySeason();
      // v1 constants: the only formula where form (and so the weighting)
      // changes the estimate.
      final weighted = runBacktest(
        events: events,
        weights: const PredictionWeights.v1(),
      );
      final plain = runBacktest(
        events: events,
        weights: const PredictionWeights.v1(recencyWeighting: false),
      );

      // Day-5 fixtures are skipped (no table yet); days 10-30 are scored.
      expect(weighted.n, 9);
      expect(weighted.skipped, 2);
      expect(plain.n, weighted.n);
      expect(plain.skipped, weighted.skipped);
      // Identical table stats, mirrored form sequences: only the weighting
      // separates the two runs, so the Brier scores must differ.
      expect(weighted.brier, isNot(closeTo(plain.brier, 1e-9)));
      expect(weighted.formulaVersion, 'v1');
      expect(plain.formulaVersion, 'v1');
    });

    test('form is context only in v1.1: the weighting changes nothing', () {
      final events = recencySeason();
      final on = runBacktest(events: events);
      final off = runBacktest(
        events: events,
        weights: const PredictionWeights(recencyWeighting: false),
      );
      expect(on.formAffectsEstimate, isFalse);
      expect(on.brier, off.brier);
    });

    test('compareBacktests runs the shipped formula against v1', () {
      final (:current, :v1) = compareBacktests(recencySeason());
      expect(current.formulaVersion, 'v1.1');
      expect(v1.formulaVersion, 'v1');
      expect(current.n, v1.n);
    });

    test('the run is deterministic', () {
      final events = recencySeason();
      final a = runBacktest(events: events);
      final b = runBacktest(events: events);
      expect(a.n, b.n);
      expect(a.skipped, b.skipped);
      expect(a.correct, b.correct);
      expect(a.brier, b.brier);
      expect(a.baselineBrier, b.baselineBrier);
    });
  });

  group('formatReport', () {
    test('n = 0 prints "not enough data" and no metrics', () {
      final report = runBacktest(events: const []);
      final text = formatReport(report);
      expect(text, contains('not enough data'));
      expect(text.contains('Brier'), isFalse);
      expect(text.contains('accuracy'), isFalse);
      expect(text.contains('NaN'), isFalse);
    });

    test('a full report carries counts, metrics, baseline and the warning',
        () {
      final text = formatReport(
        runBacktest(events: simpleSeason()),
      );
      expect(text, contains('formula v1.1, form is context only'));
      expect(text.contains('recencyWeighting'), isFalse);
      expect(text, contains('n = 2'));
      expect(text, contains('argmax accuracy'));
      expect(text, contains('Brier score'));
      expect(text, contains('in-sample baseline'));
      expect(text, contains('too small to support a tuning decision'));
      // CON-003: no team names in aggregate output.
      expect(text.contains('T1'), isFalse);
      expect(text.contains('T2'), isFalse);
    });

    test('a formula where form counts reports the recency setting', () {
      final text = formatReport(
        runBacktest(
          events: simpleSeason(),
          weights: const PredictionWeights.v1(),
        ),
      );
      expect(text, contains('formula v1, recencyWeighting = true'));
    });
  });

  group('parseArgs', () {
    test('parses league, season and the env key', () {
      final args = parseArgs(
        ['--league=4328', '--season=2025-2026'],
        {'SPORTSDB_API_KEY': ' premium-key '},
      );
      expect(args.leagueId, 4328);
      expect(args.season, '2025-2026');
      expect(args.apiKey, 'premium-key');
      expect(args.help, isFalse);
    });

    test('a blank or missing env key is null', () {
      expect(
        parseArgs(const [], {'SPORTSDB_API_KEY': '   '}).apiKey,
        isNull,
      );
      expect(parseArgs(const [], {}).apiKey, isNull);
    });

    test('--help is recognised', () {
      expect(parseArgs(['--help'], const {}).help, isTrue);
      expect(parseArgs(['-h'], const {}).help, isTrue);
    });

    test('unknown arguments and malformed values are rejected', () {
      expect(
        () => parseArgs(['--verbose'], const {}),
        throwsArgumentError,
      );
      expect(
        () => parseArgs(['--league=abc'], const {}),
        throwsArgumentError,
      );
      expect(
        () => parseArgs(['--season=  '], const {}),
        throwsArgumentError,
      );
    });
  });

  test('the CLI never reads a key file and the tool is Flutter-free', () {
    final cli = File('tool/predictions_backtest.dart').readAsStringSync();
    expect(cli.contains('API-KEY'), isFalse);
    expect(cli.contains('File('), isFalse);
    // avoid_print: only stdout/stderr writes, never a bare print call.
    // multiLine is required: without it `^` only matches the very start of
    // the file and the check would pass no matter what the file contains.
    expect(
      RegExp(r'^\s*print\(', multiLine: true).allMatches(cli),
      isEmpty,
    );

    // Flutter-free means the whole transitive chain, not just backtest.dart's
    // own imports: walk both entry points. dart:io is fine (console tool); the
    // only non-Flutter third-party import in the chain is dio.
    for (final entry in [
      'tool/src/backtest.dart',
      'tool/predictions_backtest.dart',
    ]) {
      for (final path in _transitiveDartSources(entry)) {
        expect(
          RegExp(r"^import '(package:flutter|dart:ui)", multiLine: true)
              .allMatches(File(path).readAsStringSync()),
          isEmpty,
          reason: '$path must not import Flutter (reached from $entry)',
        );
      }
    }
  });
}

/// [entry] plus every repo file it imports, transitively ([package:my_football]
/// and relative imports; `dart:` and third-party packages are not followed).
Set<String> _transitiveDartSources(String entry) {
  final seen = <String>{};
  final pending = <String>[entry];
  while (pending.isNotEmpty) {
    final file = File(pending.removeLast()).absolute;
    if (!seen.add(file.path)) continue;
    for (final match in RegExp(r"^import '([^']+)';", multiLine: true)
        .allMatches(file.readAsStringSync())) {
      final uri = match.group(1)!;
      if (uri.startsWith('package:my_football/')) {
        pending.add('lib/${uri.substring('package:my_football/'.length)}');
      } else if (!uri.startsWith('package:') && !uri.startsWith('dart:')) {
        pending.add(file.parent.uri.resolve(uri).toFilePath());
      }
    }
  }
  return seen;
}
