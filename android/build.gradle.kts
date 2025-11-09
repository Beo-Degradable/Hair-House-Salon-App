// Removed explicit plugins DSL declaration of google-services (4.4.4) to avoid
// version conflict with the one already on the classpath (4.3.15 provided by Flutter tooling).
// If you want to upgrade, do it via buildscript classpath in Android (Groovy) builds,
// but for Kotlin DSL Flutter template relying on classpath injection you can omit it.

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
