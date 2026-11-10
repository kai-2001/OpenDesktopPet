class_name InstanceLink
extends RefCounted

# Keeps one running pet per save folder. Two pets sharing a save overwrite
# each other's progress, so the first one listens on a local port derived
# from its user data folder and a later launch asks it what to do instead of
# starting a second pet. Isolated tests use their own data folder, so they
# never reach the user's running pet.

const UpdateCheckServiceScript = preload("res://scripts/update_check_service.gd")

const PROTOCOL := "open-desktop-pet-instance/1"
const PORT_BASE := 41000
const PORT_SPAN := 8000
const HOST := "127.0.0.1"
const CONNECT_TIMEOUT_MS := 1500
const REPLY_TIMEOUT_MS := 3000
const MAX_MESSAGE_BYTES := 4096

## The launching copy may stay: it is newer, so the running one exits.
const REPLY_YIELD := "yield"
## The launching copy must exit: the running one shows its pet instead.
const REPLY_STAY := "stay"

const ROLE_PRIMARY := "primary"
const ROLE_SECONDARY := "secondary"

var port := 0
## Valid launch requests answered so far.
var answered := 0
var _server: TCPServer
var _clients: Array[Dictionary] = []


func _init(port_override := 0) -> void:
	port = port_override if port_override > 0 else port_for(OS.get_user_data_dir())


static func port_for(user_data_dir: String) -> int:
	var digest := user_data_dir.to_lower().sha256_buffer()
	var value := (digest[0] << 16) | (digest[1] << 8) | digest[2]
	return PORT_BASE + value % PORT_SPAN


## What a running copy tells a launching one, from both versions.
static func decide(incoming_version: String, running_version: String) -> String:
	if UpdateCheckServiceScript.is_newer(incoming_version, running_version):
		return REPLY_YIELD
	return REPLY_STAY


static func current_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", ""))


## Becomes the running copy, or asks the running copy what to do.
## Returns {"role": ROLE_PRIMARY} or {"role": ROLE_SECONDARY, "reply": ...}.
## A port held by something that does not answer as a pet still starts this
## copy, unlinked, so an unrelated program never keeps the pet from opening.
func claim(version := current_version()) -> Dictionary:
	if _listen():
		return {"role": ROLE_PRIMARY}
	var reply := _ask_running(version)
	if reply.is_empty():
		return {"role": ROLE_PRIMARY, "unlinked": true}
	return {"role": ROLE_SECONDARY, "reply": reply}


## Waits for a running copy that agreed to yield to release the port.
func wait_until_free(timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if _listen():
			return true
		OS.delay_msec(100)
	return false


func is_listening() -> bool:
	return _server != null and _server.is_listening()


## Answers launching copies. `decider` receives the launching version and
## returns REPLY_YIELD or REPLY_STAY; it is called once per valid request.
func poll(decider: Callable) -> void:
	if not is_listening():
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer != null:
			_clients.append({"peer": peer, "buffer": "", "since": Time.get_ticks_msec()})
	for index in range(_clients.size() - 1, -1, -1):
		var client: Dictionary = _clients[index]
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		var status := peer.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED \
				or Time.get_ticks_msec() - int(client.since) > REPLY_TIMEOUT_MS:
			peer.disconnect_from_host()
			_clients.remove_at(index)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_data(available)
			if int(chunk[0]) == OK:
				client.buffer = String(client.buffer) + (chunk[1] as PackedByteArray).get_string_from_utf8()
		var buffer := String(client.buffer)
		if buffer.length() > MAX_MESSAGE_BYTES:
			peer.disconnect_from_host()
			_clients.remove_at(index)
			continue
		var line_end := buffer.find("\n")
		if line_end < 0:
			continue
		var request: Variant = _parse(buffer.substr(0, line_end))
		if request is Dictionary and String(request.get("protocol", "")) == PROTOCOL:
			var reply := String(decider.call(String(request.get("version", ""))))
			answered += 1
			peer.put_data((JSON.stringify({"protocol": PROTOCOL, "reply": reply}) + "\n").to_utf8_buffer())
		peer.disconnect_from_host()
		_clients.remove_at(index)


func close() -> void:
	for client: Dictionary in _clients:
		(client.peer as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	if _server != null:
		_server.stop()
	_server = null


func _listen() -> bool:
	if is_listening():
		return true
	var server := TCPServer.new()
	if server.listen(port, HOST) != OK:
		return false
	_server = server
	return true


func _ask_running(version: String) -> String:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host(HOST, port) != OK:
		return ""
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		if Time.get_ticks_msec() > deadline:
			return ""
		OS.delay_msec(10)
		peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return ""
	peer.put_data((JSON.stringify({"protocol": PROTOCOL, "version": version}) + "\n").to_utf8_buffer())
	var buffer := ""
	deadline = Time.get_ticks_msec() + REPLY_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_data(available)
			if int(chunk[0]) == OK:
				buffer += (chunk[1] as PackedByteArray).get_string_from_utf8()
			var line_end := buffer.find("\n")
			if line_end >= 0:
				peer.disconnect_from_host()
				var response: Variant = _parse(buffer.substr(0, line_end))
				if response is Dictionary and String(response.get("protocol", "")) == PROTOCOL:
					var reply := String(response.get("reply", ""))
					if reply in [REPLY_YIELD, REPLY_STAY]:
						return reply
				return ""
		elif peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		OS.delay_msec(10)
	peer.disconnect_from_host()
	return ""


## Quietly rejects anything that is not JSON, since any local program can
## connect to the port.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null
