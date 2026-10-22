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

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force a consistent JVM target (Java 17) for the app and every plugin module.
// Plugins such as home_widget and receive_sharing_intent declare Java 1.8 / 11
// in their own build scripts, which clashes with the app's Java 17 and makes
// Gradle fail with "Inconsistent JVM Target Compatibility Between Java and
// Kotlin Tasks".
//
// `gradle.projectsEvaluated` runs after every project (and after AGP's own
// afterEvaluate callbacks, which re-create the compile tasks), so the values
// set here are the last ones applied and therefore win.
gradle.projectsEvaluated {
    rootProject.allprojects.forEach { sub ->
        sub.tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
            sourceCompatibility = "17"
            targetCompatibility = "17"
        }
        sub.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
