package com.Android.stremini_ai

import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.content.SharedPreferences
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.os.Build
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.Menu
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.widget.PopupMenu
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.min

class StreminiIME : InputMethodService() {

    companion object {
        private const val TAG = "StreminiIME"
        private const val PREFS_NAME = "keyboard_prefs"
        private const val CLIPBOARD_HISTORY_KEY = "clipboard_history"
        private const val CLIPBOARD_HISTORY_LIMIT = 12
    }

    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var clipboardManager: ClipboardManager
    private lateinit var sharedPrefs: SharedPreferences

    private val imeBackendClient = IMEBackendClient()

    // Animation Helpers (Pre-allocated for performance)
    private val pressInterpolator = DecelerateInterpolator()
    private val releaseInterpolator = AccelerateDecelerateInterpolator()
    private val handler = Handler(Looper.getMainLooper())

    // State
    private var isShiftOn = false
    private var isSymbolsMode = false
    private val letterKeyViews = mutableListOf<TextView>()
    private var shiftKeyView: View? = null
    private var symbolsKeyView: TextView? = null
    private var enterKeyView: TextView? = null
    private var keyboardRootView: View? = null
    private val keyTextViewCache = HashMap<Int, TextView>()
    private var currentAppContext = "general"
    private var selectedTone = "professional"
    private var isAiFeatureMode = true
    private var aiActionJob: Job? = null
    private var lastAiActionTs = 0L
    private var translationLanguages: List<Pair<String, String>> = emptyList()

    private val defaultMajorLanguages = listOf(
        "en" to "English",
        "es" to "Spanish",
        "fr" to "French",
        "de" to "German",
        "hi" to "Hindi",
        "pt" to "Portuguese",
        "ar" to "Arabic",
        "ja" to "Japanese"
    )

    private val alphaNumericKeyMap = mapOf(
        R.id.key_q to "q", R.id.key_w to "w", R.id.key_e to "e", R.id.key_r to "r", R.id.key_t to "t",
        R.id.key_y to "y", R.id.key_u to "u", R.id.key_i to "i", R.id.key_o to "o", R.id.key_p to "p",
        R.id.key_a to "a", R.id.key_s to "s", R.id.key_d to "d", R.id.key_f to "f", R.id.key_g to "g",
        R.id.key_h to "h", R.id.key_j to "j", R.id.key_k to "k", R.id.key_l to "l",
        R.id.key_z to "z", R.id.key_x to "x", R.id.key_c to "c", R.id.key_v to "v", R.id.key_b to "b",
        R.id.key_n to "n", R.id.key_m to "m",
        R.id.key_1 to "1", R.id.key_2 to "2", R.id.key_3 to "3", R.id.key_4 to "4", R.id.key_5 to "5",
        R.id.key_6 to "6", R.id.key_7 to "7", R.id.key_8 to "8", R.id.key_9 to "9", R.id.key_0 to "0",
        R.id.key_dot to ".", R.id.key_comma to ","
    )

    private val specialCharacterKeyMap = mapOf(
        "key_at" to "@",
        "key_hash" to "#",
        "key_amp" to "&",
        "key_question" to "?",
        "key_exclaim" to "!",
        "key_underscore" to "_",
        "key_dash" to "-",
        "key_colon" to ":"
    )

    private val symbolsKeyMap = mapOf(
        R.id.key_q to "@", R.id.key_w to "#", R.id.key_e to "$", R.id.key_r to "%", R.id.key_t to "&",
        R.id.key_y to "-", R.id.key_u to "+", R.id.key_i to "(", R.id.key_o to ")", R.id.key_p to "/",
        R.id.key_a to "*", R.id.key_s to "\"", R.id.key_d to "'", R.id.key_f to ":", R.id.key_g to ";",
        R.id.key_h to "!", R.id.key_j to "?", R.id.key_k to "~", R.id.key_l to "=",
        R.id.key_z to "[", R.id.key_x to "]", R.id.key_c to "{", R.id.key_v to "}", R.id.key_b to "_",
        R.id.key_n to "\\", R.id.key_m to "|",
        R.id.key_1 to "!", R.id.key_2 to "@", R.id.key_3 to "#", R.id.key_4 to "$", R.id.key_5 to "%",
        R.id.key_6 to "^", R.id.key_7 to "&", R.id.key_8 to "*", R.id.key_9 to "(", R.id.key_0 to ")",
        R.id.key_dot to ".", R.id.key_comma to ","
    )

