extends SceneTree

## O JOGO INTEIRO ATE A PORTA, SEM PLACA E SEM MENTIRA NO MEIO.
##
## Roda por conta do tools/conferir_ponte.sh, que antes de chamar aqui
## abre um par de pseudo-terminais e fica do outro lado bancando o
## Arduino. O que este arquivo exercita e a pilha de verdade: o backend
## PonteProcessoLink, o ajudante tools/ponte_serial.sh, o cano entre os
## dois e uma porta serial que o sistema operacional trata como porta
## serial. So o fio de cobre fica de fora.
##
## E a diferenca importa: os testes do jogo trocam o ajudante por um de
## mentira, entao um defeito no ajudante DE VERDADE passaria por eles sem
## ser notado -- e apareceria no gabinete como "o Arduino nao funciona".

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var porta := OS.get_environment("PUNCH_PORTA_FALSA")
	if porta.is_empty():
		print("FALHA: sem PUNCH_PORTA_FALSA")
		quit(1)
		return
	PonteProcessoLink.receita_de_teste = [
		[ProjectSettings.globalize_path("res://tools/ponte_serial.sh")], ["/bin/sh"]
	]
	var ponte := PonteProcessoLink.new()
	if not ponte.available():
		print("FALHA: a ponte nao subiu")
		quit(1)
		return

	var recebidas: Array[String] = []
	ponte.line_received.connect(func(l: String) -> void: recebidas.append(l))
	var abertas: Array[String] = []
	ponte.opened.connect(func(p: String) -> void: abertas.append(p))

	if not await _ate(ponte, func() -> bool: return ponte.open_port(porta, 115200)):
		print("FALHA: open_port recusou")
		quit(1)
		return
	if not await _ate(ponte, func() -> bool: return abertas.has(porta)):
		print("FALHA: a porta nunca confirmou abertura")
		quit(1)
		return
	# O `READY` e o que prova que a placa esta do outro lado. Uma linha
	# com um `\r` invisivel no fim nao seria reconhecida por comparacao
	# nenhuma -- e a porta certa seria descartada como muda.
	if not await _ate(ponte, func() -> bool: return recebidas.has("READY,PUNCH_MPU6050,V3")):
		print("FALHA: READY nao chegou inteiro; recebi ", recebidas)
		quit(1)
		return
	if ArduinoProtocol.parse("READY,PUNCH_MPU6050,V3")["type"] != "READY":
		print("FALHA: o protocolo nao reconheceu a linha")
		quit(1)
		return

	# Ida e volta: sem isto nao ha PING, nem CONFIG, nem fitas.
	recebidas.clear()
	ponte.send_line("PING")
	if not await _ate(ponte, func() -> bool: return recebidas.has("PONG")):
		print("FALHA: PONG nao voltou; recebi ", recebidas)
		quit(1)
		return

	# Rajada: o botao apertado depressa manda linhas coladas, e nenhuma
	# pode se perder nem se embaralhar no caminho.
	recebidas.clear()
	ponte.send_line("RAJADA")
	if not await _ate(ponte, func() -> bool: return recebidas.size() >= 30):
		print("FALHA: a rajada chegou pela metade (", recebidas.size(), ")")
		quit(1)
		return
	for i in range(30):
		if recebidas[i] != "RAJADA,%d" % i:
			print("FALHA: rajada fora de ordem em ", i, ": ", recebidas[i])
			quit(1)
			return

	ponte.encerrar()
	PonteProcessoLink.receita_de_teste = []
	print("PONTA_A_PONTA_OK")
	quit(0)

func _ate(ponte: PonteProcessoLink, condicao: Callable) -> bool:
	for _i in range(300):
		ponte.poll()
		if bool(condicao.call()):
			return true
		OS.delay_msec(10)
		await process_frame
	return false
