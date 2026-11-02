import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/ai/ai_providers.dart';
import 'package:my_football/features/predictions/prediction_providers.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/features/predictions/prediction_sheet.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_ai_service.dart';

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

const _validSummary =
    'Arsenal look slightly ahead of Chelsea. The table gap and home '
    'advantage point the same way, and recent form supports that. A draw '
    'is possible but less likely.';

/// Opens the sheet through [showPredictionSheet] with [predictionProvider]
/// overridden, so no repository (and no network) is touched.
Future<void> _openSheet(
  WidgetTester tester, {
  required Object Function() outcome,
  double textScale = 1.0,
  List<Override> overrides = const [],
}) async {
  // The AI summary is overridden to null unless a test supplies its own
  // overrides: the narration provider would otherwise construct a
  // [CacheStore] from `sharedPreferencesProvider`, which these tests do not
  // override. The deterministic content must also never wait for the model
  // (CON-001), which this default pins.
  final narrationOverrides = overrides.isEmpty
      ? [
          predictionNarrationProvider(
            NarrationRequest(fixture: _fixture(), key: _predictionKey),
          ).overrideWith((ref) async => null),
        ]
      : overrides;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        predictionProvider(_predictionKey).overrideWith((ref) async {
          final value = outcome();
          if (value is PredictionUnavailable) throw value;
          if (value is Exception) throw value;
          return value as PredictionResult;
        }),
        ...narrationOverrides,
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
      find.text('Estimate based on the league table. Not betting advice.'),
      findsOneWidget,
    );
    expect(find.textContaining('odds'), findsNothing);
    expect(find.textContaining('calibrated'), findsNothing);
  });

  testWidgets('the too-close verdict is shown verbatim with tip 1X2', (
    tester,
  ) async {
    await _openSheet(
      tester,
      outcome: () => _result(verdict: Verdict.tooClose),
    );
    expect(find.text('Too close to call'), findsOneWidget);
    expect(find.text('1X2'), findsOneWidget);
  });

  testWidgets('the slight-favourite verdict is shown verbatim with tip 1X', (
    tester,
  ) async {
    await _openSheet(tester, outcome: () => _result(isSlight: true));
    expect(find.text('Home win – slight favourite'), findsOneWidget);
    expect(find.text('1X'), findsOneWidget);
  });

  testWidgets('a clear verdict shows a single tip', (tester) async {
    await _openSheet(
      tester,
      outcome: () => _result(verdict: Verdict.awayWin),
    );
    expect(find.text('Away win'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('the tip is spelled out for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await _openSheet(tester, outcome: () => _result(isSlight: true));
    expect(
      find.bySemanticsLabel('Tip 1X: Home win or draw'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('tip and verdict fit at text scale 2.0', (tester) async {
    await _openSheet(
      tester,
      outcome: () => _result(verdict: Verdict.tooClose),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('1X2'), findsOneWidget);
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
      find.text('Estimate based on the league table. Not betting advice.'),
      findsOneWidget,
    );
  });

  testWidgets('no AI summary by default (no model available in tests)', (
    tester,
  ) async {
    await _openSheet(tester, outcome: () => _result());

    expect(find.text('Written by on-device AI'), findsNothing);
    expect(find.textContaining(_validSummary), findsNothing);
  });

  testWidgets('shows the validated AI summary above the reasons', (
    tester,
  ) async {
    await _openSheet(
      tester,
      outcome: () => _result(),
      overrides: [
        predictionNarrationProvider(
          NarrationRequest(fixture: _fixture(), key: _predictionKey),
        ).overrideWith((ref) async => _validSummary),
      ],
    );

    expect(find.text('Written by on-device AI'), findsOneWidget);
    expect(find.text(_validSummary), findsOneWidget);
    // The deterministic reasons are still shown alongside.
    expect(find.text('Why this estimate?'), findsOneWidget);
  });

  testWidgets('the summary appears through the real narrator wiring', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _openSheet(
      tester,
      outcome: () => _result(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiServiceProvider.overrideWithValue(
          FakeAiService(responseText: _validSummary),
        ),
        // No narration override: the real provider/narrator/cache path runs.
      ],
    );

    expect(find.text('Written by on-device AI'), findsOneWidget);
    expect(find.text(_validSummary), findsOneWidget);
  });
}
