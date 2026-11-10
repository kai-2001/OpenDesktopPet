extends SceneTree

# The single-instance link must hand its port over only once the running copy
# lets go, and must ignore anything that is not a pet asking.

const InstanceLinkScript = preload("res://scripts/instance_link.gd")
const TEST_PORT := 49231

var _failures := 0


func _init() -> void:
	var running = InstanceLinkScript.new(TEST_PORT)
	_assert_equal(running.claim()["role"], InstanceLinkScript.ROLE_PRIMARY, "the first copy claims the port")
	var waiting = InstanceLinkScript.new(TEST_PORT)
	_assert_true(not waiting.wait_until_free(300), "a newer copy waits while the old one still runs")
	running.close()
	_assert_true(waiting.wait_until_free(2000), "a newer copy takes over once the old one exits")
	_assert_true(waiting.is_listening(), "the newer copy then answers later launches")

	# Unrelated or oversized requests get no answer and never reach the decider.
	var decided := [0]
	var decider := func(_version: String) -> String:
		decided[0] += 1
		return InstanceLinkScript.REPLY_STAY
	for payload: String in ["GET / HTTP/1.1\r\n\r\n", "{\"protocol\":\"other\"}\n", "x".repeat(5000)]:
		var peer := StreamPeerTCP.new()
		peer.connect_to_host(InstanceLinkScript.HOST, TEST_PORT)
		var deadline := Time.get_ticks_msec() + 1000
		while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
			peer.poll()
			OS.delay_msec(10)
		peer.put_data(payload.to_utf8_buffer())
		for _i in 20:
			waiting.poll(decider)
			OS.delay_msec(10)
		peer.disconnect_from_host()
	_assert_equal(decided[0], 0, "only pet launch requests are answered")
	_assert_equal(waiting.answered, 0, "ignored requests are not counted")
	waiting.close()

	if _failures > 0:
		push_error("INSTANCE_LINK_TEST_FAILED: %d" % _failures)
		quit(1)
		return
	print("INSTANCE_LINK_TEST_OK")
	quit(0)


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAILED: " + label)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failures += 1
	push_error("FAILED: %s (expected %s, got %s)" % [label, expected, actual])
