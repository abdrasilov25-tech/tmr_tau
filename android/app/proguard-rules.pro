# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Supabase / Realtime
-keep class io.github.jan.supabase.** { *; }

# Agora
-keep class io.agora.** { *; }

# Google Maps
-keep class com.google.android.gms.maps.** { *; }

# Firebase (стек-трейсы Crashlytics)
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# FlutterFire (Pigeon): без этого в release возможен channel-error на initializeCore / FCM.
-keep class io.flutter.plugins.firebase.** { *; }
-dontwarn io.flutter.plugins.firebase.**

# Keep model classes used by Gson/Serialization
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
