package com.Android.stremini_ai

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

class ChatCommandCoordinator(
    private val scope: CoroutineScope,
    private val backendClient: AIBackendClient,
    private val onBotMessage: (String) -> Unit,
) {
    private val sessionHistory = mutableListOf<Map<String, String>>()

    fun processUserMessage(userMessage: String) {
        scope.launch {
            sessionHistory.add(mapOf("role" to "user", "content" to userMessage))
            if (sessionHistory.size > 20) sessionHistory.removeAt(0)

            val historyToSend = sessionHistory.dropLast(1)

            backendClient.sendChatMessage(userMessage, historyToSend)
                .onSuccess { reply ->
                    sessionHistory.add(mapOf("role" to "assistant", "content" to reply))
                    onBotMessage(reply)
                }
                .onFailure { error ->
                    sessionHistory.removeLastOrNull()
                    onBotMessage("⚠️ ${error.message}")
                }
        }
    }

    fun clearHistory() {
        sessionHistory.clear()
    }
}
