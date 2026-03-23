package com.Android.stremini_ai

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import kotlinx.coroutines.delay

/**
 * FullDeviceCommandExecutor
 *
 * A complete mapping from backend JSON action objects → live Android device operations.
 * Plug this into ScreenReaderService.executeBackendSteps() or call directly from
 * AgenticStepRunner after every /voice-command response.
 *
 * Supported action types (mirrors automation.js):
 *   tap, long_press, type, scroll, swipe, open_app, home, back, recents,
 *   notifications, quick_settings, screenshot, volume, media_key, brightness,
 *   clipboard, wait, request_screen, done
 */
object FullDeviceCommandExecutor {

    private const val TAG = "FullDeviceCmdExec"
    private const val PREFS_NAME = "security_prefs"
    private const val ALLOW_HIGH_RISK_ACTIONS_KEY = "allow_high_risk_actions"

    /**
     * Execute a single JSON action object from the backend.
     * Returns true on success, false on failure.
     */
    suspend fun execute(
        action: org.json.JSONObject,
        service: ScreenReaderService
    ): Boolean {
        val type = action.optString("action", "").lowercase().trim()
        if (isHighRiskAction(type) && !isHighRiskActionAllowed(service)) {
            Log.w(TAG, "Blocked high-risk action without explicit opt-in: $type")
            return false
        }
        Log.d(TAG, "Executing action: $type")

        return when (type) {

            // ----------------------------------------------------------------
            // UI INTERACTIONS
            // ----------------------------------------------------------------
            "tap", "click" -> {
                val text = action.optString("target_text", "")
                val coordsArr = action.optJSONArray("coordinates")
                if (coordsArr != null && coordsArr.length() >= 2) {
                    val x = coordsArr.optDouble(0).toFloat()
                    val y = coordsArr.optDouble(1).toFloat()
                    service.tapAtCoordinates(x, y)
                } else if (text.isNotBlank()) {
                    service.clickNodeByText(text)
                } else false
            }

            "long_press" -> {
                val text = action.optString("target_text", "")
                if (text.isNotBlank()) service.longPressNodeByText(text) else false
            }

            "type", "input" -> {
                val text = action.optString("text", "")
                val clearFirst = action.optBoolean("clear_first", false)
                if (text.isBlank()) return false
                if (clearFirst) service.clearFocusedField()
                service.typeText(text)
            }

            "scroll" -> {
                val direction = action.optString("direction", "down").lowercase()
                val amount = action.optInt("amount", 1)
                repeat(amount.coerceIn(1, 15)) {
                    service.scroll(direction)
                    delay(100)
                }
                true
            }

            "swipe" -> {
                val from = action.optJSONArray("from")
                val to = action.optJSONArray("to")
                val duration = action.optLong("duration_ms", 300L)
                if (from != null && to != null && from.length() >= 2 && to.length() >= 2) {
                    service.swipe(
                        from.optDouble(0).toFloat(), from.optDouble(1).toFloat(),
                        to.optDouble(0).toFloat(), to.optDouble(1).toFloat(),
                        duration
                    )
                } else false
            }

            // ----------------------------------------------------------------
            // APP MANAGEMENT
            // ----------------------------------------------------------------
            "open_app", "launch_app" -> {
                val appName = action.optString("app_name", "")
                val pkg = action.optString("package", "")
                when {
                    pkg.isNotBlank() -> service.openAppByPackage(pkg) || service.openAppByName(appName)
                    appName.isNotBlank() -> service.openAppByName(appName)
                    else -> false
                }
            }

            // ----------------------------------------------------------------
            // GLOBAL NAVIGATION
            // ----------------------------------------------------------------
            "home" -> service.performGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME)
            "back" -> service.performGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
            "recents" -> service.performGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_RECENTS)
            "notifications" -> service.performGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)
            "quick_settings" -> service.performGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS)
            "screenshot" -> service.takeScreenshot()
            "power_menu" -> service.performGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_POWER_DIALOG)

            // ----------------------------------------------------------------
            // VOLUME CONTROL
            // ----------------------------------------------------------------
            "volume" -> {
                val direction = action.optString("direction", "up").lowercase()
                service.adjustVolume(direction)
            }

            // ----------------------------------------------------------------
            // MEDIA KEYS
            // ----------------------------------------------------------------
            "media_key" -> {
                val key = action.optString("key", "play").lowercase()
                service.sendMediaKey(key)
            }

            // ----------------------------------------------------------------
            // BRIGHTNESS
            // ----------------------------------------------------------------
            "brightness" -> {
                val direction = action.optString("direction", "up").lowercase()
                val value = if (action.has("value")) action.optInt("value", -1) else -1
                service.adjustBrightness(direction, value)
            }

            // ----------------------------------------------------------------
            // CLIPBOARD
            // ----------------------------------------------------------------
            "clipboard" -> {
                val operation = action.optString("operation", "copy").lowercase()
                service.clipboardOperation(operation)
            }

            // ----------------------------------------------------------------
            // TIMING
            // ----------------------------------------------------------------
            "wait", "delay" -> {
                val ms = action.optLong("duration_ms", 1000L).coerceIn(100L, 10000L)
                delay(ms)
                true
            }

            // ----------------------------------------------------------------
            // SCREEN REFRESH (triggers a screen re-read in the agentic loop)
            // ----------------------------------------------------------------
            "request_screen" -> true // Handled externally by the step runner

            // ----------------------------------------------------------------
            // COMPLETION
            // ----------------------------------------------------------------
            "done" -> {
                val summary = action.optString("summary", "Task complete")
                Log.i(TAG, "DONE: $summary")
                true
            }

            else -> {
                Log.w(TAG, "Unknown action type: $type")
                false
            }
        }
    }

    private fun isHighRiskAction(type: String): Boolean = type in setOf(
        "open_app",
        "launch_app",
        "type",
        "input",
        "clipboard",
        "screenshot",
        "media_key",
        "power_menu",
    )

    private fun isHighRiskActionAllowed(service: ScreenReaderService): Boolean {
        val prefs = service.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(ALLOW_HIGH_RISK_ACTIONS_KEY, false)
    }
}

