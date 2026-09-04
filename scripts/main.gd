extends Control

## Punch Challenge — a máquina de soco da Lazer & Sport.
##
## A TELA INTEIRA É DESENHADA À MÃO, num `_draw` só. Não é teimosia: numa
## máquina de fliperama o computador é modesto e a tela nunca muda de
## layout, então uma árvore de nós com tema, contêiner e âncora custaria
## mais para manter do que resolve. Aqui cada estado do jogo desenha o que
## precisa, e o que voa (confete, faísca, estilhaço) mora em `fx.gd`.
##
## O CAMINHO DE QUEM JOGA:
##
##   ABERTURA → (START) → ENTRADA → 3, 2, 1 → SENSOR ARMADO → RESULTADO
##
## A abertura é a cara da máquina parada, e é ela que convence alguém a
## chegar perto: logo da Lazer & Sport, luz varrendo, partículas e o
## "PRESSIONE START" piscando. START entra no jogo; SELECT põe ficha.
##
## O RESULTADO TEM TRÊS FINAIS, e é isso que faz o cliente jogar de novo:
## soco fraco perde (tela vermelha, estilhaços caindo), médio fica no meio
## (âmbar, anéis pulsando) e forte vence (confete, fogos, raios dourados).
## As faixas são configuráveis na Central Técnica: a mecânica de cada
## máquina responde diferente, e o operador é quem sabe onde está o
## "forte" da dele.

enum GameState { ATTRACT, INTRO, COUNTDOWN, ARMED, RESULT }
enum Verdict { FRACO, MEDIO, FORTE }

const SETTINGS_PATH := "user://punch_challenge_settings.json"
const UDP_PORT := 4242
const MAX_CREDITS := 99
const TELA := Vector2(1920.0, 1080.0)

## Quanto tempo o número leva para subir de zero até a pontuação.
##
## Dois segundos é o que separa "o placar apareceu" de "o placar SUBIU".
## É neste intervalo que quem socou fica olhando, e é ele que faz a
## plateia em volta olhar junto -- por isso o veredito só entra quando a
## contagem termina, e não antes.
const CONTAGEM_DURACAO := 1.9

## Depois disso a máquina volta sozinha para a abertura. Sem isso, um
## resultado esquecido na tela é uma máquina que parece ocupada.
const RESULTADO_TIMEOUT := 16.0

const ENTRADA_DURACAO := 0.95
const JANELA_DO_SOCO := 8.0

const CORES_FESTA := [
	Color("ff2d78"), Color("ffd23f"), Color("4beaff"),
	Color("8d62ff"), Color("52f2a4"), Color("ffffff"),
]

var state: GameState = GameState.ATTRACT
var verdict: Verdict = Verdict.MEDIO
var settings_open := false
var game_mode := "credit"
var credits := 0
var plays := 0
var best_score := 0
var com_number := 3
var min_speed := 1.0
var max_speed := 12.0
var score_curve := 0.78
## Onde termina o soco fraco e onde começa o forte, na escala de 0 a 999.
var limite_fraco := 330
var limite_forte := 700
## Botões da placa zero delay. Aprendidos na Central Técnica, porque cada
## placa numera os botões de um jeito -- ver `_aprender_botao`.
var botao_start := 7
var botao_select := 6

var countdown_left := 3.0
var last_count := 3
var armed_left := JANELA_DO_SOCO
var result_score := 0
var result_speed := 0.0
var displayed_score := 0.0
var animation_time := 0.0
var state_time := 0.0
var result_time := 0.0
var verdict_time := -1.0
var proximo_tique := 0
var proximo_fogo := 0.0
var tremor := 0.0
var clarao := 0.0
var notice := ""
var notice_left := 0.0
var serial_status := "AGUARDANDO"
var last_sensor_ms := -1
var last_raw_frequency := 0.0
var bridge_pid := -1
var aprendendo := ""
var udp := PacketPeerUDP.new()
var font: Font
var logo: Texture2D = null
var fx := PunchFX.new()

@onready var sound_count: AudioStreamPlayer = $SoundCount
@onready var sound_go: AudioStreamPlayer = $SoundGo
@onready var sound_hit: AudioStreamPlayer = $SoundHit
@onready var sound_credit: AudioStreamPlayer = $SoundCredit

# OS SONS NOVOS NASCEM NO CÓDIGO, e não na cena.
#
# Os quatro antigos estão em `main.tscn` e continuam lá. Os cinco que
# entraram com a abertura e com os finais são criados aqui porque um nó a
# mais na cena é uma linha a mais para dar errado num arquivo que ninguém
# lê -- e porque assim o jogo abre igual mesmo que o áudio não tenha sido
# importado ainda: sem `stream`, `_tocar` simplesmente não faz barulho.
var sound_start: AudioStreamPlayer
var sound_win: AudioStreamPlayer
var sound_medium: AudioStreamPlayer
var sound_lose: AudioStreamPlayer
var sound_tick: AudioStreamPlayer

func _ready() -> void:
	font = ThemeDB.fallback_font
	# A LOGO É CARREGADA COM RÉDEA CURTA. Se o arquivo ainda não tiver
	# sido importado (projeto recém-clonado, aberto pela primeira vez), o
	# jogo continua abrindo com a marca desenhada em vetor -- ver
	# `_draw_marca`. Uma máquina de fliperama não pode ficar em tela preta
	# porque faltou uma textura.
	if ResourceLoader.exists("res://assets/logo_lazersport.png"):
		logo = load("res://assets/logo_lazersport.png")
	sound_start = _criar_som("res://assets/audio/start.wav", -1.0)
	sound_win = _criar_som("res://assets/audio/win.wav", 0.5)
	sound_medium = _criar_som("res://assets/audio/medium.wav", -1.0)
	sound_lose = _criar_som("res://assets/audio/lose.wav", -1.5)
	sound_tick = _criar_som("res://assets/audio/tick.wav", -12.0)
	_load_settings()
	var bind_error := udp.bind(UDP_PORT, "127.0.0.1")
	if bind_error != OK:
		serial_status = "PORTA UDP OCUPADA"
	else:
		call_deferred("_start_serial_bridge")
	_entrar_em_abertura()
	set_process(true)
	queue_redraw()

func _criar_som(caminho: String, volume_db: float) -> AudioStreamPlayer:
	var tocador := AudioStreamPlayer.new()
	if ResourceLoader.exists(caminho):
		tocador.stream = load(caminho)
	tocador.volume_db = volume_db
	add_child(tocador)
	return tocador

func _tocar(tocador: AudioStreamPlayer) -> void:
	## Toca se houver som. Áudio faltando não pode derrubar uma rodada.
	if tocador != null and tocador.stream != null:
		tocador.play()

func _exit_tree() -> void:
	_stop_serial_bridge()
	udp.close()

