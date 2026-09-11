extends SceneTree

## A SERIAL NAO ENTREGA LINHAS, ENTREGA BYTES.
##
## Este teste existe por causa de um defeito que fazia o soco SUMIR sem
## deixar rastro: cada pedaco que chegava da porta era tratado como uma
## linha inteira. Um `HIT,...` partido em dois pedacos virava duas
## metades invalidas, o protocolo recusava as duas -- em silencio, que e
## o certo para lixo -- e o jogador batia sem a maquina marcar nada.
##
## O sintoma era "o Arduino conecta, mas os impactos nao chegam durante a
## partida", e piorava com a camera ligada ou a F9 aberta, porque o
## intervalo entre leituras aumenta e os pedacos ficam maiores.
##
## Os casos abaixo sao os quatro jeitos de a serial partir uma mensagem.

var _colhidas: Array[String] = []

func _initialize() -> void:
	_test_linha_inteira()
	_test_linha_partida_ao_meio()
	_test_duas_linhas_num_pedaco_so()
	_test_byte_a_byte()
	_test_lixo_nao_ascii_nao_derruba_a_linha_boa()
	_test_teto_das_sobras()
	_test_diagnosticos_da_placa()
	print("LINHA_SERIAL_OK")
	quit(0)

func _falhar(o_que: String) -> void:
	push_error(o_que)
	printerr("FALHOU: %s" % o_que)
	quit(1)

## Monta um elo pronto para receber bytes, sem abrir porta nenhuma.
func _elo() -> GdSerialLink:
	var elo := GdSerialLink.new()
	elo.set("_port", "PORTA_DE_TESTE")
	_colhidas.clear()
	elo.line_received.connect(func(l: String) -> void: _colhidas.append(l))
	return elo

func _mandar(elo: GdSerialLink, texto: String) -> void:
	elo._on_data("PORTA_DE_TESTE", texto.to_ascii_buffer())

const HIT := "HIT,4.10,14.00,50,X"

func _test_linha_inteira() -> void:
	var elo := _elo()
	_mandar(elo, HIT + "\n")
	if _colhidas != [HIT]:
		_falhar("linha inteira: %s" % str(_colhidas))

func _test_linha_partida_ao_meio() -> void:
	# O caso que fazia o soco sumir.
	var elo := _elo()
	_mandar(elo, "HIT,4.10,14")
	if not _colhidas.is_empty():
		_falhar("meia linha nao pode virar mensagem: %s" % str(_colhidas))
	_mandar(elo, ".00,50,X\n")
	if _colhidas != [HIT]:
		_falhar("linha partida ao meio: %s" % str(_colhidas))

func _test_duas_linhas_num_pedaco_so() -> void:
	var elo := _elo()
	_mandar(elo, "PONG\n" + HIT + "\nPINS,0,0\n")
	if _colhidas != ["PONG", HIT, "PINS,0,0"]:
		_falhar("tres linhas num pedaco: %s" % str(_colhidas))

func _test_byte_a_byte() -> void:
	# O pior caso: um byte por leitura.
	var elo := _elo()
	for i in HIT.length():
		_mandar(elo, HIT[i])
	if not _colhidas.is_empty():
		_falhar("sem \\n nao ha mensagem: %s" % str(_colhidas))
	_mandar(elo, "\n")
	if _colhidas != [HIT]:
		_falhar("byte a byte: %s" % str(_colhidas))

func _test_lixo_nao_ascii_nao_derruba_a_linha_boa() -> void:
	# Ruido de linha, reset da placa, baud divergente: bytes fora do
	# ASCII imprimivel. Eram eles que viravam "Unicode parsing error" no
	# console. Agora somem sem levar a mensagem junto.
	var elo := _elo()
	var cru := PackedByteArray([0xDA, 0xF4, 0x00])
	cru.append_array(HIT.to_ascii_buffer())
	cru.append_array(PackedByteArray([0x0D, 0x0A]))   # \r\n do Windows
	elo._on_data("PORTA_DE_TESTE", cru)
	if _colhidas != [HIT]:
		_falhar("lixo nao-ASCII: %s" % str(_colhidas))

func _test_teto_das_sobras() -> void:
	# Porta que nao e Arduino e despeja bytes sem nunca mandar \n: a
	# memoria nao pode subir a noite inteira.
	var elo := _elo()
	for i in 40:
		_mandar(elo, "x".repeat(500))
	var sobras: PackedByteArray = elo.get("_sobras")
	if sobras.size() > GdSerialLink.LIMITE_DE_SOBRAS:
		_falhar("sobras sem teto: %d bytes" % sobras.size())
	# e depois disso uma linha boa ainda passa
	_mandar(elo, "\n" + HIT + "\n")
	if not _colhidas.has(HIT):
		_falhar("depois do lixo a linha boa tem de passar: %s" % str(_colhidas))


## AS MENSAGENS DE DIAGNÓSTICO DA PLACA.
##
## Elas são a diferença entre "nada acontece" e uma frase que aponta o
## limiar errado. Se o protocolo as recusar, elas somem exatamente como
## sumia o HIT — em silêncio — e o diagnóstico volta a ser adivinhação.
func _test_diagnosticos_da_placa() -> void:
	var r := ArduinoProtocol.parse("REJECT,GIRO,9.20,45,3.1,2.10")
	if r["type"] != "REJECT" or str(r["reason"]) != "GIRO":
		_falhar("REJECT não foi entendido: %s" % str(r))
	if not is_equal_approx(float(r["peak_g"]), 9.2) or not is_equal_approx(float(r["speed"]), 2.10):
		_falhar("números do REJECT: %s" % str(r))

	var st := ArduinoProtocol.parse("STATUS,0,0.04,2.50")
	if st["type"] != "STATUS" or bool(st["measuring"]):
		_falhar("STATUS não foi entendido: %s" % str(st))
	if not is_equal_approx(float(st["force_g"]), 0.04):
		_falhar("a força agora: %s" % str(st))
	if not is_equal_approx(float(st["trigger_g"]), 2.50):
		_falhar("o gatilho: %s" % str(st))

	# Mensagem truncada continua sendo lixo, e lixo não vira diagnóstico.
	if ArduinoProtocol.parse("REJECT,GIRO,9.20")["type"] != "":
		_falhar("REJECT incompleto tem de ser recusado")
