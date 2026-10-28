import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_service.dart';
import 'unavailable_ai_service.dart';

/// The app-wide [AiService]. Milestone 1 will swap this for the
/// GeminiNanoService when the platform plugin lands; until then every caller
/// transparently falls back to the template recap.
final aiServiceProvider =
    Provider<AiService>((ref) => const UnavailableAiService());