# ======================================================================
# CICLO
# ======================================================================
func _process(delta: float) -> void:
	animation_time += delta
	state_time += delta
	_read_udp()
	fx.atualizar(delta)
	tremor = maxf(0.0, tremor - delta * 26.0)
	clarao = maxf(0.0, clarao - delta * 2.6)

	if notice_left > 0.0:
		notice_left -= delta
	else:
		notice = ""
	if last_sensor_ms >= 0 and Time.get_ticks_msec() - last_sensor_ms > 1800:
		last_raw_frequency = 0.0

	if not settings_open:
		match state:
			GameState.ATTRACT:
				_processar_abertura(delta)
			GameState.INTRO:
				if state_time >= ENTRADA_DURACAO:
					_iniciar_contagem()
			GameState.COUNTDOWN:
				countdown_left -= delta
				var current_count := maxi(0, int(ceil(countdown_left)))
				if current_count > 0 and current_count < last_count:
					last_count = current_count
					_tocar(sound_count)
					fx.onda(Vector2(1180, 525), 60.0, 320.0, Color(0.35, 0.9, 1.0, 0.5), 6.0, 0.6)
				if countdown_left <= 0.0:
					state = GameState.ARMED
					state_time = 0.0
					armed_left = JANELA_DO_SOCO
					_tocar(sound_go)
					fx.onda(Vector2(1180, 525), 40.0, 520.0, Color(1.0, 0.25, 0.55, 0.55), 10.0, 0.8)
					_show_notice("SENSOR ARMADO")
			GameState.ARMED:
				armed_left -= delta
				if armed_left <= 0.0:
					_entrar_em_abertura()
					_show_notice("TEMPO ESGOTADO — PRESSIONE START")
			GameState.RESULT:
				_processar_resultado(delta)
	queue_redraw()

func _processar_abertura(delta: float) -> void:
	# A abertura respira sozinha: uma poeira leve subindo mantém a tela
	# viva sem pedir nada da máquina.
	if randf() < delta * 6.0:
		fx.poeira(
			Vector2(randf_range(200.0, 1720.0), 1120.0),
			1,
			Color(0.35, 0.85, 1.0, 0.35),
			120.0,
		)

func _processar_resultado(delta: float) -> void:
	result_time += delta
	var avanco := clampf(result_time / CONTAGEM_DURACAO, 0.0, 1.0)
	# `ease` com expoente < 1 desacelera no fim: o número dispara e vai
	# frear -- que é o suspense que um placar de arcade precisa ter.
	displayed_score = float(result_score) * ease(avanco, 0.42)

	if avanco < 1.0 and int(displayed_score) >= proximo_tique:
		proximo_tique = int(displayed_score) + 11
		_tocar(sound_tick)

	if verdict_time < 0.0 and avanco >= 1.0:
		_disparar_veredito()
	elif verdict_time >= 0.0:
		verdict_time += delta
		_manter_festa(delta)

	if result_time > RESULTADO_TIMEOUT:
		_entrar_em_abertura()

func _manter_festa(delta: float) -> void:
	match verdict:
		Verdict.FORTE:
			if verdict_time < 5.0 and verdict_time >= proximo_fogo:
				proximo_fogo = verdict_time + 0.55
				fx.fogos(
					Vector2(randf_range(420.0, 1500.0), randf_range(190.0, 520.0)),
					CORES_FESTA,
				)
			if verdict_time < 2.6 and randf() < delta * 26.0:
				fx.chuva_de_confete(TELA.x, 3, CORES_FESTA)
		Verdict.MEDIO:
			if verdict_time >= proximo_fogo:
				proximo_fogo = verdict_time + 0.85
				fx.onda(Vector2(1180, 525), 90.0, 430.0, Color(1.0, 0.72, 0.2, 0.4), 7.0, 0.85)
		Verdict.FRACO:
			if verdict_time < 2.2 and randf() < delta * 9.0:
				fx.estilhacos(Vector2(randf_range(700.0, 1650.0), 300.0), 2, Color("2a3350"))

# ======================================================================
# ENTRADA DE COMANDOS
# ======================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			_toggle_settings()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			if settings_open:
				_close_settings()
			elif state != GameState.ATTRACT:
				_entrar_em_abertura()
				_show_notice("RODADA CANCELADA")
			get_viewport().set_input_as_handled()
			return
		if settings_open:
			if event.keycode == KEY_T:
				_simulate_hit()
			return
		if event.keycode in [KEY_5, KEY_C]:
			_add_credit()
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_1, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_pressionou_start()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventJoypadButton and event.pressed:
		if aprendendo != "":
			_aprender_botao(event.button_index)
			return
		if settings_open:
			return
		# O botão aprendido manda; as ações do projeto ficam de rede de
		# segurança, para a máquina responder mesmo antes de alguém abrir
		# a Central Técnica.
		if event.button_index == botao_select or event.is_action_pressed("input_credito"):
			_add_credit()
		elif event.button_index == botao_start or event.is_action_pressed("input_start"):
			_pressionou_start()
		return

	if settings_open and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_settings_click(event.position)

func _pressionou_start() -> void:
	## START faz uma coisa só em cada tela, e é sempre "seguir em frente".
	match state:
		GameState.ATTRACT:
			_start_round()
		GameState.RESULT:
			# Só depois do veredito: apertar no meio da contagem cortaria
			# justamente o momento pelo qual o cliente pagou.
			if verdict_time >= 0.0:
				_start_round()
		_:
			pass

func _start_round() -> void:
	if game_mode == "credit":
		if credits <= 0:
			_show_notice("INSIRA 1 CRÉDITO — PRESSIONE SELECT")
			return
		credits -= 1
	state = GameState.INTRO
	state_time = 0.0
	fx.limpar()
	clarao = 1.0
	tremor = 14.0
	_tocar(sound_start)
	fx.onda(TELA * 0.5, 40.0, 900.0, Color(0.35, 0.92, 1.0, 0.6), 14.0, 0.85)
	_save_settings()

func _iniciar_contagem() -> void:
	state = GameState.COUNTDOWN
	state_time = 0.0
	countdown_left = 3.0
	last_count = 3
	displayed_score = 0.0
	result_score = 0
	_tocar(sound_count)

func _entrar_em_abertura() -> void:
	state = GameState.ATTRACT
	state_time = 0.0
	verdict_time = -1.0
	result_time = 0.0
	fx.limpar()

func _add_credit() -> void:
	credits = mini(credits + 1, MAX_CREDITS)
	_tocar(sound_credit)
	fx.faiscas(Vector2(960, 980), 22, Color("52f2a4"), 420.0)
	_show_notice("CRÉDITO ADICIONADO  •  SALDO %02d" % credits)
	_save_settings()

func _finish_hit(speed: float, frequency: float = 0.0) -> void:
	if state != GameState.ARMED:
		last_raw_frequency = frequency
		last_sensor_ms = Time.get_ticks_msec()
		return
	result_speed = maxf(speed, 0.0)
	last_raw_frequency = frequency
	last_sensor_ms = Time.get_ticks_msec()
	var span := maxf(max_speed - min_speed, 0.1)
	var normalized := clampf((result_speed - min_speed) / span, 0.0, 1.0)
	result_score = clampi(int(round(pow(normalized, score_curve) * 999.0)), 0, 999)
	if result_speed > 0.0 and result_score < 10:
		result_score = 10

	displayed_score = 0.0
	proximo_tique = 0
	proximo_fogo = 0.0
	verdict_time = -1.0
	result_time = 0.0
	state = GameState.RESULT
	state_time = 0.0
	_tocar(sound_hit)
	tremor = 26.0
	fx.onda(Vector2(1180, 525), 30.0, 640.0, Color(1.0, 0.3, 0.55, 0.6), 16.0, 0.7)
	fx.faiscas(Vector2(1180, 525), 60, Color("ffd23f"), 1250.0)
	plays += 1
	best_score = maxi(best_score, result_score)
	_save_settings()

