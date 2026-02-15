extends Node

func _ready() -> void:
	randomize()
	await get_tree().create_timer(0.5).timeout

	var runner := HarnessRunner.new()
	add_child(runner)

	runner.add_test(TestSecurityVectorsProbe.new())

	#var report := await runner.run_all()
	var report := await runner.run_all()

	print("Harness finished: ", report["summary"])
	%StatusLabel.stop_draw_progress()
	%StatusLabel.text = "Harness finished: %s" % [report["summary"]]
	var exit_code := 0 if report["summary"]["failed"] == 0 else 1
	
	#get_tree().quit(exit_code)
