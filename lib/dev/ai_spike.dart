/// Debug-only Gemini Nano probe for the Milestone 1 spike.
///
/// Logs availability, the download step (if needed), and the latency and
/// output of one sample generation. Enable with:
///
/// ```bash
/// flutter run --dart-define=AI_SPIKE=true
/// ```
///
/// Read the output with `flutter logs` or the `flutter run` console, filtering
/// for `[AI spike]`. Has no effect when the flag is absent.
library;

import 'package:flutter/foundation.dart';

import '../features/ai/ai_service.dart';
import '../features/ai/gemini_nano_service.dart';

/// True when the app was launched with `--dart-define=AI_SPIKE=true`.
const bool aiSpike = bool.fromEnvironment('AI_SPIKE');

const _samplePrompt =
    'Write a two-sentence match recap using only these facts. '
    'Match: Arsenal 2-1 Chelsea. Goals: Saka 12 minutes, Palmer 34 minutes, '
    'Gabriel 77 minutes (penalty).';

Future<void> runAiSpike(GeminiNanoService service) async {
  void log(String msg) => debugPrint('[AI spike] $msg');

  try {
    final availability = await service.isAvailable();
    log(
      'availability: available=${availability.available} '
      'reason=${availability.reason.name}',
    );

    if (!availability.available &&
        availability.reason == AiReason.modelNotInstalled) {
      log('downloading model...');
      final sw = Stopwatch()..start();
      log(
        'download: ${await service.download()} in ${sw.elapsedMilliseconds} ms',
      );
    }

    final recheck = await service.isAvailable();
    log('availability after download: reason=${recheck.reason.name}');
    if (!recheck.available) return;

    for (var i = 1; i <= 2; i++) {
      final sw = Stopwatch()..start();
      final result = await service.generate(prompt: _samplePrompt);
      log(
        'generate #$i: ${sw.elapsedMilliseconds} ms, '
        'text=${result.text ?? 'null'}, error=${result.errorCode ?? 'none'}',
      );
    }
  } catch (e) {
    log('failed: $e');
  }
}
