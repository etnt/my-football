import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/predictions/prediction_calculator.dart';
import 'package:my_football/features/predictions/prediction_input.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/models/fixture.dart';

/// Builds a team whose shrunk ppg hits a chosen value exactly.
///
/// With `leagueAvgPpg = 1.0` and `shrinkageK = 3`:
/// `ppg = (points + 3) / (played + 3)`, so `points = ppg·(played + 3) − 3`.
TeamFactors _team({
  int id = 1,
  String name = 'Home',
  int rank = 1,
  int played = 7,
  required double ppg,
  int goalsDiff = 0,
  List<String> form = const [],
  bool formOrdered = false,
  FormSource formSource = FormSource.none,
}) {
  return TeamFactors(
    teamId: id,
    name: name,
    rank: rank,
    played: played,
    points: (ppg * (played + 3) - 3).round(),
    goalsDiff: goalsDiff,
    form: form,
    formOrdered: formOrdered,
    formSource: formSource,
  );
}

Fixture _fixture() => Fixture(
  id: 42,
  dateUtc: DateTime.utc(2025, 9, 20, 14),
  statusShort: 'NS',
  statusLong: '',
  elapsed: null,
  homeId: 1,
  homeName: 'Home',
  homeLogo: '',
  awayId: 2,
  awayName: 'Away',
  awayLogo: '',
  homeGoals: null,
  awayGoals: null,
);

PredictionInput _input({
  required TeamFactors home,
  required TeamFactors away,
  double leagueAvgPpg = 1.0,
}) {
  return PredictionInput(
    fixture: _fixture(),
    home: home,
    away: away,
    leagueAvgPpg: leagueAvgPpg,
  );
}

PredictionResult _run(
  TeamFactors home,
  TeamFactors away, {
  double leagueAvgPpg = 1.0,
}) {
  return const PredictionCalculator().calculate(
    _input(home: home, away: away, leagueAvgPpg: leagueAvgPpg),
  );
}

