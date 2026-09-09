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
	jogo._fim_do_exame()
	assert(jogo.camera_service.selected_index == 2)
	jogo.medico.indices.clear()
