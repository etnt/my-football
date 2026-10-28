/// Why an on-device model is (or is not) currently usable.
enum AiReason {
  ok,
  deviceUnsupported,
  modelDownloading,
  modelNotInstalled,
  osUnsupported,
  disabled,
  unknown,
}

/// Whether an [AiService] can generate text right now.
class AiAvailability {
  const AiAvailability({required this.available, required this.reason});

  final bool available;
  final AiReason reason;
}

/// The result of a text generation attempt.
class AiResult {
  const AiResult._({this.text, this.errorCode});

  factory AiResult.ok(String text) => AiResult._(text: text);

  factory AiResult.failure(String code) => AiResult._(errorCode: code);

  final String? text;
  final String? errorCode;
}

/// Abstraction over the on-device LLM. Milestone 1 will back this with
/// GeminiNanoService; for now `aiServiceProvider` provides the fallback.
abstract class AiService {
  Future<AiAvailability> isAvailable();

  Future<AiResult> generate({
    required String prompt,
    int maxTokens = 200,
    double temperature = 0.3,
  });
}
