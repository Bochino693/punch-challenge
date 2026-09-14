extends SceneTree

class ManagerFalso extends RefCounted:
	signal data_received(port: String, data: PackedByteArray)
	signal port_disconnected(port: String)
	var busy := false
	var writes := 0
	func poll_events() -> void:
		busy = true
		data_received.emit("COM_TEST", "READY,PUNCH_MPU6050,V9\n".to_ascii_buffer())
		busy = false
	func is_open(_port: String) -> bool:
		return true
	func write(_port: String, _data: PackedByteArray) -> bool:
		assert(not busy, "CONFIG reentered the native manager during poll_events")
		writes += 1
		return true
	func close(_port: String) -> void:
		pass

func _initialize() -> void:
	var link := GdSerialLink.new()
	var manager := ManagerFalso.new()
	link._mgr = manager
	link._port = "COM_TEST"
	manager.data_received.connect(link._on_data)
	manager.port_disconnected.connect(link._on_disconnected)
	link.line_received.connect(func(_line: String) -> void:
		assert(link.send_line("CONFIG,X,0.5,1,2,20"))
	)
	link.poll()
	assert(manager.writes == 1)
	link.encerrar()
	print("NATIVE_REENTRY_OK")
	quit(0)
