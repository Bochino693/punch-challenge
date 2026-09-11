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

func nome_do_caminho() -> String:
	return SerialLink.CAMINHO_NATIVO

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
	## UMA PORTA DESCARTADA PELO FILTRO NUNCA MAIS É TENTADA, então o
	## filtro tem de ser o último a falar. As descartadas ficam guardadas
	## aqui: se o filtro esvaziar a lista inteira, elas voltam. Uma porta
	## suspeita que talvez não exista ainda é melhor do que a certeza de
	## não ter porta nenhuma para tentar.
	var descartadas := PackedStringArray()
	var ports: Variant = _mgr.list_ports()
	if not (ports is Dictionary):
		return found
	for key in (ports as Dictionary):
		var info: Variant = (ports as Dictionary)[key]
		# O NOME DA PORTA PODE VIR NA CHAVE, E NÃO NO VALOR. Versões
		# diferentes da extensão respondem em formatos diferentes; exigir
		# um formato só é como o jogo ficava com a lista vazia — e lista
		# vazia é o "PROCURANDO ARDUINO…" que nunca termina.
		var port_name := ""
		if info is Dictionary and (info as Dictionary).has("port_name"):
			port_name = str((info as Dictionary)["port_name"])
		elif info is String and not str(info).is_empty():
			port_name = str(info)
		else:
			port_name = str(key)
		port_name = port_name.strip_edges()
		if port_name.is_empty():
			continue
		# Algumas imagens Linux anunciam ttyS0 mesmo sem o dispositivo.
		# No Windows as portas COM não usam caminho e passam normalmente.
		if port_name.begins_with("/dev/") and not FileAccess.file_exists(port_name):
			descartadas.append(port_name)
			continue
		if info is Dictionary and _cheira_a_arduino(info as Dictionary):
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
	if fila.is_empty() and not descartadas.is_empty():
		_ordenar(descartadas)
		return descartadas
	return fila

## AQUI A FILA DE PRIORIDADE NÃO FUNCIONAVA — E NINGUÉM PODIA SABER.
##
## A lista de chaves era um chute: `vid`, `manufacturer`, `product`,
## `description`, `type`. A extensão não usa NENHUMA delas. Ela responde
## `port_name`, `port_type` e `device_name` — e `Dictionary.has("type")`
## é exato, então `port_type` nunca batia com `type`. O texto examinado
## saía SEMPRE vazio, a função respondia SEMPRE falso, e a fila de
## prioridade — a parte que faz a placa ser tentada antes do Bluetooth —
## nunca existiu de verdade. Num PC com seis portas COM isso é a
## diferença entre achar a placa na primeira tentativa e achar na sexta,
## com nove segundos de espera em cada uma que não é.
##
## A correção é não chutar nome de chave nenhum: varre o dicionário
## inteiro, chaves e valores, que é o que sobrevive à próxima versão da
## extensão.
func _cheira_a_arduino(info: Dictionary) -> bool:
	var texto := ""
	for chave in info:
		texto += str(chave).to_upper() + " " + str(info[chave]).to_upper() + " "
	if texto.strip_edges().is_empty():
		return false
	for marca in FABRICANTES_ARDUINO:
		if marca in texto:
			return true
	return "ARDUINO" in texto or "CH340" in texto or "CH341" in texto or "USB" in texto

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
	# O meio de linha que ficou nao vale para a proxima porta.
	_sobras.clear()
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

## O QUE SOBROU DE UMA LEITURA, esperando o \n que fecha a linha.
var _sobras := PackedByteArray()

## Teto do que se guarda sem nunca ver um \n. Placa muda com o cabo na
## tomada, ou porta que nao e Arduino nenhum, despeja bytes para sempre:
## sem um teto, isso e memoria subindo a noite inteira.
const LIMITE_DE_SOBRAS := 4096

## AQUI ESTAVAM DOIS DEFEITOS, e os dois faziam SUMIR o soco.
##
## 1. CADA PEDACO ERA TRATADO COMO UMA LINHA INTEIRA.
##    A serial nao entrega linhas, entrega bytes: um `HIT,4.10,14.00,50,X`
##    chega partido em dois pedacos com frequencia, e dois pedacos chegam
##    juntos com a mesma frequencia. Tratar cada pedaco como uma linha
##    fazia o `ArduinoProtocol.parse` recusar as duas metades -- e a
##    recusa e SILENCIOSA, porque e a mesma recusa que protege o jogo de
##    lixo. O sintoma exato: "o Arduino conecta, mas os impactos nao
##    chegam durante a partida". E piora com a camera ligada ou a F9
##    aberta, porque o intervalo entre leituras aumenta e os pedacos
##    ficam maiores.
##
## 2. OS BYTES ERAM LIDOS COMO UTF-8.
##    `get_string_from_utf8()` num fluxo que e ASCII puro por contrato:
##    qualquer byte de ruido de linha, lixo do reset da placa ou baud
##    divergente vira "Unicode parsing error: Byte N is not a correct
##    continuation byte after XX" no console -- e leva a linha junto.
##
## Agora os bytes sao acumulados, cortados no \n, e so o que e ASCII
## imprimivel passa. O protocolo inteiro cabe em 0x20..0x7E, entao
## descartar o resto nao perde nada que o jogo saiba ler.
func _on_data(port: String, data: PackedByteArray) -> void:
	if port != _port:
		return
	_sobras.append_array(data)
	if _sobras.size() > LIMITE_DE_SOBRAS:
		# Fica com a cauda: o comeco ja e lixo velho sem fim de linha.
		_sobras = _sobras.slice(_sobras.size() - LIMITE_DE_SOBRAS)
	while true:
		var corte := _sobras.find(10)   # \n
		if corte < 0:
			break
		var cru := _sobras.slice(0, corte)
		_sobras = _sobras.slice(corte + 1)
		var linha := _somente_ascii(cru)
		if not linha.is_empty():
			line_received.emit(linha)

## So o ASCII imprimivel sobrevive. O \r do fim de linha do Windows cai
## aqui junto com o ruido, que e o que se quer.
static func _somente_ascii(cru: PackedByteArray) -> String:
	var limpo := PackedByteArray()
	for b in cru:
		if b >= 32 and b <= 126:
			limpo.append(b)
	return limpo.get_string_from_ascii().strip_edges()

func _on_disconnected(port: String) -> void:
	if port != _port:
		return
	_port = ""
	closed.emit(port)
