import '../recap/fact_sheet.dart';

/// Version tag embedded in recap cache keys. Bumping it invalidates cached
/// model recaps when the prompt changes; the template is rebuilt every time
/// and never cached.
const recapPromptVersion = 'v1';

/// Builds the prompt sent to the on-device model for a match recap.
String buildRecapPrompt(FactSheet f) {
  final buffer = StringBuffer()
    ..writeln('Write a short match recap in plain English.')
    ..writeln('Rules:')
    ..writeln('- 2 to 4 sentences.')
    ..writeln('- Use only the facts listed below.')
    ..writeln('- Do not invent names, numbers, injuries, transfers or')
    ..writeln('  referee decisions that are not in the facts.')
    ..writeln('- Do not add opinions or clichés.')
    ..writeln('Facts:')
    ..write(f.toFactLines().join('\n'));
  return buffer.toString();
}
