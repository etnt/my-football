import 'package:flutter/foundation.dart';

import '../../core/text/lookup_text_normalizer.dart';
import '../../models/fixture.dart';
import '../ai/output_validator.dart';
import 'prediction_prompt.dart';
import 'prediction_result.dart';

/// Extra vocabulary for prediction prose, on top of [recapNameAllowlist].
/// Deliberately small and prediction-specific: recap-only words (goals,
/// cards, months, VAR) stay out of predictions even though the shared
/// sentence-starter allowlist is reused.
const _predictionVocabulary = {
  // Prediction / estimate wording.
  'prediction', 'predictions', 'predicted', 'predicts', 'predicting',
  'estimate', 'estimates', 'estimated', 'forecast',
  'chance', 'chances', 'likelihood', 'likely', 'unlikely',
  'slight', 'slightly', 'close', 'favourite', 'favorite', 'underdog',
  // Factor vocabulary used by the reason texts.
  'form', 'recent', 'recency', 'streak', 'table', 'rank', 'ranking',
  'points', 'point', 'games', 'game', 'matches', 'match', 'played',
  'per', 'adjustment', 'advantage', 'factor', 'fixed', 'included',
  'stronger', 'weaker', 'better', 'best', 'favourable', 'favorable',
  'ahead', 'behind', 'against', 'versus',
  // Outcome wording.
  'win', 'wins', 'won', 'losing', 'drawn', 'draws', 'victory',
  'possible', 'possibly', 'probably', 'suggests', 'suggesting', 'suggest',
  // "Too close to call" verdict wording.
  'too', 'call', 'either', 'way', 'uncertain', 'open',
  'edges', 'lean', 'leans', 'leaning', 'favours', 'favors',
  // Sentence openers a faithful rewrite commonly starts with. The recap's
  // shared opener list lacks these, and a false reject means the summary is
  // never shown, so the most frequent ones are added here.
  'based', 'according', 'given', 'compared', 'comparing',
  // Data-availability wording.
  'missing', 'unknown', 'data', 'available', 'confidence', 'low', 'season',
  'early', 'counts', 'count', 'same', 'every', 'order', 'ordered',
  'mathematically', 'calculation', 'calculated', 'numbers', 'number',
};

/// Why a candidate prediction summary was rejected. Logged only — the UI
/// silently keeps the deterministic reasons. Reuses the recap's
/// [ValidationResult]/[RejectReason] and the recap's capitalised-word and
/// number rules so both features behave the same way.
///
/// Validates a model-generated prediction summary against the fixture and
/// the computed [PredictionResult]. Every number must come from the prompt,
/// every capitalised word must be a team name or a known word, and gambling
/// or over-confidence language is rejected outright.
///
/// Known limitation, accepted for v1: the number check is set-based, so a
/// number is accepted whenever it appears anywhere in the prediction —
/// "Chelsea 52%" passes when 52 is the home percent. Catching the
/// mis-attribution would need a strict adjacency check that adds false
/// rejects; the deterministic percentages always stay visible above the
/// summary, so the user can compare (see the documented test).
ValidationResult validatePredictionText(
  String text,
  Fixture fixture,
  PredictionResult result,
) {
  final trimmed = text.trim();

  // Logs carry the rule name only, never the matched value: a number or a
  // capitalised word can be match data, and logs must not leak it (CON-003).
  // The log-capture test in prediction_text_validator_test.dart pins this.
  if (trimmed.length < 20) {
    debugPrint(
      'validatePredictionText: rejected (${RejectReason.tooShort.name})',
    );
    return const ValidationResult.failure(RejectReason.tooShort);
  }
  if (trimmed.length > 400) {
    debugPrint(
      'validatePredictionText: rejected (${RejectReason.tooLong.name})',
    );
    return const ValidationResult.failure(RejectReason.tooLong);
  }

  // Same `\d+` tokenisation as [predictionAllowedNumbers], so the two lists
  // stay in parity.
  final numberPattern = RegExp(r'\d+');
  final allowedNumbers = predictionAllowedNumbers(fixture, result);
  for (final match in numberPattern.allMatches(trimmed)) {
    if (!allowedNumbers.contains(match.group(0))) {
      debugPrint(
        'validatePredictionText: rejected (${RejectReason.unknownNumber.name})',
      );
      return const ValidationResult.failure(RejectReason.unknownNumber);
    }
  }

  // Capitalised words must be team names or allowlisted. The lookbehind
  // instead of `\b` is deliberate: Dart's `\b` is ASCII-based, so it sees
  // no word boundary before a leading capital like "Ødegaard" and the
  // token would go unchecked. Same pattern as the recap validator.
  final wordPattern = RegExp(
    r"(?<![\p{L}\p{N}])\p{Lu}[\p{L}-]*(?:['’]\p{Lu}[\p{L}-]*)*",
    unicode: true,
  );
  final allowedNames = predictionAllowedNameTokens(fixture);
  for (final match in wordPattern.allMatches(trimmed)) {
    final normalized = normalizeLookupText(match.group(0)!);
    if (normalized.isEmpty) continue;
    final parts = normalized.split(' ');
    final known = parts.every(
      (part) =>
          allowedNames.contains(part) ||
          recapNameAllowlist.contains(part) ||
          _predictionVocabulary.contains(part),
    );
    if (!known) {
      debugPrint(
        'validatePredictionText: rejected (${RejectReason.unknownName.name})',
      );
      return const ValidationResult.failure(RejectReason.unknownName);
    }
  }

  // Forbidden language: betting/gambling wording and over-confidence
  // claims (REQ-010). Whole-word Unicode lookarounds: "better" and
  // "alphabet" must pass while "betting" fails; "guarantee*" and
  // "calibrat*" cover the word families, not single spellings.
  final forbiddenPattern = RegExp(
    r"(?<![\p{L}\p{N}])(odds|bets?|betting|betted|guarantee\w*|calibrat\w*)(?![\p{L}\p{N}])",
    caseSensitive: false,
    unicode: true,
  );
  final forbidden = forbiddenPattern.firstMatch(trimmed);
  if (forbidden != null) {
    debugPrint(
      'validatePredictionText: rejected (${RejectReason.forbiddenClaim.name})',
    );
    return const ValidationResult.failure(RejectReason.forbiddenClaim);
  }

  return const ValidationResult.ok();
}