void main() {
  group('probabilities', () {
    test('sum to 1 for several inputs', () {
      final cases = [
        _run(_team(ppg: 1.5), _team(id: 2, name: 'Away', ppg: 1.5)),
        _run(_team(ppg: 2.3), _team(id: 2, name: 'Away', ppg: 1.5)),
        _run(
          _team(
            ppg: 1.5,
            form: const ['W', 'W', 'W', 'L', 'L'],
            formOrdered: true,
            formSource: FormSource.seasonEvents,
          ),
          _team(id: 2, name: 'Away', ppg: 1.5),
        ),
      ];
      for (final result in cases) {
        expect(result.pHome + result.pDraw + result.pAway, closeTo(1, 1e-9));
      }
    });

    test('display percentages sum to exactly 100 for several inputs', () {
      final cases = [
        _run(_team(ppg: 1.5), _team(id: 2, name: 'Away', ppg: 1.5)),
        _run(_team(ppg: 2.3), _team(id: 2, name: 'Away', ppg: 1.5)),
        _run(_team(ppg: 1.0), _team(id: 2, name: 'Away', ppg: 2.3)),
        _run(
          _team(
            ppg: 1.5,
            form: const ['L', 'L', 'W', 'W', 'W'],
            formOrdered: true,
            formSource: FormSource.seasonEvents,
          ),
          _team(
            id: 2,
            name: 'Away',
            ppg: 1.5,
            form: const ['W', 'D', 'D'],
            formOrdered: true,
            formSource: FormSource.seasonEvents,
          ),
        ),
      ];
      for (final result in cases) {
        final sum = result.displayPercents.values.fold<int>(0, (a, b) => a + b);
        expect(sum, 100);
        for (final p in result.displayPercents.values) {
          expect(p, greaterThanOrEqualTo(0));
        }
      }
    });

    test('match the plan §4.3 reference values (±1 point)', () {
      // d = ppgHome − ppgAway + 0.20 with missing form and no goal diff.
      // ppg steps of 0.1 come from played = 7 and leagueAvgPpg = 1.0.
      // d = 0.0: away side better by exactly H.
      var r = _run(_team(ppg: 1.4), _team(id: 2, name: 'Away', ppg: 1.6));
      expect(r.displayPercents[Outcome.home], closeTo(37, 1));
      expect(r.displayPercents[Outcome.draw], closeTo(27, 1));
      expect(r.displayPercents[Outcome.away], closeTo(37, 1));
      // d = 0.2: equal teams, only home advantage.
      r = _run(_team(ppg: 1.5), _team(id: 2, name: 'Away', ppg: 1.5));
      expect(r.displayPercents[Outcome.home], closeTo(44, 1));
      expect(r.displayPercents[Outcome.draw], closeTo(26, 1));
      expect(r.displayPercents[Outcome.away], closeTo(30, 1));
      // d = 0.5: clear home favourite.
      r = _run(_team(ppg: 1.8), _team(id: 2, name: 'Away', ppg: 1.5));
      expect(r.displayPercents[Outcome.home], closeTo(56, 1));
      expect(r.displayPercents[Outcome.draw], closeTo(23, 1));
      expect(r.displayPercents[Outcome.away], closeTo(21, 1));
      // d = 1.0: top vs bottom.
      r = _run(_team(ppg: 2.3), _team(id: 2, name: 'Away', ppg: 1.5));
      expect(r.displayPercents[Outcome.home], closeTo(74, 1));
      expect(r.displayPercents[Outcome.draw], closeTo(16, 1));
      expect(r.displayPercents[Outcome.away], closeTo(10, 1));
    });
  });

  group('verdict', () {
    test('equal teams: home win, slight favourite', () {
      final r = _run(_team(ppg: 1.5), _team(id: 2, name: 'Away', ppg: 1.5));
      expect(r.verdict, Verdict.homeWin);
      expect(r.isSlight, isTrue);
    });

    test('d ≈ 0: close, draw likely, never "slight"', () {
      final r = _run(_team(ppg: 1.4), _team(id: 2, name: 'Away', ppg: 1.6));
      expect(r.verdict, Verdict.closeDrawLikely);
      expect(r.isSlight, isFalse);
    });

    test('strong home favourite: home win, not slight', () {
      final r = _run(_team(ppg: 1.8), _team(id: 2, name: 'Away', ppg: 1.5));
      expect(r.verdict, Verdict.homeWin);
      expect(r.isSlight, isFalse);
    });

    test('with H = 0, swapping the teams mirrors the result', () {
      const weights = PredictionWeights(homeAdvantage: 0);
      final home = _team(ppg: 2.0);
      final away = _team(id: 2, name: 'Away', ppg: 1.4);
      final forward = PredictionCalculator(
        weights: weights,
      ).calculate(_input(home: home, away: away));
      final swapped = PredictionCalculator(
        weights: weights,
      ).calculate(_input(home: away, away: home));
      expect(
        swapped.displayPercents[Outcome.home],
        forward.displayPercents[Outcome.away],
      );
      expect(
        swapped.displayPercents[Outcome.away],
        forward.displayPercents[Outcome.home],
      );
      expect(
        swapped.displayPercents[Outcome.draw],
        forward.displayPercents[Outcome.draw],
      );
      expect(swapped.verdict, Verdict.awayWin);
      expect(forward.verdict, Verdict.homeWin);
    });
  });

  group('small samples and missing data', () {
    test('played = 0 does not divide by zero (ppg falls back to league)', () {
      final r = _run(
        _team(played: 0, ppg: 1.0), // points become 10·1−3=7, ignored: ppg
        _team(id: 2, name: 'Away', played: 0, ppg: 1.0),
      );
      // Both teams at the league average → only home advantage remains.
      expect(r.displayPercents[Outcome.home], closeTo(44, 1));
      expect(r.verdict, Verdict.homeWin);
    });

    test('leagueAvgPpg ≤ 0 falls back to the 1.37 constant', () {
      // One team has played nothing (ppg = league average, whatever it is);
      // the other sits on 1.5 from 7 games. With the fallback 1.37 the two
      // strengths nearly cancel (d ≈ −0.04 → close, draw likely); with the
      // raw 1.0 the away side would clearly win instead.
      const calculator = PredictionCalculator();
      final r = calculator.calculate(
        PredictionInput(
          fixture: _fixture(),
          home: _team(played: 0, ppg: 1.0),
          away: _team(id: 2, name: 'Away', ppg: 1.5),
          leagueAvgPpg: 0,
        ),
      );
      expect(r.verdict, Verdict.closeDrawLikely);
    });

    test('missing form never lowers strength below table-only strength', () {
      // ppg = 1.0 exactly; form [D, D, D] has formPpg = 1.0, so its shrunk
      // formAdj equals ppg and the form term is zero — identical to missing
      // form. Missing data must never be treated as a loss (REQ-006).
      final withoutForm = _run(
        _team(ppg: 1.0),
        _team(id: 2, name: 'Away', ppg: 1.0),
      );
      final neutralForm = _run(
        _team(
          ppg: 1.0,
          form: const ['D', 'D', 'D'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
        _team(id: 2, name: 'Away', ppg: 1.0),
      );
      expect(neutralForm.pHome, withoutForm.pHome);
      expect(neutralForm.pDraw, withoutForm.pDraw);
      expect(neutralForm.pAway, withoutForm.pAway);
      // The home team has form, the away team does not: partial.
      expect(neutralForm.completeness, Completeness.partial);
      expect(withoutForm.completeness, Completeness.tableOnly);
    });
  });

  group('recency weighting', () {
    test('WWWLL scores 2.03 and LLWWW scores 1.58 (newest first)', () {
      const ordered = true;
      const weighted = true;
      expect(
        formPpg(
          const ['W', 'W', 'W', 'L', 'L'],
          ordered: ordered,
          recencyWeighting: weighted,
        ),
        closeTo(2.03, 0.01),
      );
      expect(
        formPpg(
          const ['L', 'L', 'W', 'W', 'W'],
          ordered: ordered,
          recencyWeighting: weighted,
        ),
        closeTo(1.58, 0.01),
      );
    });

    test('unordered form or weighting off gives the plain 1.8 for both', () {
      for (final form in const [
        ['W', 'W', 'W', 'L', 'L'],
        ['L', 'L', 'W', 'W', 'W'],
      ]) {
        expect(
          formPpg(form, ordered: false, recencyWeighting: true),
          closeTo(1.8, 0.001),
        );
        expect(
          formPpg(form, ordered: true, recencyWeighting: false),
          closeTo(1.8, 0.001),
        );
      }
    });

    test(
      'the rising team gets a higher home-win chance than the falling one',
      () {
        PredictionResult run(List<String> form) => _run(
          _team(
            ppg: 1.5,
            form: form,
            formOrdered: true,
            formSource: FormSource.seasonEvents,
          ),
          _team(id: 2, name: 'Away', ppg: 1.5),
        );
        final rising = run(const ['W', 'W', 'W', 'L', 'L']);
        final falling = run(const ['L', 'L', 'W', 'W', 'W']);
        expect(rising.pHome, greaterThan(falling.pHome));
        // All else equal, the difference is small (gentle weights).
        expect(rising.pHome - falling.pHome, lessThan(0.06));
      },
    );
  });

  group('streaks', () {
    test(
      'streak lines appear for runs ≥ 2 and do not change probabilities',
      () {
        // Same weighted formPpg (8.1 / 4 = 2.025), different streaks:
        // WWWLL has a 3-win streak, WDWLW has no leading run ≥ 2.
        PredictionResult run(List<String> form) => _run(
          _team(
            ppg: 1.5,
            form: form,
            formOrdered: true,
            formSource: FormSource.seasonEvents,
          ),
          _team(id: 2, name: 'Away', ppg: 1.5),
        );
        final winStreak = run(const ['W', 'W', 'W', 'L', 'L']);
        final noStreak = run(const ['W', 'D', 'W', 'L', 'W']);
        expect(winStreak.pHome, noStreak.pHome);
        expect(winStreak.pDraw, noStreak.pDraw);
        expect(winStreak.pAway, noStreak.pAway);

        expect(
          winStreak.reasons.any(
            (r) =>
                r.factor == 'streak' &&
                r.text == 'Home have won their last 3.' &&
                r.favours == PredictionFavour.home,
          ),
          isTrue,
        );
        expect(noStreak.reasons.any((r) => r.factor == 'streak'), isFalse);
      },
    );

    test('no streak line when the form order is unknown', () {
      // A leading run in an unordered `strForm` list is not a real "last N"
      // streak: the letters may be oldest first (plan §4.1, RISK-006).
      final r = _run(
        _team(
          ppg: 1.5,
          form: const ['W', 'W', 'L'],
          formOrdered: false,
          formSource: FormSource.standingsForm,
        ),
        _team(id: 2, name: 'Away', ppg: 1.5),
      );
      expect(r.reasons.any((r) => r.factor == 'streak'), isFalse);
    });

    test('a losing streak favours the opponent', () {
      final r = _run(
        _team(ppg: 1.5),
        _team(
          id: 2,
          name: 'Away',
          ppg: 1.5,
          form: const ['L', 'L', 'W'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
      );
      expect(
        r.reasons.any(
          (r) =>
              r.factor == 'streak' &&
              r.text == 'Away have lost their last 2.' &&
              r.favours == PredictionFavour.home,
        ),
        isTrue,
      );
    });
  });

  group('reasons', () {
    test('quote only numbers from the inputs', () {
      final r = _run(
        _team(name: 'Arsenal', rank: 3, ppg: 2.1),
        _team(id: 2, name: 'Fulham', rank: 12, ppg: 1.3),
      );
      final table = r.reasons.firstWhere((r) => r.factor == 'table');
      expect(
        table.text,
        'Arsenal are 3rd, Fulham are 12th (2.1 vs 1.3 points per game).',
      );
      expect(table.favours, PredictionFavour.home);
      expect(table.numbers['homePpg'], closeTo(2.1, 0.001));
      expect(table.numbers['awayPpg'], closeTo(1.3, 0.001));

      final homeAdvantage = r.reasons.firstWhere((r) => r.factor == 'home');
      expect(
        homeAdvantage.text,
        'Home advantage is included as a fixed factor.',
      );
    });

    test('form reason compares points and mentions weighting when used', () {
      final r = _run(
        _team(
          name: 'Arsenal',
          ppg: 1.5,
          form: const ['W', 'W', 'W', 'L', 'L'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
        _team(
          id: 2,
          name: 'Fulham',
          ppg: 1.5,
          form: const ['L', 'L', 'D', 'D', 'D'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
      );
      final form = r.reasons.firstWhere((r) => r.factor == 'form');
      expect(
        form.text,
        'Arsenal’s recent form has the more favourable form adjustment: '
        '9 of 15 points vs 3 of 15 points, with recent matches counting '
        'more.',
      );
      expect(form.favours, PredictionFavour.home);
    });

    test('form reason does not contradict the raw points it quotes', () {
      // Home is much stronger over the season (ppg 3.0 vs 1.0) but in a
      // slump (WWWDL, 10 pts) while away is rising (WWLLL, 6 pts). The raw
      // points favour home, yet the form term favours away — the old "have
      // the better recent form" wording contradicted its own numbers.
      final r = _run(
        _team(
          ppg: 3.0,
          form: const ['W', 'W', 'W', 'D', 'L'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
        _team(
          id: 2,
          name: 'Fulham',
          ppg: 1.0,
          form: const ['W', 'W', 'L', 'L', 'L'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
      );
      final form = r.reasons.firstWhere((r) => r.factor == 'form');
      expect(form.favours, PredictionFavour.away);
      expect(
        form.text,
        'Fulham’s recent form has the more favourable form adjustment: '
        '10 of 15 points vs 6 of 15 points, with recent matches counting '
        'more.',
      );
      expect(form.text, isNot(contains('better recent form')));
    });

    test('form reason stays neutral when both form terms are negative', () {
      // Arsenal are strong (ppg 3.0) but take 6 of 15 points, so their form
      // ppg is 1.2 and formTerm ≈ 0.35 · (12/7 − 3) ≈ −0.45. Fulham are
      // weaker (ppg 2.0) and take 3 of 15, so form ppg is 0.6 and formTerm ≈
      // 0.35 · (1.0 − 2.0) ≈ −0.35. Both terms are negative; away is only
      // less negative, so the text must not say their form "lifts" the
      // estimate.
      final r = _run(
        _team(
          name: 'Arsenal',
          ppg: 3.0,
          form: const ['L', 'L', 'W', 'W', 'L'], // 6 points
        ),
        _team(
          id: 2,
          name: 'Fulham',
          ppg: 2.0,
          form: const ['D', 'D', 'D', 'L', 'L'], // 3 points
        ),
      );
      final form = r.reasons.firstWhere((r) => r.factor == 'form');
      expect(form.favours, PredictionFavour.away);
      expect(
        form.text,
        'Fulham’s recent form has the more favourable form adjustment: '
        '6 of 15 points vs 3 of 15 points.',
      );
      expect(form.text, isNot(contains('lifts')));
    });

    test('unordered source B adds the order note', () {
      final r = _run(
        _team(
          ppg: 1.5,
          form: const ['W', 'W', 'L'],
          formOrdered: false,
          formSource: FormSource.standingsForm,
        ),
        _team(
          id: 2,
          name: 'Away',
          ppg: 1.5,
          form: const ['D', 'W', 'L'],
          formOrdered: false,
          formSource: FormSource.standingsForm,
        ),
      );
      expect(
        r.reasons.any(
          (r) =>
              r.factor == 'formOrder' &&
              r.text ==
                  'Recent form order is unknown for this league, so every '
                      'match counts the same.',
        ),
        isTrue,
      );
      // Ordered season-event form adds no order note.
      final ordered = _run(
        _team(
          ppg: 1.5,
          form: const ['W', 'W', 'L'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
        _team(
          id: 2,
          name: 'Away',
          ppg: 1.5,
          form: const ['D', 'W', 'L'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
      );
      expect(ordered.reasons.any((r) => r.factor == 'formOrder'), isFalse);
    });

    test('no weighting clause when only one side\'s form order is known', () {
      // Mixed sources: the sentence must not imply both lists are weighted
      // when the away `strForm` order is unknown (navigator open question 1).
      final r = _run(
        _team(
          ppg: 1.5,
          form: const ['W', 'W', 'W', 'L', 'L'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
        _team(
          id: 2,
          name: 'Fulham',
          ppg: 1.5,
          form: const ['L', 'L', 'D', 'D', 'D'],
          formOrdered: false,
          formSource: FormSource.standingsForm,
        ),
      );
      final form = r.reasons.firstWhere((r) => r.factor == 'form');
      expect(form.text, isNot(contains('with recent matches counting more')));
    });

    test('equal form gets a neutral wording, not "better"', () {
      // Identical ppg and form: the form term cancels exactly, so the text
      // must not name a side (navigator open question 2).
      final r = _run(
        _team(
          ppg: 1.5,
          form: const ['W', 'W', 'L'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
        _team(
          id: 2,
          name: 'Fulham',
          ppg: 1.5,
          form: const ['W', 'W', 'L'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
      );
      final form = r.reasons.firstWhere((r) => r.factor == 'form');
      expect(
        form.text,
        'Both teams’ recent form has a similar effect after adjustment: '
        '6 of 9 points vs 6 of 9 points, with recent matches counting more.',
      );
      expect(form.favours, PredictionFavour.none);
    });

    test('are sorted by contribution to d, largest first', () {
      final r = _run(_team(ppg: 2.3), _team(id: 2, name: 'Away', ppg: 1.0));
      // Home advantage (0.20) is the only factor here; both table sides
      // favour home. The table factor must outrank the home factor.
      final factors = r.reasons.map((r) => r.factor).toList();
      expect(factors.indexOf('table'), lessThan(factors.indexOf('home')));
    });
  });

  group('completeness and notes', () {
    test(
      'partial when only one team has form; notes list the missing side',
      () {
        final r = _run(
          _team(
            ppg: 1.5,
            form: const ['W', 'W', 'W'],
            formOrdered: true,
            formSource: FormSource.seasonEvents,
          ),
          _team(id: 2, name: 'Away', ppg: 1.5),
        );
        expect(r.completeness, Completeness.partial);
        expect(r.missingNotes, contains('Recent form is missing for Away.'));
      },
    );

    test('early-season note when either team has played fewer than 3', () {
      final r = _run(
        _team(played: 2, ppg: 1.5),
        _team(id: 2, name: 'Away', ppg: 1.5),
      );
      expect(r.missingNotes, contains('Early in the season – low confidence.'));
    });

    test('full data produces no notes', () {
      final r = _run(
        _team(
          ppg: 1.5,
          form: const ['W', 'W', 'W'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
        _team(
          id: 2,
          name: 'Away',
          ppg: 1.5,
          form: const ['L', 'D', 'W'],
          formOrdered: true,
          formSource: FormSource.seasonEvents,
        ),
      );
      expect(r.completeness, Completeness.full);
      expect(r.missingNotes, isEmpty);
    });

    test('carries the formula version', () {
      final r = _run(_team(ppg: 1.5), _team(id: 2, name: 'Away', ppg: 1.5));
      expect(r.formulaVersion, 'v1');
    });
  });
}
