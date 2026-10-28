package com.myfootball.my_football

import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Method channel `my_football/ai` backed by ML Kit GenAI (Gemini Nano, direct
 * model access). Dart side: `GeminiNanoService`.
 *
 * Methods:
 * - `status` -> `{status: AVAILABLE | DOWNLOADABLE | DOWNLOADING | UNAVAILABLE | UNKNOWN}`
 * - `download` -> `"completed"`; errors if the download fails.
 * - `generate` (args: `prompt`, `maxTokens`, `temperature`) -> `String`.
 *
 * Failures are reported as `result.error("genai_error", message)`; nothing
 * throws across the channel.
 */
class GeminiNanoChannel(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    // ML Kit's suspend calls run on Main; replies must be delivered on Main too.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val model: GenerativeModel by lazy { Generation.getClient() }

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> scope.launch {
                guarded(result) {
                    val raw = model.checkStatus()
                    mapOf("status" to statusName(raw), "raw" to raw)
                }
            }

            "download" -> scope.launch {
                guarded(result) {
                    model.download().collect { status ->
                        if (status is DownloadStatus.DownloadFailed) {
                            throw status.e
                        }
                    }
                    "completed"
                }
            }

            "generate" -> {
                val prompt = call.argument<String>("prompt")
                val maxTokens = call.argument<Int>("maxTokens") ?: 200
                val temperature = call.argument<Double>("temperature") ?: 0.3
                if (prompt.isNullOrBlank()) {
                    result.error("bad_args", "prompt is required", null)
                    return
                }
                scope.launch {
                    guarded(result) {
                        val response = model.generateContent(
                            generateContentRequest(TextPart(prompt)) {
                                this.temperature = temperature.toFloat()
                                this.maxOutputTokens = maxTokens
                            },
                        )
                        response.candidates.firstOrNull()?.text
                            ?: throw IllegalStateException("empty response")
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    private suspend fun guarded(result: MethodChannel.Result, block: suspend () -> Any) {
        try {
            result.success(block())
        } catch (e: Exception) {
            result.error(
                "genai_error",
                "${e.javaClass.simpleName}: ${e.message ?: "no message"}",
                null,
            )
        }
    }

    private fun statusName(status: Int): String = when (status) {
        FeatureStatus.AVAILABLE -> "AVAILABLE"
        FeatureStatus.DOWNLOADABLE -> "DOWNLOADABLE"
        FeatureStatus.DOWNLOADING -> "DOWNLOADING"
        FeatureStatus.UNAVAILABLE -> "UNAVAILABLE"
        else -> "UNKNOWN"
    }

    companion object {
        const val CHANNEL = "my_football/ai"
    }
}
