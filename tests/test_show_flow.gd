extends SceneTree

## Testes de fluxo: abre a cena de verdade e dirige a máquina de estados.
## Prova as regras que valem dinheiro — crédito, golpe válido, foto — e
## as que valem confiança: a barra de espaço não pontua em salão.

class FakeCamera extends CameraService:
	var shots := 0
	func _ready() -> void:
		pass
	func capture_photo() -> String:
		shots += 1
		return ""

## `arcade_stage.gd` não tem `class_name` — ele é carregado por preload
## em quem o usa. Aqui vale o mesmo caminho, e não um nome global.
const ArcadeStage = preload("res://scripts/presentation/arcade_stage.gd")

var jogo: Control

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	jogo = load("res://scenes/main.tscn").instantiate()
	root.add_child(jogo)
	await process_frame
	jogo.set_process(false)
	# A máquina de testes nunca é a de um salão: sem simulação ligada e
	# sem Central aberta, para as regras de produção valerem.
	jogo.simulacao_bancada = false
	jogo.simulacao_por_ambiente = false
	jogo.central_aberta = false

	_test_entrada()
	_test_audio_dos_estados()
	await _test_foto_antes_de_armar()
	_test_hit_so_em_armed()
	_test_um_golpe_por_rodada()
	_test_barra_nao_pontua_em_producao()
	_test_start_e_credito_independentes()
	_test_timeout_devolve_credito()
	_test_quatro_digitos()
	_test_bancada_sem_sensor()
	_test_medico_da_camera()
	_test_interpretador_da_ponte()
	_test_exame_nao_briga_com_a_ponte()
	_test_camera_acesa_nao_apaga()
	_test_contagem_espera_a_camera()
	_test_rolagem_da_central()
	_test_obturador_da_pose()

	jogo.queue_free()
	await process_frame
	print("SHOW_FLOW_OK")
	quit(0)

# ------------------------------------------------------------ entrada
func _test_entrada() -> void:
	assert(jogo.intro_active)
	jogo._processar_abertura(ArcadeStage.INTRO_SECONDS + 0.1)
	assert(not jogo.intro_active)
	assert(jogo.state == GameDef.State.IDLE)

