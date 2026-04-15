// ─────────────────────────────────────────────────────────────────────────────
// keyboard_service.dart  —  FIX: AI Keyboard crash on sidebar tap
//
// ROOT CAUSE: The crash was caused by calling openKeyboardSettingsActivity()
// without null-checking the platform channel result and without a try/catch
// at the call site in home_screen.dart. The drawer tap called
// ref.read(keyboardServiceProvider).openKeyboardSettingsActivity() directly,
// which threw a PlatformException on some devices when the activity intent
// could not be resolved, and the uncaught exception crashed the app.
//
// FIX:
//   1. All channel calls now have granular try/catch that returns a typed
//      result instead of throwing.
//   2. Added openKeyboardSetupSafe() which wraps the three-step setup flow
//      (isEnabled → isSelected → open appropriate screen) entirely inside
//      the service, so call-sites never need to handle PlatformException.
//   3. openKeyboardSettingsActivity() no longer throws — it returns bool.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class KeyboardService {
  static const MethodChannel _channel = MethodChannel('stremini.keyboard');

  // ── Raw channel wrappers (never throw) ──────────────────────────────────

  Future<bool> isKeyboardEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? enabled = await _channel.invokeMethod<bool>('isKeyboardEnabled');
      return enabled ?? false;
    } on PlatformException catch (e) {
      debugPrint('[KeyboardService] isKeyboardEnabled error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[KeyboardService] isKeyboardEnabled unexpected: $e');
      return false;
    }
  }

  Future<bool> isKeyboardSelected() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? selected = await _channel.invokeMethod<bool>('isKeyboardSelected');
      return selected ?? false;
    } on PlatformException catch (e) {
      debugPrint('[KeyboardService] isKeyboardSelected error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[KeyboardService] isKeyboardSelected unexpected: $e');
      return false;
    }
  }

  Future<void> openKeyboardSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openKeyboardSettings');
    } on PlatformException catch (e) {
      debugPrint('[KeyboardService] openKeyboardSettings error: ${e.message}');
    } catch (e) {
      debugPrint('[KeyboardService] openKeyboardSettings unexpected: $e');
    }
  }

  Future<void> showKeyboardPicker() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('showKeyboardPicker');
    } on PlatformException catch (e) {
      debugPrint('[KeyboardService] showKeyboardPicker error: ${e.message}');
    } catch (e) {
      debugPrint('[KeyboardService] showKeyboardPicker unexpected: $e');
    }
  }

  /// FIX: was throwing PlatformException when activity intent was unresolvable.
  /// Now returns true on success, false on any error — never throws.
  Future<bool> openKeyboardSettingsActivity() async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod('openKeyboardSettingsActivity');
      return true;
    } on PlatformException catch (e) {
      debugPrint('[KeyboardService] openKeyboardSettingsActivity PlatformException: ${e.message}');
      // Fallback: try the generic keyboard settings screen
      try {
        await _channel.invokeMethod('openKeyboardSettings');
        return true;
      } catch (_) {
        return false;
      }
    } catch (e) {
      debugPrint('[KeyboardService] openKeyboardSettingsActivity unexpected: $e');
      return false;
    }
  }

  Future<KeyboardStatus> checkKeyboardStatus() async {
    final enabled = await isKeyboardEnabled();
    final selected = await isKeyboardSelected();
    return KeyboardStatus(isEnabled: enabled, isSelected: selected);
  }

  // ── FIX: Safe three-step setup flow used by drawer tap ─────────────────
  //
  // Call this from the drawer instead of openKeyboardSettingsActivity() directly.
  // Returns a [KeyboardSetupResult] describing what happened so the UI can show
  // the right snack-bar message.
  Future<KeyboardSetupResult> openKeyboardSetupSafe() async {
    try {
      final status = await checkKeyboardStatus();

      if (!status.isEnabled) {
        await openKeyboardSettings();
        return KeyboardSetupResult.openedSettings;
      }

      if (!status.isSelected) {
        await showKeyboardPicker();
        return KeyboardSetupResult.openedPicker;
      }

      // Already fully configured
      return KeyboardSetupResult.alreadyActive;
    } catch (e) {
      debugPrint('[KeyboardService] openKeyboardSetupSafe error: $e');
      return KeyboardSetupResult.error;
    }
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class KeyboardStatus {
  final bool isEnabled;
  final bool isSelected;

  const KeyboardStatus({
    required this.isEnabled,
    required this.isSelected,
  });

  bool get isActive => isEnabled && isSelected;
  bool get needsSetup => !isEnabled || !isSelected;
}

enum KeyboardSetupResult {
  openedSettings,
  openedPicker,
  alreadyActive,
  error,
}