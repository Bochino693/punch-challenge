extends SceneTree

## A CAMADA SERIAL QUE NÃO DESISTE — e cada teste aqui é um defeito que
## já aconteceu numa máquina de verdade.
##
## O `tests/test_show_flow.gd` prova as regras do espetáculo. Este prova a
## única coisa de que todas elas dependem: que a máquina ACHA o Arduino, e
## que continua achando depois de tudo o que dá errado num PC que não é o
## de quem escreveu o jogo. Os defeitos cobrados aqui tinham todos o mesmo
## sintoma na tela — "PROCURANDO ARDUINO…" para sempre — e causas
## diferentes, que é o que fazia o diagnóstico não bater de um PC para o
## outro.
##
## Roda sem placa, sem porta COM e sem câmera:
##   godot --headless --path . --script tests/test_serial_teimoso.gd

## Um backend de mentira, para cobrar do JOGO o que só o jogo decide.
class LinkFalso extends SerialLink:
	var vezes_polled := 0
	var vezes_aberto := 0
	var esta_disponivel := true
	var confirma_abertura := true
	var portas := PackedStringArray(["COMBOA"])
	var ultima_porta := ""

	func nome_do_caminho() -> String:
		return SerialLink.CAMINHO_NATIVO

	func available() -> bool:
		return esta_disponivel

	func descricao() -> String:
		return "falso"

	func list_ports() -> PackedStringArray:
		return portas

	func open_port(port: String, _baud: int = GameDef.SERIAL_BAUD) -> bool:
		vezes_aberto += 1
		ultima_porta = port
		if confirma_abertura:
			opened.emit(port)
		return true

	func is_open() -> bool:
		return not ultima_porta.is_empty()

	func close_port() -> void:
		var qual := ultima_porta
		ultima_porta = ""
		if not qual.is_empty():
			closed.emit(qual)

	func send_line(_line: String) -> bool:
		return true

	func poll() -> void:
		vezes_polled += 1

var jogo: Control

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# A ponte de mentira vale para todo o arquivo: nenhum teste daqui
	# pode subir um PowerShell nem um ajudante de verdade.
	PonteProcessoLink.receita_de_teste = [
		[ProjectSettings.globalize_path("res://tests/ponte_falsa.sh")], ["/bin/sh"]
	]
	jogo = load("res://scenes/main.tscn").instantiate()
	root.add_child(jogo)
	await process_frame
	jogo.set_process(false)
	# A câmera não entra nesta prova, e sem isto ela fica pedindo um
	# Python com OpenCV que a máquina de teste não tem.
	if jogo.camera_service != null:
		jogo.camera_service.set_process(false)
		jogo.camera_service.set_enabled(false)
	jogo.central_aberta = false

	_test_batimento_nao_para_quando_o_caminho_cai()
	_test_porta_fixa_nao_e_cadeado()
	_test_varredura_cega_cobre_o_sistema()
	_test_paciencia_conta_da_confirmacao()
	_test_troca_de_caminho_espera_a_volta_fechar()
	_test_fila_gira_e_nao_repete()
	await _test_a_ponte_ressuscita_sozinha()
	_test_despedida_velha_nao_mata_ajudante_novo()
	await _test_a_central_desenha_o_diagnostico()

	jogo.queue_free()
	await process_frame
	PonteProcessoLink.receita_de_teste = []
	print("SERIAL_TEIMOSO_OK")
	quit(0)

## Troca o backend do jogo por um de mentira, sem deixar o de verdade
## ligado nos sinais.
func _por_link(falso: LinkFalso) -> void:
	jogo._soltar_link()
	jogo.link = falso
	falso.line_received.connect(jogo._on_serial_line)
	falso.opened.connect(jogo._on_serial_opened)
	falso.closed.connect(jogo._on_serial_closed)
	# O backend acabou de entrar: o relógio da vigilância começa agora,
	# como `_iniciar_serial` faz na máquina de verdade.
	jogo._caminho_desde = jogo.animation_time
	jogo._caminho_provado = false
	jogo._varreduras = 0
	jogo._porta_da_vez = 0

