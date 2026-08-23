import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Выравнивание JVM-таргета Kotlin под Java КАЖДОГО модуля: flutter_js и
// прочие плагины задают свои kotlinOptions (1.8), а AGP-модули имеют разные
// java-таргеты (11/17) — KGP роняет сборку на проверке консистентности.
// Читаем compileOptions.targetCompatibility модуля рефлексией (AGP-типы
// недоступны в корневом класспасе) и ставим Kotlin туда же.
fun Project.androidJavaTargetCompatibility(): String? = runCatching {
    val androidExt = extensions.findByName("android") ?: return@runCatching null
    val getCompileOptions = androidExt.javaClass.methods
        .firstOrNull { it.name == "getCompileOptions" } ?: return@runCatching null
    val opts = getCompileOptions.invoke(androidExt)
    val getTarget = opts.javaClass.methods
        .firstOrNull { it.name == "getTargetCompatibility" } ?: return@runCatching null
    val value = getTarget.invoke(opts)?.toString() ?: return@runCatching null
    value.substringAfterLast('.').removePrefix("JAVA_") // e.g. "11", "17"
}.getOrNull()

subprojects {
    afterEvaluate {
        plugins.withId("org.jetbrains.kotlin.android") {
            val target = androidJavaTargetCompatibility()
            if (target != null) {
                tasks.withType<KotlinCompile>().configureEach {
                    compilerOptions.jvmTarget.set(JvmTarget.fromTarget(target))
                }
            }
        }
    }
}
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
