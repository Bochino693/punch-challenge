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

## A ESCOLHA DO CAMINHO ATÉ O ARDUINO, DO MELHOR PARA O QUE SEMPRE EXISTE.
##
## 1. A extensão nativa (`gdserial`), quando o Godot conseguiu carregá-la:
##    é a mais rápida e a única que fala a porta direto do processo.
## 2. A PONTE POR PROCESSO, quando não conseguiu — e é este o caso do
##    gabinete, onde a extensão não carregou e a máquina inteira ficou
##    morta: START, CRÉDITO, sensor e fitas. A ponte não depende de
##    binário nenhum que possa faltar; ela usa o que o sistema já tem
##    (PowerShell no Windows, `stty` no Linux).
## 3. O backend vazio, só para o jogo abrir e explicar o que houve.
##
## Ter o degrau 2 é a diferença entre "não funciona nada e ninguém sabe
## por quê" e uma máquina que trabalha.
static func create_best() -> SerialLink:
	# Uma saída pela porta dos fundos para quem estiver com a máquina na
	# mão: `PUNCH_SERIAL=ponte` pula a extensão nativa mesmo que ela tenha
	# carregado. Serve para comparar os dois caminhos no mesmo gabinete
	# sem trocar arquivo nenhum de lugar.
	var forcado := OS.get_environment("PUNCH_SERIAL").strip_edges().to_lower()
	if forcado != "ponte" and ClassDB.class_exists(&"GdSerialManager"):
		var nativa := GdSerialLink.new()
		if nativa.available():
			return nativa
	var ponte := PonteProcessoLink.new()
	if ponte.available():
		return ponte
	var vazia := NullSerialLink.new()
	vazia.explicar(ponte.motivo_da_falta())
	return vazia

## A extensão serial está presente e carregada?
func available() -> bool:
	return false

## Como o jogo está falando com a placa, em duas palavras, para a Central.
func descricao() -> String:
	return "nenhuma"

## Quando não há caminho nenhum: a frase que diz por quê.
func motivo_da_falta() -> String:
	return ""

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

## Solta tudo o que o backend segurar fora do processo do jogo.
func encerrar() -> void:
	pass