func _disparar_veredito() -> void:
	## O momento em que a máquina diz se você venceu. Um por soco.
	verdict_time = 0.0
	proximo_fogo = 0.0
	if result_score >= limite_forte:
		verdict = Verdict.FORTE
		_tocar(sound_win)
		tremor = 30.0
		clarao = 0.85
		fx.confete(Vector2(1180, 620), 130, CORES_FESTA, 1250.0)
		fx.chuva_de_confete(TELA.x, 90, CORES_FESTA)
		fx.onda(Vector2(1180, 525), 60.0, 900.0, Color(1.0, 0.85, 0.25, 0.55), 18.0, 1.0)
	elif result_score >= limite_fraco:
		verdict = Verdict.MEDIO
		_tocar(sound_medium)
		tremor = 14.0
		fx.faiscas(Vector2(1180, 525), 46, Color("ffb648"), 700.0)
		fx.onda(Vector2(1180, 525), 60.0, 520.0, Color(1.0, 0.72, 0.25, 0.5), 12.0, 0.9)
	else:
		verdict = Verdict.FRACO
		_tocar(sound_lose)
		tremor = 9.0
		fx.estilhacos(Vector2(1180, 380), 34, Color("222b47"))
		fx.poeira(Vector2(1180, 560), 26, Color(0.55, 0.16, 0.26, 0.5), 260.0)

func _simulate_hit() -> void:
	var speed := randf_range(min_speed + 1.2, max_speed * 0.86)
	last_raw_frequency = randf_range(90.0, 420.0)
	last_sensor_ms = Time.get_ticks_msec()
	if state == GameState.ARMED:
		_finish_hit(speed, last_raw_frequency)
	else:
		_show_notice("PULSO DE TESTE RECEBIDO  •  %.1f Hz" % last_raw_frequency)

# ======================================================================
# SENSOR
# ======================================================================
func _read_udp() -> void:
	while udp.get_available_packet_count() > 0:
		var message := udp.get_packet().get_string_from_utf8().strip_edges()
		_parse_serial_message(message)

func _parse_serial_message(message: String) -> void:
	var parts := message.split(",")
	if parts.is_empty():
		return
	match parts[0]:
		"STATUS":
			serial_status = parts[1] if parts.size() > 1 else "CONECTADO"
		"PULSE":
			last_sensor_ms = Time.get_ticks_msec()
			last_raw_frequency = parts[1].to_float() if parts.size() > 1 else 0.0
		"HIT":
			var speed := parts[1].to_float() if parts.size() > 1 else 0.0
			var freq := parts[2].to_float() if parts.size() > 2 else 0.0
			_finish_hit(speed, freq)
		"PONG":
			serial_status = "CONECTADO COM%d" % com_number

func _start_serial_bridge() -> void:
	_stop_serial_bridge()
	serial_status = "CONECTANDO COM%d" % com_number
	var script_path := _materialize_bridge_script()
	if script_path == "":
		serial_status = "PONTE SERIAL INDISPONÍVEL"
		return
	var args := PackedStringArray([script_path, "--port", "COM%d" % com_number, "--udp-port", str(UDP_PORT)])
	bridge_pid = OS.create_process("python", args, false)
	if bridge_pid <= 0:
		bridge_pid = OS.create_process("py", args, false)
	if bridge_pid <= 0:
		serial_status = "PONTE SERIAL NÃO INICIADA"

func _materialize_bridge_script() -> String:
	var source := FileAccess.open("res://tools/serial_bridge.py", FileAccess.READ)
	if source == null:
		return ""
	var target_path := "user://punch_serial_bridge.py"
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return ""
	target.store_string(source.get_as_text())
	target.close()
	return ProjectSettings.globalize_path(target_path)

func _stop_serial_bridge() -> void:
	if bridge_pid > 0:
		OS.kill(bridge_pid)
	bridge_pid = -1

# ======================================================================
# CENTRAL TÉCNICA (F9)
# ======================================================================
func _toggle_settings() -> void:
	if settings_open:
		_close_settings()
	else:
		if state != GameState.ATTRACT and state != GameState.RESULT:
			_entrar_em_abertura()
		settings_open = true

func _close_settings() -> void:
	settings_open = false
	aprendendo = ""
	_save_settings()

func _aprender_botao(indice: int) -> void:
	## APRENDER O BOTÃO EM VEZ DE ADIVINHAR.
	##
	## Cada placa zero delay numera os botões de um jeito, e o número que
	## funciona numa não funciona na outra. Em vez de listar índices no
	## código, a Central Técnica pede para apertar o botão físico e guarda
	## o que chegou. Uma vez por máquina, e acabou.
	if aprendendo == "start":
		botao_start = indice
		_show_notice("START APRENDIDO — BOTÃO %d" % indice)
	elif aprendendo == "select":
		botao_select = indice
		_show_notice("SELECT APRENDIDO — BOTÃO %d" % indice)
	aprendendo = ""
	_save_settings()

func _handle_settings_click(p: Vector2) -> void:
	if Rect2(1530, 122, 70, 60).has_point(p) or Rect2(1325, 894, 235, 62).has_point(p):
		_close_settings()
	elif Rect2(370, 353, 235, 58).has_point(p):
		game_mode = "free"
	elif Rect2(620, 353, 235, 58).has_point(p):
		game_mode = "credit"
	elif Rect2(1080, 353, 56, 58).has_point(p):
		com_number = maxi(1, com_number - 1)
		_start_serial_bridge()
	elif Rect2(1460, 353, 56, 58).has_point(p):
		com_number = mini(99, com_number + 1)
		_start_serial_bridge()
	elif Rect2(376, 552, 52, 52).has_point(p):
		min_speed = maxf(0.1, min_speed - 0.1)
	elif Rect2(590, 552, 52, 52).has_point(p):
		min_speed = minf(max_speed - 0.5, min_speed + 0.1)
	elif Rect2(697, 552, 52, 52).has_point(p):
		max_speed = maxf(min_speed + 0.5, max_speed - 0.5)
	elif Rect2(910, 552, 52, 52).has_point(p):
		max_speed = minf(40.0, max_speed + 0.5)
	elif Rect2(1035, 540, 240, 70).has_point(p):
		last_raw_frequency = randf_range(80.0, 350.0)
		last_sensor_ms = Time.get_ticks_msec()
		_show_notice("TESTE VISUAL ATIVADO")
	elif Rect2(1295, 540, 240, 70).has_point(p):
		credits = 0
		plays = 0
		best_score = 0
		_show_notice("CONTADORES ZERADOS")
	elif Rect2(376, 700, 52, 52).has_point(p):
		limite_fraco = maxi(50, limite_fraco - 10)
	elif Rect2(590, 700, 52, 52).has_point(p):
		limite_fraco = mini(limite_forte - 50, limite_fraco + 10)
	elif Rect2(697, 700, 52, 52).has_point(p):
		limite_forte = maxi(limite_fraco + 50, limite_forte - 10)
	elif Rect2(910, 700, 52, 52).has_point(p):
		limite_forte = mini(990, limite_forte + 10)
	elif Rect2(1035, 688, 240, 70).has_point(p):
		aprendendo = "start"
		_show_notice("APERTE O BOTÃO START DA MÁQUINA")
	elif Rect2(1295, 688, 240, 70).has_point(p):
		aprendendo = "select"
		_show_notice("APERTE O BOTÃO SELECT DA MÁQUINA")
	elif Rect2(360, 894, 270, 62).has_point(p):
		game_mode = "credit"
		com_number = 3
		min_speed = 1.0
		max_speed = 12.0
		score_curve = 0.78
		limite_fraco = 330
		limite_forte = 700
		botao_start = 7
		botao_select = 6
		_show_notice("PADRÕES RESTAURADOS")
	elif Rect2(650, 894, 270, 62).has_point(p):
		_start_serial_bridge()
		_show_notice("RECONEXÃO SOLICITADA")
	_save_settings()