// ============================================================================
// Extension functions added to ScreenReaderService
// (Add these to the bottom of ScreenReaderService.kt or call via companion)
// ============================================================================

/**
 * These are public entry-points that the AgenticStepRunner calls.
 * They delegate to existing private helpers already in ScreenReaderService,
 * making them accessible from FullDeviceCommandExecutor.
 */
fun ScreenReaderService.tapAtCoordinates(x: Float, y: Float): Boolean =
    performTapGesture(x, y)

fun ScreenReaderService.clickNodeByText(text: String): Boolean {
    val root = rootInActiveWindow ?: return false
    val node = findFirstAccessibleNode(root) { node ->
        val t = node.text?.toString()?.lowercase().orEmpty()
        val d = node.contentDescription?.toString()?.lowercase().orEmpty()
        t.contains(text.lowercase()) || d.contains(text.lowercase())
    }
    if (node != null) {
        val bounds = android.graphics.Rect()
        node.getBoundsInScreen(bounds)
        return performAccessibilityClick(node) || performTapGesture(bounds.exactCenterX(), bounds.exactCenterY())
    }
    return false
}

fun ScreenReaderService.longPressNodeByText(text: String): Boolean {
    val root = rootInActiveWindow ?: return false
    val node = findFirstAccessibleNode(root) { n ->
        val t = n.text?.toString()?.lowercase().orEmpty()
        val d = n.contentDescription?.toString()?.lowercase().orEmpty()
        t.contains(text.lowercase()) || d.contains(text.lowercase())
    }
    if (node != null) {
        val bounds = android.graphics.Rect()
        node.getBoundsInScreen(bounds)
        if (node.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)) return true
        return performLongPressGesture(bounds.exactCenterX(), bounds.exactCenterY())
    }
    return false
}

fun ScreenReaderService.clearFocusedField(): Boolean {
    val root = rootInActiveWindow ?: return false
    val node = findFirstAccessibleNode(root) { it.isFocused && it.isEditable }
        ?: findFirstAccessibleNode(root) { it.isEditable }
    if (node != null) {
        // Select all + delete
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val selectArgs = Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, 0)
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, node.text?.length ?: 0)
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selectArgs)
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }
    return false
}

fun ScreenReaderService.typeText(text: String): Boolean {
    val root = rootInActiveWindow ?: return false
    val node = findFirstAccessibleNode(root) { it.isFocused && it.isEditable }
        ?: findFirstAccessibleNode(root) { it.isEditable }
    if (node != null) {
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }
    return false
}

fun ScreenReaderService.scroll(direction: String): Boolean {
    val root = rootInActiveWindow ?: return false
    val scrollable = findFirstAccessibleNode(root) { it.isScrollable }
    return when (direction) {
        "down", "forward" -> scrollable?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) ?: false
        "up", "backward" -> scrollable?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD) ?: false
        "left" -> scrollable?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD) ?: false
        "right" -> scrollable?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) ?: false
        else -> false
    }
}

fun ScreenReaderService.swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean =
    performGestureSwipe(x1, y1, x2, y2, durationMs)

fun ScreenReaderService.openAppByPackage(pkg: String): Boolean {
    val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    startActivity(intent)
    return true
}

