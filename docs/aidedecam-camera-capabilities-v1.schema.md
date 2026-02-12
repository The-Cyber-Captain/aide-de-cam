# AideDeCam Camera Capabilities JSON
**Schema version:** `1`  
**Generator:** `"AideDeCam"`

This document describes the JSON produced by the AideDeCam Kotlin generator. The generator returns **either** a **Success** payload (normal capabilities) **or** an **Error** payload (generation failed early).

> Canonicality note: this Markdown is intended to be *human-canonical* (reviewable, diff-friendly), while the accompanying JSON Schema is the *machine-canonical* contract used for validation.

---

## Conventions

### Permission-blocked sentinel string
On Android **API 29+** when CAMERA permission is **not granted**, some camera characteristics may be hidden. In that case, certain fields are replaced by the literal string:

```
"Requires Camera permissions; grant them"
```

This is referred to below as the **permission sentinel**.

### Optional fields
A field marked *optional* may be absent entirely (not `null`).

---

# 1. Success payload

## 1.1 Top-level object

### Required fields
| Field | Type | Description |
|---|---|---|
| `schema_version` | int | Always `1`. |
| `generator` | string | Always `"AideDeCam"`. |
| `sdk_version` | int | Android SDK integer (`Build.VERSION.SDK_INT`). |
| `device_model` | string | Device model (`Build.MODEL`). |
| `device_manufacturer` | string | Device manufacturer (`Build.MANUFACTURER`). |
| `android_version` | string | Android release string (`Build.VERSION.RELEASE`). |
| `timestamp_ms` | int | Unix epoch milliseconds when generated. |
| `camera_permission_granted` | bool | Whether CAMERA permission is currently granted. |
| `concurrent_camera_support` | object \| string | Concurrent camera support info (details below). |
| `concurrent_camera_min_sdk` | int | Always `30`. |
| `cameras` | array<object> | Per-camera entries (details below). |
| `warnings` | array<string> | Aggregated warnings, including per-camera warnings (details below). |

### Optional fields
| Field | Type | When present | Description |
|---|---|---|---|
| `generator_version` | string | Only when using `*WithMeta` calls [PREFERRED!] and non-blank passed | Caller-supplied version string for plugin/bundle. |
| `godot_version` | string | Only when using `*WithMeta` calls [PREFERRED!] and non-blank passed | Caller-supplied Godot version. |
| `camera_permission_note` | string | Only when `camera_permission_granted=false` AND `sdk_version < 29` | Explains that characteristic visibility may be OEM-dependent on older Android. |

---

## 1.2 `concurrent_camera_support`

### A) SDK < 30
If `sdk_version < 30`:
```json
"concurrent_camera_support": "not_available_sdk_too_low",
"concurrent_camera_min_sdk": 30
```

### B) SDK >= 30 (normal)
If `sdk_version >= 30` and the query succeeds:
```json
"concurrent_camera_support": {
  "supported": true,
  "max_concurrent_cameras": 2,
  "camera_id_combinations": [
    ["0", "1"],
    ["0", "2"]
  ]
},
"concurrent_camera_min_sdk": 30
```

Fields:
| Field | Type | Description |
|---|---|---|
| `supported` | bool | True if at least one concurrent set is reported. |
| `max_concurrent_cameras` | int | Maximum size among reported sets (0 if none). |
| `camera_id_combinations` | array<array<string>> | Each inner array is a camera-id set that can run concurrently. |

### C) SDK >= 30 but query failed
If an exception occurs querying concurrent sets:
```json
"concurrent_camera_support": {
  "supported": false,
  "error": "ExceptionType: message"
},
"concurrent_camera_min_sdk": 30
```

Fields:
| Field | Type | Description |
|---|---|---|
| `supported` | bool | False. |
| `error` | string | Exception name and message. |

---

## 1.3 `cameras[]` entries

The `cameras` array contains one entry per `cameraId` returned by `cameraManager.cameraIdList`.

### 1.3.1 Normal camera entry

#### Required
| Field | Type | Description |
|---|---|---|
| `camera_id` | string | Camera2 camera ID. |
| `is_logical_multi_camera` | bool | True if camera reports `LOGICAL_MULTI_CAMERA` capability. |

