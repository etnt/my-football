import 'package:flutter/foundation.dart';

/// Recent on-device AI events, kept in memory and shown in the recap's
/// "AI diagnostics" panel. Also written to logcat via [debugPrint].
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
