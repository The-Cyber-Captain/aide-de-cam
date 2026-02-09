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
        private const val MIN_SDK_VERSION = 21 // Camera2 API minimum
        private const val CONCURRENT_CAMERA_SDK = 30 // Android 11

        // Public/shared filename + naming conventions
        private const val CAPABILITIES_BASENAME = "camera_capabilities"
        private const val CAPABILITIES_USER_FILENAME = "${CAPABILITIES_BASENAME}.json"
        private const val CAPABILITIES_TIMESTAMP_FORMAT = "yyyyMMdd_HHmmss"

        // Defensive caps to avoid pathological path/segment behavior (hang/ANR vectors)
        private const val MAX_DOCUMENTS_SUBDIR_LENGTH = 512
        private const val MAX_DOCUMENTS_SUBDIR_SEGMENTS = 16

        // Signals
        private const val SIGNAL_CAPABILITIES_UPDATED = "capabilities_updated"
        private const val SIGNAL_CAPABILITIES_WARNING = "capabilities_warning"
    }

    init {
        android.util.Log.i("AideDeCam", "Plugin initialized!")
    }

    override fun getPluginName() = "AideDeCam"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo(SIGNAL_CAPABILITIES_UPDATED),
        SignalInfo(SIGNAL_CAPABILITIES_WARNING, String::class.java)
    )

    override fun getPluginMethods(): List<String> = listOf(
    "getCameraCapabilities",
    "getCameraCapabilitiesToFile"
)

@UsedByGodot
fun getCameraCapabilities(): String {
    // True 0-arg entry point for GDScript dot-calls.
    // Does NOT write a duplicate into Documents.
    return getCameraCapabilitiesInternal(null)
}

@UsedByGodot
fun getCameraCapabilitiesToFile(documentsSubdir: String): String {
    // Writes a duplicate JSON file under:
    //   Documents/<app-name>/(documentsSubdir)/
    // Passing "." or "" means: Documents/<app-name>/
    return getCameraCapabilitiesInternal(documentsSubdir)
}

