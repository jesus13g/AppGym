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

// Escape para `file_picker` bajo AGP 9 con `android.builtInKotlin=false` (ver
// android/app/build.gradle.kts, que aplica el mismo plugin por la misma razón).
//
// `file_picker` 11.x deja de aplicar el KGP clásico en su propio build.gradle en cuanto detecta
// AGP 9 o superior, asumiendo que el Kotlin integrado compilará sus fuentes. Pero aquí el Kotlin
// integrado está apagado a propósito: lo necesita `share_plus`, que sigue aplicando KGP sin
// ninguna condición y chocaría con el Kotlin integrado si estuviera activo. Con los dos plugins
// resolviendo AGP 9 de maneras opuestas, ninguno de los dos valores de `builtInKotlin` sirve a la
// vez para los dos, así que aquí se le aplica a `file_picker` desde fuera el mismo plugin que él
// mismo se salta. Se retira cuando el paquete deje de mirar solo la versión de AGP y respete la
// propiedad `android.builtInKotlin`.
//
// `withPlugin` y no aplicarlo a las primeras de cambio: el plugin de Kotlin necesita que
// `com.android.library` ya esté aplicado —para encontrar su extensión `android {}`—, y
// `subprojects {}` se ejecuta antes de que el propio build.gradle de cada módulo corra el suyo.
subprojects {
    if (project.name == "file_picker") {
        pluginManager.withPlugin("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
