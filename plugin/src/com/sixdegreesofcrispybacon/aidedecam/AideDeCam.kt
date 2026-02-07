package com.sixdegreesofcrispybacon.aidedecam

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.os.Build
import android.os.Environment
import androidx.core.content.ContextCompat
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
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
    }

    override fun getPluginName() = "AideDeCam"

    @UsedByGodot
    fun getCameraCapabilities(saveToDocuments: Boolean = false): String {
        val sdkVersion = Build.VERSION.SDK_INT
        
        // Check SDK version first
        if (sdkVersion < MIN_SDK_VERSION) {
            return createErrorJson(
                "SDK version too low. Camera2 API requires SDK $MIN_SDK_VERSION or higher. Current SDK: $sdkVersion"
            )
        }

        if (!checkCameraPermission()) {
            return createErrorJson("Camera permission not granted", sdkVersion)
        }

        val cameraManager = activity?.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: return createErrorJson("Unable to access Camera Manager", sdkVersion)

        return try {
            val capabilitiesJson = buildCapabilitiesJson(cameraManager, sdkVersion)
            
            // Always save to user dir
            saveToUserDir(capabilitiesJson)
            
            // Optionally save to Documents
            if (saveToDocuments) {
                saveToDocuments(capabilitiesJson)
            }
            
            capabilitiesJson
        } catch (e: Exception) {
            createErrorJson("Error gathering camera capabilities: ${e.message}", sdkVersion)
        }
    }

    private fun buildCapabilitiesJson(cameraManager: CameraManager, sdkVersion: Int): String {
        val rootObject = JSONObject()
        val camerasArray = JSONArray()
        val warningsArray = JSONArray()

        // System info
        rootObject.put("sdk_version", sdkVersion)
        rootObject.put("device_model", Build.MODEL)
        rootObject.put("device_manufacturer", Build.MANUFACTURER)
        rootObject.put("android_version", Build.VERSION.RELEASE)
        rootObject.put("timestamp", System.currentTimeMillis())

        // Concurrent camera support (Android 11+)
        if (sdkVersion >= CONCURRENT_CAMERA_SDK) {
            addConcurrentCameraInfo(cameraManager, rootObject)
        } else {
            rootObject.put("concurrent_camera_support", "not_available_sdk_too_low")
            rootObject.put("concurrent_camera_min_sdk", CONCURRENT_CAMERA_SDK)
        }

        for (cameraId in cameraManager.cameraIdList) {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val cameraObject = JSONObject()
            val cameraWarnings = mutableListOf<String>()

            cameraObject.put("camera_id", cameraId)
            cameraObject.put("facing", getFacing(characteristics))
            cameraObject.put("hardware_level", getHardwareLevel(characteristics))
            
            // Sensor info with null checks
            val sensorObject = JSONObject()
            var hasSensorData = false
            
            characteristics.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)?.let {
                if (it.width > 0 && it.height > 0) {
                    sensorObject.put("pixel_array_width", it.width)
                    sensorObject.put("pixel_array_height", it.height)
                    hasSensorData = true
                } else {
                    cameraWarnings.add("Invalid pixel array size: ${it.width}x${it.height}")
                }
            } ?: cameraWarnings.add("Pixel array size not provided by vendor")

            characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)?.let {
                if (it.width > 0 && it.height > 0) {
                    sensorObject.put("physical_width_mm", it.width)
                    sensorObject.put("physical_height_mm", it.height)
                    hasSensorData = true
                } else {
                    cameraWarnings.add("Invalid physical sensor size")
                }
            } ?: cameraWarnings.add("Physical sensor size not provided by vendor")

            characteristics.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)?.let {
                if (it.lower >= 0 && it.upper > it.lower) {
                    sensorObject.put("iso_min", it.lower)
                    sensorObject.put("iso_max", it.upper)
                    hasSensorData = true
                } else {
                    cameraWarnings.add("Invalid ISO sensitivity range")
                }
            } ?: cameraWarnings.add("ISO sensitivity range not provided by vendor")

            if (hasSensorData) {
                cameraObject.put("sensor", sensorObject)
            }

            // Available focal lengths
            characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.let {
                if (it.isNotEmpty() && it.all { fl -> fl > 0 }) {
                    val focalLengthsArray = JSONArray()
                    it.forEach { fl -> focalLengthsArray.put(fl) }
                    cameraObject.put("focal_lengths", focalLengthsArray)
                } else {
                    cameraWarnings.add("Invalid focal length data")
                }
            } ?: cameraWarnings.add("Focal lengths not provided by vendor")

            // Apertures
            characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_APERTURES)?.let {
                if (it.isNotEmpty() && it.all { ap -> ap > 0 }) {
                    val aperturesArray = JSONArray()
                    it.forEach { ap -> aperturesArray.put(ap) }
                    cameraObject.put("apertures", aperturesArray)
                } else {
                    cameraWarnings.add("Invalid aperture data")
                }
            }

            // Supported output formats
            val streamConfigMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            if (streamConfigMap != null) {
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
            characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)?.let {
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
                        characteristics.get(CameraCharacteristics.LOGICAL_MULTI_CAMERA_PHYSICAL_IDS)?.let { ids ->
                            val physicalIdsArray = JSONArray()
                            ids.forEach { id -> physicalIdsArray.put(id) }
                            cameraObject.put("physical_camera_ids", physicalIdsArray)
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
        return when (format) {
            0x1 -> "RGBA_8888"
            0x2 -> "RGBX_8888"
            0x3 -> "RGB_888"
            0x4 -> "RGB_565"
            0x11 -> "NV16"
            0x14 -> "NV21"
            0x20 -> "YUY2"
            0x22 -> "JPEG"
            0x23 -> "YUV_420_888"
            0x25 -> "YUV_422_888"
            0x27 -> "YUV_444_888"
            0x28 -> "FLEX_RGB_888"
            0x29 -> "FLEX_RGBA_8888"
            0x100 -> "RAW_SENSOR"
            0x20 -> "RAW10"
            0x25 -> "RAW12"
            0x2C -> "DEPTH16"
            0x44 -> "DEPTH_POINT_CLOUD"
            0x45 -> "PRIVATE"
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
        val userDir = activity?.getExternalFilesDir(null) ?: return
        val file = File(userDir, "camera_capabilities.json")
        file.writeText(json)
    }

    private fun saveToDocuments(json: String) {
        val documentsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        if (!documentsDir.exists()) {
            documentsDir.mkdirs()
        }
        
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val filename = "camera_capabilities_$timestamp.json"
        val file = File(documentsDir, filename)
        file.writeText(json)
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