extends Node
const EXIT_DELAY = 10


func _ready() -> void:
	randomize()
	# UX wait. Should really be removed for 'pure' edge-case testing. But... come on! :-D
	await get_tree().create_timer(0.75).timeout
	%StatusLabel.start_draw_progress()

	var runner := HarnessRunner.new()
	add_child(runner)

	runner.add_test(TestNonSecurityContract.new())
	runner.add_test(TestSignalAndFallback.new())
	runner.add_test(TestSecurityVectorsProbe.new())

	var report := await runner.run_all()

	print("Harness finished: ", report["summary"])
	%StatusLabel.stop_draw_progress()
	var status : String = "Harness finished: "
	var summary : Dictionary = report["summary"]
	for item_key in summary:
		status += "%s: %s\n" % [item_key, summary[item_key]]
	%StatusLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	%StatusLabel.text = status
	var exit_code := 0 if report["summary"]["failed"] == 0 else 1
	
	await get_tree().create_timer(EXIT_DELAY).timeout
	get_tree().quit(exit_code)
