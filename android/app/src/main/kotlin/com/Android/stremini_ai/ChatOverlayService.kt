package com.Android.stremini_ai

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import org.json.JSONArray
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

class ChatOverlayService : Service(), View.OnTouchListener {

    companion object {
        const val ACTION_SEND_MESSAGE = "com.Android.stremini_ai.SEND_MESSAGE"
        const val EXTRA_MESSAGE = "message"
        const val ACTION_SCANNER_START = "com.Android.stremini_ai.SCANNER_START"
        const val ACTION_SCANNER_STOP = "com.Android.stremini_ai.SCANNER_STOP"
        const val ACTION_TOGGLE_BUBBLE = "com.Android.stremini_ai.TOGGLE_BUBBLE"
        const val ACTION_STOP_SERVICE = "com.Android.stremini_ai.STOP_SERVICE"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "chat_head_service"
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
    private var isBubbleVisible = true
    private lateinit var inputMethodManager: InputMethodManager

    private var autoTaskerView: View? = null
    private var autoTaskerParams: WindowManager.LayoutParams? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var isAutoTaskerVisible = false
    private var keepListeningLoop = false

    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false
    private var hasMoved = false

    private val bubbleSizeDp = 60f
    private val menuItemSizeDp = 50f
    private val radiusDp = 80f

    private var bubbleScreenX = 0
    private var bubbleScreenY = 0

    private var isMenuAnimating = false
    private var windowAnimator: ValueAnimator? = null
    private var isWindowResizing = false
    private var preventPositionUpdates = false

    // Idle shrink/fade state
    private var idleRunnable: Runnable? = null
    private val idleHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var isBubbleIdle = false
    private var idleAnimator: ValueAnimator? = null
    private var preIdleX = 0
    private val IDLE_TIMEOUT_MS = 3000L
    private val IDLE_SCALE = 0.6f
    private val IDLE_ALPHA = 0.4f
    private val IDLE_ANIM_DURATION = 400L


    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())


    private val client = OkHttpClient.Builder()
        .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
        .build()

    private val aiBackendClient = AIBackendClient()
    private val deviceCommandRouter = DeviceCommandRouter()
    private lateinit var chatCommandCoordinator: ChatCommandCoordinator
    private lateinit var bubbleController: BubbleController
    private lateinit var floatingChatController: FloatingChatController
    private lateinit var voiceController: VoiceController
    private lateinit var idleAnimationController: IdleAnimationController

