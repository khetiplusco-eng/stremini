package com.Android.stremini_ai

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

class ScreenAnalysisClient(
    private val baseUrl: String = "https://ai-keyboard-backend.vishwajeetadkine705.workers.dev"
) {
    private val client = secureHttpClient(
        connectTimeoutSeconds = 30,
        readTimeoutSeconds = 30,
    )

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
