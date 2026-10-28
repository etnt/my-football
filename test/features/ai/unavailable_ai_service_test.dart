import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/ai/ai_service.dart';
import 'package:my_football/features/ai/unavailable_ai_service.dart';

void main() {
  test('isAvailable reports false with the reason given at construction',
      () async {
    final service = const UnavailableAiService(AiReason.modelNotInstalled);

    final availability = await service.isAvailable();

    expect(availability.available, isFalse);
    expect(availability.reason, AiReason.modelNotInstalled);
  });

  test('isAvailable defaults to deviceUnsupported', () async {
    final availability = await const UnavailableAiService().isAvailable();

    expect(availability.available, isFalse);
    expect(availability.reason, AiReason.deviceUnsupported);
  });

  test('generate returns a failure and never throws', () async {
    final service = const UnavailableAiService();

    final result = await service.generate(prompt: 'write a recap');

    expect(result.text, isNull);
    expect(result.errorCode, 'unavailable');
  });

  test('generate works for every reason variant', () async {
    for (final reason in AiReason.values) {
      final service = UnavailableAiService(reason);
      final availability = await service.isAvailable();
      expect(availability.reason, reason);
      final result = await service.generate(prompt: 'x');
      expect(result.errorCode, 'unavailable');
    }
  });
}
