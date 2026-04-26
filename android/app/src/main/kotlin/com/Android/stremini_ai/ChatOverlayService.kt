package com.Android.stremini_ai

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.ViewConfiguration
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlin.math.hypot
import kotlin.math.cos
import kotlin.math.sin

class ChatOverlayService : Service(), View.OnTouchListener {
    private val autoTasker = AutoTaskerManager(this)

    companion object {
        const val ACTION_SEND_MESSAGE  = "com.Android.stremini_ai.SEND_MESSAGE"
        const val EXTRA_MESSAGE        = "message"
        const val ACTION_SCANNER_START = "com.Android.stremini_ai.SCANNER_START"
        const val ACTION_SCANNER_STOP  = "com.Android.stremini_ai.SCANNER_STOP"
        const val ACTION_TOGGLE_BUBBLE = "com.Android.stremini_ai.TOGGLE_BUBBLE"
        const val ACTION_STOP_SERVICE  = "com.Android.stremini_ai.STOP_SERVICE"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID      = "chat_head_service"
        val NEON_BLUE: Int = android.graphics.Color.parseColor("#00D9FF")
        val WHITE: Int     = android.graphics.Color.parseColor("#FFFFFF")
    }

    private lateinit var windowManager: WindowManager
    private lateinit var overlayView:   View
    private lateinit var params:        WindowManager.LayoutParams

    private var floatingChatView:   View? = null
    private var floatingChatParams: WindowManager.LayoutParams? = null
    private var isChatbotVisible    = false

    private lateinit var bubbleIcon: ImageView
    private lateinit var menuItems:  List<ImageView>
    private var isMenuExpanded = false

    private val activeFeatures  = mutableSetOf<Int>()
    private var isScannerActive = false
    private var isBubbleVisible = true
    private lateinit var inputMethodManager: InputMethodManager

    // Touch / drag state
    private var initialX      = 0
    private var initialY      = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging    = false
    private var hasMoved      = false
    private var touchSlopPx   = 0
    private var touchDownTimeMs = 0L

    private val dragActivationDelayMs = 120L

    private val bubbleSizeDp   = 60f
    private val menuItemSizeDp = 50f
    private val radiusDp       = 80f

    private var bubbleScreenX = 0
    private var bubbleScreenY = 0

    private var isMenuAnimating       = false
    private var windowAnimator:       ValueAnimator? = null
    private var isWindowResizing      = false
    private var preventPositionUpdates= false

    private var idleRunnable: Runnable? = null
    private val idleHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var isBubbleIdle     = false
    private var idleAnimator:    ValueAnimator? = null
    private var preIdleX         = 0
    private val IDLE_TIMEOUT_MS  = 3000L
    private val IDLE_SCALE       = 0.6f
    private val IDLE_ALPHA       = 0.4f
    private val IDLE_ANIM_DURATION = 400L

    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val aiBackendClient = AIBackendClient()
    private lateinit var chatCommandCoordinator: ChatCommandCoordinator
    private lateinit var bubbleController:        BubbleController
    private lateinit var floatingChatController: FloatingChatController
    private lateinit var idleAnimationController: IdleAnimationController

    // ── Voice input for chatbot ──────────────────────────────────────────────
    private var chatSpeechRecognizer: SpeechRecognizer? = null
    private var isChatListening = false

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
        windowManager     = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        inputMethodManager= getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        startForegroundService()
        touchSlopPx = maxOf(ViewConfiguration.get(this).scaledTouchSlop * 3, dpToPx(18f))

        bubbleController        = BubbleController(::hideBubble, ::showBubble).apply { setVisible(isBubbleVisible) }
        floatingChatController  = FloatingChatController(::showFloatingChatbot, ::hideFloatingChatbot)
        idleAnimationController = IdleAnimationController(
            onIdle = { if (!isMenuExpanded && !isDragging && !isMenuAnimating) shrinkBubble() },
            onWake = { restoreBubble() }
        )
        chatCommandCoordinator  = ChatCommandCoordinator(
            scope         = serviceScope,
            backendClient = aiBackendClient,
            onBotMessage  = { message -> addMessageToChatbot(message, isUser = false) }
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
            ACTION_STOP_SERVICE  -> { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
        }
        return START_STICKY
    }

