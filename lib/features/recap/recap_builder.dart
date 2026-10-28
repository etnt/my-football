import 'dart:async';

import '../ai/ai_service.dart';
import '../ai/output_validator.dart';
import '../ai/prompt_templates.dart';
import '../../core/storage/cache_store.dart';
import 'fact_sheet.dart';

/// A finished recap: either the template (cheap, follows the data) or a
/// model rewrite (marked `aiWritten`).
class RecapResult {
  const RecapResult({
    required this.text,
    required this.aiWritten,
    required this.facts,
  });

  final String text;
  final bool aiWritten;
  final FactSheet facts;
}

/// Builds template recaps and, when on-device generation is available,
/// attempts a validated model rewrite.
class RecapBuilder {
  RecapBuilder({
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

  /// How long to wait for the model before giving up and keeping the template.
  final Duration timeout;

  /// Deterministic, fact-only recap. Synchronous and cheap — rebuilt on every
  /// call so it always reflects the current data.
  RecapResult template(FactSheet facts) {
    return RecapResult(text: buildTemplateRecap(facts), aiWritten: false, facts: facts);
  }

  /// Whether a model rewrite is worth attempting: without a complete goal
  /// list the model can only invent scorers, and the template already
  /// covers the score.
  bool shouldTryModel(FactSheet facts) =>
      facts.eventsComplete || facts.goals.isNotEmpty;

  /// Tries to produce (or read from cache) a model-written recap. Returns null
  /// whenever the model path is unavailable, fails, times out or is rejected
  /// by the validator — the caller then keeps the template.
  Future<RecapResult?> tryModelRewrite(FactSheet facts) async {
    // Nothing to add (see [shouldTryModel]): skip the model entirely.
    if (!shouldTryModel(facts)) return null;

    final key = _cacheKey(facts.fixtureId);

    // 1. Cache first: a prompt-version bump invalidates the entry.
    final cached = _cache.readJson(key);
    if (cached != null) {
      final text = cached.data;
      if (text is String && text.isNotEmpty) {
        return RecapResult(text: text, aiWritten: true, facts: facts);
      }
    }

    // 2. Run the whole model path — the availability check and generation —
    //    under one hard timeout, so neither a hung `isAvailable()` nor a
    //    slow generate can leave the spinner up.
    String? generated;
    try {
      generated = await _checkAndGenerate(facts).timeout(timeout);
    } on TimeoutException {
      return null;
    } on Exception {
      return null;
    }
    if (generated == null || generated.trim().isEmpty) return null;

    // 3. Guard against hallucination before showing or caching anything.
    final validation = validateRecapText(generated, facts);
    if (!validation.ok) return null;

    // 4. Cache the model text so a later open of the sheet is instant.
    try {
      await _cache.writeJson(key, generated.trim());
    } on Exception {
      // Cache writes are best-effort; the recap is still valid.
    }

    return RecapResult(text: generated.trim(), aiWritten: true, facts: facts);
  }

  /// Availability check plus generation. Callers must apply the timeout —
  /// a hung `isAvailable()` must fail exactly like a hung `generate()`.
  Future<String?> _checkAndGenerate(FactSheet facts) async {
    final availability = await _ai.isAvailable();
    if (!availability.available) return null;

    final result = await _ai.generate(
      prompt: buildRecapPrompt(facts),
      maxTokens: 200,
      temperature: 0.3,
    );
    return result.text;
  }

  String _cacheKey(int fixtureId) => 'recap_${fixtureId}_$recapPromptVersion';
}

/// Fact-only fallback text shown while the model is unavailable or pending.
String buildTemplateRecap(FactSheet f) {
  final buffer = StringBuffer();
  buffer.write('${f.homeName} ${f.homeGoals}–${f.awayGoals} ${f.awayName}.');

  if (f.goals.isNotEmpty) {
    final goalParts = <String>[];
    for (final goal in f.goals) {
      final bits = <String>[goal.scorer];
      if (goal.minute != null) bits.add("${goal.minute}'");
      if (goal.penalty) bits.add('(pen.)');
      if (goal.ownGoal) bits.add('(o.g.)');
      goalParts.add(bits.join(' '));
    }
    buffer.write(' Goals: ${goalParts.join(', ')}.');
  }

  final redCards = f.cards.where((c) => c.red).toList();
  if (redCards.isNotEmpty) {
    final redParts = <String>[];
    for (final card in redCards) {
      final team = card.team.isNotEmpty ? ' (${card.team})' : '';
      redParts.add('${card.player}$team');
    }
    buffer.write(' Red card: ${redParts.join(', ')}.');
  }

  return buffer.toString();
}
