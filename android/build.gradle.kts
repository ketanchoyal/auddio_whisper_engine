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

// Private release: fetched via `gh release download` (authenticated). Requires
// gh on PATH + 'gh auth login' (or GH_TOKEN/GITHUB_TOKEN in CI).
val RELEASE_TAG = "whisper-v0.0.1"
val RELEASE_REPO = "ketanchoyal/auddio_whisper_engine"
val downloadWhisperLibraries = tasks.register("downloadWhisperLibraries") {
    val abis = mapOf(
        "arm64-v8a" to mapOf(
            "asset" to "libauddio_whisper-arm64-v8a.so",
            "sha256" to "803e9dced8f01ce953d3ba4de16c72ab3150b0b24aafa042e09ea6d28e2ac942"
        ),
        "armeabi-v7a" to mapOf(
            "asset" to "libauddio_whisper-armeabi-v7a.so",
            "sha256" to "9919c78011a3e934679f16ce446af296290e2c90f32301633091ae1c92934c96"
        ),
        "x86_64" to mapOf(
            "asset" to "libauddio_whisper-x86_64.so",
            "sha256" to "6c2e5dd41360e5eafeec15b794864d78d12c65308e6052cf3a3ea83e7f31d70d"
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

            val asset = info["asset"]!!
            println("Downloading $asset for $abi via gh release download")
            val proc = ProcessBuilder(
                "gh", "release", "download", RELEASE_TAG,
                "--repo", RELEASE_REPO,
                "--pattern", asset,
                "--output", targetFile.absolutePath,
                "--clobber"
            ).redirectErrorStream(true).start()
            val output = proc.inputStream.bufferedReader().readText()
            if (proc.waitFor() != 0) {
                throw GradleException(
                    "gh release download failed for $abi ($asset). " +
                        "Ensure gh is installed and authenticated.\n$output"
                )
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
