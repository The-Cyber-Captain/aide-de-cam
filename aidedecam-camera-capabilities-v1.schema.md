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
| `generator_version` | string | Only when using `*WithMeta` calls and non-blank passed | Caller-supplied version string for plugin/bundle. |
| `godot_version` | string | Only when using `*WithMeta` calls and non-blank passed | Caller-supplied Godot version. |
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

# 4. Can Markdown be canonical enough to regenerate JSON?

**Not by itself.** Markdown is great as the *canonical* human-readable spec, but it does not reliably preserve all machine-checkable constraints unless you impose a strict, parseable structure.

If your goal is “a script can regenerate the JSON Schema (or other validators) from the Markdown,” you’ll want one of these patterns:

### Option A (recommended): MD is canonical, JSON Schema is embedded verbatim
Keep the Markdown as the canonical narrative spec, and include the exact JSON Schema in the same repo as the authoritative machine contract.

- Pros: simplest, no tooling needed, no drift if you update both in the same PR.
- Cons: you still maintain two artifacts (but they’re easy to review together).

### Option B: Add a machine-readable block inside the MD (YAML/JSON front-matter)
Example (illustrative):
```yaml
schema_version: 1
discriminator: error
fields:
  - name: schema_version
    type: int
    required: true
    const: 1
  ...
```
A script reads this block to generate JSON Schema / types.

- Pros: single source of truth.
- Cons: you’re inventing a mini-DSL and maintaining a generator.

### Option C: Treat JSON Schema as canonical; MD is generated
Use JSON Schema as the source of truth, and generate the MD from it.

- Pros: machine-canonical by definition.
- Cons: narrative quality may be lower without custom doc tooling.

**Practical recommendation for AideDeCam:** keep both files, but treat the **JSON Schema as machine-canonical** and the **MD as human-canonical**, updated together.

---

