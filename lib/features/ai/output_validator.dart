import 'package:flutter/foundation.dart';

import '../../core/text/lookup_text_normalizer.dart';
import '../recap/fact_sheet.dart';

/// Why a candidate recap was rejected. Logged only — the UI silently keeps
/// the template.
enum RejectReason {
  tooShort,
  tooLong,
  unknownNumber,
  unknownName,
  forbiddenClaim,
}

/// Outcome of validating a model-generated recap against the facts.
class ValidationResult {
  const ValidationResult.ok() : ok = true, reason = null;

  const ValidationResult.failure(this.reason) : ok = false;

  final bool ok;
  final RejectReason? reason;
}

/// Small allowlist so natural sentence starters, months and weekdays are not
/// rejected as "unknown names". Keep it tight: a false reject only means the
/// template is shown instead of the AI text.
const _nameAllowlist = {
  // Sentence starters / connectors.
  'the', 'a', 'an', 'and', 'but', 'after', 'despite', 'in', 'on', 'at',
  'it', 'its', 'this', 'that', 'both', 'they', 'their', 'his', 'her',
  'there', 'here',
  // Common recap vocabulary.
  'goals', 'match', 'game', 'score', 'result', 'draw', 'win', 'loss',
  'defeat', 'victory', 'home', 'away', 'first', 'second', 'half', 'time',
  'extra', 'penalty', 'penalties', 'own', 'goal', 'kick', 'off', 'minute',
  'minutes', 'fixture', 'end', 'effort', 'strike', 'header', 'team',
  'side', 'clubs', 'club', 'fans', 'crowd', 'i',
  // Quantifiers and determiners that often start a sentence.
  'several', 'many', 'few', 'some', 'each', 'every', 'all', 'no', 'one',
  'two', 'three', 'four', 'five', 'neither', 'either', 'another', 'other',
  'more', 'most', 'only', 'just', 'even', 'such',
  // Connectors and sentence-opening adverbs.
  'however', 'meanwhile', 'later', 'earlier', 'then', 'finally', 'overall',
  'also', 'still', 'yet', 'so', 'while', 'when', 'before', 'with', 'without',
  'as', 'by', 'for', 'from', 'to', 'of', 'during', 'until', 'late', 'early',
  'shortly', 'soon', 'moments', 'once', 'following', 'ultimately',
  'together', 'altogether', 'not', 'nor', 'or', 'if', 'these', 'those',
  'he', 'she', 'we', 'you', 'who', 'which', 'what',
  // Card and discipline vocabulary.
  'yellow', 'red', 'card', 'cards', 'booking', 'bookings', 'booked',
  'caution', 'cautions', 'cautioned',
  // More recap vocabulary.
  'scorers', 'scorer', 'scoring', 'scored', 'equaliser', 'equalizer',
  'winner', 'opener', 'lead', 'hosts', 'visitors', 'players', 'player',
  'teams', 'sides', 'goalless', 'stoppage',
  // The fact lines include 'Round: N'.
  'round', 'matchweek', 'week',
  // All-caps abbreviation; whether a VAR mention is allowed is decided by
  // the forbidden-claims check below, not by the name check.
  'var',
  // Months and weekdays.
  'january', 'february', 'march', 'april', 'may', 'june', 'july',
  'august', 'september', 'october', 'november', 'december',
  'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday',
  'sunday',
};

