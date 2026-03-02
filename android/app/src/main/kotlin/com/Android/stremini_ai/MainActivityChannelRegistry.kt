package com.Android.stremini_ai

import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivityChannelRegistry(
    private val activity: MainActivity,
    private val actions: Actions,
) {
    data class Actions(
        val hasOverlayPermission: () -> Boolean,
        val requestOverlayPermission: () -> Unit,
        val hasAccessibilityPermission: () -> Boolean,
        val requestAccessibilityPermission: () -> Unit,
        val hasMicrophonePermission: () -> Boolean,
        val requestMicrophonePermission: () -> Unit,
        val startScreenScan: () -> Unit,
        val stopScreenScan: () -> Unit,
        val startOverlayService: () -> Unit,
        val stopOverlayService: () -> Unit,
        val isKeyboardEnabled: () -> Boolean,
        val isKeyboardSelected: () -> Boolean,
        val openKeyboardSettings: () -> Unit,
        val showKeyboardPicker: () -> Unit,
        val openKeyboardSettingsActivity: () -> Unit,
        val setEventSink: (EventChannel.EventSink?) -> Unit,
    )

    fun register(flutterEngine: FlutterEngine) {
        registerOverlayChannel(flutterEngine)
        registerScannerChannel(flutterEngine)
        registerKeyboardChannel(flutterEngine)
        registerEventChannel(flutterEngine)
    }

    private fun registerOverlayChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stremini.chat.overlay")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasOverlayPermission" -> result.success(actions.hasOverlayPermission())
                    "requestOverlayPermission" -> { actions.requestOverlayPermission(); result.success(true) }
                    "hasAccessibilityPermission" -> result.success(actions.hasAccessibilityPermission())
                    "requestAccessibilityPermission" -> { actions.requestAccessibilityPermission(); result.success(true) }
                    "hasMicrophonePermission" -> result.success(actions.hasMicrophonePermission())
                    "requestMicrophonePermission" -> { actions.requestMicrophonePermission(); result.success(true) }
                    "startScreenScan" -> handleAccessibilityGate(result) { actions.startScreenScan() }
                    "startOverlayService" -> { actions.startOverlayService(); result.success(true) }
                    "stopOverlayService" -> { actions.stopOverlayService(); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerScannerChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stremini.screen.scanner")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAccessibilityPermission" -> result.success(actions.hasAccessibilityPermission())
                    "requestAccessibilityPermission" -> { actions.requestAccessibilityPermission(); result.success(true) }
                    "startScanning" -> handleAccessibilityGate(result) { actions.startScreenScan() }
                    "stopScanning" -> { actions.stopScreenScan(); result.success(true) }
                    "isScanning" -> result.success(ScreenReaderService.isScanningActive())
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerKeyboardChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stremini.keyboard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isKeyboardEnabled" -> result.success(actions.isKeyboardEnabled())
                    "isKeyboardSelected" -> result.success(actions.isKeyboardSelected())
                    "openKeyboardSettings" -> { actions.openKeyboardSettings(); result.success(true) }
                    "showKeyboardPicker" -> { actions.showKeyboardPicker(); result.success(true) }
                    "openKeyboardSettingsActivity" -> {
                        runCatching { actions.openKeyboardSettingsActivity() }
                            .onSuccess { result.success(true) }
                            .onFailure {
                                Log.e("MainActivity", "Error opening keyboard settings", it)
                                result.error("ERROR", "Failed to open keyboard settings: ${it.message}", null)
                            }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerEventChannel(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "stremini.chat.overlay/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) = actions.setEventSink(events)
                override fun onCancel(arguments: Any?) = actions.setEventSink(null)
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.Android.stremini_ai")
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "startScanner", "stopScanner" -> result.success(true)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleAccessibilityGate(result: MethodChannel.Result, action: () -> Unit) {
        if (actions.hasAccessibilityPermission()) {
            action()
            result.success(true)
        } else {
            result.error("NO_PERMISSION", "Accessibility service not enabled", null)
        }
    }
}
