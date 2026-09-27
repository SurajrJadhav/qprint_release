# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter references Play Core for deferred components; we don't use them in release APK.
# Allow missing Play Core classes so R8 does not fail.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# App launcher (namespace com.qprintsolutions.qprint)
-keep class com.qprintsolutions.qprint.MainActivity { *; }

# Razorpay
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**

# Google Play Services / Maps
-keep class com.google.android.gms.** { *; }
-keep class com.google.android.geo.** { *; }
-dontwarn com.google.android.gms.**

# Firebase / FCM (required for push in release; debug works without these)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.iid.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn com.google.firebase.**

# flutter_secure_storage (Tink/KeyStore)
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# Geolocator / location
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
