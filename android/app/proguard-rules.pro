# R8 rules for the release build (the default Android optimisation rules are added by the build file).
#
# The app has no reflection of its own. The only thing R8 cannot see through is kotlinx.serialization: the generated serializers of the
# workout data classes are looked up by name through `Companion.serializer()` / `$$serializer`, so they are kept.

-keepattributes *Annotation*, InnerClasses, Signature, RuntimeVisibleAnnotations
-dontnote kotlinx.serialization.AnnotationsKt

# kotlinx.serialization.json
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# The serializable model of the strength core (and the sealed WorkoutAction / UndoPayload hierarchies).
-keep,includedescriptorclasses class health.pulse.strength.core.**$$serializer { *; }
-keepclassmembers class health.pulse.strength.core.** {
    *** Companion;
}
-keepclasseswithmembers class health.pulse.strength.core.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Keep readable crash reports: line numbers survive, the source file name is hidden.
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
