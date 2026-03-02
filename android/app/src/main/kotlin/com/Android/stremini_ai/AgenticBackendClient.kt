package com.Android.stremini_ai

import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class AgenticBackendClient(
    private val baseUrl: String = "https://ai-keyboard-backend.vishwajeetadkine705.workers.dev"
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .build()

    fun callVoiceCommand(payload: JSONObject): JSONObject {
        val body = payload.toString().toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url("$baseUrl/voice-command")
            .post(body)
            .addHeader("Content-Type", "application/json")
            .build()
        client.newCall(request).execute().use { response ->
            val raw = response.body?.string() ?: "{}"
            return if (response.isSuccessful) {
                runCatching { JSONObject(raw) }.getOrElse { JSONObject() }
            } else {
                Log.e("AgenticBackendClient", "Backend error ${response.code}: $raw")
                JSONObject().apply { put("error", "HTTP ${response.code}") }
            }
        }
    }
}