## Appendix: Machine-canonical JSON Schema (verbatim)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://sixdegreesofcrispybacon.com/aidedecam/schema/camera_capabilities_v1.schema.json",
  "title": "AideDeCam Camera Capabilities",
  "description": "JSON output produced by the AideDeCam Kotlin generator (schema_version = 1). This schema validates both success and error outputs.",
  "type": "object",
  "oneOf": [
    { "$ref": "#/$defs/SuccessRoot" },
    { "$ref": "#/$defs/ErrorRoot" }
  ],
  "$defs": {
    "PermissionMessage": {
      "type": "string",
      "const": "Requires Camera permissions; grant them"
    },
    "VersionedGenerator": {
      "type": "object",
      "additionalProperties": false,
      "required": ["schema_version", "generator"],
      "properties": {
        "schema_version": { "type": "integer", "const": 1 },
        "generator": { "type": "string", "const": "AideDeCam" },
        "generator_version": { "type": "string", "minLength": 1 },
        "godot_version": { "type": "string", "minLength": 1 }
      }
    },
    "ConcurrentSupportObject": {
      "type": "object",
      "additionalProperties": false,
      "required": ["supported"],
      "properties": {
        "supported": { "type": "boolean" },
        "max_concurrent_cameras": { "type": "integer", "minimum": 0 },
        "camera_id_combinations": {
          "type": "array",
          "items": {
            "type": "array",
            "items": { "type": "string", "minLength": 1 }
          }
        },
        "error": { "type": "string", "minLength": 1 }
      },
      "allOf": [
        {
          "if": {
            "properties": { "supported": { "const": true } },
            "required": ["supported"]
          },
          "then": {
            "required": ["max_concurrent_cameras", "camera_id_combinations"]
          }
        },
        {
          "if": {
            "properties": { "supported": { "const": false } },
            "required": ["supported"]
          },
          "then": {
            "required": ["error"]
          }
        }
      ]
    },
    "ConcurrentSupport": {
      "description": "SDK < 30 uses a string sentinel; SDK >= 30 uses an object (or object-with-error).",
      "oneOf": [
        { "type": "string", "const": "not_available_sdk_too_low" },
        { "$ref": "#/$defs/ConcurrentSupportObject" }
      ]
    },
    "SensorObject": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "pixel_array_width": {
          "oneOf": [{ "type": "integer", "minimum": 0 }, { "$ref": "#/$defs/PermissionMessage" }]
        },
        "pixel_array_height": {
          "oneOf": [{ "type": "integer", "minimum": 0 }, { "$ref": "#/$defs/PermissionMessage" }]
        },
        "physical_width_mm": {
          "oneOf": [{ "type": "number", "minimum": 0 }, { "$ref": "#/$defs/PermissionMessage" }]
        },
        "physical_height_mm": {
          "oneOf": [{ "type": "number", "minimum": 0 }, { "$ref": "#/$defs/PermissionMessage" }]
        },
        "iso_min": {
          "oneOf": [{ "type": "integer", "minimum": 0 }, { "$ref": "#/$defs/PermissionMessage" }]
        },
        "iso_max": {
          "oneOf": [{ "type": "integer", "minimum": 0 }, { "$ref": "#/$defs/PermissionMessage" }]
        }
      },
      "minProperties": 1
    },
    "CameraObject": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "camera_id": { "type": "string", "minLength": 1 },
        "error": { "type": "string", "minLength": 1 },
        "facing": {
          "oneOf": [
            { "type": "string", "enum": ["front", "back", "external", "unknown"] },
            { "$ref": "#/$defs/PermissionMessage" }
          ]
        },
        "hardware_level": {
          "oneOf": [
            { "type": "string", "enum": ["legacy", "limited", "full", "level_3", "external", "unknown"] },
            { "$ref": "#/$defs/PermissionMessage" }
          ]
        },
        "is_logical_multi_camera": { "type": "boolean" },
        "sensor": { "$ref": "#/$defs/SensorObject" },
        "focal_lengths": {
          "oneOf": [
            { "type": "array", "items": { "type": "number" } },
            {
              "type": "array",
              "items": { "$ref": "#/$defs/PermissionMessage" },
              "minItems": 1,
              "maxItems": 1
            }
          ]
        },
        "apertures": {
          "oneOf": [
            { "type": "array", "items": { "type": "number" } },
            {
              "type": "array",
              "items": { "$ref": "#/$defs/PermissionMessage" },
              "minItems": 1,
              "maxItems": 1
            }
          ]
        },
        "warnings": {
          "type": "array",
          "items": { "type": "string", "minLength": 1 }
        }
      },
      "allOf": [
        {
          "description": "Two allowed shapes: (A) SecurityException camera entry: only 'error' (no camera_id), or (B) normal camera entry with camera_id and optional fields.",
          "oneOf": [
            { "required": ["error"], "not": { "required": ["camera_id"] } },
            { "required": ["camera_id"] }
          ]
        }
      ]
    },
    "SuccessRoot": {
      "allOf": [
        { "$ref": "#/$defs/VersionedGenerator" },
        {
          "type": "object",
          "additionalProperties": false,
          "required": [
            "sdk_version",
            "device_model",
            "device_manufacturer",
            "android_version",
            "timestamp_ms",
            "camera_permission_granted",
            "concurrent_camera_support",
            "concurrent_camera_min_sdk",
            "cameras",
            "warnings"
          ],
          "properties": {
            "schema_version": { "type": "integer", "const": 1 },
            "generator": { "type": "string", "const": "AideDeCam" },
            "generator_version": { "type": "string", "minLength": 1 },
            "godot_version": { "type": "string", "minLength": 1 },
            "sdk_version": { "type": "integer", "minimum": 0 },
            "device_model": { "type": "string" },
            "device_manufacturer": { "type": "string" },
            "android_version": { "type": "string" },
            "timestamp_ms": { "type": "integer", "minimum": 0 },
            "camera_permission_granted": { "type": "boolean" },
            "camera_permission_note": { "type": "string", "minLength": 1 },
            "concurrent_camera_support": { "$ref": "#/$defs/ConcurrentSupport" },
            "concurrent_camera_min_sdk": { "type": "integer", "const": 30 },
            "cameras": {
              "type": "array",
              "items": { "$ref": "#/$defs/CameraObject" }
            },
            "warnings": {
              "type": "array",
              "items": { "type": "string" }
            }
          }
        }
      ]
    },
    "ErrorRoot": {
      "allOf": [
        { "$ref": "#/$defs/VersionedGenerator" },
        {
          "type": "object",
          "additionalProperties": false,
          "required": [
            "error",
            "timestamp_ms",
            "sdk_version",
            "device_model",
            "device_manufacturer"
          ],
          "properties": {
            "schema_version": { "type": "integer", "const": 1 },
            "generator": { "type": "string", "const": "AideDeCam" },
            "generator_version": { "type": "string", "minLength": 1 },
            "godot_version": { "type": "string", "minLength": 1 },
            "error": { "type": "string", "minLength": 1 },
            "timestamp_ms": { "type": "integer", "minimum": 0 },
            "sdk_version": { "type": "integer", "minimum": 0 },
            "device_model": { "type": "string" },
            "device_manufacturer": { "type": "string" }
          }
        }
      ]
    }
  }
}

```
