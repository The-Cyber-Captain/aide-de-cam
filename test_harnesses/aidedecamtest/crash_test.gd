extends Node

func _ready():
	print("Imma started")
	await get_tree().create_timer(1.0).timeout
	var subdir := "B".repeat(1000) 
	var data_primary = AideDeCam.get_camera_capabilities_to_file(subdir)
	var data_secondary = Engine.get_singleton("AideDeCam").callv("getCameraCapabilitiesToFile", [subdir])

	#print("Primary: %s" % [data_primary])
	#print("Secondary: %s" % [data_secondary])
func _yell(message :String):
	print("I'm yelling %s" % message)
