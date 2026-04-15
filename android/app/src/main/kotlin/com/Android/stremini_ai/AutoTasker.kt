package com.Android.stremini_ai

// ============================================================================
// AutoTasker.kt — Premium voice + text controlled phone automation
// ============================================================================

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.text.TextUtils
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

private const val TAG              = "AutoTasker"
private const val BACKEND_URL      = "https://ai-keyboard-backend.vishwajeetadkine705.workers.dev"
private const val VOICE_COMMAND_EP = "$BACKEND_URL/automation/voice-command"
private const val MAX_STEPS        = 20
private const val NOTIF_CHANNEL_ID = "autotasker_channel"
private const val NOTIF_ID         = 42

// ─────────────────────────────────────────────────────────────────────────────
// VoiceEngine  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class VoiceEngine(
    private val context: Context,
    private val onPartial: (String) -> Unit,
    private val onFinal:   (String) -> Unit,
    private val onError:   (Int)    -> Unit,
    private val onReady:   ()       -> Unit,
) {
    private var recognizer: SpeechRecognizer? = null
    private var active = false

    val isListening get() = active

    fun start() { if (active) return; active = true; createAndStart() }

    fun stop() {
        active = false
        recognizer?.stopListening()
        recognizer?.destroy()
        recognizer = null
    }

    private fun createAndStart() {
        if (!active) return
        recognizer?.destroy()
        if (!SpeechRecognizer.isRecognitionAvailable(context)) { Log.e(TAG, "Speech recognition not available"); onError(-1); return }
        recognizer = SpeechRecognizer.createSpeechRecognizer(context).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) { onReady() }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
                override fun onPartialResults(partialResults: Bundle?) {
                    val partial = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
                    onPartial(partial)
                }
                override fun onResults(results: Bundle?) {
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim() ?: ""
                    if (text.isNotBlank()) onFinal(text)
                }
                override fun onError(error: Int) { onError(error) }
            })
            startListening(buildIntent())
        }
    }

    private fun buildIntent() = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 500L)
    }

    fun resume() { if (active) createAndStart() }
}

// ─────────────────────────────────────────────────────────────────────────────
// ScreenCapture  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

