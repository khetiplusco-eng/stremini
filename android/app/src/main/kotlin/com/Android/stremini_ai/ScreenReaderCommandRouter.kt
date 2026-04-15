package com.Android.stremini_ai

import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo

class ScreenReaderCommandRouter {
    data class Actions(
        val globalAction: (Int) -> Boolean,
        val takeScreenshot: () -> Boolean,
        val performScroll: (Int) -> Boolean,
        val scrollToTop: () -> Boolean,
        val scrollToBottom: () -> Boolean,
        val clickNodeByText: (String) -> Boolean,
        val longClickNodeByText: (String) -> Boolean,
        val performSwipe: (String) -> Boolean,
        val typeIntoFocusedField: (String) -> Boolean,
        val performSearch: (String) -> Boolean,
        val fillFieldByHint: (String, String) -> Boolean,
        val openAppByName: (String) -> Boolean,
        val closeCurrentApp: () -> Boolean,
        val openAppSettings: (String) -> Boolean,
        val openSystemSettings: (String) -> Boolean,
        val adjustVolume: (Boolean) -> Boolean,
        val muteDevice: () -> Boolean,
        val unmuteDevice: () -> Boolean,
        val adjustBrightness: (Boolean) -> Boolean,
        val automateWhatsAppMessage: suspend (String, String) -> Boolean,
        val extractContact: (String) -> String,
        val extractMessage: (String) -> String,
        val makePhoneCall: (String) -> Boolean,
        val answerIncomingCall: () -> Boolean,
        val declineIncomingCall: () -> Boolean,
        val openUrl: (String) -> Boolean,
        val sendMediaAction: (String) -> Boolean,
        val sendMediaKey: (Int) -> Boolean,
        val openAppByPackage: (String) -> Boolean,
        val clickNodeByContentDesc: (String) -> Boolean,
        val performSelectAll: () -> Boolean,
        val performCopy: () -> Boolean,
        val performPaste: () -> Boolean,
        val performCut: () -> Boolean,
        val performUndo: () -> Boolean,
        val readScreenContent: () -> Unit,
        val findAndHighlight: (String) -> Boolean,
        val pressEnterKey: () -> Boolean,
        val dragFromTo: (String, String) -> Boolean,
        val performZoom: (Boolean) -> Boolean,
    )