fun ScreenReaderService.performGlobal(action: Int): Boolean =
    performGlobalAction(action)

fun ScreenReaderService.takeScreenshot(): Boolean =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
        performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_TAKE_SCREENSHOT)
    else false

fun ScreenReaderService.adjustVolume(direction: String): Boolean {
    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
    return try {
        when (direction) {
            "up" -> am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
            "down" -> am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
            "mute" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                am.adjustStreamVolume(AudioManager.STREAM_RING, AudioManager.ADJUST_MUTE, 0)
            else @Suppress("DEPRECATION") am.ringerMode = AudioManager.RINGER_MODE_SILENT
            "unmute" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                am.adjustStreamVolume(AudioManager.STREAM_RING, AudioManager.ADJUST_UNMUTE, 0)
            else @Suppress("DEPRECATION") am.ringerMode = AudioManager.RINGER_MODE_NORMAL
        }
        true
    } catch (e: Exception) { Log.e("Volume", "adjustVolume failed", e); false }
}

fun ScreenReaderService.sendMediaKey(key: String): Boolean {
    return try {
        val keyCode = when (key) {
            "play" -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY
            "pause" -> android.view.KeyEvent.KEYCODE_MEDIA_PAUSE
            "play_pause" -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "next" -> android.view.KeyEvent.KEYCODE_MEDIA_NEXT
            "previous", "prev" -> android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS
            "stop" -> android.view.KeyEvent.KEYCODE_MEDIA_STOP
            else -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        }
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, keyCode))
        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, keyCode))
        true
    } catch (e: Exception) { Log.e("Media", "sendMediaKey failed", e); false }
}

fun ScreenReaderService.adjustBrightness(direction: String, value: Int): Boolean {
    return try {
        val current = android.provider.Settings.System.getInt(
            contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS, 128
        )
        val newValue = when {
            value in 0..255 -> value
            direction == "up" -> minOf(255, current + 50)
            direction == "down" -> maxOf(0, current - 50)
            else -> current
        }
        android.provider.Settings.System.putInt(
            contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS, newValue
        )
        true
    } catch (e: Exception) {
        Log.e("Brightness", "adjustBrightness failed", e)
        false
    }
}

fun ScreenReaderService.clipboardOperation(operation: String): Boolean {
    val root = rootInActiveWindow ?: return false
    val node = findFirstAccessibleNode(root) { it.isFocused } ?: findFirstAccessibleNode(root) { it.isEditable }
    return when (operation) {
        "copy" -> node?.performAction(AccessibilityNodeInfo.ACTION_COPY) ?: false
        "paste" -> node?.performAction(AccessibilityNodeInfo.ACTION_PASTE) ?: false
        "cut" -> node?.performAction(AccessibilityNodeInfo.ACTION_CUT) ?: false
        "select_all" -> {
            node?.performAction(AccessibilityNodeInfo.ACTION_SELECT) ?: false
        }
        else -> false
    }
}

fun ScreenReaderService.performAccessibilityClick(node: AccessibilityNodeInfo?): Boolean {
    var current = node
    while (current != null) {
        if (current.isClickable) return current.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        current = current.parent
    }
    return false
}

fun ScreenReaderService.findFirstAccessibleNode(
    root: AccessibilityNodeInfo,
    predicate: (AccessibilityNodeInfo) -> Boolean
): AccessibilityNodeInfo? {
    val queue = java.util.ArrayDeque<AccessibilityNodeInfo>()
    queue.add(root)
    while (queue.isNotEmpty()) {
        val node = queue.removeFirst()
        if (predicate(node)) return node
        for (i in 0 until node.childCount) node.getChild(i)?.let { queue.add(it) }
    }
    return null
}

// These call into existing private methods via reflection shim
// (the actual private method calls are already in ScreenReaderService)
fun ScreenReaderService.performTapGesture(x: Float, y: Float): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
    val path = android.graphics.Path().apply { moveTo(x, y) }
    val gesture = android.accessibilityservice.GestureDescription.Builder()
        .addStroke(android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, 50))
        .build()
    dispatchGesture(gesture, null, null)
    return true
}

fun ScreenReaderService.performLongPressGesture(x: Float, y: Float): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
    val path = android.graphics.Path().apply { moveTo(x, y) }
    val gesture = android.accessibilityservice.GestureDescription.Builder()
        .addStroke(android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, 1000))
        .build()
    dispatchGesture(gesture, null, null)
    return true
}

fun ScreenReaderService.performGestureSwipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
    val path = android.graphics.Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
    val gesture = android.accessibilityservice.GestureDescription.Builder()
        .addStroke(android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, durationMs))
        .build()
    dispatchGesture(gesture, null, null)
    return true
}