/// Validates a model-generated recap. Every number must come from the fact
/// sheet, every capitalised word must match a known name (or the allowlist),
/// and injury/transfer/referee chatter is rejected outright unless it
/// appears in the facts themselves.
ValidationResult validateRecapText(String text, FactSheet facts) {
  final trimmed = text.trim();

  if (trimmed.length < 60) {
    debugPrint('validateRecapText: rejected (${RejectReason.tooShort.name})');
    return const ValidationResult.failure(RejectReason.tooShort);
  }
  if (trimmed.length > 600) {
    debugPrint('validateRecapText: rejected (${RejectReason.tooLong.name})');
    return const ValidationResult.failure(RejectReason.tooLong);
  }

  // Score separators (`–`/`-`) never match `\d+`, so they pass through here.
  final numberPattern = RegExp(r'\d+');
  for (final match in numberPattern.allMatches(trimmed)) {
    if (!facts.allowedNumbers.contains(match.group(0))) {
      debugPrint(
        'validateRecapText: rejected (${RejectReason.unknownNumber.name}: '
        '"${match.group(0)}")',
      );
      return const ValidationResult.failure(RejectReason.unknownNumber);
    }
  }

  // Capitalised words must be known names or allowlisted.
  //
  // The lookbehind instead of `\b` is deliberate: Dart's `\b` is ASCII-
  // based, so it sees no word boundary before a leading capital like
  // "Ødegaard" and the token would go unchecked. The continuation class
  // keeps hyphenated names ("Saka-Smith") together, and an apostrophe only
  // continues the match when a capital letter follows it: a name like
  // "O'Neill" is checked as one token, while a possessive like "Chelsea's"
  // still matches only "Chelsea". Internal capitals ("McGinn") are consumed
  // by the same match. The check below splits the normalised token on
  // spaces — the same way the fact sheet tokenises names — so each part of
  // a hyphenated or apostrophe name must be known on its own.
  final wordPattern = RegExp(
    r"(?<![\p{L}\p{N}])\p{Lu}[\p{L}-]*(?:['’]\p{Lu}[\p{L}-]*)*",
    unicode: true,
  );
  for (final match in wordPattern.allMatches(trimmed)) {
    final normalized = normalizeLookupText(match.group(0)!);
    if (normalized.isEmpty) continue;
    final parts = normalized.split(' ');
    final known = parts.every(
      (part) =>
          facts.allowedNameTokens.contains(part) ||
          _nameAllowlist.contains(part),
    );
    if (!known) {
      debugPrint(
        'validateRecapText: rejected (${RejectReason.unknownName.name}: '
        '"${match.group(0)}")',
      );
      return const ValidationResult.failure(RejectReason.unknownName);
    }
  }

  // Forbidden claims: reject unless the fact lines themselves mention them.
  // Unicode-aware lookarounds keep "suspended" matching only that word
  // family and VAR is case-sensitive so "various" never counts as a VAR
  // mention. Each claim word must appear in the fact text as a whole word —
  // a substring check would let a bare "VAR" through whenever the facts
  // contain a name like "Varane" or "Vardy". The lookarounds are used
  // instead of `\b` because Dart's `\b` is ASCII-based: it would see a
  // boundary inside a name like "Varé" (between "Var" and "é") and let a
  // bare "VAR" in the recap pass whenever an accented "Varé" appears in
  // the facts.
  final factText = facts.toFactLines().join(' ').toLowerCase();
  final claimPattern = RegExp(
    r'(?<![\p{L}\p{N}])(injur[\p{L}\p{N}]*|transfer[\p{L}\p{N}]*|referee|suspen[\p{L}\p{N}]*|sacked)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  final varPattern = RegExp(
    r'(?<![\p{L}\p{N}])VAR(?![\p{L}\p{N}])',
    unicode: true,
  );
  final matches = [
    ...claimPattern.allMatches(trimmed),
    ...varPattern.allMatches(trimmed),
  ];
  for (final match in matches) {
    final word = match.group(0)!.toLowerCase();
    final factWord = RegExp(
      '(?<![\\p{L}\\p{N}])${RegExp.escape(word)}(?![\\p{L}\\p{N}])',
      unicode: true,
    );
    if (!factWord.hasMatch(factText)) {
      debugPrint(
        'validateRecapText: rejected (${RejectReason.forbiddenClaim.name}: '
        '"${match.group(0)}")',
      );
      return const ValidationResult.failure(RejectReason.forbiddenClaim);
    }
  }

  return const ValidationResult.ok();
}
