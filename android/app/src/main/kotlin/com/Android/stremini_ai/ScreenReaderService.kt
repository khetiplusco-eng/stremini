package com.Android.stremini_ai

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import kotlinx.coroutines.*
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.ArrayDeque
import java.util.concurrent.TimeUnit

class ScreenReaderService : AccessibilityService() {

    companion object {
        const val ACTION_START_SCAN = "com.Android.stremini_ai.START_SCAN"
        const val ACTION_STOP_SCAN = "com.Android.stremini_ai.STOP_SCAN"
        const val ACTION_SCAN_COMPLETE = "com.Android.stremini_ai.SCAN_COMPLETE"
        const val EXTRA_SCANNED_TEXT = "scanned_text"
        private const val TAG = "ScreenReaderService"

        private var instance: ScreenReaderService? = null
        fun isRunning(): Boolean = instance != null
        fun isScanningActive(): Boolean = instance?.isScanning == true

        fun runWhatsAppMessageAutomation(contactName: String, message: String): Boolean {
            val service = instance ?: return false
            service.serviceScope.launch { service.automateWhatsAppMessage(contactName, message) }
            return true
        }

        fun runGenericAutomation(command: String): Boolean {
            val service = instance ?: return false
            service.serviceScope.launch { service.executeFullDeviceCommand(command) }
            return true
        }

        // Expose for ChatOverlayService plan execution
        fun getInstance(): ScreenReaderService? = instance

        // --- THEME COLORS ---
        private val SAFE_BG_COLOR = Color.parseColor("#1A3826")
        private val SAFE_BORDER_COLOR = Color.parseColor("#2D5C43")
        private val SAFE_TEXT_COLOR = Color.parseColor("#6DD58C")
        private val DANGER_BG_COLOR = Color.parseColor("#38261A")
        private val DANGER_BORDER_COLOR = Color.parseColor("#5C432D")
        private val DANGER_TEXT_COLOR = Color.parseColor("#FFD580")
    }

    private lateinit var windowManager: WindowManager
    private val screenAnalysisClient = ScreenAnalysisClient()

    val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var scanningOverlay: View? = null
    private var tagsContainer: FrameLayout? = null
    private var isScanning = false
    private var tagsVisible = false
    private var automationStatusView: TextView? = null
    private var automationHighlightView: View? = null
    private var lastAccessibilityEventTime: Long = 0L

    data class ScanResult(
        val isSafe: Boolean,
        val riskLevel: String,
        val summary: String,
        val taggedElements: List<TaggedElement>
    )

    data class TaggedElement(
        val label: String,
        val color: Int,
        val reason: String,
        val url: String?,
        val message: String?
    )

    data class ContentWithPosition(
        val text: String,
        val bounds: Rect,
        val area: Int
    )