object ScreenCapture {
    fun captureBase64(service: ScreenReaderService): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_TAKE_SCREENSHOT)
            null
        } catch (e: Exception) { Log.e(TAG, "Screenshot capture failed: ${e.message}"); null }
    }
    fun bitmapToBase64(bitmap: Bitmap): String {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 75, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// AutoTaskerBrain  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class AutoTaskerBrain(
    private val service: ScreenReaderService,
    private val onStatus: (String) -> Unit,
    private val onOutput: (String) -> Unit,
) {
    private val scope  = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val client = secureHttpClient(connectTimeoutSeconds = 20, readTimeoutSeconds = 45)
    private val actionHistory = mutableListOf<JSONObject>()

    fun cancel() { scope.coroutineContext.cancelChildren() }
    fun destroy() { scope.cancel() }

    fun execute(command: String): Job {
        return scope.launch {
            actionHistory.clear()
            onOutput("🎙 \"$command\"\n\n⚡ Processing...")
            onStatus("⚡ Thinking...")
            try { runAgenticLoop(command) }
            catch (e: CancellationException) { onStatus("⏹ Stopped"); onOutput("🎙 \"$command\"\n\n⏹ Cancelled") }
            catch (e: Exception) { Log.e(TAG, "Brain error: ${e.message}", e); onStatus("❌ Error"); onOutput("🎙 \"$command\"\n\n❌ ${e.message}") }
        }
    }

    private suspend fun runAgenticLoop(command: String) {
        var step = 1; var lastError: String? = null; var outputText = "🎙 \"$command\"\n\n"
        while (step <= MAX_STEPS) {
            onStatus("Step $step/$MAX_STEPS — thinking...")
            val uiContext = withContext(Dispatchers.Main) { buildUIContext() }
            val payload = JSONObject().apply {
                put("command", command); put("ui_context", uiContext); put("step", step)
                put("history", JSONArray(actionHistory.map { it.toString() }))
                if (lastError != null) put("error", lastError)
            }
            val response = callBackend(payload) ?: run { onStatus("❌ Network error"); outputText += "❌ Could not reach backend"; onOutput(outputText); return }
            val actions = response.optJSONArray("actions") ?: JSONArray()
            val isFast  = response.optBoolean("fast_path", false)
            val isDone  = response.optBoolean("is_done", false)
            if (isFast) outputText += "⚡ Fast path\n"
            var taskComplete = false; lastError = null
            for (i in 0 until actions.length()) {
                val action = actions.optJSONObject(i) ?: continue
                val actionType = action.optString("action", "")
                onStatus("▶ $actionType"); outputText += "  • $actionType"
                when (actionType) {
                    "done" -> { val s = action.optString("summary","✅ Done"); outputText += ": $s\n\n✅ $s"; onOutput(outputText); onStatus("✅ $s"); taskComplete = true; break }
                    "error" -> { val reason = action.optString("reason","Unknown error"); outputText += ": $reason\n"; lastError = reason; if (!action.optBoolean("recoverable", true)) { outputText += "\n❌ Task failed: $reason"; onOutput(outputText); onStatus("❌ Failed"); return }; break }
                    "request_screen" -> { outputText += "\n"; onOutput(outputText); delay(600); break }
                    "wait" -> { val ms = action.optLong("duration_ms", 1000L).coerceIn(100L, 8000L); outputText += " (${ms}ms)\n"; delay(ms) }
                    else -> {
                        val ok = withContext(Dispatchers.Main) { runCatching { executeAction(action) }.getOrElse { Log.e(TAG, "Action failed: $actionType — ${it.message}"); lastError = it.message; false } }
                        outputText += if (ok) " ✓\n" else " ✗\n"; actionHistory.add(action)
                        if (!ok) lastError = "Action '$actionType' failed"; delay(actionDelay(actionType))
                    }
                }
            }
            if (taskComplete) return
            if (isDone) { outputText += "\n✅ Complete"; onOutput(outputText); onStatus("✅ Complete"); return }
            onOutput(outputText); step++
        }
        onStatus("⚠ Max steps"); onOutput(outputText + "\n⚠ Stopped after $MAX_STEPS steps")
    }

    private suspend fun callBackend(payload: JSONObject): JSONObject? {
        return withContext(Dispatchers.IO) {
            try {
                val body = payload.toString().toRequestBody("application/json".toMediaType())
                val request = Request.Builder().url(VOICE_COMMAND_EP).post(body).addHeader("Content-Type","application/json").build()
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) { Log.e(TAG, "Backend HTTP ${response.code}"); return@use null }
                    val raw = response.body?.string() ?: return@use null
                    runCatching { JSONObject(raw) }.getOrNull()
                }
            } catch (e: Exception) { Log.e(TAG, "Backend call error: ${e.message}"); null }
        }
    }

    private fun buildUIContext(): JSONObject {
        val root = service.rootInActiveWindow ?: return JSONObject()
        val nodes = JSONArray(); val queue = ArrayDeque<AccessibilityNodeInfo>(); queue.add(root); var count = 0
        while (queue.isNotEmpty() && count < 120) {
            val node = queue.removeFirst()
            val text = node.text?.toString()?.trim().orEmpty(); val desc = node.contentDescription?.toString()?.trim().orEmpty()
            if (text.isNotBlank() || desc.isNotBlank()) {
                nodes.put(JSONObject().apply { put("text", text); put("desc", desc); put("viewId", node.viewIdResourceName ?: ""); put("clickable", node.isClickable); put("editable", node.isEditable); put("focused", node.isFocused) })
                count++
            }
            for (i in 0 until node.childCount) node.getChild(i)?.let { queue.add(it) }
        }
        return JSONObject().apply { put("nodes", nodes) }
    }

    private fun executeAction(action: JSONObject): Boolean {
        val type = action.optString("action", "").lowercase().trim()
        return when (type) {
            "home"           -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            "back"           -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            "recents"        -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)
            "notifications"  -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)
            "quick_settings" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS)
            "power_menu"     -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_POWER_DIALOG)
            "screenshot"     -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_TAKE_SCREENSHOT) else false
            "tap","click"    -> { val text = action.optString("target_text",""); val coords = action.optJSONArray("coordinates"); when { coords != null && coords.length() >= 2 -> tapAt(coords.optDouble(0).toFloat(), coords.optDouble(1).toFloat()); text.isNotBlank() -> tapByText(text); else -> false } }
            "long_press"     -> { val text = action.optString("target_text",""); if (text.isNotBlank()) longPressByText(text) else false }
            "type","input"   -> { val text = action.optString("text",""); val clearFirst = action.optBoolean("clear_first", false); if (clearFirst) clearFocused(); typeText(text) }
            "scroll"         -> { val dir = action.optString("direction","down").lowercase(); val amount = action.optInt("amount",1).coerceIn(1,15); repeat(amount) { scrollOnce(dir) }; true }
            "swipe"          -> { val from = action.optJSONArray("from"); val to = action.optJSONArray("to"); val dur = action.optLong("duration_ms",300L); if (from != null && to != null && from.length() >= 2 && to.length() >= 2) swipe(from.optDouble(0).toFloat(), from.optDouble(1).toFloat(), to.optDouble(0).toFloat(), to.optDouble(1).toFloat(), dur) else false }
            "open_app","launch_app" -> { val name = action.optString("app_name",""); val pkg = action.optString("package",""); if (pkg.isNotBlank()) launchPackage(pkg) else launchByName(name) }
            "volume"         -> adjustVolume(action.optString("direction","up").lowercase())
            "media_key"      -> sendMediaKey(action.optString("key","play").lowercase())
            "brightness"     -> adjustBrightness(action.optString("direction","up").lowercase())
            "clipboard"      -> clipboardOp(action.optString("operation","copy").lowercase())
            else             -> { Log.w(TAG, "Unknown action type: $type"); false }
        }
    }

    private fun tapAt(x: Float, y: Float): Boolean { if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false; val path = Path().apply { moveTo(x, y) }; val gesture = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, 50)).build(); service.dispatchGesture(gesture, null, null); return true }
    private fun tapByText(text: String): Boolean { val root = service.rootInActiveWindow ?: return false; val node = findNode(root) { n -> n.text?.toString()?.contains(text, ignoreCase = true) == true || n.contentDescription?.toString()?.contains(text, ignoreCase = true) == true } ?: return false; if (node.isClickable) return node.performAction(AccessibilityNodeInfo.ACTION_CLICK); val bounds = Rect(); node.getBoundsInScreen(bounds); return tapAt(bounds.exactCenterX(), bounds.exactCenterY()) }
    private fun longPressByText(text: String): Boolean { val root = service.rootInActiveWindow ?: return false; val node = findNode(root) { n -> n.text?.toString()?.contains(text, ignoreCase = true) == true } ?: return false; if (node.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)) return true; val bounds = Rect(); node.getBoundsInScreen(bounds); if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false; val path = Path().apply { moveTo(bounds.exactCenterX(), bounds.exactCenterY()) }; val gesture = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, 1000)).build(); service.dispatchGesture(gesture, null, null); return true }
    private fun typeText(text: String): Boolean { if (text.isBlank()) return false; val root = service.rootInActiveWindow ?: return false; val node = findNode(root) { it.isFocused && it.isEditable } ?: findNode(root) { it.isEditable } ?: return false; val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }; return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args) }
    private fun clearFocused(): Boolean { val root = service.rootInActiveWindow ?: return false; val node = findNode(root) { it.isFocused && it.isEditable } ?: findNode(root) { it.isEditable } ?: return false; val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "") }; return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args) }
    private fun scrollOnce(direction: String): Boolean { val root = service.rootInActiveWindow ?: return false; val scrollable = findNode(root) { it.isScrollable } ?: return false; return when (direction) { "up","backward","left" -> scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD); else -> scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) } }
    private fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean { if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false; val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }; val gesture = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, durationMs)).build(); service.dispatchGesture(gesture, null, null); return true }
    private fun launchPackage(pkg: String): Boolean { val intent = service.packageManager.getLaunchIntentForPackage(pkg) ?: return false; intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); service.startActivity(intent); return true }
    private fun launchByName(name: String): Boolean { if (name.isBlank()) return false; val lower = name.lowercase().trim(); val apps = service.packageManager.getInstalledApplications(0); val match = apps.firstOrNull { service.packageManager.getApplicationLabel(it).toString().lowercase().contains(lower) } ?: return false; return launchPackage(match.packageName) }
    private fun adjustVolume(direction: String): Boolean { val am = service.getSystemService(Context.AUDIO_SERVICE) as AudioManager; return try { when (direction) { "up" -> am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI); "down" -> am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI); "mute" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) am.adjustStreamVolume(AudioManager.STREAM_RING, AudioManager.ADJUST_MUTE, 0) else @Suppress("DEPRECATION") am.ringerMode = AudioManager.RINGER_MODE_SILENT; "unmute" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) am.adjustStreamVolume(AudioManager.STREAM_RING, AudioManager.ADJUST_UNMUTE, 0) else @Suppress("DEPRECATION") am.ringerMode = AudioManager.RINGER_MODE_NORMAL }; true } catch (e: Exception) { false } }
    private fun sendMediaKey(key: String): Boolean { return try { val code = when (key) { "play" -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY; "pause" -> android.view.KeyEvent.KEYCODE_MEDIA_PAUSE; "play_pause" -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE; "next" -> android.view.KeyEvent.KEYCODE_MEDIA_NEXT; "previous","prev" -> android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS; "stop" -> android.view.KeyEvent.KEYCODE_MEDIA_STOP; else -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE }; val am = service.getSystemService(Context.AUDIO_SERVICE) as AudioManager; am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, code)); am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, code)); true } catch (e: Exception) { false } }
    private fun adjustBrightness(direction: String): Boolean { return try { val current = android.provider.Settings.System.getInt(service.contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS, 128); val newVal = when (direction) { "up" -> minOf(255, current + 50); "down" -> maxOf(0, current - 50); else -> current }; android.provider.Settings.System.putInt(service.contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS, newVal); true } catch (e: Exception) { false } }
    private fun clipboardOp(operation: String): Boolean { val root = service.rootInActiveWindow ?: return false; val node = findNode(root) { it.isFocused } ?: findNode(root) { it.isEditable } ?: return false; return when (operation) { "copy" -> node.performAction(AccessibilityNodeInfo.ACTION_COPY); "paste" -> node.performAction(AccessibilityNodeInfo.ACTION_PASTE); "cut" -> node.performAction(AccessibilityNodeInfo.ACTION_CUT); "select_all" -> node.performAction(AccessibilityNodeInfo.ACTION_SELECT); else -> false } }
    private fun findNode(root: AccessibilityNodeInfo, predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? { val queue = ArrayDeque<AccessibilityNodeInfo>(); queue.add(root); while (queue.isNotEmpty()) { val node = queue.removeFirst(); if (predicate(node)) return node; for (i in 0 until node.childCount) node.getChild(i)?.let { queue.add(it) } }; return null }
    private fun actionDelay(type: String): Long = when (type) { "open_app","launch_app" -> 2000L; "tap","click" -> 500L; "long_press" -> 800L; "type","input" -> 350L; "scroll" -> 200L; "swipe" -> 400L; "home","back","recents" -> 600L; "notifications","quick_settings" -> 600L; "screenshot" -> 1000L; else -> 350L }
}

