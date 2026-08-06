class_name CodexNotificationReceiver
extends RefCounted

signal notification_received(notification: Dictionary)

const DEFAULT_PORT := 38571
const BIND_ADDRESS := "127.0.0.1"
const MAX_PACKET_BYTES := 8192

var _socket: PacketPeerUDP
var _port := 0


func start(port := DEFAULT_PORT) -> bool:
	stop()
	_socket = PacketPeerUDP.new()
	var result := _socket.bind(port, BIND_ADDRESS)
	if result != OK:
		_socket.close()
		_socket = null
		return false
	_port = port
	return true


func poll() -> void:
	if _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		if packet.size() > MAX_PACKET_BYTES:
			continue
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if parsed is Dictionary:
			notification_received.emit(parsed)


func stop() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_port = 0


func is_running() -> bool:
	return _socket != null


func get_port() -> int:
	return _port