func _show_notice(message: String) -> void:
	notice = message
	notice_left = 2.8

# ======================================================================
# ESTADO EM DISCO
# ======================================================================
func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		game_mode = str(parsed.get("mode", game_mode))
		credits = int(parsed.get("credits", credits))
		plays = int(parsed.get("plays", plays))
		best_score = int(parsed.get("best_score", best_score))
		com_number = int(parsed.get("com_number", com_number))
		min_speed = float(parsed.get("min_speed", min_speed))
		max_speed = float(parsed.get("max_speed", max_speed))
		score_curve = float(parsed.get("score_curve", score_curve))
		limite_fraco = int(parsed.get("limite_fraco", limite_fraco))
		limite_forte = int(parsed.get("limite_forte", limite_forte))
		botao_start = int(parsed.get("botao_start", botao_start))
		botao_select = int(parsed.get("botao_select", botao_select))

func _save_settings() -> void:
	var data := {
		"mode": game_mode,
		"credits": credits,
		"plays": plays,
		"best_score": best_score,
		"com_number": com_number,
		"min_speed": min_speed,
		"max_speed": max_speed,
		"score_curve": score_curve,
		"limite_fraco": limite_fraco,
		"limite_forte": limite_forte,
		"botao_start": botao_start,
		"botao_select": botao_select,
	}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))

# ======================================================================
# DESENHO
# ======================================================================
func _draw() -> void:
	# O TREMOR SACODE A TELA INTEIRA, e não cada desenho. Um deslocamento
	# só, aplicado antes de tudo: é o que faz o soco forte ser sentido
	# mesmo por quem está olhando de longe.
	if tremor > 0.1:
		draw_set_transform(
			Vector2(randf_range(-tremor, tremor), randf_range(-tremor, tremor)),
			0.0,
			Vector2.ONE,
		)

	if state == GameState.ATTRACT:
		_draw_abertura()
	else:
		_draw_background()
		_draw_header()
		_draw_main_stage()
		_draw_footer()

	fx.desenhar(self)

	if state == GameState.INTRO:
		_draw_entrada()
	if clarao > 0.01:
		draw_rect(Rect2(Vector2.ZERO, TELA), Color(1, 1, 1, clarao * 0.55))
	if notice != "" and not settings_open:
		_draw_notice()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if settings_open:
		_draw_settings()

