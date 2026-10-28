import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_service.dart';
import 'gemini_nano_service.dart';
import 'unavailable_ai_service.dart';

/// The app-wide [AiService]. Gemini Nano on Android; every other platform
/// uses the fallback, so callers always degrade to the template recap.
final aiServiceProvider = Provider<AiService>((ref) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return GeminiNanoService();
  }
  return const UnavailableAiService(AiReason.osUnsupported);
});
