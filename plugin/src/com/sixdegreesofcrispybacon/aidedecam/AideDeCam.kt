package com.sixdegreesofcrispybacon.aidedecam

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.os.Build
import android.os.Environment
import android.util.Log
import androidx.core.content.ContextCompat
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class AideDeCam(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val PLUGIN_NAME = "AideDeCam"
		private const val SCHEMA_VER = 1

		private const val MIN_SDK_VERSION = 21
		private const val CONCURRENT_CAMERA_SDK = 30

		private const val CAPABILITIES_BASENAME = "camera_capabilities"
		private const val CAPABILITIES_USER_FILENAME = "${CAPABILITIES_BASENAME}.json"
		private const val CAPABILITIES_TIMESTAMP_FORMAT = "yyyyMMdd_HHmmss"

		private const val MAX_DOCUMENTS_SUBDIR_LENGTH = 512
		private const val MAX_DOCUMENTS_SUBDIR_SEGMENTS = 16

		private const val SIGNAL_CAPABILITIES_UPDATED = "capabilities_updated"
		private const val SIGNAL_CAPABILITIES_WARNING = "capabilities_warning"

		private data class ExposedMethod(
			val name: String,
			val argc: Int,
			val argTypes: List<String> = emptyList(),
			val returnType: String = "String",
			val tags: List<String> = emptyList()
		)

		// Single source of truth for exported surface.
		private val EXPOSED_METHODS: List<ExposedMethod> = listOf(
			ExposedMethod(
				name = "getCameraCapabilities",
				argc = 0,
				tags = listOf("caps", "writes_user")
			),
			ExposedMethod(
				name = "getCameraCapabilitiesToFile",
				argc = 1,
				argTypes = listOf("String"),
				tags = listOf("caps", "writes_user", "writes_documents")
			),
			ExposedMethod(
				name = "getCameraCapabilitiesWithMeta",
				argc = 2,
				argTypes = listOf("String", "String"),
				tags = listOf("caps", "writes_user")
			),
			ExposedMethod(
				name = "getCameraCapabilitiesToFileWithMeta",
				argc = 3,
				argTypes = listOf("String", "String", "String"),
				tags = listOf("caps", "writes_user", "writes_documents")
			),
			ExposedMethod(
				name = "getExposedMethods",
				argc = 0,
				tags = listOf("inventory")
			),
		)
	}


    private data class CapMeta(
        val godotVersion: String?,
        val generatorVersion: String?
    )

    init {
        android.util.Log.i("AideDeCam", "AAR (plugin) initialized!")
    }

    override fun getPluginName() = PLUGIN_NAME

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo(SIGNAL_CAPABILITIES_UPDATED),
        SignalInfo(SIGNAL_CAPABILITIES_WARNING, String::class.java)
    )

		
	// NOTE: Godot JNISingleton introspection (has_method) can be unreliable.
	// We still provide an explicit exported method list here and a runtime inventory via getExposedMethods().
    //override fun getPluginMethods(): List<String> = listOf(
    //"getCameraCapabilities",
    //"getCameraCapabilitiesToFile"
    //)
	
	override fun getPluginMethods(): List<String> =
		EXPOSED_METHODS.map { it.name }
	
	@UsedByGodot
	fun getExposedMethods(): String {
		val root = JSONObject()

		// Inventory contract version (independent of camera capabilities schema)
		root.put("inventory_schema_version", 1)
		root.put("generator", PLUGIN_NAME)
		root.put("generator_kind", "android_plugin_inventory")
		root.put("plugin_name", PLUGIN_NAME)

		// Exports: explicitly report what Godot should treat as exported
		val exportsObj = JSONObject()
		exportsObj.put("export_mechanism", "getPluginMethods")

		val exportedMethodsArr = JSONArray()
		for (name in getPluginMethods()) exportedMethodsArr.put(name)
		exportsObj.put("exported_methods", exportedMethodsArr)

		val signalsArr = JSONArray()
		signalsArr.put(JSONObject().put("name", SIGNAL_CAPABILITIES_UPDATED).put("argc", 0))
		signalsArr.put(
			JSONObject()
				.put("name", SIGNAL_CAPABILITIES_WARNING)
				.put("argc", 1)
				.put("arg_types", JSONArray().put("String"))
		)
		exportsObj.put("signals", signalsArr)
		root.put("exports", exportsObj)

		// Methods: rich metadata (forward-compatible)
		val methodsArr = JSONArray()
		for (m in EXPOSED_METHODS) {
			val mObj = JSONObject()
			mObj.put("name", m.name)
			mObj.put("argc", m.argc)
			mObj.put("return_type", m.returnType)

			if (m.argTypes.isNotEmpty()) {
				val a = JSONArray()
				for (t in m.argTypes) a.put(t)
				mObj.put("arg_types", a)
			}

			if (m.tags.isNotEmpty()) {
				val t = JSONArray()
				for (tag in m.tags) t.put(tag)
				mObj.put("tags", t)
			}

			methodsArr.put(mObj)
		}
		root.put("methods", methodsArr)

		// Reserved forward-compat fields (keep them even if empty)
		root.put("extensions", JSONObject())

		return root.toString(2)
	}
	
    @UsedByGodot
    fun getCameraCapabilities(): String {
        // True 0-arg entry point for GDScript dot-calls.
        // Does NOT write a duplicate into Documents.
        return getCameraCapabilitiesInternal(null, null)
    }

    @UsedByGodot
    fun getCameraCapabilitiesToFile(documentsSubdir: String): String {
        // Writes a duplicate JSON file under:
        //   Documents/<app-name>/(documentsSubdir)/
        // Passing ".", "/", or "" means: Documents/<app-name>/
        return getCameraCapabilitiesInternal(documentsSubdir, null)
    }

    @UsedByGodot
    fun getCameraCapabilitiesWithMeta(godotVersion: String, generatorVersion: String): String {
        // Call this from an Autoload to include engine/plugin bundle metadata in the JSON.
        return getCameraCapabilitiesInternal(null, CapMeta(godotVersion, generatorVersion))
    }

    @UsedByGodot
    fun getCameraCapabilitiesToFileWithMeta(documentsSubdir: String, godotVersion: String, generatorVersion: String): String {
        // Same as getCameraCapabilitiesToFile(), but also includes meta fields in the JSON.
        return getCameraCapabilitiesInternal(documentsSubdir, CapMeta(godotVersion, generatorVersion))
    }

    private fun getCameraCapabilitiesInternal(documentsSubdirOrNull: String?, meta: CapMeta?): String {
        val sdkVersion = Build.VERSION.SDK_INT

        // Check SDK version first
        if (sdkVersion < MIN_SDK_VERSION) {
            return createErrorJson(
                "SDK version too low. Camera2 API requires SDK $MIN_SDK_VERSION or higher. Current SDK: $sdkVersion",
                sdkVersion,
                meta
            )
        }

        val hasCameraPermission = checkCameraPermission()

        val cameraManager = activity?.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: return createErrorJson("Unable to access Camera Manager", sdkVersion, meta)

        return try {
            val capabilitiesJson = buildCapabilitiesJson(cameraManager, sdkVersion, hasCameraPermission, meta)

            // Always save to user dir (Godot user:// equivalent on Android: Context.filesDir)
            // This is the canonical location read by GDScript via user://camera_capabilities.json
            saveToUserDir(capabilitiesJson)

 //           // Optionally write a duplicate to Documents/<app-name>/(documentsSubdir)/
 //           // If documentsSubdir is abusive (too long / too many segments), fall back to the 0-arg behavior.
 //           val validatedDocumentsSubdir = documentsSubdirOrNull?.let { validateDocumentsSubdirOrNull(it) }
 //           if (validatedDocumentsSubdir != null) {
 //               try {
 //                   saveToDocuments(capabilitiesJson, validatedDocumentsSubdir)
 //               } catch (e: Exception) {
 //                   emitCapabilitiesWarning(
 //                       "Couldn't write camera capabilities to Documents (skipping). Reason: ${e.javaClass.simpleName}: ${e.message}"
 //                   )
 //               }
 //           }

			// Optionally write a duplicate to Documents/<app-name>/(documentsSubdir)/
			if (documentsSubdirOrNull != null) {
				val validatedDocumentsSubdir = validateDocumentsSubdirOrNull(documentsSubdirOrNull)
				
				if (validatedDocumentsSubdir == null) {
					// Validation failed - emit warning
					emitCapabilitiesWarning("Invalid documentsSubdir parameter (too long or invalid path)")
				} else {
					// Validation passed - try to save
					try {
						saveToDocuments(capabilitiesJson, validatedDocumentsSubdir)
					} catch (e: Exception) {
						emitCapabilitiesWarning(
							"Couldn't write camera capabilities to Documents (skipping). Reason: ${e.javaClass.simpleName}: ${e.message}"
						)
					}
				}
			}


            // Signal after we have successfully written the primary app-scoped file
            emitSignal(SIGNAL_CAPABILITIES_UPDATED)

            capabilitiesJson
        } catch (e: Exception) {
            createErrorJson("Error gathering camera capabilities: ${e.message}", sdkVersion, meta)
        }
    }

    private fun emitCapabilitiesWarning(message: String) {
        // Emit to Godot (editor Output panel) when running from the editor, and also logcat.
        try {
            emitSignal(SIGNAL_CAPABILITIES_WARNING, message)
        } catch (_: Throwable) {
            // ignore
        }
        godotWarn(message)
    }

    private fun buildCapabilitiesJson(cameraManager: CameraManager, sdkVersion: Int, hasCameraPermission: Boolean, meta: CapMeta?): String {
        val rootObject = JSONObject()
        val camerasArray = JSONArray()
        val warningsArray = JSONArray()

        // Plugin info
        rootObject.put("schema_version", SCHEMA_VER)
        rootObject.put("generator", PLUGIN_NAME)

        // Optional meta injected by GDScript/autoload (diagnostic only)
        if (meta != null) {
		    if (!meta.generatorVersion.isNullOrBlank()) rootObject.put("generator_version", meta.generatorVersion)
            if (!meta.godotVersion.isNullOrBlank()) rootObject.put("godot_version", meta.godotVersion)
        }

        // System info
        rootObject.put("sdk_version", sdkVersion)
        rootObject.put("device_model", Build.MODEL)
        rootObject.put("device_manufacturer", Build.MANUFACTURER)
        rootObject.put("android_version", Build.VERSION.RELEASE)
        rootObject.put("timestamp_ms", System.currentTimeMillis())

        // Camera permission context
        rootObject.put("camera_permission_granted", hasCameraPermission)
        if (!hasCameraPermission && sdkVersion < 29) {
            // On API < 29, capability visibility without CAMERA permission is device/OEM dependent.
            rootObject.put("camera_permission_note", "On Android API < 29, some camera characteristics may be unavailable unless CAMERA permission is granted.")
        }

        // Concurrent camera support (Android 11+)
        if (sdkVersion >= CONCURRENT_CAMERA_SDK) {
            addConcurrentCameraInfo(cameraManager, rootObject)
        } else {
            rootObject.put("concurrent_camera_support", "not_available_sdk_too_low")
            rootObject.put("concurrent_camera_min_sdk", CONCURRENT_CAMERA_SDK)
        }

        for (cameraId in cameraManager.cameraIdList) {
            val cameraObject = JSONObject()
            val cameraWarnings = mutableListOf<String>()

            val characteristics = try {
                cameraManager.getCameraCharacteristics(cameraId)
            } catch (se: SecurityException) {
                cameraObject.put("error", "Requires Camera permissions; grant them")
                camerasArray.put(cameraObject)
                warningsArray.put("Camera $cameraId: Requires Camera permissions; grant them")
                continue
            }

            val permissionBlockedKeys: Set<CameraCharacteristics.Key<*>> = if (!hasCameraPermission && sdkVersion >= 29) {
                try {
                    characteristics.getKeysNeedingPermission().toSet()
                } catch (_: Exception) {
                    emptySet()
                }
            } else {
                emptySet()
            }

            fun isPermissionBlocked(key: CameraCharacteristics.Key<*>): Boolean = permissionBlockedKeys.contains(key)

            val permissionMsg = "Requires Camera permissions; grant them"

            // Camera ID
            cameraObject.put("camera_id", cameraId)

            // Lens facing
            val lensFacingKey = CameraCharacteristics.LENS_FACING
            if (isPermissionBlocked(lensFacingKey)) {
                cameraObject.put("facing", permissionMsg)
            } else {
                val facing = characteristics.get(lensFacingKey)
                cameraObject.put("facing", when (facing) {
                    CameraMetadata.LENS_FACING_FRONT -> "front"
                    CameraMetadata.LENS_FACING_BACK -> "back"
                    CameraMetadata.LENS_FACING_EXTERNAL -> "external"
                    else -> "unknown"
                })
            }

            // Hardware level
            val hwLevelKey = CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL
            if (isPermissionBlocked(hwLevelKey)) {
                cameraObject.put("hardware_level", permissionMsg)
            } else {
                val hwLevel = characteristics.get(hwLevelKey)
                cameraObject.put("hardware_level", when (hwLevel) {
                    CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY -> "legacy"
                    CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED -> "limited"
                    CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_FULL -> "full"
                    CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_3 -> "level_3"
                    CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL -> "external"
                    else -> "unknown"
                })
            }

            // Logical multi camera (API 28+ key exists but safe to query generally)
            val logicalKey = CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES
            val capabilities = characteristics.get(logicalKey)
            val isLogical = capabilities?.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA) == true
            cameraObject.put("is_logical_multi_camera", isLogical)

            // Sensor block
            val sensorObject = JSONObject()
            var hasSensorData = false

            val paWidthKey = CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE
            if (isPermissionBlocked(paWidthKey)) {
                sensorObject.put("pixel_array_width", permissionMsg)
                sensorObject.put("pixel_array_height", permissionMsg)
                hasSensorData = true
            } else {
                val pa = characteristics.get(paWidthKey)
                if (pa != null) {
                    sensorObject.put("pixel_array_width", pa.width)
                    sensorObject.put("pixel_array_height", pa.height)
                    hasSensorData = true
                } else {
                    cameraWarnings.add("Pixel array size not provided by vendor")
                }
            }

            val physSizeKey = CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE
            if (isPermissionBlocked(physSizeKey)) {
                sensorObject.put("physical_width_mm", permissionMsg)
                sensorObject.put("physical_height_mm", permissionMsg)
                hasSensorData = true
            } else {
                val ps = characteristics.get(physSizeKey)
                if (ps != null) {
                    sensorObject.put("physical_width_mm", ps.width)
                    sensorObject.put("physical_height_mm", ps.height)
                    hasSensorData = true
                } else {
                    cameraWarnings.add("Physical sensor size not provided by vendor")
                }
            }

            val isoRangeKey = CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE
            if (isPermissionBlocked(isoRangeKey)) {
                sensorObject.put("iso_min", permissionMsg)
                sensorObject.put("iso_max", permissionMsg)
                hasSensorData = true
            } else {
                val isoRange = characteristics.get(isoRangeKey)
                if (isoRange != null) {
                    sensorObject.put("iso_min", isoRange.lower)
                    sensorObject.put("iso_max", isoRange.upper)
                    hasSensorData = true
                } else {
                    cameraWarnings.add("ISO sensitivity range not provided by vendor")
                }
            }

            if (hasSensorData) {
                cameraObject.put("sensor", sensorObject)
            }

            // Focal lengths
            val focalKey = CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS
            if (isPermissionBlocked(focalKey)) {
                cameraObject.put("focal_lengths", JSONArray().put(permissionMsg))
            } else {
                val focalLengths = characteristics.get(focalKey)
                if (focalLengths != null) {
                    val flArr = JSONArray()
                    for (f in focalLengths) flArr.put(f)
                    cameraObject.put("focal_lengths", flArr)
                }
            }

            // Apertures
            val apertureKey = CameraCharacteristics.LENS_INFO_AVAILABLE_APERTURES
            if (isPermissionBlocked(apertureKey)) {
                cameraObject.put("apertures", JSONArray().put(permissionMsg))
            } else {
                val apertures = characteristics.get(apertureKey)
                if (apertures != null) {
                    val apArr = JSONArray()
                    for (a in apertures) apArr.put(a)
                    cameraObject.put("apertures", apArr)
                }
            }

            // Per-camera warnings
            if (cameraWarnings.isNotEmpty()) {
                val wArr = JSONArray()
                for (w in cameraWarnings) wArr.put(w)
                cameraObject.put("warnings", wArr)
                for (w in cameraWarnings) warningsArray.put("Camera $cameraId: $w")
            }

            camerasArray.put(cameraObject)
        }

        rootObject.put("cameras", camerasArray)
        rootObject.put("warnings", warningsArray)

        return rootObject.toString(2)
    }

    private fun addConcurrentCameraInfo(cameraManager: CameraManager, rootObject: JSONObject) {
        try {
            val combos = cameraManager.concurrentCameraIds
            val ccObj = JSONObject()
            ccObj.put("supported", combos.isNotEmpty())
            ccObj.put("max_concurrent_cameras", combos.maxOfOrNull { it.size } ?: 0)

            val combosArr = JSONArray()
            for (set in combos) {
                val setArr = JSONArray()
                for (id in set) setArr.put(id)
                combosArr.put(setArr)
            }
            ccObj.put("camera_id_combinations", combosArr)

            rootObject.put("concurrent_camera_support", ccObj)
            rootObject.put("concurrent_camera_min_sdk", CONCURRENT_CAMERA_SDK)
        } catch (e: Exception) {
            val ccObj = JSONObject()
            ccObj.put("supported", false)
            ccObj.put("error", "${e.javaClass.simpleName}: ${e.message}")
            rootObject.put("concurrent_camera_support", ccObj)
            rootObject.put("concurrent_camera_min_sdk", CONCURRENT_CAMERA_SDK)
        }
    }

    private fun checkCameraPermission(): Boolean {
        val ctx = activity ?: return false
        return ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }

	private fun saveToUserDir(jsonText: String) {
		val ctx = activity ?: throw IllegalStateException("Activity unavailable; cannot write capabilities file")
		val userDir = ctx.filesDir
			?: throw java.io.IOException("FilesDir unavailable; cannot write capabilities file")
		val outFile = File(userDir, CAPABILITIES_USER_FILENAME)
		outFile.writeText(jsonText)
	}


    private fun validateDocumentsSubdirOrNull(documentsSubdir: String): String? {
        val trimmed = documentsSubdir.trim()
        if (trimmed.isEmpty() || trimmed == "." || trimmed == "/") return ""

        if (trimmed.length > MAX_DOCUMENTS_SUBDIR_LENGTH) return null

        val normalized = trimmed.replace('\\', '/').trim('/')
        if (normalized.isEmpty()) return ""

        val segs = normalized.split('/').filter { it.isNotEmpty() }
        if (segs.size > MAX_DOCUMENTS_SUBDIR_SEGMENTS) return null

        // Reject path traversal attempts
        if (segs.any { it == "." || it == ".." }) return null

        return normalized
    }

    private fun saveToDocuments(jsonText: String, documentsSubdir: String) {
        val docsRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)

        val ctx = activity ?: return
        val appName = ctx.applicationInfo.loadLabel(ctx.packageManager).toString().ifBlank { ctx.packageName }

        val baseDir = File(docsRoot, appName)

        val targetDir = if (documentsSubdir.isBlank()) {
            baseDir
        } else {
            File(baseDir, documentsSubdir)
        }

        if (!targetDir.exists()) {
            targetDir.mkdirs()
        }

        val timestamp = SimpleDateFormat(CAPABILITIES_TIMESTAMP_FORMAT, Locale.US).format(Date())
        val outName = "${CAPABILITIES_BASENAME}_${timestamp}.json"
        val outFile = File(targetDir, outName)

        outFile.writeText(jsonText)
    }

    private fun godotWarn(message: String) {
        try {
            Log.w(PLUGIN_NAME, message)
        } catch (_: Throwable) {
            // ignore
        }
    }

    private fun createErrorJson(message: String, sdkVersion: Int? = null, meta: CapMeta? = null): String {
        val errorObject = JSONObject()
        // Plugin info
        errorObject.put("schema_version", SCHEMA_VER)
        errorObject.put("generator", PLUGIN_NAME)
        if (meta != null) {
            if (!meta.godotVersion.isNullOrBlank()) errorObject.put("godot_version", meta.godotVersion)
            if (!meta.generatorVersion.isNullOrBlank()) errorObject.put("generator_version", meta.generatorVersion)
        }

        errorObject.put("error", message)
        errorObject.put("timestamp_ms", System.currentTimeMillis())
        errorObject.put("sdk_version", sdkVersion ?: Build.VERSION.SDK_INT)
        errorObject.put("device_model", Build.MODEL)
        errorObject.put("device_manufacturer", Build.MANUFACTURER)
        return errorObject.toString(2)
    }
}
