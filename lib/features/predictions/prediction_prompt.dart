import '../../core/text/lookup_text_normalizer.dart';
import '../../models/fixture.dart';
import 'prediction_result.dart';

/// Version tag embedded in the prediction cache key (via the narrator).
/// Bumping it invalidates cached AI summaries when the prompt changes.
const predictionPromptVersion = 'v1';

/// Builds the prompt sent to the on-device model for one prediction.
///
/// It contains only what the app already computed: the team names, the
/// verdict, the three percentages and the deterministic reason texts. The
/// model may only rewrite these into plain prose — it never picks the
/// outcome and must not add facts (plan CON-001).
///
/// The wording avoids every word the text validator forbids ("odds", the
/// "bet" word family, "guarantee"/"calibrated"), so a faithful model answer
/// cannot be rejected for repeating the prompt.
String buildPredictionPrompt(Fixture fixture, PredictionResult result) {
  final percents = result.displayPercents;
  final buffer = StringBuffer()
    ..writeln('Write a short summary of a football match prediction.')
    ..writeln('The prediction was already calculated by the app.')
    ..writeln('Rules:')
    ..writeln('- 2 to 3 plain sentences.')
    ..writeln('- Use only the facts listed below.')
    ..writeln('- Do not add new facts, names or numbers.')
    ..writeln('- Do not give gambling advice.')
    ..writeln('Fixture: ${fixture.homeName} vs ${fixture.awayName}')
    ..writeln('Verdict: ${_verdictText(result)}')
    ..writeln(
      'Chances: ${fixture.homeName} ${percents[Outcome.home]}%, '
      'Draw ${percents[Outcome.draw]}%, '
      '${fixture.awayName} ${percents[Outcome.away]}%.',
    )
    ..writeln('Reasons:')
    ..write(result.reasons.map((r) => '- ${r.text}').join('\n'));
  return buffer.toString();
}

/// Same wording as the sheet's verdict line, so the model quotes what the
/// user sees.
String _verdictText(PredictionResult result) {
  final slight = result.isSlight ? ' – slight favourite' : '';
  return switch (result.verdict) {
    Verdict.homeWin => 'Home win$slight',
    Verdict.awayWin => 'Away win$slight',
    Verdict.tooClose => 'Too close to call',
  };
}

/// Every `\d+` run the model output may contain: the displayed percentages,
/// the numbers quoted in the reason texts (including digits inside values
/// like `2.1` and inside the reason texts themselves), and digits that
/// appear inside the team names. The validator applies the same `\d+` rule,
/// so the two stay in parity.
Set<String> predictionAllowedNumbers(Fixture fixture, PredictionResult result) {
  final set = <String>{};
  void addRuns(String raw) {
    for (final match in RegExp(r'\d+').allMatches(raw)) {
      set.add(match.group(0)!);
    }
  }

  for (final percent in result.displayPercents.values) {
    addRuns(percent.toString());
  }
  for (final reason in result.reasons) {
    addRuns(reason.text);
    for (final value in reason.numbers.values) {
      addRuns(value.toString());
    }
  }
  addRuns(fixture.homeName);
  addRuns(fixture.awayName);
  return set;
}

/// Normalised name tokens the model output may mention: the two team names.
/// The validator adds a fixed sentence/vocabulary allowlist on top; deriving
/// it from the reason texts would be looser and harder to reason about,
/// because the reason texts use a small fixed vocabulary anyway.
Set<String> predictionAllowedNameTokens(Fixture fixture) {
  final tokens = <String>{};
  for (final name in [fixture.homeName, fixture.awayName]) {
    final normalized = normalizeLookupText(name);
    for (final token in normalized.split(' ')) {
      if (token.isNotEmpty) tokens.add(token);
    }
  }
  return tokens;
}
