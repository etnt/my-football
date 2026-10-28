import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/ai/ai_service.dart';
import 'package:my_football/features/ai/gemini_nano_service.dart';

const _channel = MethodChannel('my_football/ai');

void _mock(
  TestDefaultBinaryMessengerBinding binding,
  Future<Object?> Function(MethodCall call) handler,
) {
  binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final binding = TestDefaultBinaryMessengerBinding.instance;

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  group('aiAvailabilityFromStatus', () {
    test('maps each FeatureStatus to a reason', () {
      expect(aiAvailabilityFromStatus('AVAILABLE').reason, AiReason.ok);
      expect(aiAvailabilityFromStatus('AVAILABLE').available, isTrue);
      expect(
        aiAvailabilityFromStatus('DOWNLOADABLE').reason,
        AiReason.modelNotInstalled,
      );
      expect(
        aiAvailabilityFromStatus('DOWNLOADING').reason,
        AiReason.modelDownloading,
      );
      expect(
        aiAvailabilityFromStatus('UNAVAILABLE').reason,
        AiReason.deviceUnsupported,
      );
    });

    test('unknown or missing status is not available', () {
      final a = aiAvailabilityFromStatus('SOMETHING_NEW');
      expect(a.available, isFalse);
      expect(a.reason, AiReason.unknown);
      expect(aiAvailabilityFromStatus(null).available, isFalse);
    });
  });

  group('GeminiNanoService', () {
    test('isAvailable reads the status from the channel', () async {
      _mock(binding, (call) async {
        expect(call.method, 'status');
        return {'status': 'AVAILABLE'};
      });
      final a = await GeminiNanoService().isAvailable();
      expect(a.available, isTrue);
    });

    test('isAvailable treats a missing plugin as OS unsupported', () async {
      // No mock handler registered: the channel raises MissingPluginException.
      final a = await GeminiNanoService().isAvailable();
      expect(a.available, isFalse);
      expect(a.reason, AiReason.osUnsupported);
    });

    test('isAvailable turns a platform error into unknown', () async {
      _mock(binding, (call) async {
        throw PlatformException(code: 'genai_error', message: 'boom');
      });
      final a = await GeminiNanoService().isAvailable();
      expect(a.available, isFalse);
      expect(a.reason, AiReason.unknown);
    });

    test('generate passes arguments and returns the text', () async {
      _mock(binding, (call) async {
        expect(call.method, 'generate');
        expect(call.arguments, {
          'prompt': 'hello',
          'maxTokens': 50,
          'temperature': 0.2,
        });
        return 'Arsenal won 2-1.';
      });
      final r = await GeminiNanoService().generate(
        prompt: 'hello',
        maxTokens: 50,
        temperature: 0.2,
      );
      expect(r.text, 'Arsenal won 2-1.');
      expect(r.errorCode, isNull);
    });

    test('generate maps a platform error to its code', () async {
      _mock(binding, (call) async {
        throw PlatformException(code: 'genai_error', message: 'quota');
      });
      final r = await GeminiNanoService().generate(prompt: 'hello');
      expect(r.text, isNull);
      expect(r.errorCode, 'genai_error');
    });

    test('generate treats an empty reply as a failure', () async {
      _mock(binding, (call) async => '   ');
      final r = await GeminiNanoService().generate(prompt: 'hello');
      expect(r.text, isNull);
      expect(r.errorCode, 'empty');
    });
  });
}