    // ── Bubble hide/show ─────────────────────────────────────────────────────

    private fun hideBubble() {
        if (!isBubbleVisible) return
        if (isMenuExpanded) collapseMenu()
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
        bubbleIcon.scaleX = 1f; bubbleIcon.scaleY = 1f; bubbleIcon.alpha = 1f
        isBubbleIdle    = false
        isBubbleVisible = true
        bubbleController.setVisible(true)
        updateNotification()
        resetIdleTimer()
    }

    // ── Overlay setup ─────────────────────────────────────────────────────────

    private fun setupOverlay() {
        overlayView = LayoutInflater.from(this).inflate(R.layout.chat_bubble_layout, null)
        bubbleIcon  = overlayView.findViewById(R.id.bubble_icon)
        menuItems   = listOf(
            overlayView.findViewById(R.id.btn_auto_tasker),
            overlayView.findViewById(R.id.btn_settings),
            overlayView.findViewById(R.id.btn_ai),
            overlayView.findViewById(R.id.btn_scanner),
            overlayView.findViewById(R.id.btn_keyboard)
        )

        val typeParam = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val radiusPx             = dpToPx(radiusDp).toFloat()
        val bubbleSizePx         = dpToPx(bubbleSizeDp).toFloat()
        val collapsedWindowSizePx= (bubbleSizePx + dpToPx(10f)).toInt()

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
        bubbleIcon.setOnLongClickListener { openKeyboardSwitcher(); true }

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
        resetIdleTimer()
    }

    // ── Idle animation ────────────────────────────────────────────────────────

    private fun resetIdleTimer() { idleAnimationController.resetTimer() }

