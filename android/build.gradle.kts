allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

// -----------------------------------------------------------------
// Two `subprojects { … }` blocks in a specific order — see
// gray_part_pitfalls.md §7.  The `afterEvaluate` override MUST be
// registered BEFORE the `evaluationDependsOn(":app")` block,
// otherwise Gradle refuses to attach the callback because target
// projects have already been evaluated.
// -----------------------------------------------------------------
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Some plugin releases still hard-code compileSdk = 34, while their
    // transitive dependencies (flutter_plugin_android_lifecycle, etc.)
    // require 36.  Force every Android library subproject up to 36 so
    // Gradle's CheckAarMetadata does not abort the build.
    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
