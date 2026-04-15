# Add project specific ProGuard rules here.

# Keep Flutter classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep AccessibilityService
-keep class * extends android.accessibilityservice.AccessibilityService { *; }
-keep class com.Android.stremini_ai.ScreenReaderService { *; }

# Keep Service classes
-keep class * extends android.app.Service { *; }
-keep class com.Android.stremini_ai.ChatOverlayService { *; }

# Keep Activity
-keep class com.Android.stremini_ai.MainActivity { *; }

# ML Kit Text Recognition Fix
# This prevents R8 from failing when it can't find the optional language libraries
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }

# Keep OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Keep JSON
-keep class org.json.** { *; }

# Keep Android components
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# Play Core modular migration
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Prevent obfuscation of accessibility service
-keepclassmembers class * extends android.accessibilityservice.AccessibilityService {
    public <init>();
}

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# General Android keep rules
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable