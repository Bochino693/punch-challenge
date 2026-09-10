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

func descricao() -> String:
	return "extensão nativa"

## OS FABRICANTES DE CONVERSOR USB-SERIAL QUE VIRAM ARDUINO.
##
## Um PC de gabinete quase nunca tem só uma porta COM: o Windows inventa
## COM3 e COM4 para o Bluetooth, o leitor de cartão traz a dele, e a
## impressora fiscal traz outra. Abrir a primeira da lista é sorteio — e
## a porta errada não responde, o jogo fica esperando um READY que nunca
## vem, e o operador conclui que o Arduino não funciona.
##
## Estes são os identificadores dos conversores que aparecem num Arduino:
## 2341/2A03 são os oficiais, 1A86 é o CH340 dos clones de Nano, 0403 é o
## FTDI e 10C4 é o CP210x. Uma porta com um desses vai para a frente da
## fila.
const FABRICANTES_ARDUINO := ["2341", "2A03", "1A86", "0403", "10C4", "1B4F"]

func list_ports() -> PackedStringArray:
	var found := PackedStringArray()
	if _mgr == null:
		return found
	var prioritarias := PackedStringArray()
	var ports: Dictionary = _mgr.list_ports()
	for key in ports:
		var info: Variant = ports[key]
		if not (info is Dictionary) or not info.has("port_name"):
			continue
		var port_name := str(info["port_name"])
		# Algumas imagens Linux anunciam ttyS0 mesmo sem o dispositivo.
		# No Windows as portas COM não usam caminho e passam normalmente.
		if port_name.begins_with("/dev/") and not FileAccess.file_exists(port_name):
			continue
		if _cheira_a_arduino(info as Dictionary):
			prioritarias.append(port_name)
		else:
			found.append(port_name)
	_ordenar(prioritarias)
	_ordenar(found)
	# As suspeitas primeiro; as outras logo atrás, porque a extensão nem
	# sempre informa o fabricante e uma porta anônima ainda pode ser a
	# placa.
	var fila := PackedStringArray()
	fila.append_array(prioritarias)
	fila.append_array(found)
	return fila

func _cheira_a_arduino(info: Dictionary) -> bool:
	var texto := ""
	for chave in ["vid", "VID", "vendor_id", "manufacturer", "product", "description", "type"]:
		if info.has(chave):
			texto += str(info[chave]).to_upper() + " "
	if texto.is_empty():
		return false
	for marca in FABRICANTES_ARDUINO:
		if marca in texto:
			return true
	return "ARDUINO" in texto or "CH340" in texto or "USB" in texto

## Ordem NATURAL, e não alfabética: `sort()` põe COM10 antes de COM3,
## porque compara texto. Numa máquina com muitas portas isso muda qual
## delas é tentada primeiro, por um motivo que não tem nada a ver com a
## placa.
func _ordenar(portas: PackedStringArray) -> void:
	var lista: Array = []
	lista.assign(portas)
	lista.sort_custom(func(a, b): return _chave(str(a)) < _chave(str(b)))
	for i in range(lista.size()):
		portas[i] = str(lista[i])

func _chave(porta: String) -> String:
	var digitos := ""
	for c in porta:
		if c >= "0" and c <= "9":
			digitos += c
	if digitos.is_empty():
		return porta
	return "%s%08d" % [porta.replace(digitos, ""), int(digitos)]

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