// ─────────────────────────────────────────────────────────────────────────────
// AutoTaskerOverlay — Premium redesigned UI with animated hide/show
// ─────────────────────────────────────────────────────────────────────────────

class AutoTaskerOverlay(private val context: Context) {

    // ── System services ──────────────────────────────────────────────────────
    private val wm: WindowManager  = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val imm: InputMethodManager = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Window params ────────────────────────────────────────────────────────
    private var rootView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var baseBottomOffsetPx = 0
    private var textModeTopOffsetPx = 0

    // ── Sub-views ─────────────────────────────────────────────────────────────
    private var tvStatus: TextView? = null
    private var tvOutput: TextView? = null
    private var tvPartial: TextView? = null
    private var tvBadge: TextView? = null
    private var tvDot: View? = null
    private var waveLayout: LinearLayout? = null
    private var btnMic: LinearLayout? = null
    private var btnStop: LinearLayout? = null
    private var etTextInput: EditText? = null
    private var inputRow: LinearLayout? = null
    private var voiceRow: LinearLayout? = null
    private var tabVoice: TextView? = null
    private var tabText: TextView? = null
    private var scrollOutput: ScrollView? = null
    private var cardContent: LinearLayout? = null  // the main card body (hideable)

    // ── Execution mini-indicator (shown while card is hidden) ─────────────
    private var miniIndicatorView: View? = null
    private var miniDot: View? = null
    private var miniStatus: TextView? = null
    private var miniPulseAnimator: ValueAnimator? = null

    // ── State ────────────────────────────────────────────────────────────────
    private val waveAnimators       = mutableListOf<ValueAnimator>()
    private var isTextMode          = false
    private var isDispatchingTextCommand = false
    private var lastTextCommandAtMs = 0L
    private var isCardVisible       = true

