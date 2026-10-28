import 'ai_service.dart';

/// A no-op [AiService] used whenever on-device generation is not available
/// (unsupported device, model not downloaded, or the platform plugin is not
/// wired up yet). Never throws: every call degrades gracefully.
class UnavailableAiService implements AiService {
  const UnavailableAiService([this.reason = AiReason.deviceUnsupported]);

  final AiReason reason;

  @override
  Future<AiAvailability> isAvailable() async {
    return AiAvailability(available: false, reason: reason);
  }

  @override
  Future<AiResult> generate({
    required String prompt,
    int maxTokens = 200,
    double temperature = 0.3,
  }) async {
    return AiResult.failure('unavailable');
  }
}