# ----------------------------------------------------------------------
#  1. O BATIMENTO NÃO PARA QUANDO O CAMINHO CAI
# ----------------------------------------------------------------------
#
#  O DEFEITO: `_poll_serial` começava com
#
#      if link == null or not link.available():
#          return
#      link.poll()
#
#  `poll()` é o único batimento do backend — é dentro dele que a ponte por
#  processo ressuscita o ajudante que morreu. E `available()` da ponte
#  responde falso exatamente no intervalo em que ela está caída. O
#  batimento parava no instante em que passava a ser necessário: um
#  ajudante que caísse UMA vez nunca mais voltava, e a tela ficava
#  congelada até alguém reiniciar o jogo. O código de ressurreição
#  existia, estava certo, e era inalcançável.
func _test_batimento_nao_para_quando_o_caminho_cai() -> void:
	var falso := LinkFalso.new()
	falso.esta_disponivel = false
	_por_link(falso)
	for _i in range(5):
		jogo._poll_serial(0.016)
	assert(falso.vezes_polled == 5)
	# E a tela precisa DIZER que está procurando outro caminho, senão o
	# operador conclui que a máquina travou.
	assert("SEM CAMINHO" in jogo.serial_status.to_upper())
	assert("PROCURANDO OUTRO" in jogo.serial_status.to_upper())

# ----------------------------------------------------------------------
#  2. A PORTA FIXADA É PREFERÊNCIA, NÃO CADEADO
# ----------------------------------------------------------------------
#
#  O DEFEITO: fixar a porta na Central gravava o nome no disco, e a partir
#  dali o jogo tentava SÓ AQUELA PORTA, para sempre. Num PC onde o Nano
#  aparece como COM3, um "COM5" gravado noutro dia é uma máquina morta com
#  a placa espetada e funcionando do lado — e o arquivo de ajustes
#  sobrevive à atualização do jogo, então o defeito atravessava versões.
func _test_porta_fixa_nao_e_cadeado() -> void:
	var antes: String = jogo.porta_configurada
	var antes_cega: bool = jogo._cega_liberada
	jogo._cega_liberada = false
	jogo.porta_configurada = "COM_FANTASMA"
	jogo.portas_visiveis = PackedStringArray(["COMBOA", "COMOUTRA"])

	# Enquanto ela tem crédito, é só ela: é isto que faz a porta escolhida
	# à mão vencer o sorteio quando está certa.
	jogo._falhas_da_porta_fixa = 0
	var fila: PackedStringArray = jogo._fila_de_tentativas()
	assert(fila.size() == 1 and fila[0] == "COM_FANTASMA")

	# Gastas as tentativas, a varredura volta a incluir TODAS — com a
	# preferência ainda na frente, porque preferência continua valendo.
	jogo._falhas_da_porta_fixa = jogo.FALHAS_ATE_SOLTAR_A_PORTA_FIXA
	fila = jogo._fila_de_tentativas()
	assert(fila[0] == "COM_FANTASMA")
	assert(fila.has("COMBOA"))
	assert(fila.has("COMOUTRA"))

	jogo.porta_configurada = antes
	jogo._falhas_da_porta_fixa = 0
	jogo._cega_liberada = antes_cega