    private val controlReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_SEND_MESSAGE -> {
                    val message = intent.getStringExtra(EXTRA_MESSAGE)
                    if (message != null) addMessageToChatbot(message, isUser = false)
                }
                ACTION_SCANNER_START -> {
                    isScannerActive = true; updateMenuItemsColor()
                    Toast.makeText(context, "Screen Detection Started", Toast.LENGTH_SHORT).show()
                }
                ACTION_SCANNER_STOP -> {
                    isScannerActive = false; updateMenuItemsColor()
                    Toast.makeText(context, "Screen Detection Stopped", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun dpToPx(dp: Float): Int = (dp * resources.displayMetrics.density).toInt()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        inputMethodManager = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        startForegroundService()

        bubbleController = BubbleController(::hideBubble, ::showBubble).apply { setVisible(isBubbleVisible) }
        floatingChatController = FloatingChatController(::showFloatingChatbot, ::hideFloatingChatbot)
        voiceController = VoiceController(
            context = this,
            onFinalText = { spokenText -> executeVoiceCommand(spokenText) },
            onError = { if (keepListeningLoop) serviceScope.launch { delay(450); startVoiceCapture() } }
        )
        idleAnimationController = IdleAnimationController(
            onIdle = { if (!isMenuExpanded && !isDragging && !isMenuAnimating) shrinkBubble() },
            onWake = { restoreBubble() }
        )
        chatCommandCoordinator = ChatCommandCoordinator(
            scope = serviceScope,
            backendClient = aiBackendClient,
            deviceCommandRouter = deviceCommandRouter,
            onBotMessage = { message -> addMessageToChatbot(message, isUser = false) }
        )

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

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE_BUBBLE -> bubbleController.toggle()
            ACTION_STOP_SERVICE -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun hideBubble() {
        if (!isBubbleVisible) return
        // Collapse menu first if expanded
        if (isMenuExpanded) collapseMenu()
        // Cancel idle timer
        idleAnimationController.cancel()
        idleRunnable?.let { idleHandler.removeCallbacks(it) }
        overlayView.visibility = View.GONE
        isBubbleVisible = false
        bubbleController.setVisible(false)
        updateNotification()
    }

    private fun showBubble() {
        if (isBubbleVisible) return
        overlayView.visibility = View.VISIBLE
        // Restore to full state
        bubbleIcon.scaleX = 1f
        bubbleIcon.scaleY = 1f
        bubbleIcon.alpha = 1f
        isBubbleIdle = false
        isBubbleVisible = true
        bubbleController.setVisible(true)
        updateNotification()
        resetIdleTimer()
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

        val typeParam = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val radiusPx = dpToPx(radiusDp).toFloat()
        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
        val expandedWindowSizePx = ((radiusPx * 2) + bubbleSizePx + dpToPx(20f)).toInt()
        val collapsedWindowSizePx = (bubbleSizePx + dpToPx(10f)).toInt()

        params = WindowManager.LayoutParams(
            collapsedWindowSizePx, collapsedWindowSizePx, typeParam,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START

        val screenHeight = resources.displayMetrics.heightPixels
        bubbleScreenX = 60
        bubbleScreenY = (screenHeight * 0.25).toInt()

        val windowHalfSize = collapsedWindowSizePx / 2
        params.x = bubbleScreenX - windowHalfSize
        params.y = bubbleScreenY - windowHalfSize

        bubbleIcon.setOnTouchListener(this)
        bubbleIcon.setOnLongClickListener {
            openKeyboardSwitcher()
            true
        }

        menuItems[0].setOnClickListener { collapseMenu(); handleAutoTasker() }
        menuItems[1].setOnClickListener { collapseMenu(); handleSettings() }
        menuItems[2].setOnClickListener { collapseMenu(); handleAIChat() }
        menuItems[3].setOnClickListener { collapseMenu(); handleScanner() }
        menuItems[4].setOnClickListener { collapseMenu(); handleKeyboard() }

        bubbleIcon.setLayerType(View.LAYER_TYPE_HARDWARE, null)
        bubbleIcon.isClickable = true; bubbleIcon.isFocusable = true

        menuItems.forEach {
            it.setLayerType(View.LAYER_TYPE_HARDWARE, null)
            it.isClickable = true; it.isFocusable = true
            it.visibility = View.INVISIBLE
        }

        updateMenuItemsColor()
        overlayView.background = null
        overlayView.isClickable = false; overlayView.isFocusable = false
        overlayView.setOnTouchListener { _, _ -> false }
        windowManager.addView(overlayView, params)

        (overlayView as? android.view.ViewGroup)?.apply {
            clipToPadding = false; clipChildren = false
            isMotionEventSplittingEnabled = false
        }
        overlayView.layoutParams = overlayView.layoutParams?.apply {
            width = params.width; height = params.height
        }
        overlayView.requestLayout()

        // Start idle timer after setup
        resetIdleTimer()
    }

    // ==========================================
    // BUBBLE IDLE SHRINK / FADE
    // ==========================================

    private fun resetIdleTimer() {
        idleAnimationController.resetTimer()
    }

    private fun shrinkBubble() {
        if (isBubbleIdle) return
        isBubbleIdle = true

        // Animate the icon scale and alpha
        bubbleIcon.animate()
            .scaleX(IDLE_SCALE)
            .scaleY(IDLE_SCALE)
            .alpha(IDLE_ALPHA)
            .setDuration(IDLE_ANIM_DURATION)
            .setInterpolator(DecelerateInterpolator())
            .start()

        // Animate the window position to partially hide off the screen edge
        preIdleX = bubbleScreenX
        val screenWidth = resources.displayMetrics.widthPixels
        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)
        val windowHalfSize = collapsedWindowSizePx / 2

        // Determine if it's closer to the left or right edge
        val targetX = if (bubbleScreenX > screenWidth / 2) {
            // Right edge: hide part of the shrunken bubble (adjust 0.4f to control how much is hidden)
            screenWidth - (bubbleSizePx / 2).toInt() + (bubbleSizePx * 0.4f).toInt()
        } else {
            // Left edge: hide part of the shrunken bubble
            (bubbleSizePx / 2).toInt() - (bubbleSizePx * 0.4f).toInt()
        }
        
        idleAnimator?.cancel()
        idleAnimator = ValueAnimator.ofInt(bubbleScreenX, targetX).apply {
            duration = IDLE_ANIM_DURATION
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                if (isDragging || isMenuExpanded || isMenuAnimating) {
                    cancel()
                    return@addUpdateListener
                }
                bubbleScreenX = animator.animatedValue as Int
                params.x = (bubbleScreenX - windowHalfSize).toInt()
                try { windowManager.updateViewLayout(overlayView, params) } catch (e: Exception) {}
            }
            start()
        }
    }

    private fun restoreBubble() {
        if (!isBubbleIdle) return
        isBubbleIdle = false
        
        // Restore scale and alpha
        bubbleIcon.animate()
            .scaleX(1f)
            .scaleY(1f)
            .alpha(1f)
            .setDuration(200L)
            .setInterpolator(DecelerateInterpolator())
            .start()

        // Restore window position
        idleAnimator?.cancel()
        
        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
        val screenWidth = resources.displayMetrics.widthPixels
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)
        val windowHalfSize = collapsedWindowSizePx / 2

        // Calculate normal resting edge
        val targetX = if (preIdleX > screenWidth / 2) {
            screenWidth - (bubbleSizePx / 2).toInt()
        } else {
            (bubbleSizePx / 2).toInt()
        }

        idleAnimator = ValueAnimator.ofInt(bubbleScreenX, targetX).apply {
            duration = 200L
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                if (isDragging) {
                    cancel()
                    return@addUpdateListener
                }
                bubbleScreenX = animator.animatedValue as Int
                params.x = (bubbleScreenX - windowHalfSize).toInt()
                try { windowManager.updateViewLayout(overlayView, params) } catch (e: Exception) {}
            }
            start()
        }
    }

    // ==========================================
    // CHATBOT
    // ==========================================

    private fun handleAIChat() {
        toggleFeature(menuItems[2].id)
        if (isFeatureActive(menuItems[2].id)) floatingChatController.show()
        else floatingChatController.hide()
    }

    private fun showFloatingChatbot() {
        if (isChatbotVisible) return
        floatingChatView = LayoutInflater.from(this).inflate(R.layout.floating_chatbot_layout, null)

        val typeParam = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        floatingChatParams = WindowManager.LayoutParams(
            dpToPx(300f), dpToPx(400f), typeParam,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        )
        floatingChatParams?.gravity = Gravity.BOTTOM or Gravity.END
        floatingChatParams?.x = dpToPx(20f); floatingChatParams?.y = dpToPx(100f)
        floatingChatView?.setLayerType(View.LAYER_TYPE_HARDWARE, null)
        setupFloatingChatListeners()
        windowManager.addView(floatingChatView, floatingChatParams)
        isChatbotVisible = true
        addMessageToChatbot("Hello! I'm Stremini AI.", isUser = false)
    }

    private fun setupFloatingChatListeners() {
        floatingChatView?.let { view ->
            val header = view.findViewById<LinearLayout>(R.id.chat_header)
            var chatInitialX = 0; var chatInitialY = 0
            var chatInitialTouchX = 0f; var chatInitialTouchY = 0f
            var chatIsDragging = false

            header?.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        chatInitialTouchX = event.rawX; chatInitialTouchY = event.rawY
                        chatInitialX = floatingChatParams?.x ?: 0; chatInitialY = floatingChatParams?.y ?: 0
                        chatIsDragging = true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (chatIsDragging && floatingChatParams != null) {
                            floatingChatParams?.x = chatInitialX - (event.rawX - chatInitialTouchX).toInt()
                            floatingChatParams?.y = chatInitialY - (event.rawY - chatInitialTouchY).toInt()
                            windowManager.updateViewLayout(floatingChatView!!, floatingChatParams!!)
                        }
                    }
                    MotionEvent.ACTION_UP -> { chatIsDragging = false }
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
                    processUserCommand(message)
                }
            }

            view.findViewById<ImageView>(R.id.btn_voice_input)?.setOnClickListener {
                Toast.makeText(this, "Voice input coming soon", Toast.LENGTH_SHORT).show()
            }
        }
    }

    /**
     * Smart command processor - routes through chat coordinator
     */
    private fun processUserCommand(userMessage: String) {
        chatCommandCoordinator.processUserMessage(userMessage)
    }


    private fun addMessageToChatbot(message: String, isUser: Boolean) {
        floatingChatView?.let { view ->
            val messagesContainer = view.findViewById<LinearLayout>(R.id.messages_container)
            val messageView = LayoutInflater.from(this).inflate(
                if (isUser) R.layout.message_bubble_user else R.layout.message_bubble_bot,
                messagesContainer, false
            )
            messageView.findViewById<TextView>(R.id.tv_message)?.text = message
            messagesContainer?.addView(messageView)
            view.findViewById<ScrollView>(R.id.scroll_messages)?.post {
                view.findViewById<ScrollView>(R.id.scroll_messages)?.fullScroll(View.FOCUS_DOWN)
            }
        }
    }

    private fun hideFloatingChatbot() {
        if (!isChatbotVisible) return
        floatingChatView?.let { windowManager.removeView(it) }
        floatingChatView = null; floatingChatParams = null; isChatbotVisible = false
        floatingChatController.setVisible(false)
    }

    // ==========================================
    // AUTO TASKER (Voice Command)
    // ==========================================

    private fun showAutoTasker(): Boolean {
        if (isAutoTaskerVisible) return true
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Toast.makeText(this, "Microphone permission required. Opening settings...", Toast.LENGTH_LONG).show()
            try {
                startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
            } catch (_: Exception) {}
            return false
        }

        autoTaskerView = LayoutInflater.from(this).inflate(R.layout.auto_tasker_overlay, null)
        val typeParam = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        autoTaskerParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, typeParam,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.CENTER }

        autoTaskerView?.findViewById<ImageView>(R.id.btn_close_tasker)?.setOnClickListener {
            hideAutoTasker()
            activeFeatures.remove(menuItems[0].id)
            updateMenuItemsColor()
        }
        autoTaskerView?.findViewById<ImageView>(R.id.btn_start_listening)?.setOnClickListener {
            keepListeningLoop = true
            startVoiceCapture()
        }

        windowManager.addView(autoTaskerView, autoTaskerParams)
        isAutoTaskerVisible = true
        keepListeningLoop = false
        return true
    }

    private fun hideAutoTasker() {
        keepListeningLoop = false
        voiceController.stop()
        speechRecognizer?.destroy(); speechRecognizer = null
        autoTaskerView?.let { windowManager.removeView(it) }
        autoTaskerView = null; autoTaskerParams = null; isAutoTaskerVisible = false
    }

    private fun startVoiceCapture() {
        val view = autoTaskerView ?: return
        val status = view.findViewById<TextView>(R.id.tv_tasker_status)
        status.text = "Listening..."
        voiceController.stop()
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
                override fun onError(error: Int) {
                    status.text = "Voice capture failed ($error). Retrying..."
                    if (keepListeningLoop && isAutoTaskerVisible) {
                        serviceScope.launch { delay(700); startVoiceCapture() }
                    }
                }
                override fun onEvent(eventType: Int, params: android.os.Bundle?) {}
                override fun onPartialResults(partialResults: android.os.Bundle?) {}
                override fun onResults(results: android.os.Bundle?) {
                    val command = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim()
                    if (command.isNullOrBlank()) {
                        status.text = "Could not understand. Try again."
                        if (keepListeningLoop && isAutoTaskerVisible) {
                            serviceScope.launch { delay(500); startVoiceCapture() }
                        }
                    } else {
                        status.text = "Understood: $command"
                        view.findViewById<TextView>(R.id.tv_tasker_output).text = "🎙 Command: $command\n\n⚙️ Executing..."
                        executeVoiceCommand(command)
                    }
                }
            })
        }

        speechRecognizer?.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        })
    }

    /**
     * Main voice command execution - routes to device control then AI fallback
     */
    private fun executeVoiceCommand(command: String) {
        serviceScope.launch {
            val view = autoTaskerView ?: return@launch
            val statusView = view.findViewById<TextView>(R.id.tv_tasker_status)
            val outputView = view.findViewById<TextView>(R.id.tv_tasker_output)

            // 1. Try direct device automation first
            val directResult = withContext(Dispatchers.IO) {
                tryDirectDeviceCommand(command)
            }

            if (directResult.executed) {
                statusView.text = "✅ ${directResult.statusMessage}"
                outputView.text = "🎙 Command: $command\n\n✅ ${directResult.details}"
                return@launch
            }

            // 2. Try AI backend for smart plan generation + execution
            statusView.text = "🤖 Sending to AI..."
            outputView.text = "🎙 Command: $command\n\n🤖 Asking AI for execution plan..."

            try {
                val (aiStatus, aiOutput) = withContext(Dispatchers.IO) {
                    sendVoiceTaskCommandToAI(command)
                }
                statusView.text = aiStatus
                outputView.text = "🎙 Command: $command\n\n$aiOutput"
            } catch (e: Exception) {
                statusView.text = "❌ Failed"
                outputView.text = "🎙 Command: $command\n\n❌ Error: ${e.message}"
            }

            if (keepListeningLoop && isAutoTaskerVisible) {
                delay(650)
                startVoiceCapture()
            }
        }
    }

    data class DirectCommandResult(
        val executed: Boolean,
        val statusMessage: String,
        val details: String
    )

    private suspend fun tryDirectDeviceCommand(command: String): DirectCommandResult {
        val normalized = command.trim().lowercase()

        return when {
            // WhatsApp messaging
            normalized.contains("whatsapp") && (normalized.contains("message") || normalized.contains("send")) -> {
                val contact = extractContact(command)
                val message = extractMessage(command)
                if (contact.isNotBlank()) {
                    val sent = ScreenReaderService.runWhatsAppMessageAutomation(contact, message)
                    delay(3000) // Wait for automation
                    DirectCommandResult(true, "WhatsApp message sent to $contact", "Sent '$message' to $contact via WhatsApp")
                } else {
                    DirectCommandResult(false, "Contact not found", "Could not extract contact name from: $command")
                }
            }

            // Open any app
            normalized.startsWith("open ") || normalized.startsWith("launch ") -> {
                val appName = normalized.removePrefix("open ").removePrefix("launch ").trim()
                val service = ScreenReaderService.getInstance()
                val opened = service?.openAppByName(appName) ?: false
                if (opened) {
                    DirectCommandResult(true, "Opened $appName", "App '$appName' launched successfully")
                } else {
                    DirectCommandResult(false, "App not found", "Could not find app: $appName")
                }
            }

            // Navigation
            normalized.contains("go home") || normalized == "home" -> {
                ScreenReaderService.runGenericAutomation("go home")
                DirectCommandResult(true, "Navigated home", "Pressed home button")
            }
            normalized.contains("go back") || normalized == "back" -> {
                ScreenReaderService.runGenericAutomation("go back")
                DirectCommandResult(true, "Navigated back", "Pressed back button")
            }
            normalized.contains("recent apps") -> {
                ScreenReaderService.runGenericAutomation("recent apps")
                DirectCommandResult(true, "Opened recent apps", "Showed app switcher")
            }
            normalized.contains("take screenshot") -> {
                ScreenReaderService.runGenericAutomation("take screenshot")
                DirectCommandResult(true, "Screenshot taken", "Screen captured")
            }
            normalized.contains("scroll down") -> {
                ScreenReaderService.runGenericAutomation("scroll down")
                DirectCommandResult(true, "Scrolled down", "Page scrolled down")
            }
            normalized.contains("scroll up") -> {
                ScreenReaderService.runGenericAutomation("scroll up")
                DirectCommandResult(true, "Scrolled up", "Page scrolled up")
            }
            normalized.startsWith("swipe ") -> {
                val dir = normalized.removePrefix("swipe ").trim()
                ScreenReaderService.runGenericAutomation("swipe $dir")
                DirectCommandResult(true, "Swiped $dir", "Gesture performed: swipe $dir")
            }
            normalized.startsWith("tap ") || normalized.startsWith("click ") -> {
                ScreenReaderService.runGenericAutomation(command)
                delay(500)
                DirectCommandResult(true, "Tapped element", "Tapped: ${normalized.removePrefix("tap ").removePrefix("click ")}")
            }
            normalized.startsWith("type ") -> {
                ScreenReaderService.runGenericAutomation(command)
                DirectCommandResult(true, "Text typed", "Typed: ${normalized.removePrefix("type ")}")
            }
            normalized.startsWith("search for ") || normalized.startsWith("search ") -> {
                ScreenReaderService.runGenericAutomation(command)
                delay(500)
                DirectCommandResult(true, "Search performed", "Searched for: ${normalized.removePrefix("search for ").removePrefix("search ")}")
            }
            normalized.contains("volume up") -> {
                ScreenReaderService.runGenericAutomation("volume up")
                DirectCommandResult(true, "Volume increased", "Volume turned up")
            }
            normalized.contains("volume down") -> {
                ScreenReaderService.runGenericAutomation("volume down")
                DirectCommandResult(true, "Volume decreased", "Volume turned down")
            }
            normalized.contains("mute") -> {
                ScreenReaderService.runGenericAutomation("mute")
                DirectCommandResult(true, "Device muted", "Ringer set to silent")
            }
            normalized.startsWith("call ") -> {
                ScreenReaderService.runGenericAutomation(command)
                DirectCommandResult(true, "Calling...", "Initiating call to ${normalized.removePrefix("call ").trim()}")
            }
            normalized.startsWith("go to ") || normalized.startsWith("open website") || normalized.startsWith("browse to ") -> {
                ScreenReaderService.runGenericAutomation(command)
                DirectCommandResult(true, "Opening website", "Loading ${command.substringAfterLast(" ")}")
            }
            normalized.contains("open settings") || normalized.contains("wifi") ||
            normalized.contains("bluetooth") || normalized.contains("display settings") -> {
                ScreenReaderService.runGenericAutomation(command)
                DirectCommandResult(true, "Opened settings", "Settings opened")
            }
            normalized.contains("lock") -> {
                ScreenReaderService.runGenericAutomation("lock screen")
                DirectCommandResult(true, "Screen locked", "Device locked")
            }

            else -> DirectCommandResult(false, "Not a device command", "Sending to AI backend...")
        }
    }

    private fun extractContact(command: String): String {
        val patterns = listOf(
            Regex("(?:message|send|whatsapp)\\s+(?:to\\s+)?([a-zA-Z][a-zA-Z0-9 _.-]{1,30})(?:\\s+(?:that|saying|:|-|,)|\\s*\$)", RegexOption.IGNORE_CASE),
            Regex("to\\s+([a-zA-Z][a-zA-Z0-9 _.-]{1,30})(?:\\s+(?:that|saying)|\\s*\$)", RegexOption.IGNORE_CASE)
        )
        for (pattern in patterns) {
            val match = pattern.find(command)
            if (match != null) return match.groupValues[1].trim()
        }
        return ""
    }

    private fun extractMessage(command: String): String {
        val patterns = listOf(
            Regex("(?:that|saying|message:|with message)\\s+(.+)\$", RegexOption.IGNORE_CASE),
            Regex(":\\s*(.+)\$"),
            Regex("-\\s*(.+)\$")
        )
        for (pattern in patterns) {
            val match = pattern.find(command)
            if (match != null) return match.groupValues[1].trim()
        }
        return "Hello"
    }

    private suspend fun sendVoiceTaskCommandToAI(command: String): Pair<String, String> {
        val service = ScreenReaderService.getInstance()
        if (service == null) {
            return "❌ Accessibility service unavailable" to "Enable Stremini Screen Reader in Accessibility settings."
        }

        val maxAgentSteps = 8
        var payload = JSONObject().apply {
            put("query", command)
            put("command", command)
            put("step_index", 0)
            put("screen_state", service.getVisibleScreenState())
        }

        repeat(maxAgentSteps) { index ->
            val request = Request.Builder()
                .url("https://ai-keyboard-backend.vishwajeetadkine705.workers.dev/classify-task")
                .post(payload.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                return "❌ Server error ${response.code}" to "Failed to classify task."
            }

            val raw = response.body?.string().orEmpty()
            val json = runCatching { JSONObject(raw) }.getOrElse {
                return "❌ Invalid backend response" to raw
            }

            val steps = json.optJSONArray("steps")
            if (steps != null && steps.length() > 0) {
                val result = service.executeBackendSteps(steps)
                val status = if (result.success) "✅ Task completed" else "⚠️ Task partially completed"
                val output = buildString {
                    appendLine("Task: ${json.optString("task", "unknown")}")
                    appendLine("✅ Executed: ${result.completedSteps}")
                    appendLine("❌ Failed: ${result.failedSteps}")
                    appendLine()
                    append(result.message)
                }
                return status to output
            }

            val nextStep = json.optJSONObject("next_step") ?: json.optJSONObject("action")
            if (nextStep != null) {
                val oneStep = org.json.JSONArray().put(nextStep)
                val result = service.executeBackendSteps(oneStep)
                if (!result.success) {
                    return "❌ Step failed" to result.message
                }
            }

            val done = json.optBoolean("done") || json.optBoolean("completed")
            if (done) {
                val summary = json.optString("summary", "Agentic loop completed")
                return "✅ Task completed" to summary
            }

            payload = JSONObject().apply {
                put("query", command)
                put("command", command)
                put("step_index", index + 1)
                put("screen_state", service.getVisibleScreenState())
                put("previous_response", json)
            }
        }

        return "⚠️ Max steps reached" to "Stopped after MAX_AGENT_STEPS without completion."
    }

    // ==========================================
    // SCANNER
    // ==========================================

    private fun handleScanner() {
        isScannerActive = !isScannerActive
        updateMenuItemsColor()
        if (isScannerActive) {
            startService(Intent(this, ScreenReaderService::class.java).apply { action = ScreenReaderService.ACTION_START_SCAN })
            Toast.makeText(this, "Screen Detection Enabled", Toast.LENGTH_SHORT).show()
        } else {
            startService(Intent(this, ScreenReaderService::class.java).apply { action = ScreenReaderService.ACTION_STOP_SCAN })
            Toast.makeText(this, "Screen Detection Disabled", Toast.LENGTH_SHORT).show()
        }
    }

    private fun handleKeyboard() {
        openKeyboardSwitcher()
    }

    private fun openKeyboardSwitcher() {
        try {
            inputMethodManager.showInputMethodPicker()
            Toast.makeText(this, "Choose keyboard", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            try {
                startActivity(Intent(android.provider.Settings.ACTION_INPUT_METHOD_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                Toast.makeText(this, "Open settings to switch keyboards", Toast.LENGTH_SHORT).show()
            } catch (_: Exception) {
                Toast.makeText(this, "Could not open keyboard switcher", Toast.LENGTH_SHORT).show()
            }
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
            if (!opened) { activeFeatures.remove(menuItems[0].id); updateMenuItemsColor() }
        } else {
            hideAutoTasker()
        }
    }

    private fun toggleFeature(featureId: Int) {
        if (activeFeatures.contains(featureId)) activeFeatures.remove(featureId)
        else activeFeatures.add(featureId)
        updateMenuItemsColor()
    }

    private fun isFeatureActive(featureId: Int): Boolean = activeFeatures.contains(featureId)

    private fun updateMenuItemsColor() {
        menuItems.forEach { item ->
            if (activeFeatures.contains(item.id) || (item.id == menuItems[3].id && isScannerActive)) {
                val layers = arrayOf(
                    android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.OVAL
                        setColor(android.graphics.Color.BLACK)
                    },
                    android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.OVAL
                        setColor(android.graphics.Color.parseColor("#23A6E2"))
                        alpha = 200
                    }
                )
                item.background = android.graphics.drawable.LayerDrawable(layers)
                item.setColorFilter(WHITE)
            } else {
                item.background = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.OVAL
                    setColor(android.graphics.Color.BLACK)
                }
                item.setColorFilter(WHITE)
            }
        }
    }

    // ==========================================
    // TOUCH / DRAG / ANIMATION
    // ==========================================

    override fun onTouch(v: View, event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                resetIdleTimer()
                initialTouchX = event.rawX; initialTouchY = event.rawY
                initialX = bubbleScreenX; initialY = bubbleScreenY
                isDragging = false; hasMoved = false; return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (isWindowResizing || preventPositionUpdates) return true
                val dx = (event.rawX - initialTouchX).toInt()
                val dy = (event.rawY - initialTouchY).toInt()
                if (abs(dx) > 10 || abs(dy) > 10) {
                    hasMoved = true
                    if (!isMenuExpanded) {
                        isDragging = true
                        bubbleScreenX = initialX + dx; bubbleScreenY = initialY + dy
                        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
                        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)
                        val windowHalfSize = collapsedWindowSizePx / 2
                        params.x = (bubbleScreenX - windowHalfSize).toInt()
                        params.y = (bubbleScreenY - windowHalfSize).toInt()
                        try { windowManager.updateViewLayout(overlayView, params) } catch (e: Exception) {}
                    } else {
                        if (!isMenuAnimating) collapseMenu()
                    }
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                resetIdleTimer()
                if (isWindowResizing || preventPositionUpdates) { isDragging = false; hasMoved = false; return true }
                if (!hasMoved && !isDragging) {
                    if (!isMenuAnimating) toggleMenu()
                } else if (isDragging) {
                    if (isWindowResizing || preventPositionUpdates) overlayView.postDelayed({ snapToEdge() }, 200)
                    else snapToEdge()
                }
                isDragging = false; hasMoved = false; return true
            }
        }
        return false
    }

    private fun toggleMenu() { if (isMenuAnimating) return; if (isMenuExpanded) collapseMenu() else expandMenu() }

    private fun expandMenu() {
        if (isMenuAnimating || isMenuExpanded) return
        isMenuExpanded = true; isMenuAnimating = true

        val radiusPx = dpToPx(radiusDp).toFloat()
        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
        val menuItemSizePx = dpToPx(menuItemSizeDp).toFloat()
        val expandedWindowSizePx = (radiusPx * 2) + bubbleSizePx + dpToPx(20f)
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)

        animateWindowSize(collapsedWindowSizePx, expandedWindowSizePx, 220L) { isMenuAnimating = false }

        val centerX = expandedWindowSizePx / 2f; val centerY = expandedWindowSizePx / 2f
        val screenWidth = resources.displayMetrics.widthPixels
        val isOnRightSide = bubbleScreenX > (screenWidth / 2)
        val fixedAngles = if (isOnRightSide) listOf(90.0, 135.0, 180.0, 225.0, 270.0)
                          else listOf(90.0, 45.0, 0.0, -45.0, -90.0)

        overlayView.postDelayed({
            for ((index, view) in menuItems.withIndex()) {
                view.visibility = View.VISIBLE; view.alpha = 0f
                view.translationX = 0f; view.translationY = 0f
                val angle = fixedAngles[index]; val rad = Math.toRadians(angle)
                val targetX = centerX + (radiusPx * cos(rad)).toFloat() - (menuItemSizePx / 2)
                val targetY = centerY + (radiusPx * -sin(rad)).toFloat() - (menuItemSizePx / 2)
                val initialCenteredX = centerX - (menuItemSizePx / 2); val initialCenteredY = centerY - (menuItemSizePx / 2)
                view.animate().translationX(targetX - initialCenteredX).translationY(targetY - initialCenteredY)
                    .alpha(1f).setDuration(220).setInterpolator(DecelerateInterpolator()).start()
            }
            updateMenuItemsColor()
        }, 160)
    }

    private fun collapseMenu() {
        if (isMenuAnimating || !isMenuExpanded) return
        isMenuExpanded = false; isMenuAnimating = true
        val radiusPx = dpToPx(radiusDp).toFloat()
        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
        val expandedWindowSizePx = (radiusPx * 2) + bubbleSizePx + dpToPx(20f)
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)

        for (view in menuItems) {
            view.animate().translationX(0f).translationY(0f).alpha(0f)
                .setDuration(150).setInterpolator(AccelerateInterpolator())
                .withEndAction { view.visibility = View.INVISIBLE }.start()
        }
        overlayView.postDelayed({
            animateWindowSize(expandedWindowSizePx, collapsedWindowSizePx, 200L) {
                isMenuAnimating = false
                resetIdleTimer() // Start idle timer after menu collapses
            }
        }, 120)
    }

    private fun animateWindowSize(fromSize: Float, toSize: Float, duration: Long = 200L, onEnd: (() -> Unit)? = null) {
        windowAnimator?.cancel()
        isWindowResizing = true; preventPositionUpdates = true
        val fromHalf = fromSize / 2f; val toHalf = toSize / 2f
        val startX = bubbleScreenX - fromHalf; val endX = bubbleScreenX - toHalf
        val startY = bubbleScreenY - fromHalf; val endY = bubbleScreenY - toHalf

        windowAnimator = ValueAnimator.ofFloat(fromSize, toSize).apply {
            this.duration = duration; interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val newSize = animator.animatedValue as Float
                val frac = if (toSize != fromSize) (newSize - fromSize) / (toSize - fromSize) else 1f
                params.width = newSize.toInt(); params.height = newSize.toInt()
                params.x = (startX + (endX - startX) * frac).toInt()
                params.y = (startY + (endY - startY) * frac).toInt()
                try { windowManager.updateViewLayout(overlayView, params) } catch (e: Exception) {}
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    windowAnimator = null; isWindowResizing = false; preventPositionUpdates = false
                    params.width = toSize.toInt(); params.height = toSize.toInt()
                    params.x = (bubbleScreenX - toHalf).toInt(); params.y = (bubbleScreenY - toHalf).toInt()
                    try { windowManager.updateViewLayout(overlayView, params) } catch (e: Exception) {}
                    onEnd?.invoke()
                }
            })
            start()
        }
    }

    private fun snapToEdge() {
        if (isWindowResizing || preventPositionUpdates || isMenuAnimating) {
            overlayView.postDelayed({ snapToEdge() }, 150); return
        }
        val bubbleSizePx = dpToPx(bubbleSizeDp).toFloat()
        val screenWidth = resources.displayMetrics.widthPixels
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)
        val windowHalfSize = collapsedWindowSizePx / 2

        val targetBubbleScreenX = if (bubbleScreenX > (screenWidth / 2))
            screenWidth - (bubbleSizePx / 2).toInt()
        else (bubbleSizePx / 2).toInt()

        ValueAnimator.ofInt(bubbleScreenX, targetBubbleScreenX).apply {
            duration = 200; interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                bubbleScreenX = animator.animatedValue as Int
                params.x = (bubbleScreenX - windowHalfSize).toInt()
                try { windowManager.updateViewLayout(overlayView, params) } catch (e: Exception) {}
            }
            start()
        }
    }

    private fun openMainApp() {
        startActivity(Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        })
    }

    private fun startForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Stremini Overlay", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): android.app.Notification {
        // Toggle Bubble action — uses BroadcastReceiver so it works from background
        val toggleIntent = Intent(ACTION_TOGGLE_BUBBLE).apply {
            setClass(this@ChatOverlayService, NotificationActionReceiver::class.java)
        }
        val togglePendingIntent = PendingIntent.getBroadcast(
            this, 0, toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Stop Service action
        val stopIntent = Intent(ACTION_STOP_SERVICE).apply {
            setClass(this@ChatOverlayService, NotificationActionReceiver::class.java)
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Open app when tapping the notification body
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this, 2, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val toggleLabel = if (isBubbleVisible) "🗕 Hide Bubble" else "💬 Show Bubble"
        val statusText = if (isBubbleVisible) "🟢 Running — Bubble visible"
                         else "🔴 Running — Bubble hidden"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Stremini AI Assistant")
            .setContentText(statusText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openAppPendingIntent)
            .addAction(0, toggleLabel, togglePendingIntent)
            .addAction(0, "❌ Stop Service", stopPendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    override fun onDestroy() {
        super.onDestroy()
        idleAnimationController.cancel()
        idleRunnable?.let { idleHandler.removeCallbacks(it) }
        serviceScope.cancel()
        unregisterReceiver(controlReceiver)
        hideFloatingChatbot(); hideAutoTasker()
        if (::overlayView.isInitialized && overlayView.windowToken != null) windowManager.removeView(overlayView)
    }
}