private fun getCameraCapabilitiesInternal(documentsSubdirOrNull: String?): String {
    val sdkVersion = Build.VERSION.SDK_INT

    // Check SDK version first
    if (sdkVersion < MIN_SDK_VERSION) {
        return createErrorJson(
            "SDK version too low. Camera2 API requires SDK $MIN_SDK_VERSION or higher. Current SDK: $sdkVersion"
        )
    }

    val hasCameraPermission = checkCameraPermission()

    val cameraManager = activity?.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
        ?: return createErrorJson("Unable to access Camera Manager", sdkVersion)

    return try {
        val capabilitiesJson = buildCapabilitiesJson(cameraManager, sdkVersion, hasCameraPermission)

        // Always save to user dir (app-scoped external files)
        saveToUserDir(capabilitiesJson)

        // Optionally write a duplicate to Documents/<app-name>/(documentsSubdir)/
        // If documentsSubdir is abusive (too long / too many segments), fall back to the 0-arg behavior.
        val validatedDocumentsSubdir = documentsSubdirOrNull?.let { validateDocumentsSubdirOrNull(it) }
        if (validatedDocumentsSubdir != null) {
            try {
                saveToDocuments(capabilitiesJson, validatedDocumentsSubdir)
            } catch (e: Exception) {
                emitCapabilitiesWarning("Couldn't write camera capabilities to Documents (skipping). Reason: ${e.javaClass.simpleName}: ${e.message}")
            }
        }

        // Signal after we have successfully written the primary app-scoped file
        emitSignal(SIGNAL_CAPABILITIES_UPDATED)

        capabilitiesJson
    } catch (e: Exception) {
        createErrorJson("Error gathering camera capabilities: ${e.message}", sdkVersion)
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

    private fun buildCapabilitiesJson(cameraManager: CameraManager, sdkVersion: Int, hasCameraPermission: Boolean): String {
        val rootObject = JSONObject()
        val camerasArray = JSONArray()
        val warningsArray = JSONArray()

        // System info
        rootObject.put("sdk_version", sdkVersion)
        rootObject.put("device_model", Build.MODEL)
        rootObject.put("device_manufacturer", Build.MANUFACTURER)
        rootObject.put("android_version", Build.VERSION.RELEASE)
        rootObject.put("timestamp", System.currentTimeMillis())

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

            cameraObject.put("camera_id", cameraId)
            cameraObject.put("facing", getFacing(characteristics))
            cameraObject.put("hardware_level", getHardwareLevel(characteristics))
            
            // Sensor info with null checks
            val sensorObject = JSONObject()
            var hasSensorData = false
            
            if (isPermissionBlocked(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)) {
                sensorObject.put("pixel_array_width", permissionMsg)
                sensorObject.put("pixel_array_height", permissionMsg)
                hasSensorData = true
            } else {
                characteristics.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)?.let {
                    if (it.width > 0 && it.height > 0) {
                        sensorObject.put("pixel_array_width", it.width)
                        sensorObject.put("pixel_array_height", it.height)
                        hasSensorData = true
                    } else {
                        cameraWarnings.add("Invalid pixel array size: ${it.width}x${it.height}")
                    }
                } ?: cameraWarnings.add("Pixel array size not provided by vendor")
            }

            if (isPermissionBlocked(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)) {
                sensorObject.put("physical_width_mm", permissionMsg)
                sensorObject.put("physical_height_mm", permissionMsg)
                hasSensorData = true
            } else {
                characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)?.let {
                    if (it.width > 0 && it.height > 0) {
                        sensorObject.put("physical_width_mm", it.width)
                        sensorObject.put("physical_height_mm", it.height)
                        hasSensorData = true
                    } else {
                        cameraWarnings.add("Invalid physical sensor size")
                    }
                } ?: cameraWarnings.add("Physical sensor size not provided by vendor")
            }

            if (isPermissionBlocked(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)) {
                sensorObject.put("iso_min", permissionMsg)
                sensorObject.put("iso_max", permissionMsg)
                hasSensorData = true
            } else {
                characteristics.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)?.let {
                    if (it.lower >= 0 && it.upper > it.lower) {
                        sensorObject.put("iso_min", it.lower)
                        sensorObject.put("iso_max", it.upper)
                        hasSensorData = true
                    } else {
                        cameraWarnings.add("Invalid ISO sensitivity range")
                    }
                } ?: cameraWarnings.add("ISO sensitivity range not provided by vendor")
            }

            if (hasSensorData) {
                cameraObject.put("sensor", sensorObject)
            }

            // Available focal lengths
            if (isPermissionBlocked(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)) {
                cameraObject.put("focal_lengths", permissionMsg)
            } else {
                characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.let {
                    if (it.isNotEmpty() && it.all { fl -> fl > 0 }) {
                        val focalLengthsArray = JSONArray()
                        it.forEach { fl -> focalLengthsArray.put(fl) }
                        cameraObject.put("focal_lengths", focalLengthsArray)
                    } else {
                        cameraWarnings.add("Invalid focal length data")
                    }
                } ?: cameraWarnings.add("Focal lengths not provided by vendor")
            }

            // Apertures
            if (isPermissionBlocked(CameraCharacteristics.LENS_INFO_AVAILABLE_APERTURES)) {
                cameraObject.put("apertures", permissionMsg)
            } else {
                characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_APERTURES)?.let {
                    if (it.isNotEmpty() && it.all { ap -> ap > 0 }) {
                        val aperturesArray = JSONArray()
                        it.forEach { ap -> aperturesArray.put(ap) }
                        cameraObject.put("apertures", aperturesArray)
                    } else {
                        cameraWarnings.add("Invalid aperture data")
                    }
                }
            }


            // Supported output formats
            val streamConfigMap = if (isPermissionBlocked(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)) {
                null
            } else {
                characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            }
            if (isPermissionBlocked(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)) {
                cameraObject.put("output_formats", permissionMsg)
            } else if (streamConfigMap != null) {
                val formatsArray = JSONArray()
                var hasValidFormats = false
                
                streamConfigMap.outputFormats.forEach { format ->
                    val sizes = streamConfigMap.getOutputSizes(format)
                    if (sizes != null && sizes.isNotEmpty()) {
                        val formatObject = JSONObject()
                        formatObject.put("format", format)
                        formatObject.put("format_name", getFormatName(format))
                        
                        val sizesArray = JSONArray()
                        sizes.forEach { size ->
                            if (size.width > 0 && size.height > 0) {
                                sizesArray.put("${size.width}x${size.height}")
                            }
                        }
                        
                        if (sizesArray.length() > 0) {
                            formatObject.put("sizes", sizesArray)
                            formatsArray.put(formatObject)
                            hasValidFormats = true
                        }
                    }
                }
                
                if (hasValidFormats) {
                    cameraObject.put("output_formats", formatsArray)
                } else {
                    cameraWarnings.add("No valid output formats available")
                }
            } else {
                cameraWarnings.add("Stream configuration map not provided by vendor")
            }

            // FPS ranges
            if (isPermissionBlocked(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)) {
                cameraObject.put("fps_ranges", permissionMsg)
            } else characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)?.let {
                if (it.isNotEmpty()) {
                    val fpsArray = JSONArray()
                    val validRanges = it.filter { range -> 
                        range.lower > 0 && range.upper >= range.lower && range.upper <= 240
                    }
                    
                    if (validRanges.isNotEmpty()) {
                        validRanges.forEach { range ->
                            fpsArray.put("${range.lower}-${range.upper}")
                        }
                        cameraObject.put("fps_ranges", fpsArray)
                    } else {
                        cameraWarnings.add("All FPS ranges have invalid values")
                    }
                } else {
                    cameraWarnings.add("Empty FPS ranges array")
                }
            } ?: cameraWarnings.add("FPS ranges not provided by vendor")


			// Logical multi-camera support (Android 9+)
			if (sdkVersion >= 28) {
				characteristics.get(CameraCharacteristics.LOGICAL_MULTI_CAMERA_SENSOR_SYNC_TYPE)?.let {
					cameraObject.put("multi_camera_sync_type", getMultiCameraSyncType(it))
				}
				
				characteristics.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)?.let { caps ->
					cameraObject.put("is_logical_multi_camera", 
						caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA))
					
					if (caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA)) {
						// Use reflection to access LOGICAL_MULTI_CAMERA_PHYSICAL_IDS (API 28+)
						try {
							val physicalIdsKey = CameraCharacteristics::class.java
								.getDeclaredField("LOGICAL_MULTI_CAMERA_PHYSICAL_IDS")
								.get(null) as CameraCharacteristics.Key<*>
							
							@Suppress("UNCHECKED_CAST")
							val physicalIds = characteristics.get(physicalIdsKey as CameraCharacteristics.Key<Set<String>>)
							
							physicalIds?.let { ids ->
								val physicalIdsArray = JSONArray()
								for (id in ids) {
									physicalIdsArray.put(id)
								}
								cameraObject.put("physical_camera_ids", physicalIdsArray)
							}
						} catch (e: Exception) {
							// Field not available, skip physical IDs
							cameraWarnings.add("Logical multi-camera detected but physical IDs unavailable")
						}
					}
				}
			}

            // Add warnings if any
            if (cameraWarnings.isNotEmpty()) {
                val cameraWarningsArray = JSONArray()
                cameraWarnings.forEach { warning ->
                    cameraWarningsArray.put(warning)
                    warningsArray.put("Camera $cameraId: $warning")
                }
                cameraObject.put("warnings", cameraWarningsArray)
            }

            camerasArray.put(cameraObject)
        }

        rootObject.put("cameras", camerasArray)
        
        if (warningsArray.length() > 0) {
            rootObject.put("warnings", warningsArray)
        }

        return rootObject.toString(2)
    }

    private fun addConcurrentCameraInfo(cameraManager: CameraManager, rootObject: JSONObject) {
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                val concurrentObject = JSONObject()
                val concurrentCameraSets = cameraManager.concurrentCameraIds
                
                concurrentObject.put("supported", concurrentCameraSets.isNotEmpty())
                
                if (concurrentCameraSets.isNotEmpty()) {
                    val setsArray = JSONArray()
                    concurrentCameraSets.forEach { cameraIdSet ->
                        val setArray = JSONArray()
                        cameraIdSet.forEach { cameraId ->
                            setArray.put(cameraId)
                        }
                        setsArray.put(setArray)
                    }
                    concurrentObject.put("camera_id_combinations", setsArray)
                    concurrentObject.put("max_concurrent_cameras", 
                        concurrentCameraSets.maxOfOrNull { it.size } ?: 0)
                } else {
                    concurrentObject.put("camera_id_combinations", JSONArray())
                    concurrentObject.put("max_concurrent_cameras", 1)
                }
                
                rootObject.put("concurrent_camera_support", concurrentObject)
            }
        } catch (e: Exception) {
            val concurrentObject = JSONObject()
            concurrentObject.put("supported", false)
            concurrentObject.put("error", "Failed to query concurrent camera support: ${e.message}")
            rootObject.put("concurrent_camera_support", concurrentObject)
        }
    }

	private fun getFormatName(format: Int): String {
    // Using actual Android ImageFormat constants
    return when (format) {
        1 -> "RGBA_8888"
        2 -> "RGBX_8888"
        3 -> "RGB_888"
        4 -> "RGB_565"
        16 -> "NV16"
        17 -> "NV21"
        20 -> "YUY2"
        32 -> "YV12"
        34 -> "PRIVATE"
        35 -> "YUV_420_888"
        37 -> "RAW10"
        39 -> "YUV_444_888"
        40 -> "FLEX_RGB_888"
        41 -> "FLEX_RGBA_8888"
        44 -> "DEPTH16"
        45 -> "RAW12"
        46 -> "RAW_PRIVATE"
        68 -> "DEPTH_POINT_CLOUD"
        256 -> "JPEG"
        257 -> "DEPTH_JPEG"
        4098 -> "HEIC"
        else -> "UNKNOWN_$format"
    }
}

    private fun getMultiCameraSyncType(syncType: Int): String {
        return when (syncType) {
            CameraMetadata.LOGICAL_MULTI_CAMERA_SENSOR_SYNC_TYPE_APPROXIMATE -> "approximate"
            CameraMetadata.LOGICAL_MULTI_CAMERA_SENSOR_SYNC_TYPE_CALIBRATED -> "calibrated"
            else -> "unknown"
        }
    }

    private fun getFacing(characteristics: CameraCharacteristics): String {
        return when (characteristics.get(CameraCharacteristics.LENS_FACING)) {
            CameraCharacteristics.LENS_FACING_FRONT -> "front"
            CameraCharacteristics.LENS_FACING_BACK -> "back"
            CameraCharacteristics.LENS_FACING_EXTERNAL -> "external"
            else -> "unknown"
        }
    }

    private fun getHardwareLevel(characteristics: CameraCharacteristics): String {
        return when (characteristics.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)) {
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY -> "legacy"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED -> "limited"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_FULL -> "full"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_3 -> "level_3"
            else -> "unknown"
        }
    }

    private fun saveToUserDir(json: String) {
        val ctx = activity ?: throw IllegalStateException("Activity unavailable; cannot write capabilities file")
        val userDir = ctx.filesDir // this equates to godot's user:// dir
            ?: throw java.io.IOException("FilesDir unavailable; cannot write capabilities file")
        val file = File(userDir, CAPABILITIES_USER_FILENAME)
        file.writeText(json)
    }

    private fun getSafeAppFolderName(): String {
    val ctx = activity ?: return "GodotApp"
    val pm = ctx.packageManager
    val label = try {
        ctx.applicationInfo.loadLabel(pm).toString()
    } catch (_: Exception) {
        null
    }
	val raw = (label?.takeIf { it.isNotBlank() } ?: ctx.packageName).trim()

    // Keep it filesystem-friendly and deterministic.
    val sanitized = raw.map { ch ->
        when {
            ch.isLetterOrDigit() -> ch
            ch == ' ' || ch == '.' || ch == '_' || ch == '-' -> ch
            else -> '_'
        }
    }.joinToString("").trim()

    return if (sanitized.isNotEmpty()) sanitized else "GodotApp"
}

