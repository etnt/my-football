import 'package:flutter/foundation.dart';

/// True when built with `--dart-define=AI_DIAGNOSTICS=true`. Shows the
/// "AI diagnostics" panel under the recap. The log always goes to logcat.
const bool aiDiagnostics = bool.fromEnvironment('AI_DIAGNOSTICS');

/// Recent on-device AI events, kept in memory for the "AI diagnostics" panel
/// and written to logcat via [debugPrint].
class AiLog {
  AiLog._();

  static const _maxLines = 40;

  /// Newest last. Each line is `HH:mm:ss message`.
  static final ValueNotifier<List<String>> lines = ValueNotifier(const []);

  static void add(String message) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    debugPrint('[AI recap] $message');
    final next = [...lines.value, '$stamp $message'];
    if (next.length > _maxLines) {
      next.removeRange(0, next.length - _maxLines);
    }
    lines.value = next;
  }

  static void clear() => lines.value = const [];
}