    // Backspace Repeater
    private var isBackspacePressed = false
    private val backspaceRunnable = object : Runnable {
        override fun run() {
            if (isBackspacePressed) {
                handleBackspace()
                handler.postDelayed(this, 50) // 50ms = 20 chars/sec deletion speed
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        sharedPrefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
    }

    override fun onCreateInputView(): View {
        val view = layoutInflater.inflate(R.layout.keyboard_layout, null)
        keyboardRootView = view
        buildKeyCache(view)
        setupKeyboardInteractions(view)
        return view
    }

    private fun buildKeyCache(view: View) {
        keyTextViewCache.clear()
        alphaNumericKeyMap.keys.forEach { id ->
            (view.findViewById<View>(id) as? TextView)?.let { keyTextViewCache[id] = it }
        }
        listOf(R.id.key_symbols, R.id.key_enter).forEach { id ->
            (view.findViewById<View>(id) as? TextView)?.let { keyTextViewCache[id] = it }
        }
    }

    private fun setupKeyboardInteractions(view: View) {
        letterKeyViews.clear()
        shiftKeyView = view.findViewById(R.id.key_shift)
        symbolsKeyView = view.findViewById(R.id.key_symbols)
        enterKeyView = view.findViewById(R.id.key_enter)

        // 1. Attach High-Performance Listeners
        alphaNumericKeyMap.forEach { (id, char) ->
            val keyView = keyTextViewCache[id] ?: view.findViewById<View>(id)
            if (keyView is TextView && char.length == 1 && char[0].isLetter()) {
                letterKeyViews.add(keyView)
            }
            keyView?.setOnTouchListener(createKeyTouchListener(id))
        }

        specialCharacterKeyMap.forEach { (idName, value) ->
            val keyId = resources.getIdentifier(idName, "id", packageName)
            if (keyId != 0) {
                view.findViewById<View>(keyId)?.setOnTouchListener(createTextTouchListener(value))
            }
        }

        // Space
        view.findViewById<View>(R.id.key_space)?.setOnTouchListener(createTextTouchListener(" "))

        // Symbol/Alphabet toggle
        symbolsKeyView?.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    feedback(v)
                    animateKey(v, true)
                }
                MotionEvent.ACTION_UP -> {
                    animateKey(v, false)
                    isSymbolsMode = !isSymbolsMode
                    updateKeyboardLabels()
                }
                MotionEvent.ACTION_CANCEL -> animateKey(v, false)
            }
            true
        }

