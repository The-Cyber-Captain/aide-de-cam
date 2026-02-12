@tool
extends EditorPlugin

const PLUGIN_NAME := "AideDeCam"
#const AUTOLOAD_NAME = "AideDeCam"
const AUTOLOAD_PATH = "res://addons/aide_de_cam/aidedecam.gd"
const PLUGIN_CFG_PATH = "res://addons/aide_de_cam/plugin.cfg"
const PLUGIN_CFG_RESOURCE_PATH = "res://addons/aide_de_cam/custom_resources/adc_cfg.tres"

var android_plugin: AndroidExportPlugin

# Track whether *we* added the autoload this session, so we don't remove a user's existing one.
var _added_autoload := false
# Avoid re-entrancy during plugin enable/disable and filesystem scans.
var _post_enable_scheduled := false

func _enter_tree() -> void:
	# Register the Android export plugin immediately (cheap, no disk writes).
	android_plugin = AndroidExportPlugin.new()
	add_export_plugin(android_plugin)

	# Defer any ProjectSettings / disk writes to avoid editor re-entrancy:
	# - avoids "plugin already enabled" warnings
	# - avoids filesystem scan thread collisions
	if not _post_enable_scheduled:
		_post_enable_scheduled = true
		call_deferred("_post_enable")

func _post_enable() -> void:
	_post_enable_scheduled = false
	if not is_inside_tree():
		return

	# Add autoload for runtime + autocomplete/docs (idempotent).
	if not has_autoload(PLUGIN_NAME):
		add_autoload_singleton(PLUGIN_NAME, AUTOLOAD_PATH)
		_added_autoload = true

	# Get PluginConfig; create it if required
	var config : PluginConfig = _get_plugin_config_resource()

	# Populate PluginConfig
	_populate_config(config)

	# Save to disk (deferred one more time to stay out of the enable call stack)
	call_deferred("_save_plugin_config_resource", config)

func _exit_tree() -> void:
	# Remove autoload only if we added it.
	if _added_autoload and has_autoload(PLUGIN_NAME):
		remove_autoload_singleton(PLUGIN_NAME)
	_added_autoload = false

	# Remove export plugin
	if android_plugin != null:
		remove_export_plugin(android_plugin)
	android_plugin = null

func has_autoload(name: String) -> bool:
	return ProjectSettings.has_setting("autoload/" + name)

func _get_plugin_config_resource() -> PluginConfig:
	var cfg : PluginConfig
	if not ResourceLoader.exists(PLUGIN_CFG_RESOURCE_PATH):
		# Ensure directory exists
		var config_dir = PLUGIN_CFG_RESOURCE_PATH.get_base_dir()
		var dir = DirAccess.open("res://")
		if not dir.dir_exists(config_dir):
			var err = dir.make_dir_recursive(config_dir)
			if err != OK:
				push_error("Failed to create config directory: ", err)
		# Create new config resource
		cfg = PluginConfig.new()
		print("Created new PluginConfig")
	else:
		cfg = load(PLUGIN_CFG_RESOURCE_PATH)
	return cfg

func _populate_config(cfg: PluginConfig) -> void:
	if FileAccess.file_exists(PLUGIN_CFG_PATH):
		var plugin_cfg := ConfigFile.new()
		plugin_cfg.load(PLUGIN_CFG_PATH)

		if plugin_cfg.get_value("plugin", "name") != null:
			cfg.name = plugin_cfg.get_value("plugin", "name")

		cfg.version = self.get_plugin_version()

		if plugin_cfg.get_value("plugin", "description") != null:
			cfg.description = plugin_cfg.get_value("plugin", "description")

		if plugin_cfg.get_value("plugin", "author") != null:
			cfg.author = plugin_cfg.get_value("plugin", "author")

		if plugin_cfg.get_value("plugin", "script") != null:
			cfg.script_gd = plugin_cfg.get_value("plugin", "script")

func _save_plugin_config_resource(cfg : PluginConfig) -> void:
	var err = ResourceSaver.save(cfg, PLUGIN_CFG_RESOURCE_PATH)
	if err == OK:
		print("Saved PluginConfig at: ", PLUGIN_CFG_RESOURCE_PATH)
	else:
		push_error("Failed to save PluginConfig at: ", PLUGIN_CFG_RESOURCE_PATH, " err=", err)

# -----------------------------------------------------------------------------
# Android export plugin (unchanged)
# -----------------------------------------------------------------------------

class AndroidExportPlugin extends EditorExportPlugin:
	const AAR_PATH := "res://addons/aide_de_cam/android/Aide-De-Cam-release.aar"

	func _get_name() -> String:
		return PLUGIN_NAME

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray([AAR_PATH])
