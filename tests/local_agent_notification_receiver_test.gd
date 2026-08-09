extends SceneTree

const ReceiverScript = preload("res://scripts/local_agent_notification_receiver.gd")

var _received: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var port := 38572 + (Time.get_ticks_msec() % 1000)
	var receiver = ReceiverScript.new()
	if not receiver.start(port):
		_fail("receiver failed to bind")
		return
	receiver.notification_received.connect(_on_notification_received)

	var sender := PacketPeerUDP.new()
	if sender.set_dest_address("127.0.0.1", port) != OK:
		receiver.stop()
		_fail("sender failed to set destination")
		return
	var payload := JSON.stringify({
		"type": "agent-turn-complete",
		"source": "codex",
		"thread_id": "thread-test",
		"turn_id": "turn-test",
	})
	var payload_bytes := payload.to_utf8_buffer()
	if sender.put_packet(payload_bytes) != OK:
		receiver.stop()
		sender.close()
		_fail("sender failed to send packet")
		return

	await process_frame
	receiver.poll()
	receiver.stop()
	sender.close()

	if _received.size() != 1:
		_fail("expected one notification, got %d" % _received.size())
		return
	if String(_received[0].get("type", "")) != "agent-turn-complete":
		_fail("notification type was not preserved")
		return

	print("LOCAL_AGENT_NOTIFICATION_RECEIVER_TEST_OK")
	quit(0)


func _on_notification_received(notification: Dictionary) -> void:
	_received.append(notification)


func _fail(message: String) -> void:
	printerr("LOCAL_AGENT_NOTIFICATION_RECEIVER_TEST_FAILED: %s" % message)
	quit(1)