private fun validateDocumentsSubdirOrNull(raw: String): String? {
    val trimmed = raw.trim()

    if (trimmed.length > MAX_DOCUMENTS_SUBDIR_LENGTH) {
        emitCapabilitiesWarning(
            "documentsSubdir is too long (len=${trimmed.length}, max=$MAX_DOCUMENTS_SUBDIR_LENGTH). Skipping Documents copy."
        )
        return null
    }

    // Normalize separators early; we only count segments on the capped-length string.
    val normalized = trimmed.replace('\\', '/')
    val segments = normalized.split('/')
        .map { it.trim() }
        .filter { it.isNotEmpty() && it != "." && it != ".." }

    if (segments.size > MAX_DOCUMENTS_SUBDIR_SEGMENTS) {
        emitCapabilitiesWarning(
            "documentsSubdir has too many path segments (${segments.size}, max=$MAX_DOCUMENTS_SUBDIR_SEGMENTS). Skipping Documents copy."
        )
        return null
    }

    // Keep original (sanitization happens later); allow "" / "." to mean app root.
    return trimmed
}

private fun sanitizeDocumentsSubdir(raw: String): String {
    // Normalize separators, strip leading/trailing, drop '.' and '..' segments.
    val normalized = raw.replace('\\', '/').trim()
    val parts = normalized.split('/')
        .map { it.trim() }
        .filter { it.isNotEmpty() && it != "." && it != ".." }

    return parts.joinToString(File.separator)
}

