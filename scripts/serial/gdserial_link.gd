class_name GdSerialLink
extends SerialLink

## Backend real sobre a extensão GdSerial v0.3.4 (MIT),
## https://github.com/SujithChristopher/gdserial
##
## Usa a classe GdSerialManager da extensão: leitura em thread própria,
## modo LINE_BUFFERED (cada evento é uma linha terminada em \n, exato
## formato do nosso protocolo) e sinais data_received / port_disconnected.
## A classe é instanciada via ClassDB para o projeto continuar abrindo
## mesmo se a extensão não carregar (o backend nulo assume).

var _mgr: Object = null
var _port := ""

func _init() -> void:
	_mgr = ClassDB.instantiate(&"GdSerialManager")
	if _mgr == null:
		return
	_mgr.connect("data_received", _on_data)
	_mgr.connect("port_disconnected", _on_disconnected)

func available() -> bool:
	return _mgr != null

func list_ports() -> PackedStringArray:
	var found := PackedStringArray()
	if _mgr == null:
		return found
	var ports: Dictionary = _mgr.list_ports()
	for key in ports:
		var info: Variant = ports[key]
		if info is Dictionary and info.has("port_name"):
			found.append(str(info["port_name"]))
	found.sort()
	return found

func open_port(port: String, baud: int = GameDef.SERIAL_BAUD) -> bool:
	if _mgr == null or port.is_empty():
		return false
	if is_open():
		close_port()
	# timeout 100 ms; modo 1 = MODE_LINE_BUFFERED (uma linha por evento).
	if _mgr.open(port, baud, 100, 1):
		_port = port
		opened.emit(_port)
		return true
	return false

func close_port() -> void:
	if _mgr != null and not _port.is_empty():
		_mgr.close(_port)
		var fechada := _port
		_port = ""
		closed.emit(fechada)

func is_open() -> bool:
	return _mgr != null and not _port.is_empty() and bool(_mgr.is_open(_port))

func send_line(line: String) -> bool:
	if not is_open():
		return false
	return bool(_mgr.write(_port, (line + "\n").to_utf8_buffer()))

func poll() -> void:
	if _mgr != null:
		_mgr.poll_events()

func _on_data(port: String, data: PackedByteArray) -> void:
	if port != _port:
		return
	var line := data.get_string_from_utf8().strip_edges()
	if not line.is_empty():
		line_received.emit(line)

func _on_disconnected(port: String) -> void:
	if port != _port:
		return
	_port = ""
	closed.emit(port)
