import 'dart:async';

import '../../core/storage/cache_store.dart';
import '../../models/fixture.dart';
import '../ai/ai_log.dart';
import '../ai/ai_service.dart';
import 'prediction_prompt.dart';
import 'prediction_result.dart';
import 'prediction_text_validator.dart';

/// Cache key for one AI summary: one entry per fixture. The formula version,
/// the prompt version and a fingerprint of the exact prompt content live in
/// the entry value, so a content change overwrites the old summary instead of
/// adding a new key for the same fixture.
String predictionCacheKey(int fixtureId) => 'prediction_ai_$fixtureId';

/// Fingerprint of the exact prompt content: the percentages and reason texts
/// can change (the standings cache is up to 6 h old and the season events
/// 30 min) while both versions stay the same, and a content-blind compare
/// would then serve a summary about stale numbers (CON-001/REQ-005).
///
/// 32-bit FNV-1a — `String.hashCode` is not stable across runs, so it cannot
/// be used.
String predictionPromptFingerprint(String prompt) {
  var hash = 0x811c9dc5;
  for (final unit in prompt.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16);
}

/// Turns the deterministic prediction into validated on-device AI prose,
/// modelled on `RecapBuilder`. Returns null whenever the model path is
/// unavailable, fails, times out or is rejected by the validator — the
/// sheet then simply keeps the deterministic reasons (CON-001).
///
/// Never triggers a model download: it only reads `isAvailable()` and calls
/// `generate()` when the model is already usable (CON-002).
class PredictionNarrator {
  PredictionNarrator({
    required AiService ai,
    required CacheStore cache,
    this.timeout = const Duration(seconds: 8),
  }) : // Named parameters can't start with an underscore, so the public
       // `ai`/`cache` names are kept and assigned here.
       // ignore: prefer_initializing_formals
       _ai = ai,
       // ignore: prefer_initializing_formals
       _cache = cache;

  final AiService _ai;
  final CacheStore _cache;

  /// How long to wait for the model before giving up.
  final Duration timeout;

  /// Produces (or reads from cache) the AI summary, or null.
  Future<String?> summarize(Fixture fixture, PredictionResult result) async {
    final prompt = buildPredictionPrompt(fixture, result);
    final fingerprint = predictionPromptFingerprint(prompt);

    // 1. Cache first, but only when the entry was written for this formula
    //    version, this prompt version and this exact prompt content. A
    //    mismatch is a miss: the model runs and overwrites the entry. The
    //    cached text is re-validated too, so an entry written by an older
    //    validator can never reach the UI.
    final cachedText = _cachedText(
      _cache.readJson(predictionCacheKey(fixture.id))?.data,
      result.formulaVersion,
      fingerprint,
    );
    if (cachedText != null) {
      if (validatePredictionText(cachedText, fixture, result).ok) {
        _log('cache hit');
        return cachedText;
      }
      _log('cached text rejected, regenerating');
    } else {
      _log('cache miss (version or content changed)');
    }

    // 2. Run the whole model path — availability check plus generation —
    //    under one hard timeout, so neither a hung `isAvailable()` nor a
    //    slow generate can keep the sheet waiting.
    String? generated;
    final clock = Stopwatch()..start();
    // `timeout()` does not cancel `_checkAndGenerate`: the awaited future
    // keeps running. This flag tells the late continuation not to start a
    // `generate()` call for a caller that already got null.
    var abandoned = false;
    try {
      generated = await _checkAndGenerate(prompt, () => abandoned)
          .timeout(timeout);
    } on TimeoutException {
      abandoned = true;
      _log(
        'timed out after ${clock.elapsedMilliseconds} ms '
        '(limit ${timeout.inMilliseconds} ms)',
      );
      return null;
    } on Object catch (e) {
      // Log the type only, never the message: exception text can carry
      // match data or the request URL (CON-003), exactly like
      // `prediction_providers.dart`.
      _log('failed after ${clock.elapsedMilliseconds} ms: ${e.runtimeType}');
      return null;
    }
    if (generated == null || generated.trim().isEmpty) {
      _log('no text returned after ${clock.elapsedMilliseconds} ms');
      return null;
    }

    // 3. Guard against hallucination before showing or caching anything.
    final validation = validatePredictionText(generated, fixture, result);
    if (!validation.ok) return null;

    final text = generated.trim();

    // 4. Cache so a later open of the sheet is instant. Best-effort: a
    //    failed write still leaves a valid summary on screen.
    try {
      await _cache.writeJson(predictionCacheKey(fixture.id), {
        'v': result.formulaVersion,
        'p': predictionPromptVersion,
        'fp': fingerprint,
        'text': text,
      });
    } on Exception {
      // Cache writes are best-effort; the summary is still valid.
    }
    return text;
  }

  /// The cached text, but only when the entry matches the current formula
  /// version, prompt version and prompt fingerprint; otherwise null (miss).
  /// A miss never deletes the entry: the write after a successful
  /// generation overwrites it, and an unchanged entry stays valid.
  String? _cachedText(Object? data, String formulaVersion, String fingerprint) {
    if (data is! Map) return null;
    if (data['v'] != formulaVersion) return null;
    if (data['p'] != predictionPromptVersion) return null;
    if (data['fp'] != fingerprint) return null;
    final text = data['text'];
    return text is String && text.isNotEmpty ? text : null;
  }

  /// Availability check plus generation. Callers must apply the timeout —
  /// a hung `isAvailable()` must fail exactly like a hung `generate()`.
  Future<String?> _checkAndGenerate(
    String prompt,
    bool Function() isAbandoned,
  ) async {
    final availability = await _ai.isAvailable();
    // The timeout may have fired while isAvailable() was pending. Return
    // before generate(): a hung availability check must never lead to a
    // generate call after the caller already got null.
    if (isAbandoned()) return null;
    _log(
      'availability: available=${availability.available} '
      'reason=${availability.reason.name}',
    );
    // Reason-agnostic on purpose (CON-002): whatever the reason —
    // `modelNotInstalled`, `modelDownloading`, unsupported device — the
    // answer is the same: no generate call, so never a download.
    if (!availability.available) return null;

    final result = await _ai.generate(
      prompt: prompt,
      maxTokens: 200,
      temperature: 0.3,
    );
    _log(
      result.text != null
          ? 'generate ok (${result.text!.length} chars)'
          : 'generate error: ${result.errorCode}',
    );
    return result.text;
  }

  /// Written to logcat via [AiLog]. No team names or percentages — no match
  /// data leaves the device (CON-003), including not into logs.
  static void _log(String message) => AiLog.add('prediction: $message');
}