    // ==========================================
    // LIFECYCLE
    // ==========================================

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        Log.d(TAG, "Accessibility Service Connected - Full device control enabled")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_SCAN -> { if (tagsVisible) clearTags(); if (!isScanning) startScreenScan() }
            ACTION_STOP_SCAN -> clearAllOverlays()
        }
        return START_NOT_STICKY
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        lastAccessibilityEventTime = System.currentTimeMillis()
    }
    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        clearAllOverlays()
        clearAutomationOverlay()
        instance = null
    }

    data class PlanRunResult(
        val success: Boolean,
        val completedSteps: Int,
        val failedSteps: Int,
        val message: String
    )

    suspend fun executeBackendSteps(
        steps: JSONArray,
        onStatus: (String) -> Unit = {}
    ): PlanRunResult = withContext(Dispatchers.Main) {
        var completed = 0
        var failed = 0
        ensureAutomationOverlay()

        for (i in 0 until steps.length()) {
            val step = steps.optJSONObject(i) ?: continue
            val action = step.optString("action", "").ifBlank { step.optString("type", "") }
            val friendly = "Step ${i + 1}/${steps.length()}: ${action.ifBlank { "action" }}"
            showAutomationStatus(friendly)
            onStatus(friendly)

            val ok = runCatching { runAtomicStep(step, onStatus) }.getOrDefault(false)
            if (ok) completed++ else failed++
            waitForUiToSettle()
        }

        val done = failed == 0
        val finalMsg = if (done) {
            "Completed $completed steps"
        } else {
            "Completed $completed, failed $failed"
        }
        showAutomationStatus(finalMsg, isError = !done)
        PlanRunResult(done, completed, failed, finalMsg)
    }

    fun getVisibleScreenState(maxNodes: Int = 140): JSONArray {
        val root = rootInActiveWindow ?: return JSONArray()
        val out = JSONArray()
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty() && out.length() < maxNodes) {
            val node = queue.removeFirst()
            val text = node.text?.toString()?.trim().orEmpty()
            val desc = node.contentDescription?.toString()?.trim().orEmpty()
            if (text.isNotBlank() || desc.isNotBlank()) {
                out.put(JSONObject().apply {
                    put("text", text)
                    put("description", desc)
                    put("viewId", node.viewIdResourceName ?: "")
                    put("clickable", node.isClickable)
                    put("editable", node.isEditable)
                })
            }
            for (i in 0 until node.childCount) node.getChild(i)?.let { queue.add(it) }
        }
        return out
    }

    private suspend fun runAtomicStep(step: JSONObject, onStatus: (String) -> Unit): Boolean {
        val action = step.optString("action", "").lowercase().trim()
        val target = step.optString("target", "").trim()
        val targetType = step.optString("type", "text").lowercase().trim()
        val text = step.optString("text", "").trim()

        return when {
            action == "open_app" -> {
                val pkg = step.optString("package", step.optString("app", ""))
                if (pkg.isBlank()) false else openAppByName(pkg)
            }
            action == "click" || action == "tap" -> {
                val node = findNodeByTarget(target, targetType)
                if (node == null) {
                    onStatus("Element '$target' not found")
                    showAutomationStatus("Element '$target' not found", isError = true)
                    false
                } else {
                    val bounds = Rect()
                    node.getBoundsInScreen(bounds)
                    flashNodeHighlight(bounds, false)
                    performClick(node)
                }
            }
            action == "type" || action == "input" -> {
                if (text.isBlank()) return false
                val node = if (target.isBlank()) findFocusedEditableNode() else findNodeByTarget(target, targetType)
                val editable = node ?: findFocusedEditableNode()
                if (editable == null) {
                    onStatus("No editable field found")
                    showAutomationStatus("No editable field found", isError = true)
                    false
                } else {
                    val bounds = Rect()
                    editable.getBoundsInScreen(bounds)
                    flashNodeHighlight(bounds, false)
                    setNodeText(editable, text)
                }
            }
            action == "wait" || action == "delay" -> {
                delay(step.optLong("milliseconds", 800L))
                true
            }
            else -> executeFullDeviceCommand(action)
        }
    }

    private fun findFocusedEditableNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return findFirstNode(root) { it.isEditable && (it.isFocused || it.isFocusable) }
            ?: findFirstNode(root) { it.isEditable }
    }

    private fun findNodeByTarget(target: String, type: String): AccessibilityNodeInfo? {
        if (target.isBlank()) return null
        val root = rootInActiveWindow ?: return null
        return when (type) {
            "description" -> findFirstNode(root) {
                it.contentDescription?.toString()?.contains(target, ignoreCase = true) == true
            }
            "view_id" -> {
                val byId = runCatching { root.findAccessibilityNodeInfosByViewId(target) }.getOrDefault(emptyList())
                byId.firstOrNull()
            }
            else -> {
                val byText = root.findAccessibilityNodeInfosByText(target)
                byText.firstOrNull() ?: findFirstNode(root) {
                    it.text?.toString()?.contains(target, ignoreCase = true) == true
                }
            }
        }
    }

    private suspend fun waitForUiToSettle(stableMs: Long = 450L, timeoutMs: Long = 3_000L) {
        val start = System.currentTimeMillis()
        while (System.currentTimeMillis() - start < timeoutMs) {
            val idleFor = System.currentTimeMillis() - lastAccessibilityEventTime
            if (idleFor >= stableMs) return
            delay(80)
        }
    }

    private fun ensureAutomationOverlay() {
        if (automationStatusView != null) return
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        automationStatusView = TextView(this).apply {
            textSize = 13f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(8))
            background = GradientDrawable().apply {
                cornerRadius = dpToPx(10).toFloat()
                setColor(Color.parseColor("#CC111827"))
                setStroke(dpToPx(1), Color.parseColor("#334155"))
            }
            text = "Agent ready"
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dpToPx(42)
        }
        windowManager.addView(automationStatusView, params)
    }

    private fun showAutomationStatus(message: String, isError: Boolean = false) {
        ensureAutomationOverlay()
        val view = automationStatusView ?: return
        view.text = message
        val bgColor = if (isError) "#CC7F1D1D" else "#CC111827"
        val borderColor = if (isError) "#F87171" else "#60A5FA"
        view.background = GradientDrawable().apply {
            cornerRadius = dpToPx(10).toFloat()
            setColor(Color.parseColor(bgColor))
            setStroke(dpToPx(1), Color.parseColor(borderColor))
        }
    }

    private fun flashNodeHighlight(bounds: Rect, isError: Boolean) {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        automationHighlightView?.let { runCatching { windowManager.removeView(it) } }
        val highlight = View(this).apply {
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                cornerRadius = dpToPx(8).toFloat()
                setStroke(dpToPx(3), if (isError) Color.parseColor("#FF3B30") else Color.parseColor("#22C55E"))
            }
        }

        val params = WindowManager.LayoutParams(
            bounds.width().coerceAtLeast(dpToPx(32)),
            bounds.height().coerceAtLeast(dpToPx(32)),
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = bounds.left
            y = bounds.top
        }
        automationHighlightView = highlight
        runCatching { windowManager.addView(highlight, params) }
        serviceScope.launch {
            delay(500)
            automationHighlightView?.let { runCatching { windowManager.removeView(it) } }
            automationHighlightView = null
        }
    }

    private fun clearAutomationOverlay() {
        automationStatusView?.let { runCatching { windowManager.removeView(it) } }
        automationStatusView = null
        automationHighlightView?.let { runCatching { windowManager.removeView(it) } }
        automationHighlightView = null
    }

    // ==========================================
    // FULL DEVICE CONTROL ENGINE
    // ==========================================

    suspend fun executeFullDeviceCommand(command: String): Boolean {
        val normalized = command.trim().lowercase()
        if (normalized.isBlank()) return false

        return withContext(Dispatchers.Main) {
            try {
                when {
                    // --- GLOBAL NAVIGATION ---
                    normalized.contains("go home") || normalized == "home" ->
                        performGlobalAction(GLOBAL_ACTION_HOME)

                    normalized.contains("go back") || normalized == "back" ->
                        performGlobalAction(GLOBAL_ACTION_BACK)

                    normalized.contains("recent apps") || normalized.contains("app switcher") ->
                        performGlobalAction(GLOBAL_ACTION_RECENTS)

                    normalized.contains("open notifications") || normalized.contains("notification bar") ->
                        performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)

                    normalized.contains("quick settings") ->
                        performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)

                    normalized.contains("lock screen") || normalized.contains("lock phone") ->
                        performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)

                    normalized.contains("take screenshot") || normalized.contains("screenshot") ->
                        takeScreenshot()

                    normalized.contains("power menu") ->
                        performGlobalAction(GLOBAL_ACTION_POWER_DIALOG)

                    // --- SCROLL COMMANDS ---
                    normalized.contains("scroll down") ->
                        performScroll(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)

                    normalized.contains("scroll up") ->
                        performScroll(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)

                    normalized.contains("scroll to top") ->
                        scrollToTop()

                    normalized.contains("scroll to bottom") ->
                        scrollToBottom()

                    // --- TAP / CLICK ---
                    normalized.startsWith("tap ") || normalized.startsWith("click ") -> {
                        val label = normalized.removePrefix("tap ").removePrefix("click ").trim()
                        clickNodeByText(label)
                    }

                    normalized.startsWith("long press ") || normalized.startsWith("long tap ") -> {
                        val label = normalized.removePrefix("long press ").removePrefix("long tap ").trim()
                        longClickNodeByText(label)
                    }

                    // --- SWIPE GESTURES ---
                    normalized.contains("swipe up") -> performSwipe("up")
                    normalized.contains("swipe down") -> performSwipe("down")
                    normalized.contains("swipe left") -> performSwipe("left")
                    normalized.contains("swipe right") -> performSwipe("right")

                    // --- TEXT INPUT ---
                    normalized.startsWith("type ") -> {
                        val value = command.trim().substringAfter("type ").trim()
                        typeIntoFocusedField(value)
                    }

                    normalized.startsWith("search for ") || normalized.startsWith("search ") -> {
                        val query = command.trim()
                            .removePrefix("search for ")
                            .removePrefix("Search for ")
                            .removePrefix("search ")
                            .removePrefix("Search ")
                            .trim()
                        performSearch(query)
                    }

                    normalized.startsWith("fill ") && normalized.contains(" with ") -> {
                        val parts = normalized.removePrefix("fill ").split(" with ", limit = 2)
                        if (parts.size == 2) fillFieldByHint(parts[0].trim(), parts[1].trim())
                        else false
                    }

                    // --- APP CONTROL ---
                    normalized.startsWith("open ") || normalized.startsWith("launch ") -> {
                        val appName = normalized.removePrefix("open ").removePrefix("launch ").trim()
                        openAppByName(appName)
                    }

                    normalized.startsWith("close ") && (normalized.contains("app") || normalized.contains("tab")) -> {
                        closeCurrentApp()
                    }

                    normalized.contains("force stop") || normalized.contains("kill app") -> {
                        val appName = normalized
                            .removePrefix("force stop ")
                            .removePrefix("kill app ")
                            .trim()
                        openAppSettings(appName)
                    }

                    // --- SYSTEM SETTINGS ---
                    normalized.contains("open wifi") || normalized.contains("wifi settings") ->
                        openSystemSettings(android.provider.Settings.ACTION_WIFI_SETTINGS)

                    normalized.contains("open bluetooth") || normalized.contains("bluetooth settings") ->
                        openSystemSettings("android.settings.BLUETOOTH_SETTINGS")

                    normalized.contains("open settings") ->
                        openSystemSettings(android.provider.Settings.ACTION_SETTINGS)

                    normalized.contains("open display settings") ->
                        openSystemSettings(android.provider.Settings.ACTION_DISPLAY_SETTINGS)

                    normalized.contains("open sound settings") ->
                        openSystemSettings(android.provider.Settings.ACTION_SOUND_SETTINGS)

                    normalized.contains("open battery settings") ->
                        openSystemSettings(android.provider.Settings.ACTION_BATTERY_SAVER_SETTINGS)

                    normalized.contains("open location settings") ->
                        openSystemSettings(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS)

                    normalized.contains("open app settings") || normalized.contains("app permissions") -> {
                        val appName = normalized
                            .removePrefix("open app settings for ")
                            .removePrefix("open app settings ")
                            .trim()
                        openAppSettings(appName)
                    }

                    normalized.contains("open developer options") ->
                        openSystemSettings(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)

                    // --- VOLUME CONTROL ---
                    normalized.contains("volume up") -> adjustVolume(true)
                    normalized.contains("volume down") -> adjustVolume(false)
                    normalized.contains("mute") -> muteDevice()
                    normalized.contains("unmute") -> unmuteDevice()

                    // --- BRIGHTNESS ---
                    normalized.contains("increase brightness") -> adjustBrightness(true)
                    normalized.contains("decrease brightness") || normalized.contains("reduce brightness") ->
                        adjustBrightness(false)

                    // --- WHATSAPP ---
                    normalized.contains("whatsapp") && (normalized.contains("message") || normalized.contains("send")) -> {
                        val contact = extractContact(command)
                        val message = extractMessage(command)
                        if (contact.isNotBlank())
                            automateWhatsAppMessage(contact, message)
                        else
                            false
                    }

                    // --- CALLS ---
                    normalized.startsWith("call ") -> {
                        val name = command.trim().substringAfter("call ").trim()
                        makePhoneCall(name)
                    }

                    normalized.contains("answer call") || normalized.contains("pick up") ->
                        answerIncomingCall()

                    normalized.contains("decline call") || normalized.contains("reject call") ->
                        declineIncomingCall()

                    // --- BROWSER ---
                    normalized.startsWith("open website ") || normalized.startsWith("go to ") ||
                    normalized.startsWith("browse to ") -> {
                        val url = command.trim()
                            .removePrefix("open website ")
                            .removePrefix("go to ")
                            .removePrefix("browse to ")
                            .trim()
                        openUrl(url)
                    }

                    // --- MEDIA CONTROLS ---
                    normalized.contains("play") && (normalized.contains("music") || normalized.contains("video")) ->
                        sendMediaAction(Intent.ACTION_MEDIA_BUTTON)

                    normalized.contains("pause") || normalized.contains("stop music") ->
                        sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_PAUSE)

                    normalized.contains("next song") || normalized.contains("next track") ->
                        sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_NEXT)

                    normalized.contains("previous song") || normalized.contains("previous track") ->
                        sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS)

                    // --- CAMERA ---
                    normalized.contains("open camera") ->
                        openAppByPackage("com.android.camera2")
                            .let { if (!it) openAppByName("camera") else it }

                    normalized.contains("take photo") || normalized.contains("take picture") ->
                        clickNodeByText("shutter") || clickNodeByContentDesc("take photo")

                    // --- KEYBOARD / TEXT ACTIONS ---
                    normalized.contains("select all") -> performSelectAll()
                    normalized.contains("copy") -> performCopy()
                    normalized.contains("paste") -> performPaste()
                    normalized.contains("cut") -> performCut()
                    normalized.contains("undo") -> performUndo()

                    // --- READING CONTENT ---
                    normalized.contains("read screen") || normalized.contains("what is on screen") -> {
                        readScreenContent()
                        true
                    }

                    normalized.startsWith("find ") -> {
                        val target = normalized.removePrefix("find ").trim()
                        findAndHighlight(target)
                    }

                    // --- SUBMIT / CONFIRM ---
                    normalized.contains("press enter") || normalized.contains("submit") ||
                    normalized.contains("confirm") ->
                        pressEnterKey()

                    normalized.contains("cancel") || normalized.contains("dismiss") ->
                        clickNodeByText("cancel") || clickNodeByText("dismiss") || clickNodeByText("no")

                    // --- DRAG & DROP ---
                    normalized.startsWith("drag ") && normalized.contains(" to ") -> {
                        val parts = normalized.removePrefix("drag ").split(" to ", limit = 2)
                        if (parts.size == 2) dragFromTo(parts[0].trim(), parts[1].trim())
                        else false
                    }

                    // --- PINCH / ZOOM ---
                    normalized.contains("zoom in") -> performZoom(true)
                    normalized.contains("zoom out") -> performZoom(false)

                    else -> {
                        Log.w(TAG, "Unknown command: $command")
                        false
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Command execution failed: $command", e)
                false
            }
        }
    }

    // ==========================================
    // NAVIGATION & GESTURES
    // ==========================================

    private fun performSwipe(direction: String): Boolean {
        val display = windowManager.defaultDisplay
        val width = display.width
        val height = display.height

        val (startX, startY, endX, endY) = when (direction) {
            "up" -> listOf(width / 2f, height * 0.7f, width / 2f, height * 0.3f)
            "down" -> listOf(width / 2f, height * 0.3f, width / 2f, height * 0.7f)
            "left" -> listOf(width * 0.8f, height / 2f, width * 0.2f, height / 2f)
            "right" -> listOf(width * 0.2f, height / 2f, width * 0.8f, height / 2f)
            else -> return false
        }

        return performGestureSwipe(startX, startY, endX, endY, 300)
    }

    private fun performGestureSwipe(startX: Float, startY: Float, endX: Float, endY: Float, durationMs: Long): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path()
        path.moveTo(startX, startY)
        path.lineTo(endX, endY)

        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()

        var result = false
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) { result = true }
            override fun onCancelled(gestureDescription: GestureDescription?) { result = false }
        }, null)
        return true
    }

    private fun performTapGesture(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path()
        path.moveTo(x, y)

        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 50))
            .build()
        dispatchGesture(gesture, null, null)
        return true
    }

    private fun performLongPressGesture(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path()
        path.moveTo(x, y)

        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 1000))
            .build()
        dispatchGesture(gesture, null, null)
        return true
    }

    private fun performZoom(zoomIn: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val display = windowManager.defaultDisplay
        val cx = display.width / 2f
        val cy = display.height / 2f
        val offset = if (zoomIn) 200f else -200f

        val path1 = Path().apply { moveTo(cx - 100, cy); lineTo(cx - 100 + offset, cy) }
        val path2 = Path().apply { moveTo(cx + 100, cy); lineTo(cx + 100 - offset, cy) }

        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path1, 0, 400))
            .addStroke(GestureDescription.StrokeDescription(path2, 0, 400))
            .build()
        dispatchGesture(gesture, null, null)
        return true
    }

    private fun takeScreenshot(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            performGlobalAction(GLOBAL_ACTION_TAKE_SCREENSHOT)
        } else {
            false
        }
    }

    // ==========================================
    // SCROLL ACTIONS
    // ==========================================

    private fun performScroll(action: Int): Boolean {
        val root = rootInActiveWindow ?: return false
        val scrollable = findFirstNode(root) { it.isScrollable }
        return scrollable?.performAction(action) ?: false
    }

    private fun scrollToTop(): Boolean {
        repeat(10) { performScroll(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD) }
        return true
    }

    private fun scrollToBottom(): Boolean {
        repeat(10) { performScroll(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) }
        return true
    }

    // ==========================================
    // CLICK / TAP NODE ACTIONS
    // ==========================================

    private fun clickNodeByText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findFirstNode(root) { node ->
            val t = node.text?.toString()?.lowercase().orEmpty()
            val d = node.contentDescription?.toString()?.lowercase().orEmpty()
            t.contains(text.lowercase()) || d.contains(text.lowercase())
        }
        if (node != null) {
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            return performClick(node) || performTapGesture(bounds.exactCenterX(), bounds.exactCenterY())
        }
        return false
    }

    private fun clickNodeByContentDesc(desc: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findFirstNode(root) { node ->
            node.contentDescription?.toString()?.lowercase()?.contains(desc.lowercase()) == true
        }
        return performClick(node)
    }

    private fun longClickNodeByText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findFirstNode(root) { node ->
            val t = node.text?.toString()?.lowercase().orEmpty()
            val d = node.contentDescription?.toString()?.lowercase().orEmpty()
            t.contains(text.lowercase()) || d.contains(text.lowercase())
        }
        if (node != null) {
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            if (node.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)) return true
            return performLongPressGesture(bounds.exactCenterX(), bounds.exactCenterY())
        }
        return false
    }

    private fun dragFromTo(fromText: String, toText: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val fromNode = findFirstNode(root) { it.text?.toString()?.lowercase()?.contains(fromText) == true }
        val toNode = findFirstNode(root) { it.text?.toString()?.lowercase()?.contains(toText) == true }
        if (fromNode == null || toNode == null) return false

        val fromBounds = Rect()
        val toBounds = Rect()
        fromNode.getBoundsInScreen(fromBounds)
        toNode.getBoundsInScreen(toBounds)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path()
        path.moveTo(fromBounds.exactCenterX(), fromBounds.exactCenterY())
        path.lineTo(toBounds.exactCenterX(), toBounds.exactCenterY())

        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 800))
            .build()
        dispatchGesture(gesture, null, null)
        return true
    }

    // ==========================================
    // TEXT INPUT ACTIONS
    // ==========================================

    private fun typeIntoFocusedField(value: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = findFirstNode(root) { it.isFocused && it.isEditable }
            ?: findFirstNode(root) { it.isEditable }
        return setNodeText(focused, value)
    }

    private fun fillFieldByHint(hint: String, value: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val field = findFirstNode(root) { node ->
            val h = node.hintText?.toString()?.lowercase().orEmpty()
            val d = node.contentDescription?.toString()?.lowercase().orEmpty()
            (h.contains(hint) || d.contains(hint)) && node.isEditable
        } ?: findFirstNode(root) { node ->
            node.isEditable && (node.text?.toString()?.lowercase()?.contains(hint) == true)
        }
        return setNodeText(field, value)
    }

    private fun performSearch(query: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val searchField = findFirstNode(root) { node ->
            val h = node.hintText?.toString()?.lowercase().orEmpty()
            val d = node.contentDescription?.toString()?.lowercase().orEmpty()
            val id = node.viewIdResourceName?.lowercase().orEmpty()
            (h.contains("search") || d.contains("search") || id.contains("search")) && (node.isEditable || node.isClickable)
        }
        if (searchField != null) {
            performClick(searchField)
            Thread.sleep(300)
            if (searchField.isEditable) {
                setNodeText(searchField, query)
            } else {
                val root2 = rootInActiveWindow ?: return false
                val editField = findFirstNode(root2) { it.isEditable }
                setNodeText(editField, query)
            }
            Thread.sleep(300)
            pressEnterKey()
            return true
        }
        return false
    }

    private fun performSelectAll(): Boolean {
        val root = rootInActiveWindow ?: return false
        val editNode = findFirstNode(root) { it.isFocused && it.isEditable }
            ?: findFirstNode(root) { it.isEditable }
        return editNode?.performAction(AccessibilityNodeInfo.ACTION_SELECT) ?: false
    }

    private fun performCopy(): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findFirstNode(root) { it.isFocused } ?: return false
        return node.performAction(AccessibilityNodeInfo.ACTION_COPY)
    }

    private fun performPaste(): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findFirstNode(root) { it.isFocused && it.isEditable }
            ?: findFirstNode(root) { it.isEditable }
        return node?.performAction(AccessibilityNodeInfo.ACTION_PASTE) ?: false
    }

    private fun performCut(): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findFirstNode(root) { it.isFocused } ?: return false
        return node.performAction(AccessibilityNodeInfo.ACTION_CUT)
    }

    private fun performUndo(): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findFirstNode(root) { it.isFocused } ?: return false
        return node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
    }

    private fun pressEnterKey(): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findFirstNode(root) { it.isFocused }
        if (node != null) {
            val args = Bundle()
            args.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_MOVEMENT_GRANULARITY_INT,
                AccessibilityNodeInfo.MOVEMENT_GRANULARITY_LINE)
            node.performAction(AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY, args)
        }
        return clickNodeByText("search") || clickNodeByText("go") ||
               clickNodeByText("done") || clickNodeByText("send") ||
               clickNodeByText("submit") || clickNodeByText("ok")
    }

    private fun findAndHighlight(target: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findFirstNode(root) { node ->
            node.text?.toString()?.lowercase()?.contains(target) == true
        }
        if (node != null) {
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            performTapGesture(bounds.exactCenterX(), bounds.exactCenterY())
            return true
        }
        return false
    }

    private fun readScreenContent(): String {
        val root = rootInActiveWindow ?: return "Screen content unavailable"
        val sb = StringBuilder()
        fun traverse(node: AccessibilityNodeInfo, depth: Int = 0) {
            val text = node.text?.toString() ?: node.contentDescription?.toString()
            if (!text.isNullOrBlank()) sb.appendLine(text.trim())
            for (i in 0 until node.childCount) node.getChild(i)?.let { traverse(it, depth + 1) }
        }
        traverse(root)
        return sb.toString()
    }

    // ==========================================
    // APP MANAGEMENT
    // ==========================================

    fun openAppByName(rawName: String): Boolean {
        if (rawName.isBlank()) return false
        val aliases = mapOf(
            "whatsapp" to "com.whatsapp",
            "chrome" to "com.android.chrome",
            "youtube" to "com.google.android.youtube",
            "instagram" to "com.instagram.android",
            "telegram" to "org.telegram.messenger",
            "gmail" to "com.google.android.gm",
            "maps" to "com.google.android.apps.maps",
            "google maps" to "com.google.android.apps.maps",
            "play store" to "com.android.vending",
            "settings" to "com.android.settings",
            "facebook" to "com.facebook.katana",
            "messenger" to "com.facebook.orca",
            "twitter" to "com.twitter.android",
            "x" to "com.twitter.android",
            "spotify" to "com.spotify.music",
            "netflix" to "com.netflix.mediaclient",
            "snapchat" to "com.snapchat.android",
            "tiktok" to "com.zhiliaoapp.musically",
            "linkedin" to "com.linkedin.android",
            "amazon" to "com.amazon.mShop.android.shopping",
            "flipkart" to "com.flipkart.android",
            "phone" to "com.android.dialer",
            "dialer" to "com.android.dialer",
            "contacts" to "com.android.contacts",
            "messages" to "com.google.android.apps.messaging",
            "sms" to "com.google.android.apps.messaging",
            "calendar" to "com.google.android.calendar",
            "clock" to "com.android.deskclock",
            "calculator" to "com.android.calculator2",
            "camera" to "com.android.camera2",
            "gallery" to "com.google.android.apps.photos",
            "photos" to "com.google.android.apps.photos",
            "files" to "com.google.android.apps.nbu.files",
            "file manager" to "com.google.android.apps.nbu.files",
            "drive" to "com.google.android.apps.docs",
            "google drive" to "com.google.android.apps.docs",
            "docs" to "com.google.android.apps.docs.editors.docs",
            "sheets" to "com.google.android.apps.docs.editors.sheets",
            "slides" to "com.google.android.apps.docs.editors.slides",
            "meet" to "com.google.android.apps.tachyon",
            "google meet" to "com.google.android.apps.tachyon",
            "duo" to "com.google.android.apps.tachyon",
            "zoom" to "us.zoom.videomeetings",
            "discord" to "com.discord",
            "reddit" to "com.reddit.frontpage",
            "paypal" to "com.paypal.android.p2pmobile",
            "phonepe" to "com.phonepe.app",
            "gpay" to "com.google.android.apps.nbu.paisa.user",
            "google pay" to "com.google.android.apps.nbu.paisa.user",
            "paytm" to "net.one97.paytm",
            "swiggy" to "in.swiggy.android",
            "zomato" to "com.application.zomato",
            "ola" to "com.olacabs.customer",
            "uber" to "com.ubercab",
            "amazon music" to "com.amazon.mp3",
            "apple music" to "com.apple.android.music",
            "podcast" to "com.google.android.apps.podcasts",
            "youtube music" to "com.google.android.apps.youtube.music"
        )

        val lowerName = rawName.lowercase()
        val packageName = aliases.entries.firstOrNull { lowerName.contains(it.key) }?.value

        val launchIntent = if (packageName != null) {
            packageManager.getLaunchIntentForPackage(packageName)
        } else {
            val apps = packageManager.getInstalledApplications(0)
            val matched = apps.firstOrNull {
                packageManager.getApplicationLabel(it).toString().lowercase().contains(lowerName)
            }
            matched?.let { packageManager.getLaunchIntentForPackage(it.packageName) }
        }

        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(launchIntent)
            return true
        }
        return false
    }

    private fun openAppByPackage(packageName: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    private fun closeCurrentApp(): Boolean {
        performGlobalAction(GLOBAL_ACTION_RECENTS)
        Thread.sleep(600)
        val display = windowManager.defaultDisplay
        performGestureSwipe(
            display.width / 2f, display.height / 2f,
            display.width.toFloat(), display.height / 2f, 300
        )
        return true
    }

    private fun openAppSettings(appName: String): Boolean {
        val aliases = mapOf(
            "whatsapp" to "com.whatsapp",
            "chrome" to "com.android.chrome",
            "instagram" to "com.instagram.android"
        )
        val pkg = aliases.entries.firstOrNull { appName.contains(it.key) }?.value ?: return false
        val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = android.net.Uri.parse("package:$pkg")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return true
    }

    private fun openSystemSettings(action: String): Boolean {
        return try {
            val intent = Intent(action).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open settings: $action", e)
            false
        }
    }

    // ==========================================
    // PHONE & CALLS
    // ==========================================

    private fun makePhoneCall(name: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_DIAL).apply {
                data = android.net.Uri.parse("tel:")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            serviceScope.launch {
                delay(1000)
                performSearch(name)
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Call failed", e)
            false
        }
    }

    private fun answerIncomingCall(): Boolean {
        return clickNodeByContentDesc("answer") ||
               clickNodeByText("answer") ||
               clickNodeByText("accept") ||
               performGestureSwipe(
                   windowManager.defaultDisplay.width / 2f,
                   windowManager.defaultDisplay.height * 0.7f,
                   windowManager.defaultDisplay.width / 2f,
                   windowManager.defaultDisplay.height * 0.3f,
                   300
               )
    }

    private fun declineIncomingCall(): Boolean {
        return clickNodeByContentDesc("decline") ||
               clickNodeByText("decline") ||
               clickNodeByText("reject") ||
               performGestureSwipe(
                   windowManager.defaultDisplay.width / 2f,
                   windowManager.defaultDisplay.height * 0.7f,
                   windowManager.defaultDisplay.width / 2f,
                   windowManager.defaultDisplay.height * 0.9f,
                   300
               )
    }

    // ==========================================
    // VOLUME / BRIGHTNESS / MEDIA
    // ==========================================

    private fun adjustVolume(increase: Boolean): Boolean {
        return try {
            val am = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
            val direction = if (increase) android.media.AudioManager.ADJUST_RAISE
                            else android.media.AudioManager.ADJUST_LOWER
            am.adjustStreamVolume(
                android.media.AudioManager.STREAM_MUSIC,
                direction,
                android.media.AudioManager.FLAG_SHOW_UI
            )
            true
        } catch (e: Exception) {
            Log.e(TAG, "adjustVolume failed", e)
            false
        }
    }

    private fun muteDevice(): Boolean {
        val am = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.adjustStreamVolume(
                android.media.AudioManager.STREAM_RING,
                android.media.AudioManager.ADJUST_MUTE,
                0
            )
        } else {
            @Suppress("DEPRECATION")
            am.setRingerMode(android.media.AudioManager.RINGER_MODE_SILENT)
        }
        return true
    }

    private fun unmuteDevice(): Boolean {
        val am = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.adjustStreamVolume(
                android.media.AudioManager.STREAM_RING,
                android.media.AudioManager.ADJUST_UNMUTE,
                0
            )
        } else {
            @Suppress("DEPRECATION")
            am.setRingerMode(android.media.AudioManager.RINGER_MODE_NORMAL)
        }
        return true
    }

    private fun adjustBrightness(increase: Boolean): Boolean {
        return try {
            val current = android.provider.Settings.System.getInt(
                contentResolver,
                android.provider.Settings.System.SCREEN_BRIGHTNESS,
                128
            )
            val newValue = if (increase) minOf(255, current + 50) else maxOf(0, current - 50)
            android.provider.Settings.System.putInt(
                contentResolver,
                android.provider.Settings.System.SCREEN_BRIGHTNESS,
                newValue
            )
            true
        } catch (e: Exception) {
            openSystemSettings(android.provider.Settings.ACTION_DISPLAY_SETTINGS)
            false
        }
    }

    private fun sendMediaAction(action: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            sendBroadcast(intent)
            true
        } catch (e: Exception) { false }
    }

    private fun sendMediaKey(keyCode: Int): Boolean {
        return try {
            val down = android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, keyCode)
            val up = android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, keyCode)
            val am = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
            am.dispatchMediaKeyEvent(down)
            am.dispatchMediaKeyEvent(up)
            true
        } catch (e: Exception) { false }
    }

    // ==========================================
    // BROWSER / URL
    // ==========================================

    private fun openUrl(url: String): Boolean {
        return try {
            val fullUrl = if (!url.startsWith("http")) "https://$url" else url
            val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(fullUrl)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open URL", e)
            false
        }
    }

    // ==========================================
    // WHATSAPP AUTOMATION (Enhanced)
    // ==========================================

    suspend fun automateWhatsAppMessage(contactName: String, message: String): Boolean {
        return withContext(Dispatchers.Main) {
            try {
                val launchIntent = packageManager.getLaunchIntentForPackage("com.whatsapp")
                    ?: return@withContext false
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
                delay(1500)

                // 1) Open search
                rootInActiveWindow?.let { root ->
                    val searchNode = findFirstNode(root) { node ->
                        val desc = node.contentDescription?.toString()?.lowercase().orEmpty()
                        val id = node.viewIdResourceName?.lowercase().orEmpty()
                        desc.contains("search") || id.contains("search")
                    }
                    if (searchNode != null) performClick(searchNode)
                    else {
                        performSwipe("down")
                    }
                }
                delay(800)

                // 2) Type contact name
                rootInActiveWindow?.let { root ->
                    val inputNode = findFirstNode(root) { node ->
                        node.isEditable || node.className?.toString()?.contains("EditText") == true
                    }
                    setNodeText(inputNode, contactName)
                }
                delay(1200)

                // 3) Open matching chat
                var chatOpened = false
                rootInActiveWindow?.let { root ->
                    val contactNode = findFirstNode(root) { node ->
                        val txt = node.text?.toString().orEmpty()
                        txt.equals(contactName, ignoreCase = true)
                    } ?: findFirstNode(root) { node ->
                        val txt = node.text?.toString().orEmpty()
                        txt.contains(contactName, ignoreCase = true) && txt.length < 50
                    }
                    if (contactNode != null) {
                        performClick(contactNode)
                        chatOpened = true
                    }
                }

                if (!chatOpened) return@withContext false
                delay(1200)

                // 4) Type message
                rootInActiveWindow?.let { root ->
                    val msgNode = findFirstNode(root) { node ->
                        node.isEditable && (
                            node.hintText?.toString()?.lowercase()?.contains("message") == true ||
                            node.contentDescription?.toString()?.lowercase()?.contains("message") == true ||
                            node.className?.toString()?.contains("EditText") == true
                        )
                    } ?: findFirstNode(root) { it.isEditable }
                    setNodeText(msgNode, message)
                }
                delay(400)

                // 5) Send message
                val sent = rootInActiveWindow?.let { root ->
                    val sendNode = findFirstNode(root) { node ->
                        val desc = node.contentDescription?.toString()?.lowercase().orEmpty()
                        val id = node.viewIdResourceName?.lowercase().orEmpty()
                        desc.contains("send") || id.contains("send")
                    }
                    performClick(sendNode)
                } ?: false

                Log.d(TAG, "WhatsApp message sent to $contactName: $sent")
                sent
            } catch (e: Exception) {
                Log.e(TAG, "WhatsApp automation failed", e)
                false
            }
        }
    }

    // ==========================================
    // HELPER: Extract Contact/Message from command
    // ==========================================

    private fun extractContact(command: String): String {
        val patterns = listOf(
            Regex("(?:message|send|whatsapp)\\s+(?:to\\s+)?([a-zA-Z][a-zA-Z0-9 _.-]{1,30})(?:\\s+(?:that|saying|:|-|,|with message)|\\s*$)", RegexOption.IGNORE_CASE),
            Regex("to\\s+([a-zA-Z][a-zA-Z0-9 _.-]{1,30})(?:\\s+(?:that|saying|:|-)|\\s*$)", RegexOption.IGNORE_CASE)
        )
        for (pattern in patterns) {
            val match = pattern.find(command)
            if (match != null) return match.groupValues[1].trim()
        }
        return ""
    }

    private fun extractMessage(command: String): String {
        val patterns = listOf(
            Regex("(?:that|saying|message:|with message)\\s+(.+)$", RegexOption.IGNORE_CASE),
            Regex(":\\s*(.+)$"),
            Regex("-\\s*(.+)$")
        )
        for (pattern in patterns) {
            val match = pattern.find(command)
            if (match != null) return match.groupValues[1].trim()
        }
        return "Hello"
    }

    // ==========================================
    // NODE UTILITIES
    // ==========================================

    private fun findFirstNode(
        root: AccessibilityNodeInfo,
        predicate: (AccessibilityNodeInfo) -> Boolean
    ): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (predicate(node)) return node
            for (i in 0 until node.childCount) node.getChild(i)?.let { queue.add(it) }
        }
        return null
    }

    private fun performClick(node: AccessibilityNodeInfo?): Boolean {
        var current = node
        while (current != null) {
            if (current.isClickable) return current.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            current = current.parent
        }
        return false
    }

    private fun setNodeText(node: AccessibilityNodeInfo?, value: String): Boolean {
        val target = node ?: return false
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value)
        }
        return target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    // ==========================================
    // SCREEN SCANNER (Original)
    // ==========================================

    private fun startScreenScan() {
        isScanning = true
        showScanningAnimation()
        serviceScope.launch {
            try {
                delay(800)
                val rootNode = rootInActiveWindow
                if (rootNode == null) {
                    hideScanningAnimation(); isScanning = false; return@launch
                }
                val contentList = mutableListOf<ContentWithPosition>()
                extractContentWithPositions(rootNode, contentList)
                rootNode.recycle()
                val fullText = contentList.joinToString("\n") { it.text }
                val result = analyzeScreenContent(fullText)
                hideScanningAnimation()
                displayTagsForAllThreats(contentList, result)
                val broadcastIntent = Intent(ACTION_SCAN_COMPLETE).apply {
                    setPackage(packageName)
                    putExtra(EXTRA_SCANNED_TEXT, fullText)
                }
                sendBroadcast(broadcastIntent)
                isScanning = false
                tagsVisible = true
            } catch (e: Exception) {
                Log.e(TAG, "Scan Error", e)
                hideScanningAnimation()
                isScanning = false
            }
        }
    }

    private fun performLocalAnalysis(text: String): ScanResult {
        val lower = text.lowercase()
        val tags = mutableListOf<TaggedElement>()
        var isSafe = true
        val threats = listOf("scam", "winner", "prize", "urgent", "password", "bank", "verify", "pirate", "crack")
        threats.forEach { threat ->
            if (lower.contains(threat)) {
                isSafe = false
                tags.add(TaggedElement("Suspicious Keyword", DANGER_TEXT_COLOR, threat, null, threat))
            }
        }
        return ScanResult(isSafe, if (isSafe) "safe" else "warning", "Analysis Complete", tags)
    }

    private suspend fun analyzeScreenContent(content: String): ScanResult = withContext(Dispatchers.IO) {
        screenAnalysisClient.analyzeText(content)
            .map { json ->
                val isThreat = json.optBoolean("is_threat", false)
                val detailsArray = json.optJSONArray("details")
                val tags = mutableListOf<TaggedElement>()
                if (detailsArray != null) {
                    for (i in 0 until detailsArray.length()) {
                        val detail = detailsArray.getString(i)
                        tags.add(TaggedElement("Alert", DANGER_TEXT_COLOR, detail, null, detail))
                    }
                }
                ScanResult(
                    !isThreat,
                    json.optString("type", "safe"),
                    "Confidence: ${json.optDouble("confidence", 0.0)}",
                    tags
                )
            }
            .getOrElse {
                Log.e(TAG, "Analysis error", it)
                performLocalAnalysis(content)
            }
    }

    private fun displayTagsForAllThreats(contentList: List<ContentWithPosition>, result: ScanResult) {
        clearTags()
        tagsContainer = FrameLayout(this)
        val containerParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        containerParams.gravity = Gravity.TOP or Gravity.START
        containerParams.x = 0; containerParams.y = 0
        windowManager.addView(tagsContainer, containerParams)

        val bannerTitle = if (result.isSafe) "Safe: No Threat Detected" else "Warning: Potential Threats"
        val bannerBg = if (result.isSafe) SAFE_BG_COLOR else DANGER_BG_COLOR
        val bannerBorder = if (result.isSafe) SAFE_BORDER_COLOR else DANGER_BORDER_COLOR
        val bannerText = if (result.isSafe) SAFE_TEXT_COLOR else DANGER_TEXT_COLOR
        createBanner(bannerTitle, bannerBg, bannerBorder, bannerText)

        if (!result.isSafe) {
            result.taggedElements.forEach { tag ->
                val searchTerms = tag.reason.split(" ").filter { it.length > 4 }
                var bestMatch: ContentWithPosition? = null
                val directMatches = contentList.filter { it.text.contains(tag.reason, ignoreCase = true) }
                if (directMatches.isNotEmpty()) {
                    bestMatch = directMatches.minByOrNull { it.area }
                } else {
                    for (term in searchTerms) {
                        val termMatches = contentList.filter { it.text.contains(term, ignoreCase = true) }
                        if (termMatches.isNotEmpty()) { bestMatch = termMatches.minByOrNull { it.area }; break }
                    }
                }
                if (bestMatch != null) {
                    createFloatingTag(bestMatch.bounds, tag.label, DANGER_BG_COLOR, DANGER_BORDER_COLOR, DANGER_TEXT_COLOR, tag.reason)
                }
            }
        } else {
            val safeMatches = contentList.filter {
                it.text.contains("google", ignoreCase = true) || it.text.contains("wikipedia", ignoreCase = true)
            }
            safeMatches.minByOrNull { it.area }?.let {
                createFloatingTag(it.bounds, "Verified Safe", SAFE_BG_COLOR, SAFE_BORDER_COLOR, SAFE_TEXT_COLOR, "Source Verified")
            }
        }
    }

    private fun createBanner(title: String, bgColor: Int, borderColor: Int, textColor: Int) {
        val bannerLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpToPx(16), dpToPx(12), dpToPx(16), dpToPx(12))
            background = GradientDrawable().apply {
                setColor(bgColor); setStroke(dpToPx(2), borderColor); cornerRadius = dpToPx(24).toFloat()
            }
            elevation = 10f
        }
        bannerLayout.addView(TextView(this).apply {
            text = if (title.contains("Safe")) "🛡️" else "⚠️"; textSize = 18f
            setPadding(0, 0, dpToPx(8), 0); setTextColor(Color.WHITE)
        })
        bannerLayout.addView(TextView(this).apply {
            text = title; setTextColor(Color.WHITE); textSize = 14f; setTypeface(Typeface.DEFAULT_BOLD)
        })
        bannerLayout.addView(TextView(this).apply {
            text = if (title.contains("Safe")) "SECURE" else "RISK"
            setTextColor(textColor); textSize = 12f; setPadding(dpToPx(10), 0, 0, 0)
            setTypeface(Typeface.DEFAULT_BOLD)
        })
        val params = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; topMargin = dpToPx(50) }
        tagsContainer?.addView(bannerLayout, params)
    }

    private fun createFloatingTag(bounds: Rect, labelText: String, bgColor: Int, borderColor: Int, textColor: Int, subText: String? = null) {
        val pill = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dpToPx(10), dpToPx(6), dpToPx(10), dpToPx(6))
            background = GradientDrawable().apply {
                setColor(bgColor); cornerRadius = dpToPx(8).toFloat(); setStroke(dpToPx(1), borderColor)
            }
            elevation = 15f
        }
        val header = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        header.addView(TextView(this).apply {
            text = if (bgColor == SAFE_BG_COLOR) "✓" else "!"; setTextColor(textColor)
            textSize = 12f; setTypeface(null, Typeface.BOLD); setPadding(0, 0, dpToPx(4), 0)
        })
        header.addView(TextView(this).apply {
            text = labelText; setTextColor(textColor); textSize = 12f; setTypeface(Typeface.DEFAULT_BOLD); maxLines = 1
        })
        pill.addView(header)
        if (!subText.isNullOrEmpty()) {
            pill.addView(TextView(this).apply {
                text = subText; setTextColor(Color.parseColor("#DDDDDD"))
                textSize = 10f; maxLines = 2; gravity = Gravity.CENTER
            })
        }
        val params = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            this.gravity = Gravity.TOP or Gravity.START
            leftMargin = bounds.left.coerceAtLeast(0)
            val tagHeightEstimate = dpToPx(40)
            val bannerZone = dpToPx(110)
            topMargin = if (bounds.top - tagHeightEstimate > bannerZone) {
                bounds.top - tagHeightEstimate - dpToPx(5)
            } else {
                bounds.bottom + dpToPx(5)
            }
        }
        tagsContainer?.addView(pill, params)
    }

    private fun extractContentWithPositions(node: AccessibilityNodeInfo, list: MutableList<ContentWithPosition>) {
        val text = node.text?.toString() ?: node.contentDescription?.toString()
        if (!text.isNullOrBlank() && text.trim().length > 2) {
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            if (bounds.width() > 10 && bounds.height() > 10 && bounds.left >= 0 && bounds.top >= 0) {
                list.add(ContentWithPosition(text.trim(), bounds, bounds.width() * bounds.height()))
            }
        }
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { extractContentWithPositions(it, list); it.recycle() }
        }
    }

    private fun showScanningAnimation() {
        try {
            val scanView = FrameLayout(this).apply {
                background = GradientDrawable().apply { setColor(Color.parseColor("#60000000")) }
            }
            scanView.addView(TextView(this).apply {
                text = "Analyzing..."; setTextColor(Color.WHITE); textSize = 20f; gravity = Gravity.CENTER
            }, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER })
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT
            )
            windowManager.addView(scanView, params)
            scanningOverlay = scanView
        } catch (e: Exception) { Log.e(TAG, "Overlay Error", e) }
    }

    private fun hideScanningAnimation() {
        scanningOverlay?.let { try { windowManager.removeView(it) } catch (e: Exception) {} }
        scanningOverlay = null
    }

    private fun clearTags() {
        tagsContainer?.let { try { windowManager.removeView(it) } catch (e: Exception) {} }
        tagsContainer = null; tagsVisible = false
    }

    private fun clearAllOverlays() {
        hideScanningAnimation(); clearTags(); isScanning = false
    }

    private fun dpToPx(dp: Int): Int = (dp * resources.displayMetrics.density).toInt()
}
