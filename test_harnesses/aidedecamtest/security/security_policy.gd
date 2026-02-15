class_name SecurityPolicy
extends RefCounted

const MAX_DOCUMENTS_SUBDIR_LENGTH := 512
const MAX_DOCUMENTS_SUBDIR_SEGMENTS := 16

const REQUIRE_WARNING_ON_FALLBACK := true

# Some editors/runtimes warn or sanitize when NUL bytes appear in Strings.
# Keep this off by default; enable only if your environment handles it cleanly.
const ENABLE_NUL_VECTOR := false

const SIGNAL_TIMEOUT_SEC := 6.0

const WRAPPER_AUTOLOAD_NAME := "AideDeCam"
const SINGLETON_NAME := "AideDeCam"

const SCHEMA_PATH := "res://addons/aide_de_cam/doc_classes/aidedecam-camera-capabilities-v1.schema.json"
const SCHEMA_SHA256 := "ee1db6a57d8046a790500000ded0000012c2cd1486774efddd6f7fa0b6d98a37" # ded
#const SCHEMA_SHA256 := "9168c92a9a4adcb5fc528d9d16600cb7571cdc1b8e270befae181f4a516bb6cb" # good

#const SCHEMA_SHA256 := "c33c6224dc2334950317a3fefefc5a8adf9693e5c56d5d01833dbf47bca40170"