private fun saveToDocuments(json: String, documentsSubdir: String) {
    val documentsRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
    if (!documentsRoot.exists()) {
        documentsRoot.mkdirs()
    }

    val appDir = File(documentsRoot, getSafeAppFolderName())
    if (!appDir.exists()) {
        appDir.mkdirs()
    }

    val sanitizedSubdir = sanitizeDocumentsSubdir(documentsSubdir)
    val targetDir = if (sanitizedSubdir.isEmpty()) appDir else File(appDir, sanitizedSubdir)
    if (!targetDir.exists()) {
        targetDir.mkdirs()
    }

    val timestamp = SimpleDateFormat(CAPABILITIES_TIMESTAMP_FORMAT, Locale.US).format(Date())
    val filename = "${CAPABILITIES_BASENAME}_$timestamp.json"
    val file = File(targetDir, filename)
    file.writeText(json)
}



    private fun godotWarn(message: String) {
        // Best-effort: print a warning into Godot's output, and also logcat.
        try {
            val godotLibClass = Class.forName("org.godotengine.godot.GodotLib")
            // Godot 4 Android templates commonly expose:
            //   printWarning(String message, String function, String file, int line)
            // but we try a couple of signatures to be safe.
            val methods = godotLibClass.methods
            val candidate = methods.firstOrNull { m ->
                m.name == "printWarning" && m.parameterTypes.isNotEmpty()
            }
            if (candidate != null) {
                val params = candidate.parameterTypes
                when (params.size) {
                    1 -> candidate.invoke(null, message)
                    4 -> candidate.invoke(null, message, "AideDeCam", "AideDeCam.kt", 0)
                    else -> candidate.invoke(null, message)
                }
            } else {
                Log.w("AideDeCam", message)
            }
        } catch (_: Throwable) {
            Log.w("AideDeCam", message)
        }
    }

    private fun checkCameraPermission(): Boolean {
        return activity?.let {
            ContextCompat.checkSelfPermission(it, Manifest.permission.CAMERA) == 
                PackageManager.PERMISSION_GRANTED
        } ?: false
    }

    private fun createErrorJson(message: String, sdkVersion: Int? = null): String {
        val errorObject = JSONObject()
        errorObject.put("error", message)
        errorObject.put("timestamp", System.currentTimeMillis())
        errorObject.put("sdk_version", sdkVersion ?: Build.VERSION.SDK_INT)
        errorObject.put("device_model", Build.MODEL)
        errorObject.put("device_manufacturer", Build.MANUFACTURER)
        return errorObject.toString(2)
    }
}