    private fun shrinkBubble() {
        if (isBubbleIdle) return
        isBubbleIdle = true
        bubbleIcon.animate().scaleX(IDLE_SCALE).scaleY(IDLE_SCALE).alpha(IDLE_ALPHA)
            .setDuration(IDLE_ANIM_DURATION).setInterpolator(DecelerateInterpolator()).start()
        preIdleX = bubbleScreenX
        val screenWidth    = resources.displayMetrics.widthPixels
        val bubbleSizePx   = dpToPx(bubbleSizeDp).toFloat()
        val collapsedSize  = bubbleSizePx + dpToPx(10f)
        val windowHalfSize = collapsedSize / 2
        val targetX = if (bubbleScreenX > screenWidth / 2)
            screenWidth - (bubbleSizePx / 2).toInt() + (bubbleSizePx * 0.4f).toInt()
        else (bubbleSizePx / 2).toInt() - (bubbleSizePx * 0.4f).toInt()

        idleAnimator?.cancel()
        idleAnimator = ValueAnimator.ofInt(bubbleScreenX, targetX).apply {
            duration = IDLE_ANIM_DURATION
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                if (isDragging || isMenuExpanded || isMenuAnimating) { cancel(); return@addUpdateListener }
                bubbleScreenX = animator.animatedValue as Int
                params.x = (bubbleScreenX - windowHalfSize).toInt()
                try { windowManager.updateViewLayout(overlayView, params) } catch (_: Exception) {}
            }
            start()
        }
    }

    private fun restoreBubble() {
        if (!isBubbleIdle) return
        isBubbleIdle = false
        bubbleIcon.animate().scaleX(1f).scaleY(1f).alpha(1f)
            .setDuration(200L).setInterpolator(DecelerateInterpolator()).start()
        idleAnimator?.cancel()
        val bubbleSizePx   = dpToPx(bubbleSizeDp).toFloat()
        val screenWidth    = resources.displayMetrics.widthPixels
        val collapsedSize  = bubbleSizePx + dpToPx(10f)
        val windowHalfSize = collapsedSize / 2
        val targetX = if (preIdleX > screenWidth / 2)
            screenWidth - (bubbleSizePx / 2).toInt() else (bubbleSizePx / 2).toInt()

        idleAnimator = ValueAnimator.ofInt(bubbleScreenX, targetX).apply {
            duration = 200L; interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                if (isDragging) { cancel(); return@addUpdateListener }
                bubbleScreenX = animator.animatedValue as Int
                params.x = (bubbleScreenX - windowHalfSize).toInt()
                try { windowManager.updateViewLayout(overlayView, params) } catch (_: Exception) {}
            }
            start()
        }
    }

    // ── Chatbot ───────────────────────────────────────────────────────────────

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
        floatingChatParams?.x = dpToPx(20f)
        floatingChatParams?.y = dpToPx(100f)
        floatingChatView?.setLayerType(View.LAYER_TYPE_HARDWARE, null)
        setupFloatingChatListeners()
        windowManager.addView(floatingChatView, floatingChatParams)
        isChatbotVisible = true
        addMessageToChatbot("Hello! I'm Stremini AI. How can I help?", isUser = false)
    }

    private fun setupFloatingChatListeners() {
        val view = floatingChatView ?: return

        // ── Header drag ───────────────────────────────────────────────────────
        val header = view.findViewById<LinearLayout>(R.id.chat_header)
        var chatInitialX = 0; var chatInitialY = 0
        var chatInitialTouchX = 0f; var chatInitialTouchY = 0f
        var chatIsDragging = false

        header?.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    chatInitialTouchX = event.rawX; chatInitialTouchY = event.rawY
                    chatInitialX = floatingChatParams?.x ?: 0
                    chatInitialY = floatingChatParams?.y ?: 0
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

        // ── Close ─────────────────────────────────────────────────────────────
        view.findViewById<ImageView>(R.id.btn_close_chat)?.setOnClickListener {
            stopChatVoiceInput()
            hideFloatingChatbot()
            toggleFeature(menuItems[2].id)
        }

        // ── Send text ─────────────────────────────────────────────────────────
        view.findViewById<ImageView>(R.id.btn_send_message)?.setOnClickListener {
            val input   = view.findViewById<EditText>(R.id.et_chat_input)
            val message = input?.text?.toString()?.trim()
            if (!message.isNullOrEmpty()) {
                addMessageToChatbot(message, isUser = true)
                input.text?.clear()
                processUserCommand(message)
            }
        }

        // ── Voice input mic ───────────────────────────────────────────────────
        view.findViewById<ImageView>(R.id.btn_voice_input)?.setOnClickListener {
            if (isChatListening) {
                stopChatVoiceInput()
            } else {
                startChatVoiceInput()
            }
        }

        // ── Cancel voice ──────────────────────────────────────────────────────
        view.findViewById<TextView>(R.id.btn_cancel_voice)?.setOnClickListener {
            stopChatVoiceInput()
        }
    }

    // ── Chat voice input ──────────────────────────────────────────────────────

    private fun startChatVoiceInput() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Toast.makeText(this, "Speech recognition not available", Toast.LENGTH_SHORT).show()
            return
        }

        isChatListening = true
        updateVoiceUi(listening = true, partialText = "Listening…")

        chatSpeechRecognizer?.destroy()
        chatSpeechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    updateVoiceUi(listening = true, partialText = "Listening…")
                }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() { updateVoiceUi(listening = true, partialText = "Processing…") }
                override fun onEvent(eventType: Int, params: Bundle?) {}

                override fun onPartialResults(partialResults: Bundle?) {
                    val partial = partialResults
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull() ?: return
                    updateVoiceUi(listening = true, partialText = "\"$partial\"")
                }

                override fun onResults(results: Bundle?) {
                    val text = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()?.trim() ?: ""
                    stopChatVoiceInput()
                    if (text.isNotBlank()) {
                        addMessageToChatbot(text, isUser = true)
                        processUserCommand(text)
                    }
                }

                override fun onError(error: Int) {
                    stopChatVoiceInput()
                    val msg = when (error) {
                        SpeechRecognizer.ERROR_NO_MATCH        -> "Didn't catch that — try again"
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT  -> "No speech detected"
                        SpeechRecognizer.ERROR_NETWORK         -> "Network error"
                        SpeechRecognizer.ERROR_AUDIO           -> "Audio error"
                        else                                   -> "Voice error ($error)"
                    }
                    serviceScope.launch {
                        floatingChatView?.let { v ->
                            val et = v.findViewById<EditText>(R.id.et_chat_input)
                            et?.hint = msg
                        }
                    }
                }
            })

            startListening(
                Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
                }
            )
        }
    }

    private fun stopChatVoiceInput() {
        isChatListening = false
        chatSpeechRecognizer?.stopListening()
        chatSpeechRecognizer?.destroy()
        chatSpeechRecognizer = null
        updateVoiceUi(listening = false)
    }

    private fun updateVoiceUi(listening: Boolean, partialText: String = "") {
        val view = floatingChatView ?: return
        serviceScope.launch {
            val statusBar    = view.findViewById<LinearLayout>(R.id.voice_status_bar)
            val tvPartial    = view.findViewById<TextView>(R.id.tv_voice_partial)
            val btnMic       = view.findViewById<ImageView>(R.id.btn_voice_input)
            val etInput      = view.findViewById<EditText>(R.id.et_chat_input)

            statusBar?.visibility = if (listening) View.VISIBLE else View.GONE
            if (partialText.isNotBlank()) tvPartial?.text = partialText

            // Change mic icon tint to indicate active state
            if (listening) {
                btnMic?.setColorFilter(android.graphics.Color.parseColor("#22C55E"))
                etInput?.hint = "Listening…"
            } else {
                btnMic?.setColorFilter(android.graphics.Color.parseColor("#23A6E2"))
                etInput?.hint = "Ask anything..."
            }
        }
    }

    // ── Message handling ──────────────────────────────────────────────────────

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
            
            // Allow users to copy the text from the chat bubble
            val tvMessage = messageView.findViewById<TextView>(R.id.tv_message)
            tvMessage?.text = message
            tvMessage?.setTextIsSelectable(true)
            
            // Explicitly handle long click to copy the full message, as 
            // Action Modes for text selection can fail to render in System Overlays
            tvMessage?.setOnLongClickListener {
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = ClipData.newPlainText("Chat Message", tvMessage.text.toString())
                clipboard.setPrimaryClip(clip)
                Toast.makeText(this@ChatOverlayService, "Text copied to clipboard", Toast.LENGTH_SHORT).show()
                true // Consume the long-click event
            }
            
            messagesContainer?.addView(messageView)
            view.findViewById<ScrollView>(R.id.scroll_messages)?.post {
                view.findViewById<ScrollView>(R.id.scroll_messages)?.fullScroll(View.FOCUS_DOWN)
            }
        }
    }

    private fun hideFloatingChatbot() {
        if (!isChatbotVisible) return
        stopChatVoiceInput()
        floatingChatView?.let { windowManager.removeView(it) }
        floatingChatView = null; floatingChatParams = null; isChatbotVisible = false
        floatingChatController.setVisible(false)
    }

    // ── Feature handlers ──────────────────────────────────────────────────────

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
        val imeManager = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        val enabledMethods = imeManager.enabledInputMethodList
        val streminiEnabled = enabledMethods.any { it.packageName == packageName }

        if (!streminiEnabled) {
            try {
                startActivity(Intent(android.provider.Settings.ACTION_INPUT_METHOD_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                Toast.makeText(this, "Find 'Stremini AI Keyboard' and enable it", Toast.LENGTH_LONG).show()
            } catch (_: Exception) {
                Toast.makeText(this, "Could not open keyboard settings", Toast.LENGTH_SHORT).show()
            }
            return
        }

        try {
            imeManager.showInputMethodPicker()
        } catch (_: Exception) {
            Toast.makeText(this, "Could not open keyboard picker", Toast.LENGTH_SHORT).show()
        }
    }

    private fun openKeyboardSwitcher() {
        try {
            inputMethodManager.showInputMethodPicker()
            Toast.makeText(this, "Choose keyboard", Toast.LENGTH_SHORT).show()
        } catch (_: Exception) {
            try {
                startActivity(Intent(android.provider.Settings.ACTION_INPUT_METHOD_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
            } catch (_: Exception) {}
        }
    }

    private fun handleSettings() { openMainApp(); Toast.makeText(this, "Opening Stremini…", Toast.LENGTH_SHORT).show() }

    private fun handleAutoTasker() {
        autoTasker.toggle(menuItems[0].id, activeFeatures)
        updateMenuItemsColor()
    }

    private fun toggleFeature(featureId: Int) {
        if (activeFeatures.contains(featureId)) activeFeatures.remove(featureId) else activeFeatures.add(featureId)
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

    // ── Touch / drag ──────────────────────────────────────────────────────────

    override fun onTouch(v: View, event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                resetIdleTimer()
                initialTouchX = event.rawX; initialTouchY = event.rawY
                initialX = bubbleScreenX; initialY = bubbleScreenY
                touchDownTimeMs = event.eventTime
                isDragging = false; hasMoved = false; return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (isWindowResizing || preventPositionUpdates) return true
                if (isMenuExpanded) return true
                if ((event.eventTime - touchDownTimeMs) < dragActivationDelayMs) return true

                val dx = (event.rawX - initialTouchX).toInt()
                val dy = (event.rawY - initialTouchY).toInt()
                val movementDistance = hypot(dx.toDouble(), dy.toDouble())
                if (movementDistance > touchSlopPx) {
                    hasMoved = true
                    isDragging = true
                    bubbleScreenX = initialX + dx; bubbleScreenY = initialY + dy
                    val bubbleSizePx       = dpToPx(bubbleSizeDp).toFloat()
                    val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)
                    val windowHalfSize     = collapsedWindowSizePx / 2
                    params.x = (bubbleScreenX - windowHalfSize).toInt()
                    params.y = (bubbleScreenY - windowHalfSize).toInt()
                    try { windowManager.updateViewLayout(overlayView, params) } catch (_: Exception) {}
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                resetIdleTimer()
                if (isWindowResizing || preventPositionUpdates) { isDragging = false; hasMoved = false; return true }
                if (!hasMoved && !isDragging) { if (!isMenuAnimating) toggleMenu() }
                else if (isDragging) {
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

        val radiusPx              = dpToPx(radiusDp).toFloat()
        val bubbleSizePx          = dpToPx(bubbleSizeDp).toFloat()
        val menuItemSizePx        = dpToPx(menuItemSizeDp).toFloat()
        val expandedWindowSizePx  = (radiusPx * 2) + bubbleSizePx + dpToPx(20f)
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)

        animateWindowSize(collapsedWindowSizePx, expandedWindowSizePx, 220L) { isMenuAnimating = false }

        val centerX    = expandedWindowSizePx / 2f; val centerY = expandedWindowSizePx / 2f
        val screenWidth = resources.displayMetrics.widthPixels
        val isOnRightSide = bubbleScreenX > (screenWidth / 2)
        val fixedAngles   = if (isOnRightSide) listOf(90.0, 135.0, 180.0, 225.0, 270.0)
                            else listOf(90.0, 45.0, 0.0, -45.0, -90.0)

        overlayView.postDelayed({
            for ((index, view) in menuItems.withIndex()) {
                view.visibility = View.VISIBLE; view.alpha = 0f
                view.translationX = 0f; view.translationY = 0f
                val angle = fixedAngles[index]; val rad = Math.toRadians(angle)
                val targetX = centerX + (radiusPx * cos(rad)).toFloat() - (menuItemSizePx / 2)
                val targetY = centerY + (radiusPx * -sin(rad)).toFloat() - (menuItemSizePx / 2)
                val initialCenteredX = centerX - (menuItemSizePx / 2)
                val initialCenteredY = centerY - (menuItemSizePx / 2)
                view.animate()
                    .translationX(targetX - initialCenteredX).translationY(targetY - initialCenteredY)
                    .alpha(1f).setDuration(220).setInterpolator(DecelerateInterpolator()).start()
            }
            updateMenuItemsColor()
        }, 160)
    }

    private fun collapseMenu() {
        if (isMenuAnimating || !isMenuExpanded) return
        isMenuExpanded = false; isMenuAnimating = true
        val radiusPx              = dpToPx(radiusDp).toFloat()
        val bubbleSizePx          = dpToPx(bubbleSizeDp).toFloat()
        val expandedWindowSizePx  = (radiusPx * 2) + bubbleSizePx + dpToPx(20f)
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)

        for (view in menuItems) {
            view.animate().translationX(0f).translationY(0f).alpha(0f)
                .setDuration(150).setInterpolator(AccelerateInterpolator())
                .withEndAction { view.visibility = View.INVISIBLE }.start()
        }
        overlayView.postDelayed({
            animateWindowSize(expandedWindowSizePx, collapsedWindowSizePx, 200L) {
                isMenuAnimating = false; resetIdleTimer()
            }
        }, 120)
    }

    private fun animateWindowSize(fromSize: Float, toSize: Float, duration: Long = 200L, onEnd: (() -> Unit)? = null) {
        windowAnimator?.cancel()
        isWindowResizing = true; preventPositionUpdates = true
        val fromHalf = fromSize / 2f; val toHalf = toSize / 2f
        val startX   = bubbleScreenX - fromHalf; val endX = bubbleScreenX - toHalf
        val startY   = bubbleScreenY - fromHalf; val endY = bubbleScreenY - toHalf

        windowAnimator = ValueAnimator.ofFloat(fromSize, toSize).apply {
            this.duration = duration; interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val newSize = animator.animatedValue as Float
                val frac    = if (toSize != fromSize) (newSize - fromSize) / (toSize - fromSize) else 1f
                params.width  = newSize.toInt(); params.height = newSize.toInt()
                params.x = (startX + (endX - startX) * frac).toInt()
                params.y = (startY + (endY - startY) * frac).toInt()
                try { windowManager.updateViewLayout(overlayView, params) } catch (_: Exception) {}
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    windowAnimator = null; isWindowResizing = false; preventPositionUpdates = false
                    params.width  = toSize.toInt(); params.height = toSize.toInt()
                    params.x = (bubbleScreenX - toHalf).toInt()
                    params.y = (bubbleScreenY - toHalf).toInt()
                    try { windowManager.updateViewLayout(overlayView, params) } catch (_: Exception) {}
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
        val bubbleSizePx          = dpToPx(bubbleSizeDp).toFloat()
        val screenWidth           = resources.displayMetrics.widthPixels
        val collapsedWindowSizePx = bubbleSizePx + dpToPx(10f)
        val windowHalfSize        = collapsedWindowSizePx / 2

        val targetBubbleScreenX = if (bubbleScreenX > (screenWidth / 2))
            screenWidth - (bubbleSizePx / 2).toInt() else (bubbleSizePx / 2).toInt()

        ValueAnimator.ofInt(bubbleScreenX, targetBubbleScreenX).apply {
            duration = 200; interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                bubbleScreenX = animator.animatedValue as Int
                params.x = (bubbleScreenX - windowHalfSize).toInt()
                try { windowManager.updateViewLayout(overlayView, params) } catch (_: Exception) {}
            }
            start()
        }
    }

    // ── Misc ──────────────────────────────────────────────────────────────────

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
        val toggleIntent = Intent(ACTION_TOGGLE_BUBBLE).apply {
            setClass(this@ChatOverlayService, NotificationActionReceiver::class.java)
        }
        val togglePendingIntent = PendingIntent.getBroadcast(
            this, 0, toggleIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = Intent(ACTION_STOP_SERVICE).apply {
            setClass(this@ChatOverlayService, NotificationActionReceiver::class.java)
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            this, 1, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this, 2, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val toggleLabel = if (isBubbleVisible) "🗕 Hide Bubble" else "💬 Show Bubble"
        val statusText  = if (isBubbleVisible) "🟢 Running — Bubble visible" else "🔴 Running — Bubble hidden"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Stremini AI Assistant")
            .setContentText(statusText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openAppPendingIntent)
            .addAction(0, toggleLabel, togglePendingIntent)
            .addAction(0, "❌ Stop Service", stopPendingIntent)
            .setOngoing(true).setSilent(true).setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification() {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification())
    }

    override fun onDestroy() {
        super.onDestroy()
        idleAnimationController.cancel()
        idleRunnable?.let { idleHandler.removeCallbacks(it) }
        serviceScope.cancel()
        stopChatVoiceInput()
        unregisterReceiver(controlReceiver)
        hideFloatingChatbot()
        if (::overlayView.isInitialized && overlayView.windowToken != null) windowManager.removeView(overlayView)
    }
}