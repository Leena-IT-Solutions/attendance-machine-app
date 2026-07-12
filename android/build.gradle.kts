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
    
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        val targetCompatibility = android?.compileOptions?.targetCompatibility
        
        compilerOptions {
            if (targetCompatibility != null) {
                val versionStr = targetCompatibility.toString()
                if (versionStr == "1.8" || versionStr == "8" || versionStr == "VERSION_1_8") {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
                } else if (versionStr == "11" || versionStr == "VERSION_11") {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
                } else if (versionStr == "17" || versionStr == "VERSION_17") {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                } else if (versionStr == "21" || versionStr == "VERSION_21") {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
                } else {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            } else {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
