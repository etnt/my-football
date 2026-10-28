import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/ai/ai_providers.dart';
import 'package:my_football/features/live/live_providers.dart';
import 'package:my_football/features/recap/recap_builder.dart';
import 'package:my_football/features/recap/recap_providers.dart';
import 'package:my_football/features/recap/recap_sheet.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/models/match_timeline.dart';
import 'package:my_football/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fixture_helpers.dart';
import '../../support/fake_ai_service.dart';

/// A recap the fake model returns that passes validation for the 2–1
/// Arsenal/Chelsea fact sheet built from [completeTimelineRed]: numbers
/// 2 and 1, and only names that appear in the facts (Saka, Jackson —
/// no Gabriel, who is not in that timeline).
const validModelRecap =
    'Arsenal edged Chelsea 2 to 1. Saka struck first for the home side '
    'and Jackson was sent off for the visitors late in the game.';

/// The template recap for [completeTimelineRed]: 3 goals (one an own goal,
/// one a penalty) and a red card.
const templateRecap =
    "Arsenal 2–1 Chelsea. Goals: Saka 12', Palmer 34' (o.g.), "
    "Gabriel 77' (pen.). Red card: Jackson (Chelsea).";

/// Renders [RecapSection] for [fixture] with canned providers.
Future<void> _pumpSection(
  WidgetTester tester, {
  required Fixture fixture,
  MatchTimeline Function(int eventId)? timelineFor,
  FakeAiService? ai,
  bool throwTimeline = false,
  Duration builderTimeout = const Duration(seconds: 8),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final service = ai ?? FakeAiService();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiServiceProvider.overrideWithValue(service),
        recapBuilderProvider.overrideWith(
          (ref) => RecapBuilder(
            ai: ref.watch(aiServiceProvider),
            cache: CacheStore(prefs),
            timeout: builderTimeout,
          ),
        ),
        matchTimelineProvider.overrideWith((ref, eventId) async {
          if (throwTimeline) throw Exception('timeline unavailable');
          return timelineFor?.call(eventId) ?? emptyTimeline;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(body: RecapSection(fixture: fixture)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('not shown for an upcoming fixture', (tester) async {
    await _pumpSection(tester, fixture: fixtureUpcoming());

    expect(find.textContaining('Arsenal'), findsNothing);
    expect(find.textContaining('Goals:'), findsNothing);
  });

  testWidgets('finished with timeline: no recap sentence by default', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      fixture: fixtureFinished(),
      timelineFor: (_) => completeTimelineRed(),
    );
    // The goal list below the sheet already shows these details, so the
    // template sentence stays out of the default view.
    expect(find.text(templateRecap), findsNothing);
    expect(find.text('Show facts'), findsOneWidget);
    expect(find.text('Written by on-device AI'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('finished with a fake valid model: AI text inside Show facts', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      fixture: fixtureFinished(),
      timelineFor: (_) => completeTimelineRed(),
      ai: FakeAiService(responseText: validModelRecap),
    );
    expect(find.text(validModelRecap), findsNothing);

    await tester.tap(find.text('Show facts'));
    await tester.pumpAndSettle();
    expect(find.text(validModelRecap), findsOneWidget);
    expect(find.text('Written by on-device AI'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('invalid model output: no AI label, no spinner', (tester) async {
    await _pumpSection(
      tester,
      fixture: fixtureFinished(),
      timelineFor: (_) => completeTimelineRed(),
      ai: FakeAiService(
        responseText:
            'Arsenal beat Chelsea 9 to 1. Saka opened the scoring early '
            'and the home side controlled the rest of the game fully.',
      ),
    );
    await tester.tap(find.text('Show facts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('9 to 1'), findsNothing);
    expect(find.text('Written by on-device AI'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('timeout: no spinner is left and no AI label', (tester) async {
    await _pumpSection(
      tester,
      fixture: fixtureFinished(),
      timelineFor: (_) => completeTimelineRed(),
      ai: FakeAiService(
        responseText: validModelRecap,
        delay: const Duration(seconds: 5),
      ),
      builderTimeout: const Duration(milliseconds: 100),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Show facts'));
    await tester.pumpAndSettle();
    expect(find.text('Written by on-device AI'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // pump past the delay so no pending timer is left at teardown.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('"Show facts" toggle shows and hides the fact lines', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      fixture: fixtureFinished(),
      timelineFor: (_) => completeTimelineRed(),
    );

    expect(find.textContaining('Match: Arsenal 2–1 Chelsea'), findsNothing);

    await tester.tap(find.text('Show facts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Match: Arsenal 2–1 Chelsea'), findsOneWidget);
    expect(
      find.textContaining('Card: Jackson (Chelsea) – red card'),
      findsOneWidget,
    );

    await tester.tap(find.text('Hide facts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Match: Arsenal 2–1 Chelsea'), findsNothing);
  });

  testWidgets('timeline error: score-only facts, no crash', (tester) async {
    await _pumpSection(tester, fixture: fixtureFinished(), throwTimeline: true);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Show facts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Match: Arsenal 2–1 Chelsea'), findsOneWidget);
  });
}
