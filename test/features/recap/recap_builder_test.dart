import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/recap/fact_sheet.dart';
import 'package:my_football/features/recap/recap_builder.dart';
import 'package:my_football/models/card_event.dart';
import 'package:my_football/models/goal_event.dart';
import 'package:my_football/models/match_timeline.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fixture_helpers.dart';
import '../../support/fake_ai_service.dart';

/// A recap the fake model returns that passes validation for the 2–1
/// Arsenal/Chelsea fact sheet built from [completeTimelineRed]: numbers
/// 2 and 1, and only names that appear in the facts (Arsenal, Chelsea,
/// Saka, Jackson — no Gabriel, who is not in that timeline).
const validModelRecap =
    'Arsenal edged Chelsea 2 to 1. Saka struck first for the home side '
    'and Jackson was sent off for the visitors late in the game.';

Future<CacheStore> _cache() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return CacheStore(prefs);
}

void main() {
  group('buildTemplateRecap', () {
    test('full timeline: score, scorers, minutes, pen and red card', () {
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );
      final recap = buildTemplateRecap(facts);

      expect(recap, startsWith('Arsenal 2–1 Chelsea.'));
      expect(
        recap,
        contains("Goals: Saka 12', Palmer 34' (o.g.), Gabriel 77' (pen.)."),
      );
      expect(recap, contains('Red card: Jackson (Chelsea).'));
    });

    test('score-only: no invented scorers, no clauses', () {
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: emptyTimeline,
      );
      final recap = buildTemplateRecap(facts);

      expect(recap, 'Arsenal 2–1 Chelsea.');
      expect(recap.contains('Goals:'), isFalse);
      expect(recap.contains('Red card'), isFalse);
    });

    test('yellow-only cards are not listed as red cards', () {
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: MatchTimeline(
          // 3 goal rows for the 2–1 score, so the timeline is complete
          // and the goals stay in the fact sheet.
          goals: const [
            GoalEvent(scorer: 'Saka', minute: 12, team: 'Arsenal'),
            GoalEvent(
              scorer: 'Palmer',
              minute: 34,
              team: 'Chelsea',
              ownGoal: true,
            ),
            GoalEvent(scorer: 'Saka', minute: 77, team: 'Arsenal'),
          ],
          cards: const [
            CardEvent(player: 'Caicedo', team: 'Chelsea'),
          ],
        ),
      );
      final recap = buildTemplateRecap(facts);

      expect(recap, contains('Goals:'));
      expect(recap.contains('Red card'), isFalse);
    });
  });

  group('RecapBuilder with the fake AiService', () {
    test('unavailable AI: no generate call, returns null', () async {
      final ai = FakeAiService(available: false);
      final builder = RecapBuilder(ai: ai, cache: await _cache());
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      final result = await builder.tryModelRewrite(facts);

      expect(result, isNull);
      expect(ai.generateCalls, 0);
      expect(ai.isAvailableCalls, 1);
    });

    test('valid output is returned as aiWritten and cached under '
        'recap_<id>_v1', () async {
      final ai = FakeAiService(responseText: validModelRecap);
      final cache = await _cache();
      final builder = RecapBuilder(ai: ai, cache: cache);
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      final result = await builder.tryModelRewrite(facts);

      expect(result, isNotNull);
      expect(result!.aiWritten, isTrue);
      expect(result.text, validModelRecap);
      final cached = cache.readJson('recap_2053456_v1');
      expect(cached, isNotNull);
      expect(cached!.data, validModelRecap);
    });

    test('second call is a cache hit with no new generate call', () async {
      final ai = FakeAiService(responseText: validModelRecap);
      final cache = await _cache();
      final builder = RecapBuilder(ai: ai, cache: cache);
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      await builder.tryModelRewrite(facts);
      final firstCalls = ai.generateCalls;
      final second = await builder.tryModelRewrite(facts);

      expect(second, isNotNull);
      expect(second!.aiWritten, isTrue);
      expect(ai.generateCalls, firstCalls,
          reason: 'second call must come from the cache');
    });

    test('cache entry under a different prompt version is ignored', () async {
      final cache = await _cache();
      await cache.writeJson('recap_2053456_v0', 'stale recap text');
      final ai = FakeAiService(available: false);
      final builder = RecapBuilder(ai: ai, cache: cache);
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      final result = await builder.tryModelRewrite(facts);

      expect(result, isNull, reason: 'v0 entry must not be served for v1');
    });

    test('invalid output (bad number) falls back with no cache write',
        () async {
      final ai = FakeAiService(
        responseText:
            'Arsenal beat Chelsea 9 to 1. Saka opened the scoring early '
            'and the home side controlled the rest of the game fully.',
      );
      final cache = await _cache();
      final builder = RecapBuilder(ai: ai, cache: cache);
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      final result = await builder.tryModelRewrite(facts);

      expect(result, isNull);
      expect(cache.readJson('recap_2053456_v1'), isNull);
    });

    test('invalid output (bad name) falls back with no cache write',
        () async {
      final ai = FakeAiService(
        responseText:
            'Arsenal beat Chelsea 2 to 1. Zlatan opened the scoring early '
            'and the home side controlled the rest of the game fully.',
      );
      final cache = await _cache();
      final builder = RecapBuilder(ai: ai, cache: cache);
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      final result = await builder.tryModelRewrite(facts);

      expect(result, isNull);
      expect(cache.readJson('recap_2053456_v1'), isNull);
    });

    test('timeout falls back', () async {
      final ai = FakeAiService(
        responseText: validModelRecap,
        delay: const Duration(seconds: 3),
      );
      final cache = await _cache();
      final builder = RecapBuilder(
        ai: ai,
        cache: cache,
        timeout: const Duration(milliseconds: 50),
      );
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      final result = await builder.tryModelRewrite(facts);

      expect(result, isNull);
      expect(cache.readJson('recap_2053456_v1'), isNull);
    });

    test('generate throws: falls back', () async {
      final ai = FakeAiService(throwOnGenerate: true);
      final cache = await _cache();
      final builder = RecapBuilder(ai: ai, cache: cache);
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      final result = await builder.tryModelRewrite(facts);

      expect(result, isNull);
      expect(cache.readJson('recap_2053456_v1'), isNull);
    });

    test('isAvailable throws: falls back without calling generate', () async {
      final ai = FakeAiService(throwOnIsAvailable: true);
      final builder = RecapBuilder(ai: ai, cache: await _cache());
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      final result = await builder.tryModelRewrite(facts);

      expect(result, isNull);
      expect(ai.generateCalls, 0);
    });

    test('hung isAvailable falls back after the timeout with no generate call',
        () async {
      final ai = FakeAiService(
        responseText: validModelRecap,
        isAvailableDelay: const Duration(seconds: 3),
      );
      final builder = RecapBuilder(
        ai: ai,
        cache: await _cache(),
        timeout: const Duration(milliseconds: 50),
      );
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      final result = await builder.tryModelRewrite(facts);

      expect(result, isNull);
      expect(ai.generateCalls, 0);
    });

    test('complete timeline: eventsComplete is true and the model path runs',
        () async {
      final ai = FakeAiService(responseText: validModelRecap);
      final builder = RecapBuilder(ai: ai, cache: await _cache());
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      expect(
        facts.eventsComplete,
        isTrue,
        reason: '3 goal rows account for the 2–1 score, so the timeline is '
            'complete and the eventsComplete path must be exercised',
      );
      final result = await builder.tryModelRewrite(facts);

      expect(result, isNotNull);
      expect(result!.aiWritten, isTrue);
      expect(ai.generateCalls, 1);
    });

    test('score-only fact sheet: no model call, no cache write', () async {
      final ai = FakeAiService(responseText: validModelRecap);
      final cache = await _cache();
      final builder = RecapBuilder(ai: ai, cache: cache);
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: emptyTimeline,
      );

      final result = await builder.tryModelRewrite(facts);

      expect(result, isNull);
      expect(ai.isAvailableCalls, 0);
      expect(ai.generateCalls, 0);
    });

    test('template() is synchronous and returns the template recap',
        () async {
      final builder = RecapBuilder(ai: FakeAiService(), cache: await _cache());
      final facts = FactSheet.build(
        fixture: fixtureFinished(),
        timeline: completeTimelineRed(),
      );

      final result = builder.template(facts);

      expect(result.aiWritten, isFalse);
      expect(result.text, buildTemplateRecap(facts));
      expect(result.facts, same(facts));
    });
  });
}