# ---------------------------------------------------------------- abertura
func _draw_abertura() -> void:
	## A CARA DA MÁQUINA PARADA.
	##
	## É esta tela que fica ligada o dia inteiro no salão, e é ela que faz
	## alguém atravessar o corredor para jogar. Por isso a logo da casa
	## vem em tamanho grande, com luz varrendo por cima, e o "PRESSIONE
	## START" pisca em ritmo de convite -- não de alerta.
	var entrada := clampf(state_time / 1.05, 0.0, 1.0)
	var suave := ease(entrada, 0.35)

	draw_rect(Rect2(Vector2.ZERO, TELA), Color("04060f"))
	_draw_grade_de_fundo()

	var centro := Vector2(960, 415)
	# Raios girando atrás da marca: dão movimento sem competir com ela.
	for i in range(16):
		var angulo := animation_time * 0.22 + i * TAU / 16.0
		var comprimento := 620.0 + sin(animation_time * 1.4 + i) * 40.0
		var cor := Color(0.22, 0.72, 1.0, 0.05 * suave)
		if i % 2 == 0:
			cor = Color(1.0, 0.2, 0.45, 0.045 * suave)
		draw_colored_polygon(
			PackedVector2Array([
				centro,
				centro + Vector2(cos(angulo - 0.055), sin(angulo - 0.055)) * comprimento,
				centro + Vector2(cos(angulo + 0.055), sin(angulo + 0.055)) * comprimento,
			]),
			cor,
		)

	for i in range(3):
		var raio := 250.0 + i * 90.0 + sin(animation_time * 1.1 + i * 0.7) * 14.0
		draw_arc(centro, raio * suave, 0.0, TAU, 120, Color(0.3, 0.8, 1.0, 0.12 * suave), 2.0)

	_draw_glow_circle(centro, 320.0 * suave, Color(0.08, 0.45, 0.95, 0.10 * suave))
	var flutuar := sin(animation_time * 1.6) * 12.0
	_draw_marca(centro + Vector2(0, flutuar), 560.0 * lerpf(0.82, 1.0, suave), suave)
	_draw_varredura_de_luz(centro + Vector2(0, flutuar), 560.0, 190.0)

	# Título com sombra colorida dos dois lados: é o truque barato que dá
	# cara de letreiro de néon sem carregar fonte nenhuma.
	var titulo_y := 760.0
	_text("PUNCH CHALLENGE", Vector2(-4, titulo_y + 3), 96, Color(1.0, 0.17, 0.45, 0.55 * suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("PUNCH CHALLENGE", Vector2(4, titulo_y - 3), 96, Color(0.25, 0.85, 1.0, 0.55 * suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("PUNCH CHALLENGE", Vector2(0, titulo_y), 96, Color(1, 1, 1, suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("MEDIDOR DE POTÊNCIA  •  LAZER & SPORT BRINQUEDOS", Vector2(0, titulo_y + 46), 22, Color(0.44, 0.56, 0.78, suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

	# O convite pisca; sem crédito, ele troca de texto em vez de sumir --
	# quem chegou perto precisa saber o que fazer, não ficar no escuro.
	var piscada := 0.55 + 0.45 * sin(animation_time * 4.2)
	var convite := "PRESSIONE  START"
	var cor_convite := Color(1.0, 0.85, 0.25)
	if game_mode == "credit" and credits <= 0:
		convite = "INSIRA 1 FICHA  •  SELECT"
		cor_convite = Color(0.35, 0.92, 1.0)
	var caixa := Rect2(660, 852, 600, 84)
	_panel(caixa, Color(0.05, 0.09, 0.2, 0.85 * suave), Color(cor_convite.r, cor_convite.g, cor_convite.b, 0.5 * piscada * suave), 42)
	_text(convite, Vector2(660, 906), 34, Color(cor_convite.r, cor_convite.g, cor_convite.b, piscada * suave), HORIZONTAL_ALIGNMENT_CENTER, 600)

	_draw_rodape_da_abertura(suave)

func _draw_rodape_da_abertura(alpha: float) -> void:
	var itens := [
		["RECORDE", "%03d" % best_score, Color("58e8ff")],
		["PARTIDAS", str(plays), Color("a978ff")],
		["CRÉDITOS", "∞" if game_mode == "free" else "%02d" % credits, Color("ff4c9b")],
		["MODO", "LIVRE" if game_mode == "free" else "FICHA", Color("52f2a4")],
	]
	var largura := 300.0
	var inicio := (TELA.x - largura * itens.size() - 24.0 * (itens.size() - 1)) * 0.5
	for i in range(itens.size()):
		var rect := Rect2(inicio + i * (largura + 24.0), 968.0, largura, 82.0)
		var accent: Color = itens[i][2]
		_panel(rect, Color(0.04, 0.07, 0.16, 0.75 * alpha), Color(accent.r, accent.g, accent.b, 0.28 * alpha), 18)
		_text(str(itens[i][0]), rect.position + Vector2(0, 32), 14, Color(0.44, 0.53, 0.71, alpha), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		_text(str(itens[i][1]), rect.position + Vector2(0, 68), 30, Color(accent.r, accent.g, accent.b, alpha), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

	var status_cor := Color("52f2a4") if "CONECTADO" in serial_status else Color("ffbd4a")
	draw_circle(Vector2(52, 44), 7.0, Color(status_cor.r, status_cor.g, status_cor.b, alpha))
	_text(serial_status, Vector2(70, 51), 15, Color(0.55, 0.64, 0.82, alpha), HORIZONTAL_ALIGNMENT_LEFT)
	_text("F9  •  CENTRAL TÉCNICA", Vector2(1400, 51), 15, Color(0.4, 0.49, 0.68, alpha), HORIZONTAL_ALIGNMENT_RIGHT, 460)

func _draw_varredura_de_luz(centro: Vector2, largura: float, altura: float) -> void:
	## A luz que passa por cima da marca de tempos em tempos.
	##
	## Um brilho diagonal atravessando a logo é o que separa "imagem
	## colada na tela" de "letreiro aceso". Passa a cada quatro segundos:
	## mais que isso vira nervoso, menos que isso ninguém vê.
	var ciclo := fmod(animation_time, 4.0) / 1.1
	if ciclo > 1.0:
		return
	var x := centro.x - largura * 0.75 + ciclo * largura * 1.5
	var inclinacao := 70.0
	var faixa := PackedVector2Array([
		Vector2(x - 34.0, centro.y - altura),
		Vector2(x + 34.0, centro.y - altura),
		Vector2(x + 34.0 + inclinacao, centro.y + altura),
		Vector2(x - 34.0 + inclinacao, centro.y + altura),
	])
	var forca := sin(ciclo * PI)
	draw_colored_polygon(faixa, Color(1, 1, 1, 0.10 * forca))

func _draw_entrada() -> void:
	## A transição do START: a marca vem para a frente e some no clarão.
	var t := clampf(state_time / ENTRADA_DURACAO, 0.0, 1.0)
	var escala := lerpf(1.0, 2.4, ease(t, 0.3))
	var alpha := 1.0 - ease(t, 2.2)
	draw_rect(Rect2(Vector2.ZERO, TELA), Color(0.02, 0.03, 0.08, 1.0 - t * 0.35))
	_draw_marca(Vector2(960, 470), 560.0 * escala, alpha)
	_text("PREPARE O PUNHO", Vector2(0, 880), 46, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

# ---------------------------------------------------------------- partida
func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, TELA), Color("050817"))
	for i in range(9):
		var radius := 180.0 + i * 95.0 + sin(animation_time * 0.35 + i) * 8.0
		draw_arc(Vector2(960, 555), radius, -2.8, 0.34, 80, Color(0.12, 0.25, 0.55, 0.07), 2.0)
	for i in range(20):
		var x := fmod(float(i * 389) + animation_time * (6.0 + i * 0.15), 2020.0) - 50.0
		var y := 110.0 + fmod(float(i * 173), 850.0)
		draw_circle(Vector2(x, y), 1.5 + (i % 3), Color(0.25, 0.85, 1.0, 0.22))
	_draw_glow_circle(Vector2(250, 250), 240, Color(0.02, 0.72, 0.95, 0.08))
	_draw_glow_circle(Vector2(1690, 710), 310, Color(0.74, 0.12, 0.56, 0.08))

	# O fundo responde ao veredito: a tela inteira vira o clima do golpe.
	if state == GameState.RESULT and verdict_time >= 0.0:
		match verdict:
			Verdict.FORTE:
				_draw_raios_dourados(Vector2(1180, 525))
			Verdict.MEDIO:
				draw_rect(Rect2(Vector2.ZERO, TELA), Color(0.6, 0.4, 0.05, 0.05 + 0.02 * sin(animation_time * 3.0)))
			Verdict.FRACO:
				_draw_vinheta_vermelha()

func _draw_grade_de_fundo() -> void:
	## Piso em perspectiva: dá profundidade ao fundo sem custar textura.
	for i in range(24):
		var y := 620.0 + pow(float(i) / 24.0, 2.2) * 620.0
		draw_line(Vector2(0, y), Vector2(TELA.x, y), Color(0.16, 0.42, 0.85, 0.10), 1.0)
	for i in range(-12, 13):
		var x := 960.0 + i * 160.0
		draw_line(Vector2(960 + i * 30.0, 620.0), Vector2(x, TELA.y), Color(0.16, 0.42, 0.85, 0.08), 1.0)

func _draw_raios_dourados(centro: Vector2) -> void:
	for i in range(20):
		var angulo := -animation_time * 0.5 + i * TAU / 20.0
		draw_colored_polygon(
			PackedVector2Array([
				centro,
				centro + Vector2(cos(angulo - 0.05), sin(angulo - 0.05)) * 1100.0,
				centro + Vector2(cos(angulo + 0.05), sin(angulo + 0.05)) * 1100.0,
			]),
			Color(1.0, 0.82, 0.25, 0.055),
		)

func _draw_vinheta_vermelha() -> void:
	# UMA MOLDURA QUE PULSA, e não uma tela vermelha. O que perdeu é o
	# soco, não a visão: encher a tela de vermelho esconderia justamente
	# a pontuação que a pessoa quer ler.
	var pulso := 0.09 + 0.04 * sin(animation_time * 2.4)
	for i in range(5):
		var margem := i * 22.0
		draw_rect(
			Rect2(margem, margem, TELA.x - margem * 2.0, TELA.y - margem * 2.0),
			Color(0.75, 0.08, 0.18, pulso * (1.0 - float(i) / 5.0) * 0.45),
			false,
			22.0,
		)

func _draw_header() -> void:
	draw_rect(Rect2(70, 38, 1780, 1), Color(0.3, 0.75, 1.0, 0.18))
	# A marca do cabeçalho é pequena de propósito: aqui ela identifica, e
	# quem manda na tela é a arena. Grande, ela brigava com a linha do
	# topo e com o nome do jogo.
	_draw_marca(Vector2(172, 92), 150.0, 1.0)
	_text("PUNCH", Vector2(262, 86), 26, Color("f4f7ff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("CHALLENGE", Vector2(372, 86), 26, Color("55e7ff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("ARCADE POWER SYSTEM", Vector2(262, 112), 13, Color("7182ad"), HORIZONTAL_ALIGNMENT_LEFT)
	var status_color := Color("52f2a4") if "CONECTADO" in serial_status else Color("ffbd4a")
	draw_circle(Vector2(1483, 85), 7.0, status_color)
	_text(serial_status, Vector2(1500, 92), 14, Color("aab5d1"), HORIZONTAL_ALIGNMENT_LEFT)
	var mode_text := "MODO LIVRE" if game_mode == "free" else "MODO FICHA"
	_pill(Rect2(1660, 62, 168, 48), mode_text, Color("1b2b52"), Color("69e9ff"))

func _draw_main_stage() -> void:
	_panel(Rect2(95, 155, 395, 775), Color(0.035, 0.06, 0.14, 0.82), Color(0.18, 0.35, 0.68, 0.35), 28)
	_text("SEU DESEMPENHO", Vector2(135, 215), 17, Color("6f83ad"), HORIZONTAL_ALIGNMENT_LEFT)
	_stat_card(Rect2(135, 250, 315, 120), "RECORDE", "%03d" % best_score, Color("58e8ff"))
	_stat_card(Rect2(135, 392, 315, 120), "PARTIDAS", str(plays), Color("a978ff"))
	_stat_card(Rect2(135, 534, 315, 120), "CRÉDITOS", "∞" if game_mode == "free" else "%02d" % credits, Color("ff4c9b"))
	_text("CONTROLES", Vector2(135, 722), 15, Color("6f83ad"), HORIZONTAL_ALIGNMENT_LEFT)
	_key_hint(Rect2(135, 748, 315, 52), "START", "INICIAR")
	_key_hint(Rect2(135, 812, 315, 52), "SELECT", "+1 CRÉDITO")
	_text("F9  •  CENTRAL TÉCNICA", Vector2(135, 900), 14, Color("7385ad"), HORIZONTAL_ALIGNMENT_LEFT)

	_panel(Rect2(535, 155, 1290, 775), Color(0.025, 0.04, 0.105, 0.72), Color(0.16, 0.32, 0.68, 0.28), 36)
	_draw_arena_center()

func _draw_arena_center() -> void:
	var center := Vector2(1180, 525)
	for i in range(4):
		var pulse := fmod(animation_time * (95.0 + i * 7.0) + i * 85.0, 420.0)
		draw_arc(center, 150.0 + pulse, 0, TAU, 120, Color(0.14, 0.82, 1.0, 0.11 * (1.0 - pulse / 460.0)), 3.0)

	match state:
		GameState.INTRO:
			_draw_power_core(center, 122.0)
		GameState.COUNTDOWN:
			var count := clampi(int(ceil(countdown_left)), 1, 3)
			# O número nasce grande e encolhe até o próximo: é a batida do
			# relógio que se vê, e não só se lê.
			var fracao := fmod(countdown_left, 1.0)
			var scale_pulse := 1.0 + fracao * 0.16
			_draw_glow_circle(center, 165.0 * scale_pulse, Color(0.18, 0.77, 1.0, 0.11))
			draw_arc(center, 205.0, -PI * 0.5, -PI * 0.5 + TAU * fracao, 96, Color("4beaff"), 9.0)
			_text(str(count), Vector2(880, 630), int(245 * scale_pulse), Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 600)
			_text("PREPARE-SE", Vector2(880, 764), 30, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, 600)
		GameState.ARMED:
			_draw_target(center)
			_text("SOQUE AGORA!", Vector2(770, 760), 70, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 820)
			_text("Aguardando impacto  •  %.1fs" % armed_left, Vector2(770, 812), 22, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, 820)
		GameState.RESULT:
			_draw_resultado(center)

func _draw_resultado(center: Vector2) -> void:
	_draw_score_gauge(center, displayed_score / 999.0)

	# O número da contagem vibra enquanto sobe e assenta no fim.
	var vibra := 1.0
	if verdict_time < 0.0:
		vibra = 1.0 + 0.05 * sin(animation_time * 26.0)
	_text("%03d" % int(round(displayed_score)), Vector2(825, 590), int(150 * vibra), Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 710)
	_text("PONTOS DE POTÊNCIA", Vector2(825, 665), 22, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, 710)

	if verdict_time < 0.0:
		_text("MEDINDO O IMPACTO…", Vector2(825, 815), 20, Color("8092b9"), HORIZONTAL_ALIGNMENT_CENTER, 710)
		return

	match verdict:
		Verdict.FORTE:
			_draw_carimbo("NOCAUTE!", "VOCÊ VENCEU O DESAFIO", Color("ffd23f"), Color("52f2a4"))
		Verdict.MEDIO:
			_draw_carimbo("BOM GOLPE", "QUASE LÁ — TENTE MAIS UMA", Color("ffb648"), Color("ffd8a1"))
		Verdict.FRACO:
			_draw_carimbo("FRACO!", "NÃO FOI DESSA VEZ", Color("ff4c6a"), Color("ff9aa9"))

	_text("Velocidade medida: %.2f m/s" % result_speed, Vector2(825, 868), 18, Color("8092b9"), HORIZONTAL_ALIGNMENT_CENTER, 710)
	if verdict_time > 1.0:
		var piscada := 0.55 + 0.45 * sin(animation_time * 3.6)
		_text("START PARA JOGAR NOVAMENTE", Vector2(825, 906), 18, Color(0.73, 0.77, 0.87, piscada), HORIZONTAL_ALIGNMENT_CENTER, 710)

func _draw_carimbo(titulo: String, linha: String, cor: Color, cor_linha: Color) -> void:
	## O CARIMBO CAI NA TELA, não aparece.
	##
	## Entra grande, passa do lugar e volta -- o mesmo gesto de um carimbo
	## batendo no papel. É meio segundo de animação que faz o veredito
	## parecer uma decisão, e não um texto que estava lá o tempo todo.
	var t := clampf(verdict_time / 0.45, 0.0, 1.0)
	var escala := 1.0
	if t < 1.0:
		escala = lerpf(2.6, 1.0, ease(t, 0.28)) + sin(t * PI) * 0.12
	var alpha := clampf(verdict_time / 0.2, 0.0, 1.0)
	var balanco := 0.0
	if verdict == Verdict.FRACO:
		# O carimbo do soco fraco escorrega para baixo, cansado.
		balanco = minf(verdict_time * 16.0, 14.0)
	elif verdict == Verdict.FORTE:
		balanco = -sin(verdict_time * 5.0) * 6.0

	var tamanho := int(clampf(96.0 * escala, 20.0, 300.0))
	_text(titulo, Vector2(825, 764 + balanco), tamanho, Color(cor.r, cor.g, cor.b, alpha), HORIZONTAL_ALIGNMENT_CENTER, 710)
	if verdict_time > 0.35:
		var alpha_linha := clampf((verdict_time - 0.35) / 0.35, 0.0, 1.0)
		_text(linha, Vector2(825, 814 + balanco), 26, Color(cor_linha.r, cor_linha.g, cor_linha.b, alpha_linha), HORIZONTAL_ALIGNMENT_CENTER, 710)

func _draw_footer() -> void:
	_text("LAZER & SPORT BRINQUEDOS", Vector2(95, 1004), 14, Color("536488"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("SISTEMA DE MEDIÇÃO POR ENCODER ÓPTICO", Vector2(1310, 1004), 14, Color("536488"), HORIZONTAL_ALIGNMENT_RIGHT, 515)

# ---------------------------------------------------------------- central
func _draw_settings() -> void:
	draw_rect(Rect2(Vector2.ZERO, TELA), Color(0.005, 0.009, 0.025, 0.91))
	_panel(Rect2(250, 105, 1420, 875), Color("0d142c"), Color(0.22, 0.55, 0.95, 0.52), 34)
	_text("CENTRAL TÉCNICA", Vector2(330, 172), 34, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("Configuração, diagnóstico e calibração", Vector2(330, 207), 17, Color("7e90b8"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(Rect2(1530, 122, 70, 60), "×", false, Color("ff568f"), 30)

	_panel(Rect2(330, 255, 580, 195), Color("111d3b"), Color(0.19, 0.42, 0.78, 0.4), 22)
	_text("MODO DE OPERAÇÃO", Vector2(370, 302), 15, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("Como o cliente inicia uma partida", Vector2(370, 332), 14, Color("5f7199"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(Rect2(370, 353, 235, 58), "LIVRE", game_mode == "free", Color("55e7ff"))
	_button(Rect2(620, 353, 235, 58), "1 FICHA", game_mode == "credit", Color("ff4c9b"))

	_panel(Rect2(1010, 255, 580, 195), Color("111d3b"), Color(0.19, 0.42, 0.78, 0.4), 22)
	_text("CONEXÃO DO SENSOR", Vector2(1050, 302), 15, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	var dot_color := Color("4ff0a2") if "CONECTADO" in serial_status else Color("ffba46")
	draw_circle(Vector2(1535, 294), 7.0, dot_color)
	_text(serial_status, Vector2(1050, 332), 14, dot_color, HORIZONTAL_ALIGNMENT_LEFT)
	_button(Rect2(1080, 353, 56, 58), "−", false, Color("55e7ff"), 25)
	_button(Rect2(1460, 353, 56, 58), "+", false, Color("55e7ff"), 25)
	_text("COM%d" % com_number, Vector2(1135, 391), 26, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 325)

	_panel(Rect2(330, 480, 1260, 285), Color("0e1935"), Color(0.19, 0.42, 0.78, 0.4), 22)
	_text("CALIBRAÇÃO, FAIXAS E BOTÕES", Vector2(370, 522), 15, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)

	_text("VELOCIDADE MÍNIMA", Vector2(376, 532), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(Rect2(376, 552, 52, 52), "−", false, Color("55e7ff"), 23)
	_text("%.1f m/s" % min_speed, Vector2(430, 588), 23, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 160)
	_button(Rect2(590, 552, 52, 52), "+", false, Color("55e7ff"), 23)
	_text("VELOCIDADE MÁXIMA", Vector2(697, 532), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(Rect2(697, 552, 52, 52), "−", false, Color("a978ff"), 23)
	_text("%.1f m/s" % max_speed, Vector2(750, 588), 23, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 160)
	_button(Rect2(910, 552, 52, 52), "+", false, Color("a978ff"), 23)
	_button(Rect2(1035, 540, 240, 70), "TESTAR SENSOR", false, Color("55e7ff"))
	_button(Rect2(1295, 540, 240, 70), "ZERAR DADOS", false, Color("ff568f"))

	# AS FAIXAS DO VEREDITO. É aqui que o operador decide o que a máquina
	# dele chama de fraco e de forte -- a mecânica de cada uma responde
	# diferente, e uma faixa errada faz todo mundo perder (ou todo mundo
	# ganhar), que é o jeito mais rápido de esvaziar a fila.
	_text("ATÉ AQUI É FRACO", Vector2(376, 680), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(Rect2(376, 700, 52, 52), "−", false, Color("ff4c6a"), 23)
	_text("%03d" % limite_fraco, Vector2(430, 736), 23, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 160)
	_button(Rect2(590, 700, 52, 52), "+", false, Color("ff4c6a"), 23)
	_text("DAQUI É FORTE", Vector2(697, 680), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(Rect2(697, 700, 52, 52), "−", false, Color("52f2a4"), 23)
	_text("%03d" % limite_forte, Vector2(750, 736), 23, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 160)
	_button(Rect2(910, 700, 52, 52), "+", false, Color("52f2a4"), 23)
	_button(Rect2(1035, 688, 240, 70), "APERTE START…" if aprendendo == "start" else "APRENDER START", aprendendo == "start", Color("55e7ff"))
	_button(Rect2(1295, 688, 240, 70), "APERTE SELECT…" if aprendendo == "select" else "APRENDER SELECT", aprendendo == "select", Color("a978ff"))

	var sensor_on := last_sensor_ms >= 0 and Time.get_ticks_msec() - last_sensor_ms < 850
	draw_circle(Vector2(1050, 641), 7.0, Color("4ff0a2") if sensor_on else Color("3d4b70"))
	_text(
		"ENTRADA: %s   •   FREQUÊNCIA: %.1f Hz   •   BOTÕES: START %d / SELECT %d" % [
			"ATIVA" if sensor_on else "INATIVA", last_raw_frequency, botao_start, botao_select,
		],
		Vector2(1070, 647), 13, Color("8fa1c4"), HORIZONTAL_ALIGNMENT_LEFT
	)

	_panel(Rect2(330, 790, 1260, 82), Color(0.055, 0.1, 0.19, 0.8), Color(0.17, 0.37, 0.65, 0.3), 18)
	_text("SALDO", Vector2(370, 820), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("%02d créditos" % credits, Vector2(370, 851), 22, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("PARTIDAS", Vector2(650, 820), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text(str(plays), Vector2(650, 851), 22, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("RECORDE", Vector2(900, 820), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("%03d" % best_score, Vector2(900, 851), 22, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("T simula um soco  •  F9 ou ESC fecha", Vector2(1150, 843), 15, Color("7084ad"), HORIZONTAL_ALIGNMENT_LEFT)

	_button(Rect2(360, 894, 270, 62), "RESTAURAR PADRÕES", false, Color("8094bd"))
	_button(Rect2(650, 894, 270, 62), "RECONECTAR", false, Color("a978ff"))
	_button(Rect2(1325, 894, 235, 62), "SALVAR E VOLTAR", true, Color("55e7ff"))

	if notice != "":
		_draw_notice()

func _draw_notice() -> void:
	var alpha := clampf(notice_left * 2.0, 0.0, 1.0)
	var rect := Rect2(650, 955, 620, 62)
	_panel(rect, Color(0.05, 0.11, 0.22, 0.94 * alpha), Color(0.23, 0.82, 1.0, 0.55 * alpha), 18)
	_text(notice, Vector2(670, 994), 16, Color(0.82, 0.96, 1.0, alpha), HORIZONTAL_ALIGNMENT_CENTER, 580)

# ======================================================================
# PEÇAS DE DESENHO
# ======================================================================
func _draw_marca(centro: Vector2, largura: float, alpha: float) -> void:
	## A LOGO DA CASA — a de verdade quando ela existe.
	##
	## `assets/logo_lazersport.png` é a marca oficial. Se ela não estiver
	## importada, entra o desenho vetorial do alvo com o dardo: a mesma
	## ideia, feita à mão, para a tela nunca ficar sem identidade.
	if logo != null:
		var proporcao := float(logo.get_height()) / float(logo.get_width())
		var tamanho := Vector2(largura, largura * proporcao)
		var rect := Rect2(centro - tamanho * 0.5, tamanho)
		# Um brilho por trás faz a logo "acender" sobre o fundo escuro em
		# vez de parecer um adesivo colado.
		_draw_glow_circle(centro, largura * 0.42, Color(0.18, 0.55, 1.0, 0.06 * alpha))
		draw_texture_rect(logo, rect, false, Color(1, 1, 1, alpha))
		return

	var r := largura * 0.28
	draw_circle(centro, r, Color(0.86, 0.16, 0.33, alpha))
	draw_circle(centro, r * 0.72, Color(1, 1, 1, alpha))
	draw_circle(centro, r * 0.46, Color(0.95, 0.19, 0.36, alpha))
	draw_circle(centro, r * 0.2, Color(1, 1, 1, alpha))
	var ponta := centro + Vector2(r * 0.1, -r * 0.1)
	draw_line(ponta, ponta + Vector2(r * 0.95, -r * 0.95), Color(1, 1, 1, alpha), maxf(3.0, r * 0.11))
	draw_circle(ponta + Vector2(r * 0.34, -r * 0.34), r * 0.13, Color(0.25, 0.72, 0.95, alpha))
	_text("LAZER & SPORT", Vector2(centro.x - largura * 0.5, centro.y + r + 46.0), int(maxf(14.0, largura * 0.075)), Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, largura)

func _panel(rect: Rect2, fill: Color, border: Color, radius: int = 18) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	draw_style_box(box, rect)

func _button(rect: Rect2, label: String, active: bool, accent: Color, size: int = 16) -> void:
	var fill := Color(accent.r, accent.g, accent.b, 0.19 if active else 0.065)
	var border := Color(accent.r, accent.g, accent.b, 0.92 if active else 0.32)
	_panel(rect, fill, border, 14)
	_text(label, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.64), size, accent if active else Color("c2cce2"), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _pill(rect: Rect2, label: String, fill: Color, color: Color) -> void:
	_panel(rect, fill, Color(color.r, color.g, color.b, 0.3), int(rect.size.y / 2.0))
	_text(label, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.64), 15, color, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _stat_card(rect: Rect2, label: String, value: String, accent: Color) -> void:
	_panel(rect, Color(0.055, 0.09, 0.18, 0.76), Color(accent.r, accent.g, accent.b, 0.24), 18)
	draw_rect(Rect2(rect.position.x, rect.position.y + 20, 4, rect.size.y - 40), accent)
	_text(label, rect.position + Vector2(27, 39), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text(value, rect.position + Vector2(27, 91), 39, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)

func _key_hint(rect: Rect2, key: String, action: String) -> void:
	_panel(rect, Color(0.04, 0.075, 0.15, 0.72), Color(0.16, 0.32, 0.58, 0.28), 12)
	_text(key, rect.position + Vector2(18, 33), 14, Color("63e9ff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text(action, rect.position + Vector2(130, 33), 13, Color("aab6cf"), HORIZONTAL_ALIGNMENT_LEFT)

func _draw_power_core(center: Vector2, radius: float) -> void:
	_draw_glow_circle(center, radius + 40.0, Color(0.15, 0.7, 1.0, 0.09))
	draw_circle(center, radius, Color("101b3b"))
	draw_arc(center, radius, 0, TAU, 96, Color("4beaff"), 5.0)
	draw_arc(center, radius + 22, animation_time, animation_time + 4.6, 72, Color("8d62ff"), 5.0)
	_draw_marca(center, radius * 2.6, 1.0)

func _draw_target(center: Vector2) -> void:
	_draw_glow_circle(center, 190.0, Color(0.95, 0.15, 0.52, 0.12))
	for radius in [180.0, 135.0, 88.0]:
		draw_arc(center, radius, 0, TAU, 90, Color(1.0, 0.25, 0.55, 0.78), 5.0)
	draw_circle(center, 44.0 + sin(animation_time * 8.0) * 5.0, Color("ff2d78"))
	draw_line(center - Vector2(230, 0), center + Vector2(230, 0), Color(0.3, 0.9, 1.0, 0.28), 2.0)
	draw_line(center - Vector2(0, 230), center + Vector2(0, 230), Color(0.3, 0.9, 1.0, 0.28), 2.0)

func _draw_score_gauge(center: Vector2, amount: float) -> void:
	_draw_glow_circle(center, 235.0, Color(0.25, 0.2, 0.95, 0.08))
	draw_arc(center, 235, -2.55, 0.41, 130, Color(0.12, 0.18, 0.35, 0.9), 24.0)
	var end_angle := lerpf(-2.55, 0.41, clampf(amount, 0.0, 1.0))
	# A cor do arco é o próprio veredito: vermelho, âmbar ou verde,
	# acompanhando as faixas que o operador ajustou.
	var cor := Color("ff4c6a")
	if displayed_score >= float(limite_forte):
		cor = Color("52f2a4")
	elif displayed_score >= float(limite_fraco):
		cor = Color("ffb648")
	draw_arc(center, 235, -2.55, end_angle, 130, cor, 24.0)
	# As marcas das faixas, para quem joga saber onde precisa chegar.
	for limite in [limite_fraco, limite_forte]:
		var angulo := lerpf(-2.55, 0.41, float(limite) / 999.0)
		var direcao := Vector2(cos(angulo), sin(angulo))
		draw_line(center + direcao * 218.0, center + direcao * 252.0, Color(1, 1, 1, 0.5), 3.0)

func _draw_glow_circle(center: Vector2, radius: float, color: Color) -> void:
	for i in range(5, 0, -1):
		var c := color
		c.a *= float(6 - i) / 12.0
		draw_circle(center, radius * float(i) / 5.0, c)

func _text(value: String, baseline: Vector2, size: int, color: Color, align: HorizontalAlignment, width: float = -1.0) -> void:
	draw_string(font, baseline, value, align, width, size, color)