    suspend fun execute(command: String, actions: Actions): Boolean {
        val normalized = command.trim().lowercase()
        if (normalized.isBlank()) return false

        return when {
            normalized.contains("go home") || normalized == "home" -> actions.globalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME)
            normalized.contains("go back") || normalized == "back" -> actions.globalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
            normalized.contains("recent apps") || normalized.contains("app switcher") -> actions.globalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_RECENTS)
            normalized.contains("open notifications") || normalized.contains("notification bar") -> actions.globalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)
            normalized.contains("quick settings") -> actions.globalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS)
            normalized.contains("lock screen") || normalized.contains("lock phone") -> actions.globalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
            normalized.contains("take screenshot") || normalized.contains("screenshot") -> actions.takeScreenshot()
            normalized.contains("power menu") -> actions.globalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_POWER_DIALOG)
            normalized.contains("scroll down") -> actions.performScroll(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
            normalized.contains("scroll up") -> actions.performScroll(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
            normalized.contains("scroll to top") -> actions.scrollToTop()
            normalized.contains("scroll to bottom") -> actions.scrollToBottom()
            normalized.startsWith("tap ") || normalized.startsWith("click ") -> actions.clickNodeByText(normalized.removePrefix("tap ").removePrefix("click ").trim())
            normalized.startsWith("long press ") || normalized.startsWith("long tap ") -> actions.longClickNodeByText(normalized.removePrefix("long press ").removePrefix("long tap ").trim())
            normalized.contains("swipe up") -> actions.performSwipe("up")
            normalized.contains("swipe down") -> actions.performSwipe("down")
            normalized.contains("swipe left") -> actions.performSwipe("left")
            normalized.contains("swipe right") -> actions.performSwipe("right")
            normalized.startsWith("type ") -> actions.typeIntoFocusedField(command.trim().substringAfter("type ").trim())
            normalized.startsWith("search for ") || normalized.startsWith("search ") -> actions.performSearch(command.trim().removePrefix("search for ").removePrefix("Search for ").removePrefix("search ").removePrefix("Search ").trim())
            normalized.startsWith("fill ") && normalized.contains(" with ") -> {
                val parts = normalized.removePrefix("fill ").split(" with ", limit = 2)
                if (parts.size == 2) actions.fillFieldByHint(parts[0].trim(), parts[1].trim()) else false
            }
            normalized.startsWith("open ") || normalized.startsWith("launch ") -> actions.openAppByName(normalized.removePrefix("open ").removePrefix("launch ").trim())
            normalized.startsWith("close ") && (normalized.contains("app") || normalized.contains("tab")) -> actions.closeCurrentApp()
            normalized.contains("force stop") || normalized.contains("kill app") -> actions.openAppSettings(normalized.removePrefix("force stop ").removePrefix("kill app ").trim())
            normalized.contains("open wifi") || normalized.contains("wifi settings") -> actions.openSystemSettings(android.provider.Settings.ACTION_WIFI_SETTINGS)
            normalized.contains("open bluetooth") || normalized.contains("bluetooth settings") -> actions.openSystemSettings("android.settings.BLUETOOTH_SETTINGS")
            normalized.contains("open settings") -> actions.openSystemSettings(android.provider.Settings.ACTION_SETTINGS)
            normalized.contains("open display settings") -> actions.openSystemSettings(android.provider.Settings.ACTION_DISPLAY_SETTINGS)
            normalized.contains("open sound settings") -> actions.openSystemSettings(android.provider.Settings.ACTION_SOUND_SETTINGS)
            normalized.contains("open battery settings") -> actions.openSystemSettings(android.provider.Settings.ACTION_BATTERY_SAVER_SETTINGS)
            normalized.contains("open location settings") -> actions.openSystemSettings(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            normalized.contains("open app settings") || normalized.contains("app permissions") -> actions.openAppSettings(normalized.removePrefix("open app settings for ").removePrefix("open app settings ").trim())
            normalized.contains("open developer options") -> actions.openSystemSettings(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
            normalized.contains("volume up") -> actions.adjustVolume(true)
            normalized.contains("volume down") -> actions.adjustVolume(false)
            normalized.contains("mute") -> actions.muteDevice()
            normalized.contains("unmute") -> actions.unmuteDevice()
            normalized.contains("increase brightness") -> actions.adjustBrightness(true)
            normalized.contains("decrease brightness") || normalized.contains("reduce brightness") -> actions.adjustBrightness(false)
            normalized.contains("whatsapp") && (normalized.contains("message") || normalized.contains("send")) -> {
                val contact = actions.extractContact(command)
                val message = actions.extractMessage(command)
                if (contact.isNotBlank()) actions.automateWhatsAppMessage(contact, message) else false
            }
            normalized.startsWith("call ") -> actions.makePhoneCall(command.trim().substringAfter("call ").trim())
            normalized.contains("answer call") || normalized.contains("pick up") -> actions.answerIncomingCall()
            normalized.contains("decline call") || normalized.contains("reject call") -> actions.declineIncomingCall()
            normalized.startsWith("open website ") || normalized.startsWith("go to ") || normalized.startsWith("browse to ") -> actions.openUrl(command.trim().removePrefix("open website ").removePrefix("go to ").removePrefix("browse to ").trim())
            normalized.contains("play") && (normalized.contains("music") || normalized.contains("video")) -> actions.sendMediaAction(android.content.Intent.ACTION_MEDIA_BUTTON)
            normalized.contains("pause") || normalized.contains("stop music") -> actions.sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_PAUSE)
            normalized.contains("next song") || normalized.contains("next track") -> actions.sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_NEXT)
            normalized.contains("previous song") || normalized.contains("previous track") -> actions.sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            normalized.contains("open camera") -> actions.openAppByPackage("com.android.camera2").let { if (!it) actions.openAppByName("camera") else it }
            normalized.contains("take photo") || normalized.contains("take picture") -> actions.clickNodeByText("shutter") || actions.clickNodeByContentDesc("take photo")
            normalized.contains("select all") -> actions.performSelectAll()
            normalized.contains("copy") -> actions.performCopy()
            normalized.contains("paste") -> actions.performPaste()
            normalized.contains("cut") -> actions.performCut()
            normalized.contains("undo") -> actions.performUndo()
            normalized.contains("read screen") || normalized.contains("what is on screen") -> { actions.readScreenContent(); true }
            normalized.startsWith("find ") -> actions.findAndHighlight(normalized.removePrefix("find ").trim())
            normalized.contains("press enter") || normalized.contains("submit") || normalized.contains("confirm") -> actions.pressEnterKey()
            normalized.contains("cancel") || normalized.contains("dismiss") -> actions.clickNodeByText("cancel") || actions.clickNodeByText("dismiss") || actions.clickNodeByText("no")
            normalized.startsWith("drag ") && normalized.contains(" to ") -> {
                val parts = normalized.removePrefix("drag ").split(" to ", limit = 2)
                if (parts.size == 2) actions.dragFromTo(parts[0].trim(), parts[1].trim()) else false
            }
            normalized.contains("zoom in") -> actions.performZoom(true)
            normalized.contains("zoom out") -> actions.performZoom(false)
            else -> {
                Log.w("ScreenReaderCommandRouter", "Unknown command: $command")
                false
            }
        }
    }
}
