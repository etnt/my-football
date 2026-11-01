import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/predictions/prediction_providers.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/features/predictions/prediction_sheet.dart';
import 'package:my_football/models/fixture.dart';

PredictionResult _result({
  Verdict verdict = Verdict.homeWin,
  bool isSlight = false,
}) {
  return PredictionResult(
    pHome: 0.52,
    pDraw: 0.24,
    pAway: 0.24,
    displayPercents: const {
      Outcome.home: 52,
      Outcome.draw: 24,
      Outcome.away: 24,
    },
    verdict: verdict,
    isSlight: isSlight,
    reasons: const [
      PredictionReason(
        factor: 'table',
        favours: PredictionFavour.home,
        text: 'Arsenal are 1st, Chelsea are 8th (2.1 vs 1.3 points per game).',
      ),
      PredictionReason(
        factor: 'home',
        favours: PredictionFavour.home,
        text: 'Home advantage is included as a fixed factor.',
      ),
    ],
    missingNotes: const ['Recent form is missing for Chelsea.'],
    completeness: Completeness.partial,
    formulaVersion: 'v1',
  );
}

Fixture _fixture() {
  return Fixture(
    id: 100,
    dateUtc: DateTime.now().toUtc().add(const Duration(days: 7)),
    statusShort: 'NS',
    statusLong: '',
    elapsed: null,
    homeId: 1,
    homeName: 'Arsenal',
    homeLogo: '',
    awayId: 2,
    awayName: 'Chelsea',
    awayLogo: '',
    homeGoals: null,
    awayGoals: null,
  );
}

const _predictionKey = (fixtureId: 100, leagueId: 4328, season: 2026);

/// Opens the sheet through [showPredictionSheet] with [predictionProvider]
/// overridden, so no repository (and no network) is touched.
Future<void> _openSheet(
  WidgetTester tester, {
  required Object Function() outcome,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        predictionProvider(_predictionKey).overrideWith((ref) async {
          final value = outcome();
          if (value is PredictionUnavailable) throw value;
          if (value is Exception) throw value;
          return value as PredictionResult;
        }),
      ],
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showPredictionSheet(context, ref, _fixture()),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the three percentages as text, verdict and reasons', (
    tester,
  ) async {
    await _openSheet(tester, outcome: () => _result());

    expect(find.text('Home win'), findsOneWidget);
    expect(find.text('Arsenal 52%'), findsOneWidget);
    expect(find.text('Draw 24%'), findsOneWidget);
    expect(find.text('Chelsea 24%'), findsOneWidget);
    expect(find.text('Why this estimate?'), findsOneWidget);
    expect(
      find.textContaining('2.1 vs 1.3 points per game'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Home advantage is included as a fixed factor.'),
      findsOneWidget,
    );
    // Missing data is reported, never silently folded into the numbers.
    expect(find.text('Recent form is missing for Chelsea.'), findsOneWidget);
  });

  testWidgets('shows the exact disclaimer and never "odds"/"calibrated"', (
    tester,
  ) async {
    await _openSheet(tester, outcome: () => _result());

    expect(
      find.text('Estimate based on table and form. Not betting advice.'),
      findsOneWidget,
    );
    expect(find.textContaining('odds'), findsNothing);
    expect(find.textContaining('calibrated'), findsNothing);
  });

  testWidgets('the draw verdict is shown verbatim', (tester) async {
    await _openSheet(
      tester,
      outcome: () => _result(verdict: Verdict.closeDrawLikely),
    );
    expect(find.text('Close – draw likely'), findsOneWidget);
  });

  testWidgets('the slight-favourite verdict is shown verbatim', (tester) async {
    await _openSheet(tester, outcome: () => _result(isSlight: true));
    expect(find.text('Home win – slight favourite'), findsOneWidget);
  });

  testWidgets('PredictionUnavailable shows "Not enough data" and the reason', (
    tester,
  ) async {
    await _openSheet(
      tester,
      outcome: () => const PredictionUnavailable(
        'Arsenal is not in the selected league table.',
      ),
    );

    expect(find.text('Not enough data'), findsOneWidget);
    expect(
      find.text('Arsenal is not in the selected league table.'),
      findsOneWidget,
    );
    // No percentages may appear without data (REQ-007).
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('other errors fall back to the generic error view', (
    tester,
  ) async {
    await _openSheet(tester, outcome: () => Exception('boom'));
    expect(find.text('Not enough data'), findsNothing);
    expect(find.text('Something went wrong.'), findsOneWidget);
  });

  testWidgets('no overflow at text scale 2.0', (tester) async {
    await _openSheet(tester, outcome: () => _result(), textScale: 2.0);
    expect(tester.takeException(), isNull);
    // The content is still all there, reachable through the scroll view.
    expect(
      find.text('Estimate based on table and form. Not betting advice.'),
      findsOneWidget,
    );
  });
}
