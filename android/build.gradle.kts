allprojects {
    repositories {
        google()
        mavenCentral()

        // Optional mirror for environments where official Maven repos are slow.
        // Enable with: ./gradlew -PuseAliyunMaven=true ...
        val useAliyunMaven =
            (findProperty("useAliyunMaven") as String?)?.toBoolean() == true
        if (useAliyunMaven) {
            maven(url = "https://maven.aliyun.com/repository/google")
            maven(url = "https://maven.aliyun.com/repository/central")
            maven(url = "https://maven.aliyun.com/repository/public")
        }
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
