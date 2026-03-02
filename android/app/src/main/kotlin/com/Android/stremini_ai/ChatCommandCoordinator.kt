package com.Android.stremini_ai

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

class ChatCommandCoordinator(
    private val scope: CoroutineScope,
    private val backendClient: AIBackendClient,
    private val deviceCommandRouter: DeviceCommandRouter,
    private val onBotMessage: (String) -> Unit,
) {
    fun processUserMessage(userMessage: String) {
        scope.launch {
            if (deviceCommandRouter.isDeviceCommand(userMessage)) {
                val success = deviceCommandRouter.executeDirect(userMessage)
                if (success) {
                    onBotMessage("✅ Done! Command executed successfully.")
                } else {
                    handleDeviceFallback(userMessage)
                }
                return@launch
            }

            backendClient.sendChatMessage(userMessage)
                .onSuccess { reply -> onBotMessage(reply) }
                .onFailure { error -> onBotMessage("⚠️ ${error.message}") }
        }
    }

    private suspend fun handleDeviceFallback(command: String) {
        val screenContext = buildScreenContext()
        backendClient.sendDeviceCommand(command, screenContext)
            .onSuccess { reply -> onBotMessage(reply) }
            .onFailure { error -> onBotMessage("⚠️ ${error.message}") }
    }

    private fun buildScreenContext(): String {
        return try {
            ScreenReaderService.getInstance()?.let { service ->
                val root = service.rootInActiveWindow
                val sb = StringBuilder()
                fun traverse(node: android.view.accessibility.AccessibilityNodeInfo) {
                    val text = node.text?.toString() ?: node.contentDescription?.toString()
                    if (!text.isNullOrBlank()) sb.appendLine(text.trim())
                    for (i in 0 until node.childCount) node.getChild(i)?.let { traverse(it) }
                }
                root?.let { traverse(it) }
                sb.toString().take(1000)
            } ?: ""
        } catch (_: Exception) {
            ""
        }
    }
}
