package com.myfootball.my_football

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Gemini Nano bridge for AiService (see lib/features/ai/gemini_nano_service.dart).
        GeminiNanoChannel(flutterEngine.dartExecutor.binaryMessenger)
    }
}