# ----------------------------------------------------------------------
#  3. A VARREDURA CEGA COBRE O SISTEMA
# ----------------------------------------------------------------------
#
#  O DEFEITO: toda a fila dependia de UMA coisa dar certo — o sistema
#  ENUMERAR as portas. E é essa a peça que falha de máquina para máquina,
#  sempre de um jeito diferente. Enumeração vazia significava fila vazia,
#  e fila vazia é a busca que nunca termina, com a placa falando na porta
#  que ninguém tentou.
func _test_varredura_cega_cobre_o_sistema() -> void:
	var antes: String = jogo.porta_configurada
	var antes_cega: bool = jogo._cega_liberada
	jogo.porta_configurada = ""
	jogo.portas_visiveis = PackedStringArray()

	# Antes da primeira volta a fila é honesta: não há porta à vista.
	jogo._cega_liberada = false
	assert(jogo._fila_de_tentativas().is_empty())

	# Fechada uma volta sem achar, ela deixa de perguntar e passa a tentar
	# os nomes que existem por convenção neste sistema.
	jogo._cega_liberada = true
	var fila: PackedStringArray = jogo._fila_de_tentativas()
	match OS.get_name():
		"Windows":
			assert(fila.has("COM1") and fila.has("COM5") and fila.has("COM32"))
		"Linux":
			assert(fila.has("/dev/ttyACM0") and fila.has("/dev/ttyUSB0"))
		_:
			pass
	# E uma porta que a enumeração ACHOU nunca sai da frente da cega: a
	# que o sistema conhece merece ser tentada antes do palpite.
	jogo.portas_visiveis = PackedStringArray(["COMBOA"])
	fila = jogo._fila_de_tentativas()
	assert(fila[0] == "COMBOA")
	assert(fila.size() > 1)

	jogo.porta_configurada = antes
	jogo._cega_liberada = antes_cega

# ----------------------------------------------------------------------
#  4. A PACIÊNCIA CONTA DA CONFIRMAÇÃO, NÃO DO PEDIDO
# ----------------------------------------------------------------------
#
#  O DEFEITO: um relógio só, começando quando o jogo PEDIA a abertura.
#  Pela ponte por processo, entre o pedido e a porta aberta há um cano, um
#  PowerShell e um driver; num PC lento isso passa de cinco segundos
#  sozinho. A paciência acabava ANTES de a porta existir, e a máquina
#  varria a lista inteira sem dar a nenhuma placa a chance de responder —
#  o retrato exato de "funciona no meu PC, não funciona no outro, com a
#  mesma porta".
func _test_paciencia_conta_da_confirmacao() -> void:
	# (a) A porta que nunca confirma é abandonada pelo relógio do
	#     ENCANAMENTO, e a frase diz isso.
	var mudo := LinkFalso.new()
	mudo.confirma_abertura = false
	_por_link(mudo)
	jogo.porta_configurada = ""
	jogo.proxima_tentativa = 0.0
	jogo._tentar_conectar()
	assert(mudo.vezes_aberto == 1)
	assert(not jogo._porta_confirmada)
	# Um instante antes do prazo, ninguém desiste.
	jogo.animation_time = jogo._porta_pedida_em + jogo.ESPERA_DA_CONFIRMACAO - 0.1
	jogo._poll_serial(0.016)
	assert(mudo.is_open())
	# Passado o prazo, desiste — e diz que foi a abertura que não veio.
	jogo.animation_time = jogo._porta_pedida_em + jogo.ESPERA_DA_CONFIRMACAO + 0.1
	jogo._poll_serial(0.016)
	assert("NÃO ABRIU" in jogo.serial_status)

	# (b) A porta que confirma ganha a paciência INTEIRA a partir dali —
	#     e é essa a paciência que o Arduino precisa para reiniciar.
	var bom := LinkFalso.new()
	_por_link(bom)
	jogo.animation_time = 1000.0
	jogo._caminho_desde = jogo.animation_time
	jogo.proxima_tentativa = 0.0
	jogo._tentar_conectar()
	assert(jogo._porta_confirmada)
	assert(is_equal_approx(jogo._porta_aberta_em, 1000.0))
	jogo.animation_time = 1000.0 + jogo.PORTA_PACIENCIA - 0.1
	jogo._poll_serial(0.016)
	assert(bom.is_open())
	jogo.animation_time = 1000.0 + jogo.PORTA_PACIENCIA + 0.1
	jogo._poll_serial(0.016)
	assert("SEM RESPOSTA" in jogo.serial_status)

	# (c) UMA LINHA VÁLIDA E A PACIÊNCIA NÃO CORRE MAIS. A placa que fala
	#     TELEMETRY antes do READY não pode ser descartada como muda.
	var falante := LinkFalso.new()
	_por_link(falante)
	jogo.animation_time = 2000.0
	jogo._caminho_desde = jogo.animation_time
	jogo.proxima_tentativa = 0.0
	jogo._tentar_conectar()
	falante.line_received.emit("PINS,0,0")
	jogo.animation_time = 2000.0 + jogo.PORTA_PACIENCIA + 5.0
	jogo._poll_serial(0.016)
	assert(falante.is_open())

