import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/ai/ai_service.dart';
import 'package:my_football/features/predictions/prediction_narrator.dart';
import 'package:my_football/features/predictions/prediction_prompt.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/models/fixture.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_ai_service.dart';

const _validSummary =
    'Arsenal look slightly ahead of Chelsea. The table gap and home '
    'advantage point the same way, and recent form supports that. A draw '
    'is possible but less likely.';

Fixture _fixture() => Fixture(
  id: 100,
  dateUtc: DateTime.utc(2026, 11, 8, 15),
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

PredictionResult _result() {
  return PredictionResult(
    pHome: 0.52,
    pDraw: 0.24,
    pAway: 0.24,
    displayPercents: const {
      Outcome.home: 52,
      Outcome.draw: 24,
      Outcome.away: 24,
    },
    verdict: Verdict.homeWin,
    isSlight: true,
    reasons: const [
      PredictionReason(
        factor: 'table',
        favours: PredictionFavour.home,
        text: 'Arsenal are 1st, Chelsea are 8th (2.1 vs 1.3 points per game).',
        numbers: {'homePpg': 2.1, 'awayPpg': 1.3},
      ),
      PredictionReason(
        factor: 'form',
        favours: PredictionFavour.home,
        text: 'Arsenal have won their last 3.',
        numbers: {'streak': 3},
      ),
    ],
    missingNotes: const [],
    completeness: Completeness.full,
    formulaVersion: 'v1',
  );
}

/// The same prediction, but with one changed reason text: same percents, same
/// versions — only the prompt content differs.
PredictionResult _changedResult(PredictionResult result) {
  return PredictionResult(
    pHome: result.pHome,
    pDraw: result.pDraw,
    pAway: result.pAway,
    displayPercents: result.displayPercents,
    verdict: result.verdict,
    isSlight: result.isSlight,
    reasons: const [
      PredictionReason(
        factor: 'table',
        favours: PredictionFavour.home,
        text: 'Arsenal are 2nd, Chelsea are 9th (2.1 vs 1.3 points per game).',
        numbers: {'homePpg': 2.1, 'awayPpg': 1.3},
      ),
      PredictionReason(
        factor: 'form',
        favours: PredictionFavour.home,
        text: 'Arsenal have won their last 3.',
        numbers: {'streak': 3},
      ),
    ],
    missingNotes: const [],
    completeness: Completeness.full,
    formulaVersion: 'v1',
  );
}

Future<CacheStore> _cache() async {
  SharedPreferences.setMockInitialValues({});
  return CacheStore(await SharedPreferences.getInstance());
}

void main() {
  late Fixture fixture;
  late PredictionResult result;

  setUp(() {
    fixture = _fixture();
    result = _result();
  });

  test('unavailable model: no generate call, null summary', () async {
    for (final reason in [AiReason.modelNotInstalled, AiReason.modelDownloading]) {
      final ai = FakeAiService(available: false, reason: reason);
      final narrator = PredictionNarrator(
        ai: ai,
        cache: await _cache(),
      );

      // CON-002: an unavailable model (incl. the native DOWNLOADABLE state,
      // mapped to `modelNotInstalled`) must never trigger a download —
      // there is no `download()` call and no `generate()` call either.
      expect(await narrator.summarize(fixture, result), isNull);
      expect(ai.generateCalls, 0, reason: reason.name);
      expect(ai.isAvailableCalls, 1);
    }
  });

  test('timeout around isAvailable + generate returns null', () async {
    final ai = FakeAiService(delay: const Duration(milliseconds: 200));
    final narrator = PredictionNarrator(
      ai: ai,
      cache: await _cache(),
      timeout: const Duration(milliseconds: 50),
    );

    expect(await narrator.summarize(fixture, result), isNull);
  });

  test('an invented number is rejected and not cached', () async {
    final ai = FakeAiService(
      responseText: 'Arsenal have won 7 matches in a row at home recently.',
    );
    final cache = await _cache();
    final narrator = PredictionNarrator(ai: ai, cache: cache);

    expect(await narrator.summarize(fixture, result), isNull);

    // A later open must not read a poisoned cache either.
    final second = FakeAiService(available: false);
    expect(
      await PredictionNarrator(ai: second, cache: cache).summarize(
        fixture,
        result,
      ),
      isNull,
    );
  });

  test('an invented team name is rejected', () async {
    final ai = FakeAiService(
      responseText: 'Liverpool look slightly ahead of Chelsea this weekend.',
    );
    final narrator = PredictionNarrator(ai: ai, cache: await _cache());

    expect(await narrator.summarize(fixture, result), isNull);
  });

  test('a valid output is returned and cached for the next open', () async {
    final ai = FakeAiService(responseText: _validSummary);
    final cache = await _cache();
    final narrator = PredictionNarrator(ai: ai, cache: cache);

    expect(await narrator.summarize(fixture, result), _validSummary);
    expect(ai.generateCalls, 1);

    // Second open: cache hit, the model is not even asked for availability.
    final second = FakeAiService(available: false);
    expect(
      await PredictionNarrator(ai: second, cache: cache).summarize(
        fixture,
        result,
      ),
      _validSummary,
    );
    expect(second.generateCalls, 0);
    expect(second.isAvailableCalls, 0);
  });

  test('a changed reason text is a cache miss and regenerates', () async {
    final cache = await _cache();
    await PredictionNarrator(
      ai: FakeAiService(responseText: _validSummary),
      cache: cache,
    ).summarize(fixture, result);

    final changed = _changedResult(result);

    // Same fixture id, same versions — but the prompt content changed, so
    // the content fingerprint misses and the model runs again.
    final ai = FakeAiService(responseText: _validSummary);
    final text = await PredictionNarrator(ai: ai, cache: cache).summarize(
      fixture,
      changed,
    );
    expect(text, _validSummary);
    expect(ai.generateCalls, 1);
  });

  test('an entry from another formula or prompt version is a cache miss',
      () async {
    for (final field in ['v', 'p']) {
      final cache = await _cache();
      // A *valid* summary under the current fingerprint, but an older
      // version: only the version compare can reject it, so a version-blind
      // cache would show this text instead of regenerating.
      await cache.writeJson(predictionCacheKey(fixture.id), {
        'v': field == 'v' ? 'v0' : result.formulaVersion,
        'p': field == 'p' ? 'v0' : predictionPromptVersion,
        'fp': predictionPromptFingerprint(
          buildPredictionPrompt(fixture, result),
        ),
        'text': _validSummary,
      });

      // The model returns no text, so a real miss shows nothing at all; a
      // wrong hit would show the older summary.
      final ai = FakeAiService();
      expect(
        await PredictionNarrator(
          ai: ai,
          cache: cache,
        ).summarize(fixture, result),
        isNull,
        reason: field,
      );
      expect(ai.generateCalls, 1, reason: field);
    }
  });

  test('a stale invalid cached text is re-validated and regenerated',
      () async {
    final cache = await _cache();
    final prompt = buildPredictionPrompt(fixture, result);
    await cache.writeJson(predictionCacheKey(fixture.id), {
      'v': result.formulaVersion,
      'p': predictionPromptVersion,
      'fp': predictionPromptFingerprint(prompt),
      'text': 'Arsenal will win 7 to 3, guaranteed.',
    });

    final ai = FakeAiService(responseText: _validSummary);
    final text = await PredictionNarrator(ai: ai, cache: cache).summarize(
      fixture,
      result,
    );

    expect(text, _validSummary);
    // The poisoned entry was actually read (not just a silent miss): it is
    // overwritten by the regenerated, validated summary.
    expect(ai.generateCalls, 1);
    expect(
      cache.readJson(predictionCacheKey(fixture.id))!.data,
      containsPair('text', _validSummary),
    );
  });

  test('one cache key per fixture, version and content in the value', () {
    final prompt = buildPredictionPrompt(fixture, result);
    expect(predictionCacheKey(fixture.id), 'prediction_ai_100');
    expect(
      predictionPromptFingerprint('$prompt x'),
      isNot(predictionPromptFingerprint(prompt)),
    );
  });

  test('a content change overwrites the single entry per fixture', () async {
    final cache = await _cache();
    await PredictionNarrator(
      ai: FakeAiService(responseText: _validSummary),
      cache: cache,
    ).summarize(fixture, result);
    await PredictionNarrator(
      ai: FakeAiService(responseText: _validSummary),
      cache: cache,
    ).summarize(fixture, _changedResult(result));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.startsWith('prediction_ai_')),
      ['prediction_ai_100'],
    );
  });
}
