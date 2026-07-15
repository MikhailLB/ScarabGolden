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

# AppsFlyer looks these up via Class.forName() at runtime; without
# an explicit keep R8 either renames them (Google Play Services)
# or prunes them entirely (AdvertisingIdClient — no compile-time
# references beyond reflection).  That was the actual reason
# `gaidError: ClassNotFoundException` + `af_status: Organic` kept
# firing on release APKs — GAID could not be read, so AppsFlyer
# defaulted every install to Organic and the router sent us into
# the arena.
-keep class com.google.android.gms.ads.identifier.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep interface com.google.android.gms.ads.identifier.** { *; }
-keep interface com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# Google Play Install Referrer — AppsFlyer uses this to read the
# raw referrer string set by Play Store when an install originates
# from a paid OneLink click.  Keep the whole client + its AIDL
# service binder classes.
-keep class com.android.installreferrer.** { *; }
-keep interface com.android.installreferrer.** { *; }
-dontwarn com.android.installreferrer.**

# --- Local notifications (uses reflection for the receiver) -
-keep class com.dexterous.** { *; }

# --- WebView JavaScript bridge (kept just in case a partner
#     site uses postMessage-style bridges in the future). -----
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