# ----------------------------------------------------------------------
#  5. TROCAR DE CAMINHO SÓ DEPOIS DE UMA VOLTA INTEIRA
# ----------------------------------------------------------------------
#
#  A troca de caminho é o que salva a máquina onde o caminho preferido não
#  presta. Mas ela zera a fila: feita no meio da varredura, cortaria a
#  busca sempre no mesmo ponto e as portas do fim da fila nunca seriam
#  tentadas por caminho nenhum.
func _test_troca_de_caminho_espera_a_volta_fechar() -> void:
	var falso := LinkFalso.new()
	_por_link(falso)
	jogo.animation_time = 3000.0
	jogo._caminho_desde = 0.0
	jogo.ultimo_sinal_ms = -1
	jogo.sensor_presente = false
	var trocas: int = jogo._trocas_de_caminho

	# Volta ainda aberta: o caminho não é condenado, por mais que demore.
	jogo._varreduras = 0
	assert(not jogo._vigiar_o_caminho())
	assert(jogo._trocas_de_caminho == trocas)

	# Volta fechada e nada encontrado: agora sim.
	jogo._varreduras = 1
	jogo._caminho_desde = 0.0
	assert(jogo._vigiar_o_caminho())
	assert(jogo._trocas_de_caminho == trocas + 1)
	assert(jogo.link != null)

# ----------------------------------------------------------------------
#  6. A FILA GIRA, E UMA PORTA MUDA NÃO PRENDE A PRÓXIMA
# ----------------------------------------------------------------------
func _test_fila_gira_e_nao_repete() -> void:
	var falso := LinkFalso.new()
	falso.portas = PackedStringArray(["COM_A", "COM_B", "COM_C"])
	_por_link(falso)
	jogo.porta_configurada = ""
	jogo._cega_liberada = false
	jogo._porta_da_vez = 0
	jogo._varreduras = 0
	jogo.animation_time = 4000.0
	jogo._caminho_desde = jogo.animation_time
	var tentadas: Array[String] = []
	for _i in range(3):
		jogo.proxima_tentativa = 0.0
		jogo._tentar_conectar()
		tentadas.append(falso.ultima_porta)
		falso.close_port()
	assert(tentadas.has("COM_A") and tentadas.has("COM_B") and tentadas.has("COM_C"))
	# Fechada a volta, o contador de buscas sobe — e é ele que aparece na
	# tela para a busca parecer o que é: uma busca acontecendo.
	jogo.proxima_tentativa = 0.0
	jogo._tentar_conectar()
	assert(jogo._varreduras >= 1)
	assert(jogo._cega_liberada)

# ----------------------------------------------------------------------
#  7. A PONTE RESSUSCITA SOZINHA
# ----------------------------------------------------------------------
#
#  Com o ajudante caído, `poll()` tem de subir outro. Este teste usa um
#  ajudante que se apresenta e MORRE — o retrato do PowerShell derrubado
#  por antivírus ou de um cabo USB que deu uma soluçada.
func _test_a_ponte_ressuscita_sozinha() -> void:
	var suicida := "user://ajudante_suicida.sh"
	var arquivo := FileAccess.open(suicida, FileAccess.WRITE)
	assert(arquivo != null)
	arquivo.store_string("#!/bin/sh\nprintf '#PONTE,V1,suicida\\n'\nprintf '#PORTAS,COMBOA\\n'\nexit 0\n")
	arquivo.close()
	PonteProcessoLink.receita_de_teste = [
		[ProjectSettings.globalize_path(suicida)], ["/bin/sh"]
	]
	var ponte := PonteProcessoLink.new()
	assert(ponte.available())

	# Ele fala, morre, e a ponte sobe outro. Duas ressurreições provam que
	# não é sorte: prova que o batimento continua depois da primeira.
	var alvo := 2
	var conseguiu := false
	for _i in range(900):
		ponte.poll()
		if ponte.religadas() >= alvo:
			conseguiu = true
			break
		OS.delay_msec(10)
		await process_frame
	assert(conseguiu)
	# E cada ajudante novo chegou a se apresentar de verdade: a lista de
	# portas voltou depois de a ponte ter caído.
	var voltou := false
	for _i in range(300):
		ponte.poll()
		if ponte.list_ports().has("COMBOA"):
			voltou = true
			break
		OS.delay_msec(10)
		await process_frame
	assert(voltou)
	ponte.encerrar()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(suicida))
	PonteProcessoLink.receita_de_teste = [
		[ProjectSettings.globalize_path("res://tests/ponte_falsa.sh")], ["/bin/sh"]
	]