    // ── Focus runnables ──────────────────────────────────────────────────────
    private val focusInputRunnable = Runnable {
        val input = etTextInput
        if (!isTextMode || input?.isAttachedToWindow != true) return@Runnable
        try { input.requestFocus(); imm.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT); applyOverlayAnchorForMode() } catch (_: Exception) {}
    }
    private val makeWindowNotFocusableRunnable = Runnable {
        if (!isTextMode) setWindowFocusable(false)
    }

    // ── Callbacks ────────────────────────────────────────────────────────────
    var onCloseTapped: (() -> Unit)? = null
    var onMicTapped: (() -> Unit)? = null
    var onStopTapped: (() -> Unit)? = null
    var onTextCommand: ((String) -> Unit)? = null
    var onTextModeChanged: ((Boolean) -> Unit)? = null

    // ── Design tokens ─────────────────────────────────────────────────────────
    // Refined dark-glass palette — deep navy base with electric blue accents
    private val cBg           = pc("#E8050C17")   // near-black navy, 91% opaque
    private val cCard         = pc("#F00A1020")   // slightly lighter card
    private val cBorder       = pc("#16253D")
    private val cBorderBright = pc("#1E3A5F")
    private val cAccent       = pc("#3B82F6")     // electric blue
    private val cAccentGlow   = pc("#60A5FA")
    private val cAccentDark   = pc("#1D4ED8")
    private val cGreen        = pc("#22C55E")
    private val cRed          = pc("#EF4444")
    private val cAmber        = pc("#F59E0B")
    private val cTextMain     = pc("#F1F5F9")
    private val cTextMuted    = pc("#475569")
    private val cTextDim      = pc("#1E293B")
    private val cOutputBg     = pc("#040710")
    private val cPartial      = pc("#93C5FD")
    private val cTabActive    = pc("#0F2040")
    private val cTabInactive  = pc("#00000000")
    private val cMiniDot      = pc("#3B82F6")

    // ── Public API ────────────────────────────────────────────────────────────

    fun show() { if (rootView != null) return; buildView() }

    fun hide() {
        stopWaveAnimation()
        stopMiniPulse()
        mainHandler.removeCallbacks(focusInputRunnable)
        mainHandler.removeCallbacks(makeWindowNotFocusableRunnable)
        rootView?.let { try { if (isTextMode) hideKeyboard(); wm.removeView(it) } catch (_: Exception) {} }
        rootView = null
        miniIndicatorView = null
        miniDot = null
        miniStatus = null
    }

    /**
     * Smoothly collapses the main card to a compact one-line execution pill.
     * Call when task begins. The overlay window stays attached (non-intrusive).
     */
    fun collapseToMini(statusText: String = "Running…") {
        mainHandler.post {
            val card = cardContent ?: return@post
            val root = rootView ?: return@post

            // Animate the card out (slide-down + fade)
            val slideOut = ObjectAnimator.ofFloat(card, "translationY", 0f, card.height.toFloat())
            val fadeOut  = ObjectAnimator.ofFloat(card, "alpha", 1f, 0f)
            AnimatorSet().apply {
                playTogether(slideOut, fadeOut)
                duration = 240
                interpolator = AccelerateInterpolator(1.5f)
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        card.visibility = View.GONE
                        card.translationY = 0f
                        card.alpha = 1f
                        showMiniIndicator(statusText)
                    }
                })
                start()
            }
            isCardVisible = false
        }
    }

    /**
     * Expands back from the mini pill to the full card.
     * Call when task completes.
     */
    fun expandFromMini() {
        mainHandler.post {
            val card = cardContent ?: return@post
            hideMiniIndicator {
                card.visibility = View.VISIBLE
                card.alpha = 0f
                card.translationY = 30f

                val slideIn = ObjectAnimator.ofFloat(card, "translationY", 30f, 0f)
                val fadeIn  = ObjectAnimator.ofFloat(card, "alpha", 0f, 1f)
                AnimatorSet().apply {
                    playTogether(slideIn, fadeIn)
                    duration = 280
                    interpolator = DecelerateInterpolator(1.5f)
                    start()
                }
                isCardVisible = true
            }
        }
    }

    fun setStatus(text: String) {
        mainHandler.post {
            tvStatus?.text = text
            val (bg, border) = when {
                text.startsWith("✅") -> pc("#0A1F14") to cGreen
                text.startsWith("❌") -> pc("#1F0A0A") to cRed
                text.startsWith("⚠")  -> pc("#1F170A") to cAmber
                text.startsWith("▶")  -> pc("#09142B") to cAccentGlow
                text.startsWith("🎤") -> pc("#0A1F14") to cGreen
                else                  -> pc("#060C1A") to cBorder
            }
            tvStatus?.background = rounded(bg, border, dp(20).toFloat(), dp(1).toFloat())
            tvDot?.background = pill(
                when {
                    text.startsWith("✅") || text.startsWith("🎤") -> cGreen
                    text.startsWith("❌") -> cRed
                    text.startsWith("▶") -> cAccentGlow
                    else -> pc("#1E3A5F")
                }, 0
            )
            // Also update mini indicator if visible
            miniStatus?.text = text
        }
    }

    fun setOutput(text: String) {
        mainHandler.post {
            tvOutput?.text = text
            mainHandler.postDelayed({ scrollOutput?.fullScroll(View.FOCUS_DOWN) }, 50)
        }
    }

    fun setPartialTranscript(text: String) {
        mainHandler.post { tvPartial?.text = if (text.isBlank()) "" else "\"$text\"" }
    }

    fun setStepBadge(text: String) {
        mainHandler.post { tvBadge?.text = text; tvBadge?.visibility = if (text.isBlank()) View.GONE else View.VISIBLE }
    }

    fun setMicState(listening: Boolean) {
        mainHandler.post {
            btnMic?.background = pill(if (listening) pc("#0F2B1A") else pc("#09142B"), if (listening) cGreen else cAccentGlow)
            (btnMic?.getChildAt(1) as? TextView)?.setTextColor(if (listening) cGreen else cTextMain)
            if (listening) startWaveAnimation() else stopWaveAnimation()
        }
    }

    fun setStopEnabled(enabled: Boolean) {
        mainHandler.post { btnStop?.isEnabled = enabled; btnStop?.alpha = if (enabled) 1f else 0.28f }
    }

    // ── Build ─────────────────────────────────────────────────────────────────

    private fun buildView() {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val lp = WindowManager.LayoutParams(
            dp(352), WindowManager.LayoutParams.WRAP_CONTENT, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(80)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
        baseBottomOffsetPx  = lp.y
        textModeTopOffsetPx = dp(88)
        params = lp

        val root = buildRootLayout()
        rootView = root
        wm.addView(root, lp)
        applyTabState()
    }

    private fun buildRootLayout(): LinearLayout {
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            // No background on the outer wrapper — the card has its own styled bg
        }.also { root ->
            // Main card
            val card = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                background = rounded(cBg, cBorderBright, dp(24).toFloat(), dp(1).toFloat())
                elevation = 28f
            }
            card.addView(buildHeaderBar())
            card.addView(hairline(cBorder))
            card.addView(buildStatusRow())
            card.addView(buildPartialRow())
            card.addView(buildOutputArea())
            card.addView(buildWaveContainer())
            card.addView(buildInputSection())
            cardContent = card
            root.addView(card)

            // Mini indicator (initially hidden; injected as sibling)
            val mini = buildMiniIndicator()
            miniIndicatorView = mini
            mini.visibility = View.GONE
            root.addView(mini)
        }
    }

    // ── Mini execution indicator ───────────────────────────────────────────────

    private fun buildMiniIndicator(): LinearLayout {
        return LinearLayout(context).apply {
            orientation  = LinearLayout.HORIZONTAL
            gravity      = Gravity.CENTER_VERTICAL
            background   = rounded(pc("#F00A1524"), pc("#1E3A5F"), dp(28).toFloat(), dp(1).toFloat())
            elevation    = 16f
            setPadding(dp(16), dp(10), dp(16), dp(10))

            // Pulsing dot
            val dot = View(context).apply {
                background = pill(cMiniDot, 0)
                layoutParams = LinearLayout.LayoutParams(dp(8), dp(8))
                    .also { it.marginEnd = dp(10) }
            }
            miniDot = dot
            addView(dot)

            // Status text
            val tv = TextView(context).apply {
                text = "Running…"
                setTextColor(pc("#94A3B8"))
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            }
            miniStatus = tv
            addView(tv)

            // Stop button
            val stopBtn = TextView(context).apply {
                text = "Stop"
                setTextColor(cRed)
                textSize = 11f
                typeface = Typeface.DEFAULT_BOLD
                setPadding(dp(10), dp(4), dp(10), dp(4))
                background = rounded(pc("#2A0D0D"), cRed, dp(10).toFloat(), dp(1).toFloat())
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                setOnClickListener { onStopTapped?.invoke() }
            }
            addView(stopBtn)
        }
    }

    private fun showMiniIndicator(statusText: String) {
        val mini = miniIndicatorView ?: return
        miniStatus?.text = statusText
        mini.visibility = View.VISIBLE
        mini.alpha = 0f
        mini.translationY = 20f
        mini.animate().alpha(1f).translationY(0f).setDuration(200).setInterpolator(DecelerateInterpolator()).start()
        startMiniPulse()
    }

    private fun hideMiniIndicator(onDone: () -> Unit) {
        val mini = miniIndicatorView ?: run { onDone(); return }
        stopMiniPulse()
        mini.animate().alpha(0f).translationY(20f).setDuration(160).setInterpolator(AccelerateInterpolator())
            .withEndAction { mini.visibility = View.GONE; onDone() }.start()
    }

    private fun startMiniPulse() {
        stopMiniPulse()
        val dot = miniDot ?: return
        miniPulseAnimator = ValueAnimator.ofFloat(0.3f, 1f, 0.3f).apply {
            duration = 1200
            repeatCount = ValueAnimator.INFINITE
            repeatMode  = ValueAnimator.RESTART
            addUpdateListener { dot.alpha = it.animatedValue as Float }
            start()
        }
    }

    private fun stopMiniPulse() { miniPulseAnimator?.cancel(); miniPulseAnimator = null; miniDot?.alpha = 1f }

    // ── Header bar ─────────────────────────────────────────────────────────────

    private fun buildHeaderBar(): LinearLayout {
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), dp(14), dp(14), dp(14))

            // Status dot
            val dot = View(context).apply {
                background = pill(cGreen, 0)
                layoutParams = LinearLayout.LayoutParams(dp(7), dp(7)).also { it.marginEnd = dp(10) }
            }
            tvDot = dot; addView(dot)

            // Title
            addView(TextView(context).apply {
                text = "Auto Tasker"
                setTextColor(cTextMain)
                textSize = 14.5f
                typeface = Typeface.DEFAULT_BOLD
                letterSpacing = 0.02f
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            })

            // Step badge
            val badge = TextView(context).apply {
                text = ""; setTextColor(pc("#93C5FD")); textSize = 10f; typeface = Typeface.DEFAULT_BOLD
                visibility = View.GONE
                background = rounded(pc("#091833"), pc("#2563EB"), dp(8).toFloat(), dp(1).toFloat())
                setPadding(dp(8), dp(3), dp(8), dp(3))
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).also { it.marginEnd = dp(10) }
            }
            tvBadge = badge; addView(badge)

            // Close
            addView(TextView(context).apply {
                text = "✕"; setTextColor(pc("#334155")); textSize = 13f; gravity = Gravity.CENTER
                setPadding(dp(6), dp(2), dp(4), dp(2))
                setOnClickListener { onCloseTapped?.invoke() }
                layoutParams = LinearLayout.LayoutParams(dp(28), dp(28))
            })
        }
    }

    private fun buildStatusRow(): LinearLayout {
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(14), dp(8), dp(14), dp(4))
            gravity = Gravity.CENTER_VERTICAL
            val pill = TextView(context).apply {
                text = "Ready — speak or type a command"
                setTextColor(cTextMuted)
                textSize = 11.5f
                typeface = Typeface.DEFAULT_BOLD
                setPadding(dp(14), dp(7), dp(14), dp(7))
                background = rounded(pc("#060C1A"), cBorder, dp(20).toFloat(), dp(1).toFloat())
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            }
            tvStatus = pill; addView(pill)
        }
    }

    private fun buildPartialRow(): LinearLayout {
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(18), dp(4), dp(18), dp(2))
            val t = TextView(context).apply {
                text = ""; setTextColor(cPartial); textSize = 11.5f
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.ITALIC)
            }
            tvPartial = t; addView(t)
        }
    }

    private fun buildOutputArea(): ScrollView {
        val scroll = ScrollView(context).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(96))
                .also { it.setMargins(dp(14), dp(6), dp(14), dp(4)) }
            background = rounded(cOutputBg, pc("#111827"), dp(14).toFloat(), dp(1).toFloat())
            setPadding(dp(14), dp(10), dp(14), dp(10))
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
        }
        scrollOutput = scroll
        val tv = TextView(context).apply {
            text = ""; setTextColor(pc("#64748B")); textSize = 11f
            setLineSpacing(dp(3).toFloat(), 1f); typeface = Typeface.MONOSPACE
        }
        tvOutput = tv; scroll.addView(tv)
        return scroll
    }

    private fun buildWaveContainer(): LinearLayout {
        val wave = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL or Gravity.CENTER_HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(24))
                .also { it.setMargins(0, dp(8), 0, dp(4)) }
        }
        waveLayout = wave; buildWaveBars(wave)
        return wave
    }

    // ── Input section ──────────────────────────────────────────────────────────

    private fun buildInputSection(): LinearLayout {
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(6), dp(14), dp(16))

            // Mode tabs — pill-shaped switcher
            val tabs = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                background = rounded(pc("#040810"), pc("#111827"), dp(16).toFloat(), dp(1).toFloat())
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(38))
                    .also { it.bottomMargin = dp(10) }
                setPadding(dp(3), dp(3), dp(3), dp(3))
            }
            val tVoice = buildTabLabel("🎙  Voice", active = true) { switchToVoiceMode() }
            tabVoice = tVoice; tabs.addView(tVoice)
            val tText = buildTabLabel("⌨  Text", active = false) { switchToTextMode() }
            tabText = tText; tabs.addView(tText)
            addView(tabs)

            addView(buildVoiceControlRow())
            addView(buildTextInputRow())
        }
    }

    private fun buildTabLabel(label: String, active: Boolean, onClick: () -> Unit): TextView {
        return TextView(context).apply {
            text = label
            setTextColor(if (active) cTextMain else cTextMuted)
            textSize = 12f; typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f)
            background = if (active) rounded(cTabActive, cAccentGlow, dp(13).toFloat(), dp(1).toFloat())
                         else        rounded(cTabInactive, 0, dp(13).toFloat(), 0f)
            setOnClickListener { onClick() }
        }
    }

    private fun buildVoiceControlRow(): LinearLayout {
        val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER }
        voiceRow = row

        // Stop button
        val stop = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER
            setPadding(dp(16), dp(10), dp(18), dp(10))
            background = rounded(pc("#140808"), cRed, dp(22).toFloat(), dp(1).toFloat())
            isEnabled = false; alpha = 0.28f
            setOnClickListener { onStopTapped?.invoke() }
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .also { it.marginEnd = dp(10) }
        }
        stop.addView(TextView(context).apply { text = "⏹"; setTextColor(cRed); textSize = 11f; setPadding(0, 0, dp(5), 0) })
        stop.addView(TextView(context).apply { text = "Stop"; setTextColor(cTextMain); textSize = 12f; typeface = Typeface.DEFAULT_BOLD })
        btnStop = stop; row.addView(stop)

        // Mic button — primary CTA
        val mic = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER
            setPadding(dp(22), dp(10), dp(22), dp(10))
            background = pill(pc("#09142B"), cAccentGlow)
            setOnClickListener { onMicTapped?.invoke() }
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        mic.addView(TextView(context).apply { text = "🎙"; textSize = 14f; setPadding(0, 0, dp(8), 0) })
        mic.addView(TextView(context).apply { text = "Speak"; setTextColor(cTextMain); textSize = 13f; typeface = Typeface.DEFAULT_BOLD })
        btnMic = mic; row.addView(mic)
        return row
    }

    private fun buildTextInputRow(): LinearLayout {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; visibility = View.GONE
        }
        inputRow = row

        val et = EditText(context).apply {
            hint = "Type a command…"; setHintTextColor(pc("#1E293B")); setTextColor(cTextMain)
            textSize = 13f; background = rounded(pc("#030710"), pc("#111827"), dp(18).toFloat(), dp(1).toFloat())
            setPadding(dp(14), dp(10), dp(14), dp(10)); maxLines = 2
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE
            imeOptions = EditorInfo.IME_ACTION_SEND or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            isFocusable = true; isFocusableInTouchMode = true
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).also { it.marginEnd = dp(8) }
            setOnEditorActionListener { _, actionId, event ->
                if (actionId == EditorInfo.IME_ACTION_SEND || (event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN)) { submitTextCommand(); true } else false
            }
        }
        etTextInput = et; row.addView(et)

        // Send button
        val send = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER
            setPadding(dp(14), dp(10), dp(14), dp(10)); background = pill(cAccent, 0)
            setOnClickListener { submitTextCommand() }
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        send.addView(TextView(context).apply { text = "▶"; setTextColor(Color.WHITE); textSize = 13f; typeface = Typeface.DEFAULT_BOLD })
        row.addView(send)
        return row
    }

    // ── Mode switching ─────────────────────────────────────────────────────────

    private fun switchToVoiceMode() {
        if (!isTextMode) return; isTextMode = false; onTextModeChanged?.invoke(false)
        mainHandler.removeCallbacks(focusInputRunnable)
        hideKeyboard()
        mainHandler.removeCallbacks(makeWindowNotFocusableRunnable)
        mainHandler.postDelayed(makeWindowNotFocusableRunnable, 80)
        applyOverlayAnchorForMode(); applyTabState()
    }

    private fun switchToTextMode() {
        if (isTextMode) return; isTextMode = true; onTextModeChanged?.invoke(true)
        mainHandler.removeCallbacks(makeWindowNotFocusableRunnable)
        applyTabState(); applyOverlayAnchorForMode()
        setWindowFocusable(true)
        mainHandler.removeCallbacks(focusInputRunnable)
        mainHandler.postDelayed(focusInputRunnable, 120)
    }

    private fun setWindowFocusable(focusable: Boolean) {
        val root = rootView ?: return; val lp = params ?: return
        try {
            lp.flags = if (focusable) lp.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
                       else           lp.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            wm.updateViewLayout(root, lp)
        } catch (_: Exception) {}
    }

    private fun hideKeyboard() { etTextInput?.let { it.clearFocus(); imm.hideSoftInputFromWindow(it.windowToken, 0) } }

    private fun submitTextCommand() {
        val cmd = etTextInput?.text?.toString()?.trim().orEmpty(); if (cmd.isBlank()) return
        val now = System.currentTimeMillis()
        if (isDispatchingTextCommand || (now - lastTextCommandAtMs) < 700L) return
        isDispatchingTextCommand = true; lastTextCommandAtMs = now
        try { hideKeyboard(); onTextCommand?.invoke(cmd); etTextInput?.setText("") }
        catch (t: Throwable) { Log.e(TAG, "Text command dispatch failed", t) }
        finally { mainHandler.postDelayed({ isDispatchingTextCommand = false }, 350L) }
    }

    private fun applyOverlayAnchorForMode() {
        val root = rootView ?: return; val lp = params ?: return
        try {
            val targetGravity = if (isTextMode) Gravity.TOP or Gravity.CENTER_HORIZONTAL else Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            val targetY = if (isTextMode) textModeTopOffsetPx else baseBottomOffsetPx
            if (lp.gravity != targetGravity || lp.y != targetY) { lp.gravity = targetGravity; lp.y = targetY; wm.updateViewLayout(root, lp) }
        } catch (_: Exception) {}
    }

    private fun applyTabState() {
        mainHandler.post {
            tabVoice?.apply {
                background = if (!isTextMode) rounded(cTabActive, cAccentGlow, dp(13).toFloat(), dp(1).toFloat()) else rounded(cTabInactive, 0, dp(13).toFloat(), 0f)
                setTextColor(if (!isTextMode) cTextMain else cTextMuted)
            }
            tabText?.apply {
                background = if (isTextMode) rounded(cTabActive, cAccentGlow, dp(13).toFloat(), dp(1).toFloat()) else rounded(cTabInactive, 0, dp(13).toFloat(), 0f)
                setTextColor(if (isTextMode) cTextMain else cTextMuted)
            }
            inputRow?.visibility  = if (isTextMode)  View.VISIBLE else View.GONE
            waveLayout?.visibility = if (!isTextMode) View.VISIBLE else View.GONE
            voiceRow?.visibility   = if (!isTextMode) View.VISIBLE else View.GONE
        }
    }

    // ── Wave animation ─────────────────────────────────────────────────────────

    private fun buildWaveBars(container: LinearLayout) {
        val colors = listOf("#1E3A8A","#1D4ED8","#2563EB","#3B82F6","#60A5FA","#93C5FD","#60A5FA","#3B82F6","#2563EB","#1D4ED8","#1E3A8A","#2563EB","#3B82F6","#60A5FA")
        colors.forEach { color ->
            container.addView(View(context).apply {
                background = pill(pc(color), 0)
                layoutParams = LinearLayout.LayoutParams(dp(3), dp(5)).also { it.marginStart = dp(2); it.marginEnd = dp(2) }
            })
        }
    }

    private fun startWaveAnimation() {
        stopWaveAnimation()
        val bars = waveLayout ?: return
        for (i in 0 until bars.childCount) {
            val bar = bars.getChildAt(i)
            val minH = dp(3).toFloat(); val maxH = dp(10 + (i % 5) * 5).toFloat()
            ValueAnimator.ofFloat(minH, maxH, minH).apply {
                duration = 300L + i * 50L; repeatCount = ValueAnimator.INFINITE; repeatMode = ValueAnimator.REVERSE; startDelay = i * 35L
                addUpdateListener { anim -> val h = (anim.animatedValue as Float).toInt(); (bar.layoutParams as LinearLayout.LayoutParams).height = h; bar.requestLayout() }
                start(); waveAnimators.add(this)
            }
        }
    }

    private fun stopWaveAnimation() {
        waveAnimators.forEach { it.cancel() }; waveAnimators.clear()
        val bars = waveLayout ?: return
        for (i in 0 until bars.childCount) { val bar = bars.getChildAt(i); (bar.layoutParams as LinearLayout.LayoutParams).height = dp(5); bar.requestLayout() }
    }

    // ── Drawing helpers ────────────────────────────────────────────────────────

    private fun rounded(fill: Int, stroke: Int, radius: Float, strokeW: Float): GradientDrawable =
        GradientDrawable().apply { shape = GradientDrawable.RECTANGLE; setColor(fill); cornerRadius = radius; if (stroke != 0) setStroke(strokeW.toInt(), stroke) }

    private fun pill(fill: Int, stroke: Int): GradientDrawable =
        GradientDrawable().apply { shape = GradientDrawable.RECTANGLE; setColor(fill); cornerRadius = dp(50).toFloat(); if (stroke != 0) setStroke(dp(1), stroke) }

    private fun hairline(color: Int): View = View(context).apply { layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1); setBackgroundColor(color) }

    private fun pc(hex: String): Int = Color.parseColor(hex)
    private fun dp(value: Int): Int = (value * context.resources.displayMetrics.density).toInt()
}

