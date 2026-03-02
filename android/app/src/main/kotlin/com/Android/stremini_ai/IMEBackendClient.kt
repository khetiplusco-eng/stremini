package com.Android.stremini_ai

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class IMEBackendClient(
    private val baseUrl: String = "https://ai-keyboard-backend.vishwajeetadkine705.workers.dev"
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    fun requestKeyboardAction(
        originalText: String,
        appContext: String,
        actionType: String,
        selectedTone: String,
    ): Result<String> = runCatching {
        val json = JSONObject().apply {
            put("text", originalText)
            put("appContext", appContext)
            if (actionType == "tone") put("tone", selectedTone)
        }

        val endpoint = when (actionType) {
            "complete" -> "complete"
            "tone" -> "tone"
            else -> "correct"
        }

        val request = Request.Builder()
            .url("$baseUrl/keyboard/$endpoint")
            .post(json.toString().toRequestBody("application/json".toMediaType()))
            .build()

        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful || body.isBlank()) return@use ""
            val resultJson = JSONObject(body)
            when (actionType) {
                "complete" -> resultJson.optString("completion")
                "tone" -> resultJson.optString("rewritten")
                    .ifBlank { resultJson.optString("result") }
                    .ifBlank { resultJson.optString("text") }
                    .ifBlank { resultJson.optString("corrected") }
                else -> resultJson.optString("corrected")
            }
        }
    }
}
