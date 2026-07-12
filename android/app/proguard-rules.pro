# -----------------------------------------------------------
# ProGuard / R8 rules for Scarab Golden (release + minified).
#
# Only the strictly-required keeps are listed — everything else
# is safe to obfuscate.
# -----------------------------------------------------------

# --- Flutter / Play Core -----------------------------------
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.play.core.**

# --- Firebase & AppCheck -----------------------------------
-dontwarn com.google.firebase.**
-keep class com.google.firebase.** { *; }

# --- AppsFlyer ---------------------------------------------
-keep class com.appsflyer.** { *; }
-dontwarn com.appsflyer.**

# --- Local notifications (uses reflection for the receiver) -
-keep class com.dexterous.** { *; }

# --- WebView JavaScript bridge (kept just in case a partner
#     site uses postMessage-style bridges in the future). -----
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
