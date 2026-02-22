package com.Android.stremini_ai

import android.animation.ValueAnimator
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.PixelFormat
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

class ChatOverlayService : Service(), View.OnTouchListener {

    companion object {
        const val ACTION_SEND_MESSAGE = "com.Android.stremini_ai.SEND_MESSAGE"
        const val EXTRA_MESSAGE = "message"
        const val ACTION_SCANNER_START = "com.Android.stremini_ai.SCANNER_START"
        const val ACTION_SCANNER_STOP = "com.Android.stremini_ai.SCANNER_STOP"
        val NEON_BLUE: Int = android.graphics.Color.parseColor("#00D9FF")
        val WHITE: Int = android.graphics.Color.parseColor("#FFFFFF")
    }

    private lateinit var windowManager: WindowManager
    private lateinit var overlayView: View
    private lateinit var params: WindowManager.LayoutParams

    private var floatingChatView: View? = null
    private var floatingChatParams: WindowManager.LayoutParams? = null
    private var isChatbotVisible = false

    private lateinit var bubbleIcon: ImageView
    private lateinit var menuItems: List<ImageView>
    private var isMenuExpanded = false

    private val activeFeatures = mutableSetOf<Int>()
    private var isScannerActive = false
    private lateinit var inputMethodManager: InputMethodManager
    
    private var autoTaskerView: View? = null
    private var autoTaskerParams: WindowManager.LayoutParams? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var isAutoTaskerVisible = false

    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false
    private var hasMoved = false

    private val bubbleSizeDp = 60f  // Matches layout bubble size
    private val menuItemSizeDp = 50f  // Matches layout menu item size
    private val radiusDp = 80f

    // Store bubble's screen position (center of bubble on screen, not window position)
    private var bubbleScreenX = 0
    private var bubbleScreenY = 0