# ----------------------------------------------------------------------
#  8. A DESPEDIDA DO AJUDANTE VELHO NÃO MATA O NOVO
# ----------------------------------------------------------------------
#
#  O DEFEITO, e o mais cruel de todos: ao derrubar o ajudante, a thread
#  leitora empilhava um `#MORREU` de despedida — e a fila NÃO era limpa. O
#  `#MORREU` do ajudante VELHO era digerido depois, quando o NOVO já
#  estava de pé: o jogo matava o recém-nascido, subia outro, e a despedida
#  desse matava o seguinte. A ponte nunca chegava a dizer a primeira
#  palavra, e na tela ficava "PROCURANDO ARDUINO…" a noite inteira.
func _test_despedida_velha_nao_mata_ajudante_novo() -> void:
	var ponte := PonteProcessoLink.new()
	assert(ponte.available())
	var geracao_velha: int = ponte._geracao
	ponte._derrubar()
	# A fila morre com o ajudante.
	assert(ponte._recebidas.is_empty())
	# E mesmo que uma despedida velha apareça atrasada, ela é ignorada:
	# derrubar o de agora por causa da morte do de antes é o laço.
	ponte._subir()
	assert(ponte.available())
	assert(ponte._geracao > geracao_velha)
	ponte._digerir("#MORREU,%d" % geracao_velha)
	assert(ponte.available())
	# A despedida da geração de agora, essa sim, derruba.
	ponte._digerir("#MORREU,%d" % ponte._geracao)
	assert(not ponte.available())
	ponte.encerrar()

# ----------------------------------------------------------------------
#  9. A CENTRAL DESENHA O DIAGNÓSTICO INTEIRO, EM QUALQUER ESTADO
# ----------------------------------------------------------------------
#
#  A página de diagnóstico é o que o técnico lê ao telefone, e ela é
#  desenhada com os números da busca — que existem em estados muito
#  diferentes: sem caminho, procurando, conectado. Um erro de desenho num
#  desses estados apaga a página inteira justamente na hora em que
#  alguém precisa dela.
#
#  Este teste não julga a aparência: ele passa por todas as páginas em
#  todos esses estados e cobra que nenhuma delas quebre.
func _test_a_central_desenha_o_diagnostico() -> void:
	jogo.central_aberta = true
	var estados: Array[Callable] = [
		func() -> void:
			var sem := LinkFalso.new()
			sem.esta_disponivel = false
			_por_link(sem),
		func() -> void:
			var vazio := LinkFalso.new()
			vazio.portas = PackedStringArray()
			_por_link(vazio)
			jogo._cega_liberada = true,
		func() -> void:
			var bom := LinkFalso.new()
			_por_link(bom)
			jogo.proxima_tentativa = 0.0
			jogo._tentar_conectar()
			bom.line_received.emit("READY,PUNCH_MPU6050,V3"),
	]
	for montar in estados:
		montar.call()
		for pagina in range(4):
			jogo.central_pagina = pagina
			jogo.queue_redraw()
			await process_frame
			await process_frame
	jogo.central_aberta = false
	jogo.central_pagina = 0
