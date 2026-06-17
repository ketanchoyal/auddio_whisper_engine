import java.io.FileOutputStream
import java.net.URL
import java.security.MessageDigest

group = "app.audiio.auddio_whisper_engine"
version = "0.0.1"

plugins {
    id("com.android.library")
}

android {
    namespace = "app.audiio.auddio_whisper_engine"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }
}

val RELEASE_TAG = "whisper-v0.0.1"
val RELEASE_BASE_URL =
    "https://github.com/ketanchoyal/audiio/releases/download/$RELEASE_TAG"

// TODO(release): replace each sha256 after running native/scripts/build_android.sh
// + checksums.sh and uploading per-ABI libauddio_whisper.so to GitHub Releases.
val downloadWhisperLibraries = tasks.register("downloadWhisperLibraries") {
    val abis = mapOf(
        "arm64-v8a" to mapOf(
            "file" to "libauddio_whisper-arm64-v8a.so",
            "sha256" to "REPLACE_WITH_ARM64_V8A_SHA256"
        ),
        "armeabi-v7a" to mapOf(
            "file" to "libauddio_whisper-armeabi-v7a.so",
            "sha256" to "REPLACE_WITH_ARMEABI_V7A_SHA256"
        ),
        "x86_64" to mapOf(
            "file" to "libauddio_whisper-x86_64.so",
            "sha256" to "REPLACE_WITH_X86_64_SHA256"
        )
    )

    doLast {
        val jniLibsDir = file("src/main/jniLibs")
        val abiFilters = android.defaultConfig.ndk.abiFilters.ifEmpty { abis.keys }
        abis.filter { it.key in abiFilters }.forEach { (abi, info) ->
            val expectedHash = info["sha256"]!!
            val abiDir = file("$jniLibsDir/$abi")
            if (!abiDir.exists()) abiDir.mkdirs()
            val targetFile = file("$abiDir/libauddio_whisper.so")

            if (targetFile.exists() && sha256(targetFile) == expectedHash) return@forEach
            if (targetFile.exists()) targetFile.delete()

            val url = "$RELEASE_BASE_URL/${info["file"]}"
            println("Downloading libauddio_whisper.so for $abi from $url")
            URL(url).openStream().use { input ->
                FileOutputStream(targetFile).use { output -> input.copyTo(output) }
            }
            if (sha256(targetFile) != expectedHash) {
                targetFile.delete()
                throw GradleException("SHA-256 verification failed for $abi")
            }
        }
    }
}

fun sha256(f: java.io.File): String =
    MessageDigest.getInstance("SHA-256").digest(f.readBytes())
        .joinToString("") { "%02x".format(it) }

tasks.configureEach {
    if (name.contains("preBuild")) {
        dependsOn(downloadWhisperLibraries)
    }
}