func _test_audio_dos_estados() -> void:
	for som in ["music", "charge", "score_loop"]:
		assert(jogo.sons._players[som].stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	# Os oito níveis existem como som carregado, e não só como nome.
	for nivel in ScoreTier.NIVEIS:
		var player: AudioStreamPlayer = jogo.sons._players.get(str(nivel["som"]))
		assert(player != null and player.stream != null)
	jogo.sons.music(-19.0)
	assert(jogo.sons._players["music"].playing)

# -------------------------------------------------------------- foto
func _test_foto_antes_de_armar() -> void:
	jogo.camera_service.queue_free()
	var camera := FakeCamera.new()
	jogo.add_child(camera)
	jogo.camera_service = camera
	jogo.state = GameDef.State.COUNTDOWN
	jogo.countdown_left = 3.0
	jogo.pose_finished = false
	jogo._processar_contagem(2.0)
	assert(camera.shots == 0)
	jogo._processar_contagem(1.0)
	# A foto sai DURANTE a contagem, antes de o sensor armar, e uma só.
	assert(camera.shots == 1)
	assert(jogo.state == GameDef.State.COUNTDOWN)
	jogo._processar_contagem(1.3)
	assert(jogo.state == GameDef.State.ARMED)
	assert(camera.shots == 1)
	await process_frame

# -------------------------------------------------------------- golpe
func _golpe(velocidade: float) -> Dictionary:
	return {"speed": velocidade, "accel": 9.0, "duration_ms": 45.0, "axis": "X"}

func _test_hit_so_em_armed() -> void:
	for estado in [GameDef.State.IDLE, GameDef.State.COUNTDOWN, GameDef.State.RESULT]:
		jogo.state = estado
		jogo.result_score = 0
		jogo.golpe_registrado = false
		jogo.ultimo_golpe_ms = jogo.NUNCA_MS
		jogo._receber_hit(_golpe(12.0))
		assert(jogo.result_score == 0)
		assert(jogo.state == estado)

func _test_um_golpe_por_rodada() -> void:
	_armar()
	jogo._receber_hit(_golpe(10.0))
	assert(jogo.state == GameDef.State.MEASURING)
	var primeiro: int = jogo.result_score
	assert(primeiro > 0)
	# O saco balança depois do golpe: o segundo evento não pode entrar.
	jogo.state = GameDef.State.ARMED
	jogo._receber_hit(_golpe(14.0))
	assert(jogo.result_score == primeiro)
	# Evento curto demais e evento fraco demais também não entram.
	_armar()
	jogo._receber_hit({"speed": 12.0, "accel": 9.0, "duration_ms": 3.0, "axis": "X"})
	assert(jogo.state == GameDef.State.ARMED)
	jogo._receber_hit({"speed": 12.0, "accel": 0.2, "duration_ms": 45.0, "axis": "X"})
	assert(jogo.state == GameDef.State.ARMED)

func _armar() -> void:
	jogo.state = GameDef.State.ARMED
	jogo.golpe_registrado = false
	jogo.ultimo_golpe_ms = jogo.NUNCA_MS
	jogo.result_score = 0

# ------------------------------------------------- barra de espaço
func _test_barra_nao_pontua_em_producao() -> void:
	_armar()
	assert(not jogo._simulador_liberado())
	jogo._apertou_espaco()
	assert(jogo.carga_tempo < 0.0)
	jogo._soltou_espaco()
	assert(jogo.state == GameDef.State.ARMED)
	assert(jogo.result_score == 0)
	# Com a chave da bancada ligada, ela volta a valer.
	jogo.simulacao_bancada = true
	_armar()
	jogo._apertou_espaco()
	assert(jogo.carga_tempo >= 0.0)
	jogo.carga_tempo = 2.0
	jogo._soltou_espaco()
	assert(jogo.state == GameDef.State.MEASURING)
	jogo.simulacao_bancada = false

# ------------------------------------------------- START e CRÉDITO
func _test_start_e_credito_independentes() -> void:
	# Os dois nunca podem ser o mesmo aperto.
	assert(int(jogo.botao_start["index"]) != int(jogo.botao_credito["index"]))
	jogo._entrar_em_abertura()
	jogo.game_mode = "credit"
	jogo.credits = 0
	# START sem saldo não inicia rodada nenhuma.
	jogo._pressionou_start()
	assert(jogo.state == GameDef.State.IDLE)
	assert(jogo.credits == 0)
	# CRÉDITO soma exatamente um.
	jogo._add_credit()
	assert(jogo.credits == 1)
	# E o antirrepique impede o aperto duplicado do botão físico.
	jogo.ultimo_credito_ms = Time.get_ticks_msec()
	var repique := InputEventJoypadButton.new()
	repique.button_index = int(jogo.botao_credito["index"])
	repique.pressed = true
	jogo._botao_do_gabinete(repique)
	assert(jogo.credits == 1)
	# START consome exatamente um.
	jogo._pressionou_start()
	assert(jogo.state == GameDef.State.COUNTDOWN)
	assert(jogo.credits == 0)
	assert(jogo.credito_gasto)

func _test_timeout_devolve_credito() -> void:
	jogo.state = GameDef.State.ARMED
	jogo.espera_left = 0.05
	jogo.credito_gasto = true
	jogo.game_mode = "credit"
	var antes: int = jogo.credits
	jogo._processar_armado(0.1)
	assert(jogo.credits == antes + 1)
	assert(jogo.state == GameDef.State.IDLE)
	# E a ficha devolvida não volta duas vezes.
	jogo._devolver_credito()
	assert(jogo.credits == antes + 1)

# ------------------------------------------------- quatro dígitos
func _test_quatro_digitos() -> void:
	assert(("%04d" % GameDef.SCORE_MAX).length() == 4)
	assert(("%04d" % 0) == "0000")
	jogo.ranking = RankingStore.migrate([9999, 5000, 120])
	assert(RankingStore.best(jogo.ranking) == 9999)
	jogo.state = GameDef.State.RESULT
	jogo.result_score = 9999
	jogo.verdict_time = 1.0
	jogo.displayed_score = 9999.0
	jogo.central_aberta = false
	jogo.queue_redraw()

# ------------------------------------------- bancada sem sensor
## A BARRA TEM DE VOLTAR SOZINHA NUMA MÁQUINA SEM SENSOR.
##
## Uma instalação que rodou uma versão anterior tem `simulacao_bancada:
## false` gravado no disco. Lendo só o arquivo, ela ficava com a barra
## morta para sempre, esperando um MPU-6050 que ainda não existe — e o
## sintoma era "o espaço parou de funcionar", sem nada na tela explicando.
func _test_bancada_sem_sensor() -> void:
	# Arquivo de uma versão anterior: desligada, e sem escolha do operador.
	jogo.simulacao_bancada = false
	jogo.simulacao_escolhida = false
	var disco := FileAccess.open(SettingsStore.PATH, FileAccess.WRITE)
	disco.store_string(JSON.stringify({"simulacao_bancada": false, "mode": "credit"}))
	disco.close()
	jogo._carregar()
	assert(jogo.simulacao_bancada)
	assert(jogo._simulador_liberado())

	# O sensor se apresentando desliga a chave sem ninguém pedir.
	jogo._on_serial_line("READY,PUNCH_MPU6050,V2")
	assert(not jogo.simulacao_bancada)
	assert(not jogo._simulador_liberado())

	# Mas a escolha do operador manda mais que o sensor.
	jogo.simulacao_bancada = true
	jogo.simulacao_escolhida = true
	jogo._on_serial_line("READY,PUNCH_MPU6050,V2")
	assert(jogo.simulacao_bancada)

# ------------------------------------------- médico da câmera
## O DIAGNÓSTICO TEM DE AGIR, e não só relatar.
##
## Um relatório que exige o técnico repetir à mão o que a máquina acabou
## de descobrir é meio relatório: achou câmera no índice 2, a máquina
## passa a usar o índice 2 sozinha.
func _test_medico_da_camera() -> void:
	assert(jogo.medico != null)
	assert(not jogo.medico.rodando)
	# Ruído de biblioteca não entra no relatório: numa tela de doze
	# linhas, quatro avisos do OpenCV por índice apagam o que interessa.
	var limpas: Array = jogo.medico._linhas_de([
		"[ WARN:0@0.011] global cap.cpp:475 open VIDEOIO(V4L2)",
		"Python 3.12.3",
		"",
		"[ERROR:1] alguma coisa interna",
	])
	assert(limpas.size() == 1)
	assert(str(limpas[0]) == "Python 3.12.3")

	# Achou câmera: a máquina adota o índice e reabre.
	jogo.camera_service.selected_index = 0
	# `assign`, e não `=`: `indices` é Array[int] tipado, e atribuir um
	# literal solto de fora deixa a lista vazia em silêncio.
	jogo.medico.indices.assign([2])
	jogo.medico.backend = "DSHOW"
	jogo._fim_do_exame()
	assert(jogo.camera_service.selected_index == 2)
	# O back-end descoberto também é adotado: sem isso a ponte refaz a
	# fila inteira a cada religada, e cada tentativa frustrada custa
	# segundos justamente na hora da foto.
	assert(jogo.camera_service.backend_preferido == "DSHOW")
	jogo.medico.indices.clear()
	jogo.medico.backend = ""

	# O VEREDITO MUDA COM O QUE SE DESCOBRIU. Uma frase única para todos
	# os casos ("feche o Teams") é o que fazia o operador tentar sempre a
	# mesma coisa e concluir que o botão não funciona.
	jogo.medico.cameras_do_windows = 0
	assert("cabo" in jogo.medico._veredito())

	jogo.medico.cameras_do_windows = 1
	jogo.medico.privacidade = "Deny"
	assert("PRIVACIDADE" in jogo.medico._veredito())

	jogo.medico.privacidade = "Allow"
	jogo.medico.ocupantes = "WindowsCamera, Teams"
	assert("WindowsCamera" in jogo.medico._veredito())

	jogo.medico.ocupantes = "nenhum"
	assert("OPENCV" in jogo.medico._veredito().to_upper())

	jogo.medico.cameras_do_windows = -1
	jogo.medico.privacidade = ""
	jogo.medico.ocupantes = ""

	# Sem quadro nenhum, a idade é grande — e é ela que impede a máquina
	# de anunciar "FOTO OK" para uma imagem congelada.
	assert(jogo.camera_service.idade_do_quadro() > 2000)

# --------------------------------------------------- rolagem da Central
func _test_rolagem_da_central() -> void:
	# Com a página curta não há barra e não há rolagem: rolar uma página
	# que já cabe inteira é o defeito que faz o conteúdo "sumir" para
	# cima sem nada abaixo para mostrar.
	jogo.central_fundo = 900.0
	assert(jogo._rolagem_maxima() == 0.0)
	jogo._rolar(500.0)
	assert(jogo.central_rolagem == 0.0)

	# Página comprida: rola, e para no fim.
	jogo.central_fundo = 2400.0
	var teto: float = jogo._rolagem_maxima()
	assert(teto > 0.0)
	jogo._rolar(1000000.0)
	assert(is_equal_approx(jogo.central_rolagem, teto))
	jogo._rolar(-1000000.0)
	assert(jogo.central_rolagem == 0.0)

	# O CLIQUE ACOMPANHA O PAPEL. Um controle de página desce com a
	# rolagem; os três de fora (fechar, restaurar, salvar) não saem do
	# lugar. Sem essa distinção, rolar faria o clique acertar outro botão.
	jogo.central_pagina = 0
	jogo.central_rolagem = 0.0
	var alvo: Rect2 = jogo.BOTOES_SIMPLES["simulacao"]
	var meio := alvo.position + alvo.size * 0.5
	assert(jogo._tocou("simulacao", meio))
	jogo.central_rolagem = 120.0
	assert(not jogo._tocou("simulacao", meio))
	assert(jogo._tocou("simulacao", meio - Vector2(0.0, 120.0)))
	var fixo: Rect2 = jogo.BOTOES_SIMPLES["salvar"]
	assert(jogo._tocou("salvar", fixo.position + fixo.size * 0.5))

	# Controle de outra página não responde, rolado ou não.
	assert(not jogo._tocou("calibrar", meio))
	jogo.central_rolagem = 0.0

# ------------------------------------------------- obturador da pose
func _test_obturador_da_pose() -> void:
	var camera: CameraService = jogo.camera_service
	camera.abrir_obturador(5000)

	# Um quadro de uma cor só não é imagem: é buffer não inicializado,
	# tampa na lente ou feed que ativou sem entregar nada. Era isto que
	# fazia a máquina fotografar um quadrado preto e chamar de foto.
	var preto := Image.create(64, 48, false, Image.FORMAT_RGB8)
	preto.fill(Color.BLACK)
	assert(not camera._imagem_util(preto))
	camera._oferecer_ao_obturador(preto)

	# Um quadro com contraste entra e vira o melhor.
	var cena := Image.create(64, 48, false, Image.FORMAT_RGB8)
	cena.fill(Color(0.2, 0.2, 0.2))
	for x in range(64):
		for y in range(24):
			cena.set_pixel(x, y, Color.WHITE)
	camera._oferecer_ao_obturador(cena)
	assert(camera._melhor_imagem != null)
	var nota_boa: float = camera._melhor_nota
	assert(nota_boa > camera.CONTRASTE_MINIMO)

	# Um quadro pior não substitui o guardado.
	var fraco := Image.create(64, 48, false, Image.FORMAT_RGB8)
	fraco.fill(Color(0.5, 0.5, 0.5))
	camera._oferecer_ao_obturador(fraco)
	assert(is_equal_approx(camera._melhor_nota, nota_boa))

	# Fechado o obturador, nada mais entra.
	camera._obturador_ate_ms = 0
	var outro := Image.create(64, 48, false, Image.FORMAT_RGB8)
	outro.fill(Color.WHITE)
	for x in range(64):
		outro.set_pixel(x, 0, Color.BLACK)
	camera._oferecer_ao_obturador(outro)
	assert(is_equal_approx(camera._melhor_nota, nota_boa))
	camera._melhor_imagem = null
	camera._melhor_nota = -1.0

# ------------------------------------------- qual Python a ponte usa
func _test_interpretador_da_ponte() -> void:
	var camera: CameraService = jogo.camera_service
	camera._riscados.clear()
	camera.python_exe = ""
	camera.python_args = PackedStringArray()

	# Sem nada provado, vale a lista do sistema, na ordem.
	var lista: Array = camera._lista_de_interpretadores()
	assert(camera._proximo_interpretador() == str(lista[0]))

	# Um candidato riscado sai da fila. É isto que impede o jogo de
	# insistir no atalho da Microsoft Store, que nasce, abre a loja e
	# morre — devolvendo um PID válido que o jogo tomava por sucesso.
	camera._riscar_interpretador(str(lista[0]))
	assert(camera._proximo_interpretador() == str(lista[1]))

	# Riscados todos, não sobra nada: aí é falar, não tentar de novo.
	for nome in lista:
		camera._riscar_interpretador(str(nome))
	assert(camera._proximo_interpretador() == "")

	# O que o diagnóstico PROVOU tem precedência e limpa os riscos.
	camera.adotar_python("py", PackedStringArray(["-3"]))
	assert(camera._proximo_interpretador() == "py")
	assert(camera._args_do_interpretador("py") == PackedStringArray(["-3"]))
	# E o `py` sem prova ainda recebe o -3: sem ele o lançador pode abrir
	# um Python 2 esquecido na máquina.
	camera.python_exe = ""
	assert(camera._args_do_interpretador("py") == PackedStringArray(["-3"]))
	camera._riscados.clear()
	camera.python_exe = ""
	camera.python_args = PackedStringArray()

# ------------------------------- o fluxo unico da camera
func _test_exame_nao_briga_com_a_ponte() -> void:
	var camera: CameraService = jogo.camera_service
	camera.enabled = true
	camera.estado = camera.Estado.SUBINDO

	# O exame pede a webcam. Só um programa por vez abre uma: enquanto o
	# diagnóstico sonda os índices, a ponte tem de estar fora do ar --
	# senão os dois se atropelam e a imagem pisca.
	camera.pedir_exame()
	camera._atender_pedido()
	assert(camera.estado == camera.Estado.EXAME)
	assert(camera._bridge_pid <= 0)

	# Em exame, nenhum quadro de supervisão religa nada.
	camera._supervisionar(0.016)
	camera._supervisionar(0.016)
	assert(camera.estado == camera.Estado.EXAME)
	assert(camera._bridge_pid <= 0)

	# No fim, a ponte volta com bateria nova de tentativas.
	camera._bridge_desistiu = true
	camera._bridge_reinicios = 99
	camera.enabled = false
	camera.terminar_exame()
	camera._atender_pedido()
	assert(camera.estado == camera.Estado.DESLIGADA)
	assert(not camera._bridge_desistiu)
	assert(camera._bridge_reinicios == 0)
	camera.enabled = true

# ------------------------------- camera acesa nao apaga sozinha
func _test_camera_acesa_nao_apaga() -> void:
	var camera: CameraService = jogo.camera_service
	camera.enabled = true
	camera.forcar_ponte = true

	# Finge uma ponte de pé, entregando quadro agora mesmo.
	camera.estado = camera.Estado.ACESA
	camera._bridge_pid = 999999
	camera._bridge_texture = ImageTexture.create_from_image(
		Image.create(8, 8, false, Image.FORMAT_RGB8)
	)
	camera._last_frame_ms = Time.get_ticks_msec()
	assert(camera.pronta())

	# UM PEDIDO DE ABERTURA NÃO DERRUBA O QUE JÁ ESTÁ ACESO. Era daqui
	# que vinha o acende-e-apaga: várias origens pediam "atualize" o
	# tempo todo, e cada pedido matava a ponte que estava entregando.
	camera.refresh()
	camera._atender_pedido()
	assert(camera._bridge_pid == 999999)
	assert(camera.pronta())

	# O aviso de lista de câmeras do Godot também não derruba: com a
	# ponte no ar ele é ruído, porque ela fala com a webcam por fora.
	camera._on_camera_feeds_updated(0)
	camera._atender_pedido()
	assert(camera._bridge_pid == 999999)

	# DUAS ORDENS NO MESMO QUADRO VALEM UMA. É o que o fluxo único
	# garante: antes, cada chamada agia na hora e uma atropelava a outra.
	camera.pedir_fechamento()
	camera.pedir_abertura()
	camera._atender_pedido()
	assert(camera.enabled)

	# E a ordem de desligar, essa derruba mesmo.
	camera.pedir_fechamento()
	camera._atender_pedido()
	assert(camera.estado == camera.Estado.DESLIGADA)
	assert(camera._bridge_pid <= 0)
	assert(not camera.pronta())

	camera.enabled = true
	camera.forcar_ponte = false
	camera.estado = camera.Estado.SUBINDO
	camera._bridge_texture = null

# ------------------------- a contagem so comeca com a camera acesa
func _test_contagem_espera_a_camera() -> void:
	var camera: CameraService = jogo.camera_service
	camera.enabled = true
	jogo.camera_enabled = true
	camera.estado = camera.Estado.SUBINDO
	assert(not camera.pronta())

	jogo.credits = 9
	# `_iniciar_rodada` e nao `_pressionou_start`: o segundo so vale em
	# IDLE ou RESULT, e aqui a rodada e comecada duas vezes de proposito.
	jogo._iniciar_rodada()
	assert(jogo.aguardando_camera)
	var comeco: float = jogo.countdown_left

	# Com a câmera ainda subindo, o relógio da pose NÃO anda. Contar
	# 3-2-1 enquanto a webcam sobe gasta a pose inteira esperando, e
	# quando a contagem zera não há imagem para fotografar.
	for i in range(30):
		jogo._processar_contagem(0.016)
	assert(jogo.aguardando_camera)
	assert(is_equal_approx(jogo.countdown_left, comeco))

	# Acendeu: a contagem destrava e o obturador abre junto.
	camera.estado = camera.Estado.ACESA
	jogo._processar_contagem(0.016)
	assert(not jogo.aguardando_camera)
	assert(jogo.countdown_left < comeco)

	# E A ESPERA TEM HORA MARCADA. Sem webcam, quem pôs a ficha ainda
	# tem direito à partida: passados os segundos do teto, a rodada
	# começa assim mesmo.
	camera.estado = camera.Estado.SUBINDO
	jogo._iniciar_rodada()
	assert(jogo.aguardando_camera)
	for i in range(20):
		jogo._processar_contagem(0.5)
	assert(not jogo.aguardando_camera)

	camera.estado = camera.Estado.SUBINDO
	jogo._entrar_em_abertura()