// ─────────────────────────────────────────────────────────────────────────────
// AutoTaskerService — foreground service, entry point
// ─────────────────────────────────────────────────────────────────────────────

class AutoTaskerService : Service() {

    companion object {
        const val ACTION_TOGGLE_MIC = "com.Android.stremini_ai.AUTOTASKER_TOGGLE_MIC"
        const val ACTION_STOP       = "com.Android.stremini_ai.AUTOTASKER_STOP"
    }

    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var overlay: AutoTaskerOverlay? = null
    private var voice:   VoiceEngine? = null
    private var brain:   AutoTaskerBrain? = null

    private var isExecuting    = false
    private var continuousMode = true

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground()
        try { buildComponents() }
        catch (t: Throwable) { Log.e(TAG, "AutoTasker initialization failed", t); stopSelf() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) { ACTION_TOGGLE_MIC -> toggleMic(); ACTION_STOP -> stopSelf() }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        overlay?.hide(); voice?.stop(); brain?.destroy(); serviceScope.cancel()
    }

    // ── Build ──────────────────────────────────────────────────────────────────

    /** Collapse overlay to mini pill while task runs — no abrupt removal */
    private fun collapseOverlayForExecution(statusText: String = "Starting…") {
        try { overlay?.collapseToMini(statusText) } catch (_: Exception) {}
    }

    /** Expand overlay back after task completes */
    private fun expandOverlayAfterExecution() {
        try {
            overlay?.expandFromMini()
            overlay?.setMicState(false)
        } catch (_: Exception) {}
    }

    private fun buildComponents() {
        if (!canDrawOverlays()) {
            Log.w(TAG, "Overlay permission missing.")
            Toast.makeText(this, "Enable 'Display over other apps' for Auto Tasker.", Toast.LENGTH_LONG).show()
            stopSelf(); return
        }

        overlay = AutoTaskerOverlay(this).apply {
            show()
            onCloseTapped = { stopSelf() }
            onMicTapped   = { toggleMic() }
            onTextModeChanged = { isTextMode ->
                if (isTextMode) {
                    voice?.stop(); overlay?.setMicState(false)
                    if (!isExecuting) overlay?.setStatus("⌨ Text mode — type your command")
                } else if (!isExecuting) {
                    startListening()
                }
            }
            onStopTapped = {
                brain?.cancel(); isExecuting = false
                expandOverlayAfterExecution()
                overlay?.setStatus("⏹ Stopped"); overlay?.setMicState(false)
                overlay?.setStopEnabled(false); overlay?.setStepBadge("")
                if (continuousMode) delayThenResume()
            }
            onTextCommand = { cmd -> handleCommand(cmd) }
            setMicState(false)
            setStatus("Ready — choose voice or text")
            setStopEnabled(false)
        }

        initializeBrainIfPossible()
        buildVoiceEngine()
        startListening()
    }

    private fun canDrawOverlays(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(this) else true

    private fun initializeBrainIfPossible(): Boolean {
        val service = ScreenReaderService.getInstance()
        if (service == null) {
            overlay?.setStatus(
                if (isAccessibilityServiceEnabled()) "⏳ Connecting accessibility service…"
                else "⚠ Enable Accessibility first"
            )
            return false
        }
        brain = AutoTaskerBrain(
            service  = service,
            onStatus = { msg ->
                overlay?.setStatus(msg)
                updateNotification(msg)
                val stepMatch = Regex("Step (\\d+)/(\\d+)").find(msg)
                if (stepMatch != null) overlay?.setStepBadge("${stepMatch.groupValues[1]}/${stepMatch.groupValues[2]}")
                else if (msg.startsWith("✅") || msg.startsWith("❌") || msg.startsWith("⏹") || msg.startsWith("⚠")) overlay?.setStepBadge("")
            },
            onOutput = { text -> overlay?.setOutput(text) }
        )
        return true
    }

    private suspend fun awaitConnectedAccessibilityService(timeoutMs: Long = 5000): Boolean {
        if (brain != null) return true
        if (!isAccessibilityServiceEnabled()) return false
        val startedAt = System.currentTimeMillis()
        while (System.currentTimeMillis() - startedAt < timeoutMs) { if (initializeBrainIfPossible()) return true; delay(200) }
        return false
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val serviceName = "$packageName/${ScreenReaderService::class.java.canonicalName}"
        val settingValue = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':'); splitter.setString(settingValue)
        while (splitter.hasNext()) { if (splitter.next().equals(serviceName, ignoreCase = true)) return true }
        return false
    }

    private fun buildVoiceEngine() {
        voice = VoiceEngine(
            context   = this,
            onPartial = { partial -> overlay?.setPartialTranscript(partial) },
            onFinal   = { command -> handleCommand(command) },
            onError   = { code ->
                val msg = voiceErrorMessage(code)
                overlay?.setStatus(msg)
                if (code != SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS && code != SpeechRecognizer.ERROR_RECOGNIZER_BUSY) {
                    serviceScope.launch { delay(700); if (!isExecuting) voice?.resume() }
                }
            },
            onReady   = { if (!isExecuting) { overlay?.setStatus("🎤 Listening…"); overlay?.setMicState(true) } }
        )
    }

    private fun startListening() {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            overlay?.setStatus("⚠ Microphone permission required"); return
        }
        voice?.start()
    }

    private fun toggleMic() {
        if (voice?.isListening == true) { voice?.stop(); overlay?.setMicState(false); overlay?.setStatus("Mic off") }
        else startListening()
    }

    // ── Command handling ───────────────────────────────────────────────────────

    private fun handleCommand(command: String) {
        if (command.isBlank()) { voice?.resume(); return }
        if (isExecuting) { overlay?.setStatus("⚠ Already executing a command"); return }

        val lower = command.lowercase().trim()
        if (lower == "stop" || lower == "cancel" || lower == "stop tasker") {
            brain?.cancel(); isExecuting = false
            expandOverlayAfterExecution()
            overlay?.setStatus("⏹ Stopped"); overlay?.setMicState(false)
            overlay?.setStopEnabled(false); overlay?.setStepBadge("")
            if (continuousMode) delayThenResume()
            return
        }
        if (lower == "quit" || lower == "exit" || lower == "close autotasker") { stopSelf(); return }

        voice?.stop(); overlay?.setPartialTranscript(""); overlay?.setMicState(false)
        overlay?.setStopEnabled(true)
        isExecuting = true

        serviceScope.launch {
            // Brief countdown, then collapse the overlay to the mini pill
            overlay?.setStatus("▶ Starting…")
            delay(800L)

            // ── KEY FLOW: collapse card to non-intrusive mini indicator ──
            collapseOverlayForExecution("Running: ${command.take(30)}…")

            try {
                val ready = awaitConnectedAccessibilityService()
                if (!ready) {
                    isExecuting = false
                    expandOverlayAfterExecution()
                    overlay?.setStopEnabled(false); overlay?.setStepBadge("")
                    overlay?.setStatus("⚠ Enable Accessibility first")
                    return@launch
                }
                val runJob = brain?.execute(command)
                runJob?.join()
                isExecuting = false

                // ── Expand back with smooth animation ──
                expandOverlayAfterExecution()
                overlay?.setStopEnabled(false); overlay?.setStepBadge("")

                if (continuousMode) {
                    delay(1200)
                    overlay?.setStatus("🎤 Listening…")
                    overlay?.setMicState(true)
                    voice?.resume()
                } else {
                    overlay?.setStatus("Done — tap mic or type to continue")
                }
            } catch (t: Throwable) {
                Log.e(TAG, "handleCommand failed", t)
                isExecuting = false
                expandOverlayAfterExecution()
                overlay?.setStopEnabled(false); overlay?.setStepBadge("")
                overlay?.setStatus("❌ Command failed")
            }
        }
    }

    private fun delayThenResume() {
        serviceScope.launch {
            delay(1000)
            overlay?.setStatus("🎤 Listening…")
            overlay?.setMicState(true)
            voice?.resume()
        }
    }

    // ── Notification ───────────────────────────────────────────────────────────

    private fun startForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(NOTIF_CHANNEL_ID, "Auto Tasker", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
        startForeground(NOTIF_ID, buildNotification("Ready"))
    }

    private fun updateNotification(status: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification(status))
    }

    private fun buildNotification(status: String): android.app.Notification {
        val toggleIntent = PendingIntent.getService(this, 0, Intent(this, AutoTaskerService::class.java).apply { action = ACTION_TOGGLE_MIC }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stopIntent   = PendingIntent.getService(this, 1, Intent(this, AutoTaskerService::class.java).apply { action = ACTION_STOP },       PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
            .setContentTitle("🎙 Auto Tasker").setContentText(status)
            .setSmallIcon(R.mipmap.ic_launcher)
            .addAction(0, "Toggle Mic", toggleIntent).addAction(0, "Stop", stopIntent)
            .setOngoing(true).setSilent(true).setPriority(NotificationCompat.PRIORITY_LOW).build()
    }

    private fun voiceErrorMessage(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO                    -> "🔇 Audio error"
        SpeechRecognizer.ERROR_CLIENT                   -> "⚠ Client error"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "⚠ Mic permission denied"
        SpeechRecognizer.ERROR_NETWORK                  -> "📡 Network error"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT          -> "📡 Network timeout"
        SpeechRecognizer.ERROR_NO_MATCH                 -> "🤷 No speech detected"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY          -> "⏳ Recognizer busy"
        SpeechRecognizer.ERROR_SERVER                   -> "🌐 Server error"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT           -> "⏱ Silence timeout"
        else                                            -> "⚠ Voice error ($code)"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// AutoTaskerManager
// ─────────────────────────────────────────────────────────────────────────────

class AutoTaskerManager(private val context: Context) {

    private var running = false

    fun toggle(featureId: Int, activeFeatures: MutableSet<Int>) {
        if (running) stop(featureId, activeFeatures) else start(featureId, activeFeatures)
    }

    fun start(featureId: Int, activeFeatures: MutableSet<Int>) {
        if (running) return
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Toast.makeText(context, "Microphone permission required", Toast.LENGTH_LONG).show(); return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
            Toast.makeText(context, "Enable 'Display over other apps' to use Auto Tasker", Toast.LENGTH_LONG).show(); return
        }
        val intent = Intent(context, AutoTaskerService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
        else context.startService(intent)
        running = true; activeFeatures.add(featureId)
    }

    fun stop(featureId: Int, activeFeatures: MutableSet<Int>) {
        context.stopService(Intent(context, AutoTaskerService::class.java))
        running = false; activeFeatures.remove(featureId)
    }

    fun isRunning() = running
}