#### Optional fields (may be absent)
| Field | Type | Notes |
|---|---|---|
| `facing` | string \| permission sentinel | Normal values: `front`, `back`, `external`, `unknown`. |
| `hardware_level` | string \| permission sentinel | Values: `legacy`, `limited`, `full`, `level_3`, `external`, `unknown`. |
| `sensor` | object | Included only if at least one sensor subfield is emitted. |
| `focal_lengths` | array<number> \| `[permission sentinel]` | Absent if not blocked but value is null. |
| `apertures` | array<number> \| `[permission sentinel]` | Absent if not blocked but value is null. |
| `warnings` | array<string> | Per-camera warnings (see below). |

---

### 1.3.2 Permission-blocked fields
On SDK >= 29, if a characteristic key is permission-gated and CAMERA permission is missing, the field is set to the permission sentinel string (or array containing it):

- `facing`: `"Requires Camera permissions; grant them"`
- `hardware_level`: `"Requires Camera permissions; grant them"`
- `sensor.*`: set to permission sentinel per sub-field
- `focal_lengths`: `["Requires Camera permissions; grant them"]`
- `apertures`: `["Requires Camera permissions; grant them"]`

---

### 1.3.3 `sensor` object
Present only if at least one sub-field is emitted (either real numeric data or permission sentinel).

| Field | Type | Description |
|---|---|---|
| `pixel_array_width` | int \| permission sentinel | Pixel array width. |
| `pixel_array_height` | int \| permission sentinel | Pixel array height. |
| `physical_width_mm` | number \| permission sentinel | Sensor physical width (mm). |
| `physical_height_mm` | number \| permission sentinel | Sensor physical height (mm). |
| `iso_min` | int \| permission sentinel | ISO lower bound. |
| `iso_max` | int \| permission sentinel | ISO upper bound. |

---

### 1.3.4 Per-camera warnings
The generator may add warnings if the vendor returns null for certain characteristics.

Possible warning strings:
- `Pixel array size not provided by vendor`
- `Physical sensor size not provided by vendor`
- `ISO sensitivity range not provided by vendor`

When present:
```json
"warnings": [
  "Physical sensor size not provided by vendor"
]
```

Each per-camera warning is also duplicated into top-level `warnings[]` prefixed with:
```
Camera <camera_id>: <warning>
```

---

### 1.3.5 SecurityException camera entry (special case)
If `getCameraCharacteristics(cameraId)` throws `SecurityException`, the generator emits a **minimal** object:

```json
{ "error": "Requires Camera permissions; grant them" }
```

Notes:
- This entry does **not** include `camera_id`.
- A matching string is also added to top-level `warnings[]` as:
  - `Camera <cameraId>: Requires Camera permissions; grant them`

---

## 1.4 Top-level `warnings[]`
- Type: `array<string>`
- Always present (may be empty).
- Contains:
  - Per-camera warnings, prefixed with `Camera <camera_id>: ...`
  - SecurityException-derived warnings (permission-related)

---

# 2. Error payload
If capability generation fails early (SDK too low, no camera manager, unexpected exception), the generator returns an error object.

## 2.1 Top-level error object

### Required fields
| Field | Type | Description |
|---|---|---|
| `schema_version` | int | Always `1`. |
| `generator` | string | Always `"AideDeCam"`. |
| `error` | string | Error message. |
| `timestamp_ms` | int | Unix epoch milliseconds. |
| `sdk_version` | int | SDK at time of failure. |
| `device_model` | string | Device model. |
| `device_manufacturer` | string | Device manufacturer. |

### Optional fields
| Field | Type | When present |
|---|---|---|
| `generator_version` | string | Only when meta provided and non-blank. |
| `godot_version` | string | Only when meta provided and non-blank. |

**Error payload does not include:** `cameras`, `warnings`, `android_version`, `camera_permission_granted`, etc.

---

# 3. Parsing recommendations
1. Treat the presence of top-level `error` as the discriminator between **Error** and **Success**.
2. Handle union-typed fields:
   - `concurrent_camera_support`: string or object
   - permission-gated fields: number/string unions, array unions
3. Camera entries may be either:
   - normal entries (with `camera_id`)
   - SecurityException entries (with only `error`)

---