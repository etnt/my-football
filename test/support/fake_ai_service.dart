import 'dart:async';

import 'package:my_football/features/ai/ai_service.dart';

/// Configurable [AiService] for recap tests: records calls, can delay,
/// throw, or return an invalid result.
class FakeAiService implements AiService {
  FakeAiService({
    this.available = true,
    this.responseText,
    this.errorCode,
    this.delay = Duration.zero,
    this.isAvailableDelay = Duration.zero,
    this.throwOnGenerate = false,
    this.throwOnIsAvailable = false,
    this.reason = AiReason.ok,
  });

  bool available;
  String? responseText;
  String? errorCode;
  Duration delay;

  /// Simulates an `isAvailable()` that never returns within [isAvailableDelay].
  Duration isAvailableDelay;
  bool throwOnGenerate;
  bool throwOnIsAvailable;
  AiReason reason;

  int isAvailableCalls = 0;
  int generateCalls = 0;
  List<String> prompts = [];

  @override
  Future<AiAvailability> isAvailable() async {
    isAvailableCalls++;
    if (isAvailableDelay > Duration.zero) {
      await Future<void>.delayed(isAvailableDelay);
    }
    if (throwOnIsAvailable) throw Exception('isAvailable failed');
    return AiAvailability(available: available, reason: reason);
  }

  @override
  Future<AiResult> generate({
    required String prompt,
    int maxTokens = 200,
    double temperature = 0.3,
  }) async {
    generateCalls++;
    prompts.add(prompt);
    if (throwOnGenerate) throw Exception('generate failed');
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (errorCode != null) return AiResult.failure(errorCode!);
    final text = responseText;
    if (text == null) return AiResult.failure('no-text');
    return AiResult.ok(text);
  }
}
