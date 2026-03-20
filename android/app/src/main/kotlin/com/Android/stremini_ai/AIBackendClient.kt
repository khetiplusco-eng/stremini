package com.Android.stremini_ai

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class AIBackendClient(
    private val baseUrl: String = "https://ai-keyboard-backend.vishwajeetadkine705.workers.dev"
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    suspend fun sendChatMessage(
        message: String,
        history: List<Map<String, String>> = emptyList()
    ): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            val historyArray = JSONArray()
            history.forEach { turn ->
                historyArray.put(JSONObject().apply {
                    put("role", turn["role"] ?: "user")
                    put("content", turn["content"] ?: "")
                })
            }
            val requestBody = JSONObject().apply {
                put("message", message)
                put("history", historyArray)
            }.toString().toRequestBody("application/json".toMediaType())

            val request = Request.Builder()
                .url("$baseUrl/chat/message")
                .post(requestBody)
                .build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("Server error: ${response.code}")
                val json = JSONObject(response.body?.string() ?: "{}")
                json.optString("reply", json.optString("response", json.optString("message", "No response")))
            }
        }
    }

    suspend fun sendDeviceCommand(command: String, screenContext: String): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            val requestJson = JSONObject().apply {
                put("message", command)
                put("screen_context", screenContext)
                put("mode", "device_control")
            }
            val requestBody = requestJson.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("$baseUrl/chat/message")
                .post(requestBody)
                .build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("Could not process command (${response.code})")
                val json = JSONObject(response.body?.string() ?: "{}")
                json.optString("reply", json.optString("response", json.optString("message", "Command processed")))
            }
        }
    }
}
