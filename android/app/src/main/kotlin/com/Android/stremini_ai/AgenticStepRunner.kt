package com.Android.stremini_ai

import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject

/**
 * AgenticStepRunner
 *
 * Drives the multi-step voice automation loop on the Android side.
 * 1. Sends command + current screen state → /voice-command backend
 * 2. Receives action batch
 * 3. Executes each action via FullDeviceCommandExecutor / ScreenReaderService
 * 4. Repeats until done() action or max steps reached
 *
 * Usage:
 *   AgenticStepRunner.run(context, service, "Send WhatsApp to John saying Hello")
 */
object AgenticStepRunner {

    private const val TAG = "AgenticStepRunner"
    private const val MAX_STEPS = 20

    private val backendClient = AgenticBackendClient()

    data class RunResult(
        val success: Boolean,
        val steps: Int,
        val summary: String,
        val failedReason: String? = null
    )

    /**
     * Run an agentic task to completion.
     * Call from a coroutine scope (e.g. serviceScope).
     */
    suspend fun run(
        service: ScreenReaderService,
        command: String,
        onStatusUpdate: (String) -> Unit = {}
    ): RunResult = withContext(Dispatchers.IO) {

        Log.i(TAG, "Starting agentic run: $command")
        val history = mutableListOf<JSONObject>()
        var stepCount = 0
        var lastError: String? = null

        while (stepCount < MAX_STEPS) {
            stepCount++
            onStatusUpdate("Step $stepCount: thinking...")

            // 1. Get current screen state
            val screenState = withContext(Dispatchers.Main) {
                service.getVisibleScreenState()
            }

            // 2. Build request payload
            val payload = JSONObject().apply {
                put("command", command)
                put("ui_context", screenState)
                put("step", stepCount)
                put("history", JSONArray(history.map { it.toString() }))
                if (lastError != null) put("error", lastError)
            }

            // 3. Call backend
            val response = try {
                backendClient.callVoiceCommand(payload)
            } catch (e: Exception) {
                Log.e(TAG, "Backend call failed: ${e.message}", e)
                onStatusUpdate("Network error: ${e.message}")
                return@withContext RunResult(false, stepCount, "Network error", e.message)
            }

            val actions = response.optJSONArray("actions") ?: JSONArray()
            val isFastPath = response.optBoolean("fast_path", false)

            Log.d(TAG, "Got ${actions.length()} actions (fast_path=$isFastPath)")

            // 4. Execute each action
            var isDone = false
            var doneSummary = "Completed"

            for (i in 0 until actions.length()) {
                val action = actions.optJSONObject(i) ?: continue
                val actionType = action.optString("action", "")
                onStatusUpdate("Step $stepCount: $actionType")
                history.add(action)

                when (actionType) {
                    "done" -> {
                        isDone = true
                        doneSummary = action.optString("summary", "Task completed")
                        break
                    }
                    "request_screen" -> {
                        // Signal to refresh screen on next iteration
                        delay(500)
                        break // Break inner loop to re-read screen
                    }
                    else -> {
                        val success = withContext(Dispatchers.Main) {
                            try {
                                FullDeviceCommandExecutor.execute(action, service)
                            } catch (e: Exception) {
                                Log.e(TAG, "Action execution failed: $actionType", e)
                                lastError = e.message
                                false
                            }
                        }

                        if (!success) {
                            Log.w(TAG, "Action failed: $actionType")
                            lastError = "Action '$actionType' failed"
                        } else {
                            lastError = null
                        }

                        // Wait for UI to settle between actions
                        delay(getActionDelay(actionType))
                    }
                }
            }

            if (isDone) {
                Log.i(TAG, "Task complete: $doneSummary")
                onStatusUpdate("✅ $doneSummary")
                return@withContext RunResult(true, stepCount, doneSummary)
            }

            // Check if backend says we're done
            val backendDone = response.optBoolean("is_done", false)
            if (backendDone) {
                val summary = response.optString("summary", "Task completed")
                onStatusUpdate("✅ $summary")
                return@withContext RunResult(true, stepCount, summary)
            }
        }

        Log.w(TAG, "Max steps reached for: $command")
        onStatusUpdate("⚠️ Max steps reached")
        RunResult(false, stepCount, "Max steps reached", "Stopped after $MAX_STEPS steps")
    }

    /**
     * Single-shot execution — for simple commands that don't need a loop.
     */
    suspend fun runOnce(
        service: ScreenReaderService,
        command: String,
        onStatusUpdate: (String) -> Unit = {}
    ): RunResult = withContext(Dispatchers.IO) {

        val screenState = withContext(Dispatchers.Main) { service.getVisibleScreenState() }
        val payload = JSONObject().apply {
            put("command", command)
            put("ui_context", screenState)
            put("step", 1)
            put("history", JSONArray())
        }

        val response = try { backendClient.callVoiceCommand(payload) }
        catch (e: Exception) { return@withContext RunResult(false, 1, "Network error", e.message) }

        val actions = response.optJSONArray("actions") ?: JSONArray()
        var doneSummary = "Done"

        for (i in 0 until actions.length()) {
            val action = actions.optJSONObject(i) ?: continue
            val actionType = action.optString("action", "")
            if (actionType == "done") { doneSummary = action.optString("summary", "Done"); break }
            if (actionType == "request_screen") break
            withContext(Dispatchers.Main) {
                runCatching { FullDeviceCommandExecutor.execute(action, service) }
            }
            delay(getActionDelay(actionType))
        }

        RunResult(true, 1, doneSummary)
    }