    // Animation guards to prevent overlapping/resizing flicker
    private var isMenuAnimating = false
    private var windowAnimator: ValueAnimator? = null
    private var isWindowResizing = false
    private var preventPositionUpdates = false  // NEW: Prevents position updates during resize

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
        .build()

    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val controlReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_SEND_MESSAGE -> {
                    val message = intent.getStringExtra(EXTRA_MESSAGE)
                    if (message != null) {
                        addMessageToChatbot(message, isUser = false)
                    }
                }
                ACTION_SCANNER_START -> {
                    isScannerActive = true
                    updateMenuItemsColor()
                    Toast.makeText(context, "Screen Detection Started", Toast.LENGTH_SHORT).show()
                }
                ACTION_SCANNER_STOP -> {
                    isScannerActive = false
                    updateMenuItemsColor()
                    Toast.makeText(context, "Screen Detection Stopped", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        inputMethodManager = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        startForegroundService()
        setupOverlay()

        val filter = IntentFilter().apply {
            addAction(ACTION_SEND_MESSAGE)
            addAction(ACTION_SCANNER_START)
            addAction(ACTION_SCANNER_STOP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(controlReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(controlReceiver, filter)
        }
    }

    private fun setupOverlay() {
        overlayView = LayoutInflater.from(this).inflate(R.layout.chat_bubble_layout, null)
        bubbleIcon = overlayView.findViewById(R.id.bubble_icon)

        menuItems = listOf(
            overlayView.findViewById(R.id.btn_auto_tasker),
            overlayView.findViewById(R.id.btn_settings),
            overlayView.findViewById(R.id.btn_ai),
            overlayView.findViewById(R.id.btn_scanner),
            overlayView.findViewById(R.id.btn_keyboard)
        )

        val typeParam = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        }

        val radiusPx = dpToPx(radiusDp).toFloat()
        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
        val expandedWindowSizePx = ((radiusPx * 2) + bubbleSizePx + dpToPx(20f)).toInt()
        val collapsedWindowSizePx = (bubbleSizePx + dpToPx(10f)).toInt()

        params = WindowManager.LayoutParams(
            collapsedWindowSizePx,
            collapsedWindowSizePx,
            typeParam,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START
        
        // Initialize bubble screen position (bubble center on screen)
        val screenHeight = resources.displayMetrics.heightPixels
        bubbleScreenX = 60
        bubbleScreenY = (screenHeight * 0.25).toInt()
        
        // Calculate window position from bubble position
        val windowHalfSize = collapsedWindowSizePx / 2
        params.x = bubbleScreenX - windowHalfSize
        params.y = bubbleScreenY - windowHalfSize

        bubbleIcon.setOnTouchListener(this)
        
        // Note: Bubble background is set in XML using glow_gradient_ring drawable
        // No need to override it programmatically

        menuItems[0].setOnClickListener {
            collapseMenu()
            handleAutoTasker()
        }
        menuItems[1].setOnClickListener {
            collapseMenu()
            handleSettings()
        }
        menuItems[2].setOnClickListener {
            collapseMenu()
            handleAIChat()
        }
        menuItems[3].setOnClickListener {
            collapseMenu()
            handleScanner()
        }
        menuItems[4].setOnClickListener {
            collapseMenu()
            handleKeyboard()
        }

        bubbleIcon.setLayerType(View.LAYER_TYPE_HARDWARE, null)
        bubbleIcon.isClickable = true
        bubbleIcon.isFocusable = true
        
        menuItems.forEach { 
            it.setLayerType(View.LAYER_TYPE_HARDWARE, null)
            it.isClickable = true
            it.isFocusable = true
            
            // Start as INVISIBLE (not GONE to avoid layout shifts)
            it.visibility = View.INVISIBLE
        }

        updateMenuItemsColor()
        
        // Make root overlay completely transparent and non-clickable
        // Only the bubble and menu items should receive touches
        overlayView.background = null
        overlayView.isClickable = false
        overlayView.isFocusable = false
        overlayView.setOnTouchListener { _, _ -> false }
        
        windowManager.addView(overlayView, params)

        (overlayView as? android.view.ViewGroup)?.apply {
            clipToPadding = false
            clipChildren = false
            // Don't intercept touch events - let them pass through
            isMotionEventSplittingEnabled = false
        }

        overlayView.layoutParams = overlayView.layoutParams?.apply {
            width = params.width
            height = params.height
        }
        overlayView.requestLayout()
    }

    private fun handleAIChat() {
        toggleFeature(menuItems[2].id)
        if (isFeatureActive(menuItems[2].id)) {
            showFloatingChatbot()
        } else {
            hideFloatingChatbot()
        }
    }

    private fun showFloatingChatbot() {
        if (isChatbotVisible) return

        floatingChatView = LayoutInflater.from(this).inflate(R.layout.floating_chatbot_layout, null)

        val typeParam = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        }

        floatingChatParams = WindowManager.LayoutParams(
            dpToPx(300f),
            dpToPx(400f),
            typeParam,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        )

        floatingChatParams?.gravity = Gravity.BOTTOM or Gravity.END
        floatingChatParams?.x = dpToPx(20f)
        floatingChatParams?.y = dpToPx(100f)

        floatingChatView?.setLayerType(View.LAYER_TYPE_HARDWARE, null)

        setupFloatingChatListeners()

        windowManager.addView(floatingChatView, floatingChatParams)
        isChatbotVisible = true

        addMessageToChatbot("Hello! I'm Stremini AI. How can I help you?", isUser = false)
    }

    private fun setupFloatingChatListeners() {
        floatingChatView?.let { view ->
            val header = view.findViewById<LinearLayout>(R.id.chat_header)
            var chatInitialX = 0
            var chatInitialY = 0
            var chatInitialTouchX = 0f
            var chatInitialTouchY = 0f
            var chatIsDragging = false

            header?.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        chatInitialTouchX = event.rawX
                        chatInitialTouchY = event.rawY
                        chatInitialX = floatingChatParams?.x ?: 0
                        chatInitialY = floatingChatParams?.y ?: 0
                        chatIsDragging = true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (chatIsDragging && floatingChatParams != null) {
                            val deltaX = (event.rawX - chatInitialTouchX).toInt()
                            val deltaY = (event.rawY - chatInitialTouchY).toInt()
                            floatingChatParams?.x = chatInitialX - deltaX
                            floatingChatParams?.y = chatInitialY - deltaY
                            windowManager.updateViewLayout(floatingChatView!!, floatingChatParams!!)
                        }
                    }
                    MotionEvent.ACTION_UP -> {
                        chatIsDragging = false
                    }
                }
                true
            }

            view.findViewById<ImageView>(R.id.btn_close_chat)?.setOnClickListener {
                hideFloatingChatbot()
                toggleFeature(menuItems[2].id)
            }

            view.findViewById<ImageView>(R.id.btn_send_message)?.setOnClickListener {
                val input = view.findViewById<EditText>(R.id.et_chat_input)
                val message = input?.text?.toString()?.trim()
                if (!message.isNullOrEmpty()) {
                    addMessageToChatbot(message, isUser = true)
                    input.text?.clear()
                    sendMessageToAPI(message)
                }
            }

            view.findViewById<ImageView>(R.id.btn_voice_input)?.setOnClickListener {
                Toast.makeText(this, "Voice input coming soon", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun sendMessageToAPI(userMessage: String) {
        serviceScope.launch(Dispatchers.IO) {
            try {
                val requestJson = JSONObject().apply {
                    put("message", userMessage)
                }

                val requestBody = requestJson.toString().toRequestBody("application/json".toMediaType())

                val request = Request.Builder()
                    .url("https://ai-keyboard-backend.vishwajeetadkine705.workers.dev/chat/message")
                    .post(requestBody)
                    .build()

                val response = client.newCall(request).execute()

                if (response.isSuccessful) {
                    val responseBody = response.body?.string() ?: ""
                    val json = JSONObject(responseBody)
                    val reply = json.optString("reply",
                        json.optString("response",
                            json.optString("message", "No response from AI")))
                    withContext(Dispatchers.Main) {
                        addMessageToChatbot(reply, isUser = false)
                    }
                } else {
                    withContext(Dispatchers.Main) {
                        addMessageToChatbot("❌ Server error: ${response.code}", isUser = false)
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    addMessageToChatbot("⚠️ Network error: ${e.message}", isUser = false)
                }
            }
        }
    }

    private fun addMessageToChatbot(message: String, isUser: Boolean) {
        floatingChatView?.let { view ->
            val messagesContainer = view.findViewById<LinearLayout>(R.id.messages_container)
            val messageView = LayoutInflater.from(this).inflate(
                if (isUser) R.layout.message_bubble_user else R.layout.message_bubble_bot,
                messagesContainer,
                false
            )
            messageView.findViewById<TextView>(R.id.tv_message)?.text = message
            messagesContainer?.addView(messageView)
            view.findViewById<ScrollView>(R.id.scroll_messages)?.post {
                view.findViewById<ScrollView>(R.id.scroll_messages)?.fullScroll(View.FOCUS_DOWN)
            }
        }
    }


    private fun showAutoTasker(): Boolean {
        if (isAutoTaskerVisible) return true
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Toast.makeText(this, "Microphone permission is required. Opening app settings...", Toast.LENGTH_LONG).show()
            try {
                val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } catch (_: Exception) {}
            return false
        }

        autoTaskerView = LayoutInflater.from(this).inflate(R.layout.auto_tasker_overlay, null)
        val typeParam = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        }

        autoTaskerParams = WindowManager.LayoutParams(
            dpToPx(320f),
            dpToPx(420f),
            typeParam,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        autoTaskerView?.findViewById<ImageView>(R.id.btn_close_tasker)?.setOnClickListener {
            hideAutoTasker()
            activeFeatures.remove(menuItems[0].id)
            updateMenuItemsColor()
        }

        autoTaskerView?.findViewById<ImageView>(R.id.btn_start_listening)?.setOnClickListener {
            startVoiceCapture()
        }

        windowManager.addView(autoTaskerView, autoTaskerParams)
        isAutoTaskerVisible = true
        startVoiceCapture()
        return true
    }

    private fun hideAutoTasker() {
        speechRecognizer?.destroy()
        speechRecognizer = null
        autoTaskerView?.let { windowManager.removeView(it) }
        autoTaskerView = null
        autoTaskerParams = null
        isAutoTaskerVisible = false
    }

    private fun startVoiceCapture() {
        val view = autoTaskerView ?: return
        val status = view.findViewById<TextView>(R.id.tv_tasker_status)
        status.text = "Listening..."

        speechRecognizer?.destroy()
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            status.text = "Speech recognition not available on this device"
            return
        }

        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: android.os.Bundle?) { status.text = "Speak now..." }
                override fun onBeginningOfSpeech() { status.text = "Listening..." }
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() { status.text = "Processing your command..." }
                override fun onError(error: Int) { status.text = "Voice capture failed ($error). Please try again." }
                override fun onEvent(eventType: Int, params: android.os.Bundle?) {}
                override fun onPartialResults(partialResults: android.os.Bundle?) {}
                override fun onResults(results: android.os.Bundle?) {
                    val command = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim()
                    if (command.isNullOrBlank()) {
                        status.text = "Could not understand. Try again."
                    } else {
                        status.text = "Understood: $command"
                        view.findViewById<TextView>(R.id.tv_tasker_output).text = "You said: $command\n\nPlanning actions..."
                        sendVoiceTaskCommand(command)
                    }
                }
            })
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        speechRecognizer?.startListening(intent)
    }

    // UPDATED FUNCTION with agentic multi-step execution loop
    private fun sendVoiceTaskCommand(command: String) {
        serviceScope.launch(Dispatchers.IO) {
            try {
                val agentResult = executeAgenticVoiceTask(command)

                val directCommandRan = executeDirectVoiceCommand(command)
                val finalStatus = if (directCommandRan && agentResult.first.contains("response", ignoreCase = true)) {
                    "Task completed"
                } else {
                    agentResult.first
                }
                val finalOutput = if (directCommandRan && agentResult.second.isNotBlank()) {
                    "Direct device automation executed.\n\n${agentResult.second}"
                } else if (directCommandRan) {
                    "Direct device automation executed."
                } else {
                    agentResult.second
                }

                withContext(Dispatchers.Main) {
                    autoTaskerView?.findViewById<TextView>(R.id.tv_tasker_status)?.text = finalStatus
                    autoTaskerView?.findViewById<TextView>(R.id.tv_tasker_output)?.text = finalOutput
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    autoTaskerView?.findViewById<TextView>(R.id.tv_tasker_status)?.text = "Failed to execute task"
                    autoTaskerView?.findViewById<TextView>(R.id.tv_tasker_output)?.text = e.message ?: "Unknown error"
                }
            }
        }
    }

    private fun executeAgenticVoiceTask(command: String): Pair<String, String> {
        val actionHistory = JSONArray()
        var step = 1
        var lastError: String? = null
        val notes = mutableListOf<String>()

        while (step <= 15) {
            val payload = JSONObject().apply {
                put("command", command)
                put("query", command)
                put("instruction", command)
                put("ui_context", ScreenReaderService.captureUiContextSnapshot())
                put("execute", true)
                put("dryRun", false)
                put("autoExecute", true)
                put("agentMode", true)
                put("stepNumber", step)
                put("previousActions", actionHistory)
                if (!lastError.isNullOrBlank()) put("previousError", lastError)
            }

            val body = payload.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("https://ai-keyboard-backend.vishwajeetadkine705.workers.dev/automation/execute-task")
                .post(body)
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                return "Failed to execute task" to "Server error: ${response.code}"
            }

            val raw = response.body?.string().orEmpty()
            val json = JSONObject(raw)
            val actions = when {
                json.has("actions") -> json.optJSONArray("actions")
                json.has("result") -> json.optJSONArray("result")
                json.has("execution_result") -> json.optJSONArray("execution_result")
                else -> JSONArray()
            }

            if (actions == null || actions.length() == 0) {
                val summary = json.optString("summary", "No actions returned")
                return "Task response received" to summary
            }

            val summary = executePlanLocally(actions)
            if (summary != null) {
                notes.add("Step $step: executed=${summary.executed}, skipped=${summary.skipped}, failed=${summary.failed}")
                if (summary.notes.isNotBlank()) notes.add(summary.notes)
                if (summary.failed > 0) {
                    lastError = "Failed ${summary.failed} actions in step $step"
                }
            }

            for (i in 0 until actions.length()) {
                actionHistory.put(actions.opt(i))
            }

            val isDone = json.optBoolean("is_done", false) || (0 until actions.length()).any {
                actions.optJSONObject(it)?.optString("action") == "done"
            }

            if (isDone) {
                val status = if ((summary?.failed ?: 0) > 0) "Task partially completed" else "Task completed"
                return status to buildString {
                    append(notes.joinToString("\n"))
                    val doneSummary = actionsToSummary(actions)
                    if (doneSummary.isNotBlank()) {
                        append("\n\n")
                        append(doneSummary)
                    }
                }
            }

            step++
            Thread.sleep(500)
        }

        return "Task partially completed" to "Maximum steps reached before task completed.\n\n${notes.joinToString("\n")}"
    }

    private fun actionsToSummary(actions: JSONArray): String {
        for (i in 0 until actions.length()) {
            val action = actions.optJSONObject(i) ?: continue
            if (action.optString("action") == "done") {
                return action.optString("summary")
            }
        }
        return ""
    }

    private data class PlanExecutionSummary(
        val executed: Int,
        val skipped: Int,
        val failed: Int,
        val notes: String
    )

    private fun executePlanLocally(planArray: org.json.JSONArray?): PlanExecutionSummary? {
        if (planArray == null || planArray.length() == 0) return null

        var executed = 0
        var skipped = 0
        var failed = 0
        val notes = mutableListOf<String>()

        for (i in 0 until planArray.length()) {
            val rawStep = planArray.opt(i)
            val stepJson = when (rawStep) {
                is JSONObject -> rawStep
                is String -> {
                    val parsed = JSONObject()
                    parsed.put("action", rawStep)
                    parsed
                }
                else -> null
            }

            if (stepJson == null) {
                skipped++
                notes.add("Step ${i + 1}: unsupported step format")
                continue
            }

            val didRun = runCatching { executeSinglePlanStep(stepJson) }.getOrElse {
                failed++
                notes.add("Step ${i + 1}: failed (${it.message ?: "unknown error"})")
                false
            }

            if (didRun) {
                executed++
            } else {
                skipped++
                notes.add("Step ${i + 1}: no matching local action")
            }
        }

        return PlanExecutionSummary(
            executed = executed,
            skipped = skipped,
            failed = failed,
            notes = notes.joinToString("\n")
        )
    }

    private fun executeSinglePlanStep(step: JSONObject): Boolean {
        val actionRaw = when {
            step.has("action") -> step.optString("action")
            step.has("type") -> step.optString("type")
            step.has("tool") -> step.optString("tool")
            else -> ""
        }.lowercase().trim()

        val targetRaw = step.optString("target", "").lowercase().trim()
        val description = step.optString("description", "").lowercase().trim()
        val messageText = when {
            step.has("message") -> step.optString("message")
            step.has("text") -> step.optString("text")
            else -> ""
        }
        val contactName = when {
            step.has("contact") -> step.optString("contact")
            step.has("recipient") -> step.optString("recipient")
            step.has("name") -> step.optString("name")
            else -> ""
        }
        if (ScreenReaderService.executeStructuredAction(step)) {
            return true
        }

        val combinedText = listOf(actionRaw, targetRaw, description, messageText.lowercase(), contactName.lowercase())
            .joinToString(" ")

        return when {
            combinedText.contains("whatsapp") && combinedText.contains("message") -> {
                val (parsedContact, parsedMessage) = extractWhatsAppIntentFromStep(step)
                if (parsedContact.isBlank()) return false

                val finalMessage = if (parsedMessage.isBlank()) {
                    "Hey ${parsedContact}, this is an automated message."
                } else {
                    parsedMessage
                }

                ScreenReaderService.runWhatsAppMessageAutomation(parsedContact, finalMessage)
            }
            actionRaw.contains("scanner") || targetRaw.contains("scanner") || description.contains("scan") -> {
                if (!isScannerActive) {
                    handleScanner()
                }
                true
            }
            actionRaw.contains("keyboard") || targetRaw.contains("keyboard") || description.contains("keyboard") -> {
                handleKeyboard()
                true
            }
            actionRaw.contains("settings") || targetRaw.contains("settings") -> {
                handleSettings()
                true
            }
            actionRaw.contains("chat") || targetRaw.contains("chat") -> {
                showFloatingChatbot()
                true
            }
            actionRaw.contains("home") -> {
                val intent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                true
            }
            actionRaw.contains("open_app") || actionRaw.contains("launch") -> {
                val packageName = when {
                    step.has("package") -> step.optString("package")
                    step.has("packageName") -> step.optString("packageName")
                    else -> ""
                }
                if (packageName.isBlank()) return false

                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launchIntent)
                    true
                } else {
                    false
                }
            }
            else -> false
        }
    }

    private fun executeDirectVoiceCommand(command: String): Boolean {
        val normalized = command.trim().lowercase()
        if (normalized.isBlank()) return false

        if (normalized.contains("whatsapp") && normalized.contains("message")) {
            val contact = Regex("message\\s+([a-zA-Z0-9 _.-]+?)(?:\\s+that|\\s+saying|\\s+to\\s+say|$)")
                .find(normalized)
                ?.groupValues
                ?.getOrNull(1)
                ?.trim()
                .orEmpty()

            val message = Regex("(?:that|saying|to say)\\s+(.+)$", RegexOption.IGNORE_CASE)
                .find(command)
                ?.groupValues
                ?.getOrNull(1)
                ?.trim()
                .orEmpty()

            if (contact.isNotBlank()) {
                return ScreenReaderService.runWhatsAppMessageAutomation(
                    contactName = contact,
                    message = if (message.isBlank()) "Hey $contact" else message
                )
            }
        }

        if (normalized.contains("open whatsapp")) {
            val launchIntent = packageManager.getLaunchIntentForPackage("com.whatsapp") ?: return false
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(launchIntent)
            return true
        }

        // Fallback: ask accessibility automation layer to execute broader commands.
        return ScreenReaderService.runGenericAutomation(command)
    }

    private fun extractWhatsAppIntentFromStep(step: JSONObject): Pair<String, String> {
        val directContact = when {
            step.has("contact") -> step.optString("contact")
            step.has("recipient") -> step.optString("recipient")
            step.has("name") -> step.optString("name")
            else -> ""
        }.trim()

        val directMessage = when {
            step.has("message") -> step.optString("message")
            step.has("text") -> step.optString("text")
            else -> ""
        }.trim()

        if (directContact.isNotBlank()) {
            return directContact to directMessage
        }

        val source = listOf(
            step.optString("action", ""),
            step.optString("description", ""),
            step.optString("instruction", "")
        ).joinToString(" ").trim()

        val normalized = source.lowercase()
        val contact = Regex("message\\s+([a-zA-Z0-9 _.-]+?)(?:\\s+that|\\s+saying|\\s+to\\s+say|$)")
            .find(normalized)
            ?.groupValues
            ?.getOrNull(1)
            ?.trim()
            ?: ""

        val message = Regex("(?:that|saying|to say)\\s+(.+)$", RegexOption.IGNORE_CASE)
            .find(source)
            ?.groupValues
            ?.getOrNull(1)
            ?.trim()
            ?: ""

        return contact to message
    }

    private fun hideFloatingChatbot() {
        if (!isChatbotVisible) return
        floatingChatView?.let { view ->
            windowManager.removeView(view)
            floatingChatView = null
            floatingChatParams = null
            isChatbotVisible = false
        }
    }

    private fun handleScanner() {
        isScannerActive = !isScannerActive
        updateMenuItemsColor()
        
        if (isScannerActive) {
            val intent = Intent(this, ScreenReaderService::class.java)
            intent.action = ScreenReaderService.ACTION_START_SCAN
            startService(intent)
            Toast.makeText(this, "Screen Detection Enabled", Toast.LENGTH_SHORT).show()
        } else {
            val intent = Intent(this, ScreenReaderService::class.java)
            intent.action = ScreenReaderService.ACTION_STOP_SCAN
            startService(intent)
            Toast.makeText(this, "Screen Detection Disabled", Toast.LENGTH_SHORT).show()
        }
    }
    
    private fun invokeFlutterMethod(methodName: String) {
        try {
            val intent = Intent(ACTION_SCANNER_START).apply {
                setPackage(packageName)
                putExtra("method", methodName)
            }
            sendBroadcast(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun handleKeyboard() {
        toggleFeature(menuItems[4].id)

        if (isFeatureActive(menuItems[4].id)) {
            try {
                val intent = Intent(android.provider.Settings.ACTION_INPUT_METHOD_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                Toast.makeText(this, "Open Settings to enable AI Keyboard", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                try {
                    inputMethodManager.showInputMethodPicker()
                    Toast.makeText(this, "Select AI Keyboard from the list", Toast.LENGTH_SHORT).show()
                } catch (ex: Exception) {
                    Toast.makeText(this, "AI Keyboard feature enabled", Toast.LENGTH_SHORT).show()
                }
            }
        } else {
            Toast.makeText(this, "AI Keyboard Disabled", Toast.LENGTH_SHORT).show()
        }
    }

    private fun handleSettings() {
        openMainApp()
        Toast.makeText(this, "Opening Stremini...", Toast.LENGTH_SHORT).show()
    }

    private fun handleAutoTasker() {
        toggleFeature(menuItems[0].id)
        if (isFeatureActive(menuItems[0].id)) {
            val opened = showAutoTasker()
            if (!opened) {
                activeFeatures.remove(menuItems[0].id)
                updateMenuItemsColor()
            }
        } else {
            hideAutoTasker()
        }
    }

    private fun toggleFeature(featureId: Int) {
        if (activeFeatures.contains(featureId)) {
            activeFeatures.remove(featureId)
        } else {
            activeFeatures.add(featureId)
        }
        updateMenuItemsColor()
    }

    private fun isFeatureActive(featureId: Int): Boolean {
        return activeFeatures.contains(featureId)
    }

    private fun updateMenuItemsColor() {
        menuItems.forEach { item ->
            if (activeFeatures.contains(item.id) ||
                (item.id == menuItems[3].id && isScannerActive)) {
                // Active: Neon blue FILL (no border) with semi-transparency for glow effect
                val layers = arrayOf(
                    // Layer 1: Black circle background
                    android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.OVAL
                        setColor(android.graphics.Color.BLACK)
                    },
                    // Layer 2: Neon blue fill overlay (no border)
                    android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.OVAL
                        setColor(android.graphics.Color.parseColor("#23A6E2"))  // Neon blue FILL
                        alpha = 200  // Semi-transparent for glow effect (0-255)
                    }
                )
                item.background = android.graphics.drawable.LayerDrawable(layers)
                item.setColorFilter(WHITE)  // White icon
            } else {
                // Inactive: Black background with NO border
                val drawable = android.graphics.drawable.GradientDrawable()
                drawable.shape = android.graphics.drawable.GradientDrawable.OVAL
                drawable.setColor(android.graphics.Color.BLACK)  // Black background only
                item.background = drawable
                item.setColorFilter(WHITE)  // White icon
            }
        }
    }

    override fun onTouch(v: View, event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                initialTouchX = event.rawX
                initialTouchY = event.rawY
                initialX = bubbleScreenX
                initialY = bubbleScreenY
                isDragging = false
                hasMoved = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                // FIXED: Prevent position updates during resize animation
                if (isWindowResizing || preventPositionUpdates) return true

                val dx = (event.rawX - initialTouchX).toInt()
                val dy = (event.rawY - initialTouchY).toInt()
                
                if (abs(dx) > 10 || abs(dy) > 10) {
                    hasMoved = true
                    if (!isMenuExpanded) {
                        isDragging = true

                        bubbleScreenX = initialX + dx
                        bubbleScreenY = initialY + dy

                        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
                        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)
                        val windowHalfSize = collapsedWindowSizePx / 2

                        params.x = (bubbleScreenX - windowHalfSize).toInt()
                        params.y = (bubbleScreenY - windowHalfSize).toInt()
                        
                        try {
                            windowManager.updateViewLayout(overlayView, params)
                        } catch (e: Exception) {
                            // Ignore
                        }
                    } else {
                        if (!isMenuAnimating) collapseMenu()
                    }
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                // FIXED: Ignore tap/release while resizing
                if (isWindowResizing || preventPositionUpdates) {
                    isDragging = false
                    hasMoved = false
                    return true
                }

                if (!hasMoved && !isDragging) {
                    if (!isMenuAnimating) toggleMenu()
                } else if (isDragging) {
                    // FIXED: Wait for resize to complete before snapping
                    if (isWindowResizing || preventPositionUpdates) {
                        overlayView.postDelayed({ snapToEdge() }, 200)
                    } else {
                        snapToEdge()
                    }
                }
                isDragging = false
                hasMoved = false
                return true
            }
        }
        return false
    }

    private fun toggleMenu() {
        if (isMenuAnimating) return
        if (isMenuExpanded) collapseMenu() else expandMenu()
    }

    private fun expandMenu() {
        if (isMenuAnimating || isMenuExpanded) return
        isMenuExpanded = true
        isMenuAnimating = true

        val radiusPx = dpToPx(radiusDp).toFloat()
        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
        val menuItemSizePx = dpToPx(menuItemSizeDp).toFloat()

        val expandedWindowSizePx = (radiusPx * 2) + bubbleSizePx + dpToPx(20f)
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)

        // FIXED: Animate window resizing with proper lock
        animateWindowSize(collapsedWindowSizePx.toFloat(), expandedWindowSizePx, 220L) {
            isMenuAnimating = false
        }

        val centerX = expandedWindowSizePx / 2f
        val centerY = expandedWindowSizePx / 2f

        val screenWidth = resources.displayMetrics.widthPixels
        val isOnRightSide = bubbleScreenX > (screenWidth / 2)

        val fixedAngles = if (isOnRightSide) {
            listOf(90.0, 135.0, 180.0, 225.0, 270.0)
        } else {
            listOf(90.0, 45.0, 0.0, -45.0, -90.0)
        }

        overlayView.postDelayed({
            for ((index, view) in menuItems.withIndex()) {
                view.visibility = View.VISIBLE
                view.alpha = 0f
                view.translationX = 0f
                view.translationY = 0f

                val angle = fixedAngles[index]
                val rad = Math.toRadians(angle)

                val targetX = centerX + (radiusPx * cos(rad)).toFloat() - (menuItemSizePx / 2)
                val targetY = centerY + (radiusPx * -sin(rad)).toFloat() - (menuItemSizePx / 2)

                val initialCenteredX = centerX - (menuItemSizePx / 2)
                val initialCenteredY = centerY - (menuItemSizePx / 2)

                view.animate()
                    .translationX(targetX - initialCenteredX)
                    .translationY(targetY - initialCenteredY)
                    .alpha(1f)
                    .setDuration(220)
                    .setInterpolator(DecelerateInterpolator())
                    .start()
            }
            updateMenuItemsColor()
        }, 160)
    }

    private fun collapseMenu() {
        if (isMenuAnimating || !isMenuExpanded) return
        isMenuExpanded = false
        isMenuAnimating = true

        val radiusPx = dpToPx(radiusDp).toFloat()
        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
        val expandedWindowSizePx = (radiusPx * 2) + bubbleSizePx + dpToPx(20f)
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)

        for (view in menuItems) {
            view.animate()
                .translationX(0f)
                .translationY(0f)
                .alpha(0f)
                .setDuration(150)
                .setInterpolator(AccelerateInterpolator())
                .withEndAction { view.visibility = View.INVISIBLE }
                .start()
        }

        // FIXED: Improved timing for smoother collapse
        overlayView.postDelayed({
            animateWindowSize(expandedWindowSizePx, collapsedWindowSizePx.toFloat(), 200L) {
                isMenuAnimating = false
            }
        }, 120)
    }

    private fun animateWindowSize(fromSize: Float, toSize: Float, duration: Long = 200L, onEnd: (() -> Unit)? = null) {
        windowAnimator?.cancel()
        isWindowResizing = true
        preventPositionUpdates = true  // FIXED: Lock position updates during resize

        val fromHalf = fromSize / 2f
        val toHalf = toSize / 2f
        val startX = bubbleScreenX - fromHalf
        val endX = bubbleScreenX - toHalf
        val startY = bubbleScreenY - fromHalf
        val endY = bubbleScreenY - toHalf

        windowAnimator = ValueAnimator.ofFloat(fromSize, toSize).apply {
            this.duration = duration
            interpolator = DecelerateInterpolator()
            
            addUpdateListener { animator ->
                val newSize = animator.animatedValue as Float
                val frac = if (toSize != fromSize) (newSize - fromSize) / (toSize - fromSize) else 1f
                
                params.width = newSize.toInt()
                params.height = newSize.toInt()
                params.x = (startX + (endX - startX) * frac).toInt()
                params.y = (startY + (endY - startY) * frac).toInt()

                try {
                    windowManager.updateViewLayout(overlayView, params)
                } catch (e: Exception) {
                    // Ignore if view detached
                }
            }
            
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    windowAnimator = null
                    isWindowResizing = false
                    preventPositionUpdates = false  // FIXED: Unlock position updates

                    // Ensure final position is set
                    params.width = toSize.toInt()
                    params.height = toSize.toInt()
                    params.x = (bubbleScreenX - toHalf).toInt()
                    params.y = (bubbleScreenY - toHalf).toInt()
                    
                    try {
                        windowManager.updateViewLayout(overlayView, params)
                    } catch (e: Exception) {
                        // Ignore
                    }

                    onEnd?.invoke()
                }
            })
            start()
        }
    }

    private fun snapToEdge() {
        // FIXED: Wait for all animations to complete
        if (isWindowResizing || preventPositionUpdates || isMenuAnimating) {
            overlayView.postDelayed({ snapToEdge() }, 150)
            return
        }

        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
        val screenWidth = resources.displayMetrics.widthPixels
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)
        val windowHalfSize = collapsedWindowSizePx / 2

        val targetBubbleScreenX = if (bubbleScreenX > (screenWidth / 2)) {
            screenWidth - (bubbleSizePx / 2).toInt()
        } else {
            (bubbleSizePx / 2).toInt()
        }

        ValueAnimator.ofInt(bubbleScreenX, targetBubbleScreenX).apply {
            duration = 200  // FIXED: Slightly longer for smoother snap
            interpolator = DecelerateInterpolator()
            
            addUpdateListener { animator ->
                bubbleScreenX = animator.animatedValue as Int
                params.x = (bubbleScreenX - windowHalfSize).toInt()
                
                try {
                    windowManager.updateViewLayout(overlayView, params)
                } catch (e: Exception) {
                    // Ignore
                }
            }
            start()
        }
    }

    private fun openMainApp() {
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP)
        startActivity(intent)
    }

    private fun startForegroundService() {
        val channelId = "chat_head_service"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Stremini Overlay", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Stremini AI")
            .setContentText("Active - Tap to open")
            .setSmallIcon(R.mipmap.ic_launcher)
            .build()
        startForeground(1, notification)
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        unregisterReceiver(controlReceiver)
        hideFloatingChatbot()
        hideAutoTasker()
        if (::overlayView.isInitialized && overlayView.windowToken != null) windowManager.removeView(overlayView)
    }
} 
