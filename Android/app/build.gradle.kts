import java.io.FileInputStream
import java.util.Properties

plugins {
	id("com.android.application")
}

android {
	buildToolsVersion = "37.0.0"
	compileSdk = 37
	ndkVersion = "30.0.16248370"
	namespace = "com.multicraft.game"

	val versionMajor = rootProject.extra["versionMajor"] as Int
	val versionMinor = rootProject.extra["versionMinor"] as Int
	val versionPatch = rootProject.extra["versionPatch"] as Int

	defaultConfig {
		applicationId = "com.mycraft.game"
		minSdk = 23
		targetSdk = 37
		versionName = "$versionMajor.$versionMinor.$versionPatch"
		versionCode = rootProject.extra["versionCode"] as Int
	}

	// Load keystore properties if present
	val props = Properties()
	val propFile = rootProject.file("local.properties")
	if (propFile.exists()) {
		props.load(FileInputStream(propFile))
	}

	if (props.getProperty("keystore") != null) {
		signingConfigs {
			create("release") {
				storeFile = file(props["keystore"]!!)
				storePassword = props["keystore.password"] as String?
				keyAlias = props["key"] as String?
				keyPassword = props["key.password"] as String?
			}
		}

		buildTypes {
			getByName("release") {
				isMinifyEnabled = true
				isShrinkResources = true
				signingConfig = signingConfigs.getByName("release")
				proguardFiles(
					getDefaultProguardFile("proguard-android-optimize.txt"),
					"proguard-rules.pro",
					"proguard-rules-sdl.pro"
				)
			}
			getByName("debug") {
				isDebuggable = true
				isMinifyEnabled = false
			}
		}
	}

	splits {
		abi {
			isEnable = true
			reset()
			include("armeabi-v7a", "arm64-v8a", "x86_64")
			isUniversalApk = true // MyCraft: also build one APK that installs on almost every device
		}
	}

	compileOptions {
		sourceCompatibility = JavaVersion.VERSION_17
		targetCompatibility = JavaVersion.VERSION_17
	}

	buildFeatures {
		viewBinding = true
		buildConfig = true
	}

	androidResources {
		// zipAssetsFiles already deflated it
		noCompress += "assets.zip"
	}
}

val prepareAssetsFiles = tasks.register("prepareAssetsFiles") {
	description = "Prepare assets"
	// The Irrlicht OGLES2 shaders staged below come from the downloaded
	// native dependencies. Without this dependency, parallel builds on a
	// clean machine can pack assets.zip BEFORE those deps are unpacked,
	// silently producing an APK whose main menu cannot render (blue screen).
	dependsOn(":native:getDeps")
	val assetsFolder = "build/assets/Files"
	val projRoot = "../../"

	doLast {
		copy {
			from("$projRoot/builtin")
			into("$assetsFolder/builtin")
		}
		copy {
			from("$projRoot/client/shaders")
			into("$assetsFolder/client/shaders")
		}
		copy {
			from("../native/deps/irrlicht/shaders")
			into("$assetsFolder/client/shaders/Irrlicht")
		}
		copy {
			from(
				"$projRoot/fonts/DroidSansFallback.ttf",
				"$projRoot/fonts/MultiCraftFont.ttf"
			)
			into("$assetsFolder/fonts")
		}
		copy {
			from("$projRoot/textures")
			into("$assetsFolder/textures")
			exclude("*.txt")
		}
		// MyCraft: bundle built-in mods (areas, mycraft_homes).
		// They end up in <internal storage>/mods after assets extraction and can be
		// enabled per-world from the "Select Mods" screen.
		copy {
			from("../custom_mods")
			into("$assetsFolder/mods")
		}
		// Fail loudly rather than ship an APK with no OGLES2 shaders:
		// without them the Irrlicht 2D renderer cannot draw anything and
		// the app shows only a blue screen on device.
		for (shader in listOf("COGLES2Solid.vsh", "COGLES2Solid.fsh",
				"COGLES2Renderer2D.vsh", "COGLES2Renderer2D.fsh")) {
			val shaderFile = file("$assetsFolder/client/shaders/Irrlicht/$shader")
			if (!shaderFile.exists()) {
				throw GradleException("Missing Irrlicht shader in staged assets: " +
					"$shaderFile - :native deps must be unpacked before packing assets")
			}
		}
	}
}

val zipAssetsFiles = tasks.register<Zip>("zipAssetsFiles") {
	description = "Compress assets"
	dependsOn(prepareAssetsFiles)
	archiveFileName.set("assets.zip")
	destinationDirectory.set(file("src/main/assets"))
	from("build/assets/Files")

	val projRoot = "../../"
	copy {
		from("$projRoot/client/cacert.pem")
		into(file("src/main/assets"))
	}
}

tasks.named("preBuild") {
	dependsOn(zipAssetsFiles)
}

dependencies {
	/* MultiCraft Native */
	implementation(project(":native"))

	/* Third-party libraries */
	implementation("androidx.appcompat:appcompat:1.8.0")
	implementation("androidx.appcompat:appcompat-resources:1.8.0")
	implementation("androidx.browser:browser:1.10.0")
	implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.11.0")
	implementation("com.google.android.material:material:1.14.0")
}
