package com.Android.stremini_ai

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class ScreenAnalysisClient(
    private val baseUrl: String = "https://ai-keyboard-backend.vishwajeetadkine705.workers.dev"
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .build()

    fun analyzeText(content: String): Result<JSONObject> = runCatching {
        val requestBody = JSONObject().apply {
            put("text", content.take(5000))
        }.toString().toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url("$baseUrl/security/analyze/text")
            .post(requestBody)
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("HTTP ${response.code}")
            JSONObject(response.body?.string() ?: "{}")
        }
    }
}
