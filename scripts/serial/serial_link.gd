class_name SerialLink
extends RefCounted

## Interface da camada serial. O jogo só fala com esta API; a
## implementação real (GdSerialLink, sobre a extensão GdSerial) ou a
## vazia (NullSerialLink, quando a extensão não carregou) fica por
## conta da fábrica `create_best`. Para trocar de extensão serial no
## futuro, escreva outro backend com estes mesmos métodos.

signal line_received(line: String)
signal opened(port: String)
signal closed(port: String)

static func create_best() -> SerialLink:
	if ClassDB.class_exists(&"GdSerialManager"):
		return GdSerialLink.new()
	return NullSerialLink.new()

## A extensão serial está presente e carregada?
func available() -> bool:
	return false

## Nomes das portas disponíveis (ex.: ["COM3", "COM5"]).
func list_ports() -> PackedStringArray:
	return PackedStringArray()

func open_port(_port: String, _baud: int = GameDef.SERIAL_BAUD) -> bool:
	return false

func close_port() -> void:
	pass

func is_open() -> bool:
	return false

func send_line(_line: String) -> bool:
	return false

## Chamado a cada frame pelo jogo.
func poll() -> void:
	pass