    // -----------------------------------------------------------------------
    // Timing heuristics — how long to wait after each action type
    // -----------------------------------------------------------------------

    private fun getActionDelay(actionType: String): Long = when (actionType) {
        "open_app" -> 2000L
        "tap", "click" -> 600L
        "long_press" -> 800L
        "type", "input" -> 400L
        "scroll" -> 300L
        "swipe" -> 400L
        "home", "back", "recents" -> 700L
        "notifications", "quick_settings" -> 600L
        "screenshot" -> 1000L
        "volume", "brightness", "media_key" -> 200L
        "clipboard" -> 300L
        "wait" -> 0L // wait action handles its own delay
        else -> 400L
    }
}

// ============================================================================
// VoiceCommandBridge
//
// Drop-in replacement / enhancement for the existing voice command flow in
// ChatOverlayService. Replaces sendVoiceTaskCommandToAI with a proper
// agentic loop.
// ============================================================================

class VoiceCommandBridge(private val service: ScreenReaderService) {

    companion object {
        private const val TAG = "VoiceCommandBridge"
    }

    /**
     * Execute a voice command agentically.
     * Call from ChatOverlayService.executeVoiceCommand() or similar.
     */
    suspend fun execute(
        command: String,
        onStatus: (String) -> Unit,
        onOutput: (String) -> Unit
    ) {
        onStatus("🎙 Command: $command")
        onOutput("🎙 Command: $command\n\n⚙️ Processing...")

        // First try direct fast-path commands (no network needed)
        val fastResult = tryDirectCommand(command)
        if (fastResult != null) {
            onStatus("✅ ${fastResult.summary}")
            onOutput("🎙 Command: $command\n\n✅ ${fastResult.summary}")
            return
        }

        // Use full agentic runner
        onOutput("🎙 Command: $command\n\n🤖 AI is taking control...")
        val result = AgenticStepRunner.run(service, command) { status ->
            onStatus(status)
        }

        val statusIcon = if (result.success) "✅" else "⚠️"
        onStatus("$statusIcon ${result.summary}")
        onOutput("🎙 Command: $command\n\n$statusIcon Completed in ${result.steps} step(s)\n${result.summary}")
    }

    private suspend fun tryDirectCommand(command: String): AgenticStepRunner.RunResult? {
        val cmd = command.trim().lowercase()
        return when {
            cmd.contains("go home") || cmd == "home" -> {
                service.performGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME)
                AgenticStepRunner.RunResult(true, 1, "Went home")
            }
            cmd.contains("go back") || cmd == "back" -> {
                service.performGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
                AgenticStepRunner.RunResult(true, 1, "Went back")
            }
            cmd.contains("recent apps") -> {
                service.performGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_RECENTS)
                AgenticStepRunner.RunResult(true, 1, "Opened recents")
            }
            cmd.contains("take screenshot") || cmd == "screenshot" -> {
                service.takeScreenshot()
                AgenticStepRunner.RunResult(true, 1, "Screenshot taken")
            }
            cmd.contains("volume up") || cmd == "louder" -> {
                service.adjustVolume("up")
                AgenticStepRunner.RunResult(true, 1, "Volume increased")
            }
            cmd.contains("volume down") || cmd == "quieter" -> {
                service.adjustVolume("down")
                AgenticStepRunner.RunResult(true, 1, "Volume decreased")
            }
            cmd == "mute" || cmd.contains("silent mode") -> {
                service.adjustVolume("mute")
                AgenticStepRunner.RunResult(true, 1, "Muted")
            }
            cmd == "unmute" -> {
                service.adjustVolume("unmute")
                AgenticStepRunner.RunResult(true, 1, "Unmuted")
            }
            cmd == "pause" || cmd == "pause music" -> {
                service.sendMediaKey("pause")
                AgenticStepRunner.RunResult(true, 1, "Paused")
            }
            cmd == "play" || cmd == "resume" -> {
                service.sendMediaKey("play")
                AgenticStepRunner.RunResult(true, 1, "Playing")
            }
            cmd == "next" || cmd == "next song" || cmd == "skip" -> {
                service.sendMediaKey("next")
                AgenticStepRunner.RunResult(true, 1, "Next track")
            }
            cmd == "previous" || cmd == "previous song" -> {
                service.sendMediaKey("previous")
                AgenticStepRunner.RunResult(true, 1, "Previous track")
            }
            cmd.contains("scroll down") -> {
                service.scroll("down")
                AgenticStepRunner.RunResult(true, 1, "Scrolled down")
            }
            cmd.contains("scroll up") -> {
                service.scroll("up")
                AgenticStepRunner.RunResult(true, 1, "Scrolled up")
            }
            else -> null
        }
    }
}