        // Backspace (Hold to delete)
        view.findViewById<View>(R.id.key_backspace)?.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    feedback(v)
                    animateKey(v, true)
                    isBackspacePressed = true
                    handleBackspace()
                    handler.postDelayed(backspaceRunnable, 400) // Wait 400ms before repeating
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    animateKey(v, false)
                    isBackspacePressed = false
                    handler.removeCallbacks(backspaceRunnable)
                }
            }
            true
        }

        // Enter Key
        view.findViewById<View>(R.id.key_enter)?.setOnTouchListener { v, event ->
            if (event.action == MotionEvent.ACTION_DOWN) {
                feedback(v)
                animateKey(v, true)
            } else if (event.action == MotionEvent.ACTION_UP) {
                animateKey(v, false)
                handleEnterKey()
            }
            true
        }

        // Switch keyboard key: open system keyboard picker.
        view.findViewById<View>(R.id.key_switch_keyboard)?.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    feedback(v)
                    animateKey(v, true)
                }
                MotionEvent.ACTION_UP -> {
                    animateKey(v, false)
                    showKeyboardSwitcher()
                }
                MotionEvent.ACTION_CANCEL -> animateKey(v, false)
            }
            true
        }

        // Clipboard key: tap = paste, long-press = copy selected/current text
        // Resolve by name to avoid variant-specific R.id generation issues.
        val clipboardKeyId = resources.getIdentifier("key_clipboard", "id", packageName)
        if (clipboardKeyId != 0) {
            view.findViewById<View>(clipboardKeyId)?.setOnTouchListener { v, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        feedback(v)
                        animateKey(v, true)
                    }
                    MotionEvent.ACTION_UP -> {
                        animateKey(v, false)
                        showKeyboardSwitcher()
                    }
                    MotionEvent.ACTION_CANCEL -> animateKey(v, false)
                }
                true
            }
            view.findViewById<View>(clipboardKeyId)?.setOnLongClickListener {
                showClipboardHistory(it)
                true
            }
        }

        // Shift Key
        shiftKeyView?.setOnTouchListener { v, event ->
            if (event.action == MotionEvent.ACTION_DOWN) {
                feedback(v)
                isShiftOn = !isShiftOn
                updateShiftState()
            }
            true // Consume event
        }

        // AI Actions
        view.findViewById<View>(R.id.action_undo)?.setOnClickListener {
            feedback(it)
            toggleKeyboardMode()
        }
        setupAiAction(view, R.id.action_improve, "correct")
        setupAiAction(view, R.id.action_complete, "complete")
        setupToneAction(view)
        setupTranslateAction(view)

        updateKeyboardLabels()
        updateKeyboardModeUi()
    }

    // --- Performance Touch Listener ---
    private fun createKeyTouchListener(keyId: Int): View.OnTouchListener {
        return View.OnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    // Instant feedback + instant commit for smoother typing response.
                    commitText(resolveKeyOutput(keyId))
                    feedback(v)
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> Unit
            }
            true
        }
    }



    private fun createTextTouchListener(text: String): View.OnTouchListener {
        return View.OnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    commitText(text)
                    feedback(v)
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> Unit
            }
            true
        }
    }

    // --- Core Logic ---

    private fun commitText(text: String) {
        val ic = currentInputConnection ?: return
        val output = if (!isSymbolsMode && isShiftOn && text.length == 1 && text[0].isLetter()) {
            text.uppercase()
        } else {
            text
        }
        
        ic.commitText(output, 1)
        if (aiActionJob?.isActive == true) {
            serviceScope.coroutineContext.cancelChildren(CancellationException("User continued typing"))
        }

        // Auto-turn off shift after one char
        if (!isSymbolsMode && isShiftOn) {
            isShiftOn = false
            updateKeyboardLabels()
        }
    }

    private fun resolveKeyOutput(keyId: Int): String {
        return if (isSymbolsMode) {
            symbolsKeyMap[keyId] ?: ""
        } else {
            alphaNumericKeyMap[keyId] ?: ""
        }
    }

    private fun handleBackspace() {
        val ic = currentInputConnection ?: return
        val selectedText = ic.getSelectedText(0)
        ic.beginBatchEdit()
        if (!selectedText.isNullOrEmpty()) {
            ic.commitText("", 1)
        } else {
            ic.deleteSurroundingText(1, 0)
        }
        ic.endBatchEdit()
    }

    private fun handleEnterKey() {
        val ic = currentInputConnection ?: return
        val info = currentInputEditorInfo ?: return

        // 1. Check for Multi-Line (Standard Enter)
        val isMultiLine = (info.inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE) != 0
        if (isMultiLine) {
            ic.commitText("\n", 1)
            return
        }

        // 2. Perform Action (Go, Search, Send)
        val action = info.imeOptions and EditorInfo.IME_MASK_ACTION
        if (action != EditorInfo.IME_ACTION_NONE) {
            ic.performEditorAction(action)
        } else {
            // Fallback
            ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
            ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
        }
    }

    // --- AI Feature Logic ---

    private fun handleAiAction(actionType: String) {
        val now = System.currentTimeMillis()
        if (now - lastAiActionTs < 250L) return
        lastAiActionTs = now

        val originalText = getCurrentText()
        if (originalText.isBlank()) return

        aiActionJob?.cancel(CancellationException("Replaced by a newer AI action"))

        // Lightweight feedback
        Toast.makeText(this, "Thinking...", Toast.LENGTH_SHORT).show()

        aiActionJob = serviceScope.launch(Dispatchers.IO) {
            try {
                val resultText = imeBackendClient.requestKeyboardAction(
                    originalText = originalText,
                    appContext = currentAppContext,
                    actionType = actionType,
                    selectedTone = selectedTone,
                ).getOrNull().orEmpty()

                if (resultText.isNotEmpty()) {
                    withContext(Dispatchers.Main) {
                        if (actionType == "complete") {
                            smartAppend(originalText, resultText)
                        } else {
                            replaceFullText(resultText)
                        }
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    /**
     * Smartly appends text, preventing duplication.
     * Example: Input="Hello wor", AI="Hello world" -> Appends "ld"
     * Example: Input="Hello", AI=" world" -> Appends " world"
     */
    private fun smartAppend(currentText: String, aiCompletion: String) {
        val ic = currentInputConnection ?: return
        
        // 1. If AI returned the exact full sentence including input
        if (aiCompletion.startsWith(currentText)) {
            val newPart = aiCompletion.substring(currentText.length)
            ic.commitText(newPart, 1)
            return
        }

        // 2. Overlap detection (Suffix of current matching Prefix of AI)
        // Check overlap of up to 20 characters
        val checkLen = min(currentText.length, 20)
        val suffix = currentText.takeLast(checkLen)
        
        // Find if the AI text starts with any part of the suffix
        // e.g. Suffix="lo world", AI="world is big" -> Overlap "world"
        var overlapIndex = -1
        for (i in 0 until checkLen) {
            val sub = suffix.substring(i)
            if (aiCompletion.startsWith(sub)) {
                overlapIndex = sub.length
                break // Found largest overlap
            }
        }

        if (overlapIndex > 0) {
            val newPart = aiCompletion.substring(overlapIndex)
            ic.commitText(newPart, 1)
        } else {
            // No obvious overlap, just append (add space if needed)
            val textToInsert = if (!currentText.endsWith(" ") && !aiCompletion.startsWith(" ")) {
                " $aiCompletion"
            } else {
                aiCompletion
            }
            ic.commitText(textToInsert, 1)
        }
    }

    private fun replaceFullText(newText: String) {
        val ic = currentInputConnection ?: return
        // Select slightly more than needed to ensure we catch everything
        val before = ic.getTextBeforeCursor(5000, 0) ?: ""
        val after = ic.getTextAfterCursor(5000, 0) ?: ""
        ic.deleteSurroundingText(before.length, after.length)
        ic.commitText(newText, 1)
    }

    private fun getCurrentText(): String {
        val ic = currentInputConnection ?: return ""
        val before = ic.getTextBeforeCursor(2000, 0) ?: ""
        val after = ic.getTextAfterCursor(2000, 0) ?: ""
        return "$before$after"
    }

    // --- UX Feedback ---

    private fun feedback(view: View) {
        // Keep feedback lightweight and silent for smoother typing.
        val hapticFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            android.view.HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING or
                android.view.HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
        } else {
            android.view.HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING
        }
        view.performHapticFeedback(android.view.HapticFeedbackConstants.KEYBOARD_TAP, hapticFlag)
    }

    private fun handleClipboardPaste() {
        val ic = currentInputConnection ?: return
        val clip = clipboardManager.primaryClip ?: return
        val text = clip.getItemAt(0)?.coerceToText(this)?.toString().orEmpty()
        if (text.isNotBlank()) {
            saveClipboardEntry(text)
            ic.commitText(text, 1)
        } else {
            Toast.makeText(this, "Clipboard is empty", Toast.LENGTH_SHORT).show()
        }
    }

    private fun handleClipboardCopy() {
        val ic = currentInputConnection ?: return
        val selected = ic.getSelectedText(0)?.toString().orEmpty()
        val textToCopy = if (selected.isNotBlank()) selected else getCurrentText()

        if (textToCopy.isBlank()) {
            Toast.makeText(this, "Nothing to copy", Toast.LENGTH_SHORT).show()
            return
        }

        val clip = ClipData.newPlainText("Stremini", textToCopy)
        clipboardManager.setPrimaryClip(clip)
        saveClipboardEntry(textToCopy)
        Toast.makeText(this, "Copied to clipboard", Toast.LENGTH_SHORT).show()
    }

    private fun showClipboardHistory(anchor: View) {
        val history = getClipboardHistory()
        if (history.isEmpty()) {
            handleClipboardCopy()
            return
        }

        val popup = PopupMenu(this, anchor)
        history.forEachIndexed { index, item ->
            val label = if (item.length > 40) "${item.take(40)}…" else item
            popup.menu.add(Menu.NONE, index, index, label)
        }
        popup.setOnMenuItemClickListener { menuItem ->
            val chosen = history.getOrNull(menuItem.itemId).orEmpty()
            if (chosen.isNotBlank()) {
                currentInputConnection?.commitText(chosen, 1)
                true
            } else {
                false
            }
        }
        popup.show()
    }

    private fun saveClipboardEntry(value: String) {
        val sanitized = value.trim()
        if (sanitized.isBlank()) return

        val deduped = getClipboardHistory().toMutableList().apply {
            removeAll { it == sanitized }
            add(0, sanitized)
            if (size > CLIPBOARD_HISTORY_LIMIT) {
                subList(CLIPBOARD_HISTORY_LIMIT, size).clear()
            }
        }

        sharedPrefs.edit()
            .putString(CLIPBOARD_HISTORY_KEY, JSONArray(deduped).toString())
            .apply()
    }

    private fun getClipboardHistory(): List<String> {
        val raw = sharedPrefs.getString(CLIPBOARD_HISTORY_KEY, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val item = arr.optString(i)
                    if (item.isNotBlank()) add(item)
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun animateKey(view: View, isPressed: Boolean) {
        val scale = if (isPressed) 0.92f else 1.0f
        val duration = if (isPressed) 30L else 60L // Extra-snappy for smoother perceived input latency

        view.animate().cancel()
        view.animate()
            .scaleX(scale)
            .scaleY(scale)
            .setDuration(duration)
            .setInterpolator(if (isPressed) pressInterpolator else releaseInterpolator)
            .start()
    }

    private fun showKeyboardSwitcher() {
        val switched = switchToNextInputMethod(false)
        if (!switched) {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.showInputMethodPicker()
        }
    }

    private fun updateShiftState() {
        val alpha = if (isShiftOn && !isSymbolsMode) 1.0f else 0.5f
        shiftKeyView?.alpha = alpha
        letterKeyViews.forEach { tv ->
            val keyId = tv.id
            val base = alphaNumericKeyMap[keyId] ?: return@forEach
            tv.text = if (isShiftOn && !isSymbolsMode) base.uppercase() else base.lowercase()
        }
    }

    private fun updateKeyboardLabels() {
        alphaNumericKeyMap.keys.forEach { id ->
            val view = keyTextViewCache[id] ?: keyboardRootView?.findViewById<TextView>(id)
            val text = if (isSymbolsMode) {
                symbolsKeyMap[id]
            } else {
                val base = alphaNumericKeyMap[id]
                if (base != null && isShiftOn && base.length == 1 && base[0].isLetter()) base.uppercase() else base
            }
            if (view != null && !text.isNullOrEmpty()) {
                view.text = text
            }
        }

        symbolsKeyView?.text = if (isSymbolsMode) "ABC" else "123#+"
        shiftKeyView?.isEnabled = !isSymbolsMode
        updateShiftState()
        updateEnterKeyLabel(currentInputEditorInfo)
    }

    private fun updateEnterKeyLabel(info: EditorInfo?) {
        val action = info?.imeOptions?.and(EditorInfo.IME_MASK_ACTION) ?: EditorInfo.IME_ACTION_NONE
        val label = when (action) {
            EditorInfo.IME_ACTION_GO -> "go"
            EditorInfo.IME_ACTION_SEARCH -> "search"
            EditorInfo.IME_ACTION_SEND -> "send"
            EditorInfo.IME_ACTION_NEXT -> "next"
            EditorInfo.IME_ACTION_DONE -> "done"
            else -> "return"
        }
        enterKeyView?.text = label
    }

    private fun handleUndo() {
        val ic = currentInputConnection ?: return
        val undone = ic.performContextMenuAction(android.R.id.undo)
        if (undone) return

        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_CTRL_LEFT))
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_Z))
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_Z))
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_CTRL_LEFT))
    }

    private fun toggleKeyboardMode() {
        isAiFeatureMode = !isAiFeatureMode
        updateKeyboardModeUi()
        if (!isAiFeatureMode) {
            showKeyboardSwitcher()
        }
        Toast.makeText(
            this,
            if (isAiFeatureMode) "AI tools enabled" else "Switched to system keyboard mode",
            Toast.LENGTH_SHORT
        ).show()
    }

    private fun updateKeyboardModeUi() {
        val root = keyboardRootView ?: return
        val quickActions = root.findViewById<LinearLayout>(R.id.quick_actions_container)
        val improve = root.findViewById<View>(R.id.action_improve)
        val complete = root.findViewById<View>(R.id.action_complete)
        val tone = root.findViewById<View>(R.id.action_tone)
        val translate = root.findViewById<View>(R.id.action_translate)
        val modeToggle = root.findViewById<TextView>(R.id.action_undo)
        val clipboard = root.findViewById<View>(R.id.key_clipboard)
        val emoji = root.findViewById<View>(R.id.key_switch_keyboard)

        improve?.visibility = if (isAiFeatureMode) View.VISIBLE else View.GONE
        complete?.visibility = if (isAiFeatureMode) View.VISIBLE else View.GONE
        tone?.visibility = if (isAiFeatureMode) View.VISIBLE else View.GONE
        translate?.visibility = if (isAiFeatureMode) View.VISIBLE else View.GONE

        quickActions?.visibility = View.VISIBLE
        modeToggle?.text = if (isAiFeatureMode) "↻" else "✨ AI"

        // Clipboard and emoji should come from the normal system keyboard, not Stremini IME keys.
        clipboard?.visibility = View.GONE
        emoji?.visibility = View.GONE
    }

    private fun setupAiAction(root: View, id: Int, action: String) {
        root.findViewById<View>(id)?.setOnClickListener { 
            feedback(it)
            handleAiAction(action) 
        }
    }

    private fun setupToneAction(root: View) {
        root.findViewById<View>(R.id.action_tone)?.setOnClickListener { view ->
            feedback(view)
            val tones = listOf(
                "professional",
                "friendly",
                "confident",
                "casual",
                "formal",
                "empathetic",
                "concise",
                "persuasive"
            )

            val popup = PopupMenu(this, view)
            tones.forEachIndexed { index, tone ->
                val title = if (tone == selectedTone) "✓ ${tone.replaceFirstChar { it.uppercase() }}" else tone.replaceFirstChar { it.uppercase() }
                popup.menu.add(Menu.NONE, index, index, title)
            }
            popup.setOnMenuItemClickListener { item ->
                selectedTone = tones[item.itemId]
                handleAiAction("tone")
                true
            }
            popup.show()
        }
    }


    private fun setupTranslateAction(root: View) {
        root.findViewById<View>(R.id.action_translate)?.setOnClickListener { view ->
            feedback(view)
            showTranslateLanguagePicker(view)
        }
    }

    private fun showTranslateLanguagePicker(anchor: View) {
        serviceScope.launch(Dispatchers.IO) {
            val source = if (translationLanguages.isNotEmpty()) {
                translationLanguages
            } else {
                imeBackendClient.fetchTranslationLanguages().getOrNull().orEmpty()
            }

            val displayLanguages = source
                .filter { (code, name) -> code.isNotBlank() && name.isNotBlank() }
                .distinctBy { it.first.lowercase() }
                .let { fetched ->
                    if (fetched.isEmpty()) {
                        defaultMajorLanguages
                    } else {
                        val majorByCode = defaultMajorLanguages.associateBy { it.first.lowercase() }
                        val fetchedByCode = fetched.associateBy { it.first.lowercase() }
                        defaultMajorLanguages.mapNotNull { fetchedByCode[it.first.lowercase()] ?: majorByCode[it.first.lowercase()] }
                    }
                }

            translationLanguages = if (displayLanguages.isEmpty()) defaultMajorLanguages else displayLanguages

            withContext(Dispatchers.Main) {
                val popup = PopupMenu(this@StreminiIME, anchor)
                translationLanguages.forEachIndexed { index, (code, name) ->
                    popup.menu.add(Menu.NONE, index, index, "$name (${code.uppercase()})")
                }

                popup.setOnMenuItemClickListener { item ->
                    val language = translationLanguages.getOrNull(item.itemId) ?: return@setOnMenuItemClickListener false
                    translateCurrentText(language.first, language.second)
                    true
                }
                popup.show()
            }
        }
    }

    private fun translateCurrentText(targetLanguageCode: String, targetLanguageName: String) {
        val originalText = getCurrentText()
        if (originalText.isBlank()) {
            Toast.makeText(this, "Type something to translate", Toast.LENGTH_SHORT).show()
            return
        }

        Toast.makeText(this, "Translating to $targetLanguageName...", Toast.LENGTH_SHORT).show()
        serviceScope.launch(Dispatchers.IO) {
            val translated = imeBackendClient.translateText(
                text = originalText,
                targetLanguage = targetLanguageCode
            ).getOrNull().orEmpty()

            withContext(Dispatchers.Main) {
                if (translated.isBlank()) {
                    Toast.makeText(this@StreminiIME, "Translation failed", Toast.LENGTH_SHORT).show()
                    return@withContext
                }
                replaceFullText(translated)
                Toast.makeText(this@StreminiIME, "Translated to $targetLanguageName", Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        // Detect App Context
        currentAppContext = when (info?.packageName) {
            "com.whatsapp", "com.facebook.orca" -> "messaging"
            "com.google.android.gm" -> "email"
            else -> "general"
        }
        updateEnterKeyLabel(info)
        updateKeyboardLabels()
        updateKeyboardModeUi()
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
    }
}
