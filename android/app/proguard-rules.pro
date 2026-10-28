# ML Kit GenAI (Gemini Nano) breaks under R8: in release builds
# MlKitContext.get(SharedPrefManager.class) returns null, so the GenAI client
# constructor throws a NullPointerException and the model reports unavailable.
# Keep ML Kit and its component registration intact.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_genai_** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
