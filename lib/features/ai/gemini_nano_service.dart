import 'package:flutter/services.dart';

import 'ai_log.dart';
import 'ai_service.dart';

/// Maps the native `status` string (ML Kit `FeatureStatus`) to an [AiAvailability].
AiAvailability aiAvailabilityFromStatus(String? status) {
  switch (status) {
    case 'AVAILABLE':
      return const AiAvailability(available: true, reason: AiReason.ok);
    case 'DOWNLOADABLE':
      return const AiAvailability(
        available: false,
        reason: AiReason.modelNotInstalled,
      );
    case 'DOWNLOADING':
      return const AiAvailability(
        available: false,
        reason: AiReason.modelDownloading,
      );
    case 'UNAVAILABLE':
      return const AiAvailability(
        available: false,
        reason: AiReason.deviceUnsupported,
      );
    default:
      return const AiAvailability(available: false, reason: AiReason.unknown);
  }
}

/// [AiService] backed by Gemini Nano through ML Kit GenAI on Android.
///
/// Talks to the `my_football/ai` method channel implemented in
/// `GeminiNanoChannel.kt`. Never throws: platform errors become
/// unavailability or a failed [AiResult], so callers fall back to the template.
class GeminiNanoService implements AiService {
  GeminiNanoService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'my_football/ai';

  final MethodChannel _channel;

  @override
  Future<AiAvailability> isAvailable() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('status');
      final status = result?['status'] as String?;
      if (status == null || status == 'UNKNOWN') {
        AiLog.add('status: ${status ?? 'missing'} raw=${result?['raw']}');
      }
      return aiAvailabilityFromStatus(status);
    } on MissingPluginException {
      AiLog.add('status: channel not registered (MissingPluginException)');
      return const AiAvailability(
        available: false,
        reason: AiReason.osUnsupported,
      );
    } on PlatformException catch (e) {
      AiLog.add('status error: ${e.code}: ${e.message ?? 'no message'}');
      return const AiAvailability(available: false, reason: AiReason.unknown);
    }
  }

  /// Starts the model download when the status is `DOWNLOADABLE`. Returns
  /// `completed`, or throws a [PlatformException] on failure.
  Future<String> download() async {
    final result = await _channel.invokeMethod<String>('download');
    return result ?? 'completed';
  }

  @override
  Future<AiResult> generate({
    required String prompt,
    int maxTokens = 200,
    double temperature = 0.3,
  }) async {
    try {
      final text = await _channel.invokeMethod<String>('generate', {
        'prompt': prompt,
        'maxTokens': maxTokens,
        'temperature': temperature,
      });
      if (text == null || text.trim().isEmpty) {
        return AiResult.failure('empty');
      }
      return AiResult.ok(text);
    } on MissingPluginException {
      return AiResult.failure('unavailable');
    } on PlatformException catch (e) {
      return AiResult.failure(e.code);
    }
  }
}
