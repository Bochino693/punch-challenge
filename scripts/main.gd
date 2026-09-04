extends Control

## Punch Challenge — a máquina de soco da Lazer & Sport.
##
## TELA EM PÉ, 1080 × 1920. A máquina é um armário alto com o saco na
## frente: quem joga olha para cima, não para os lados. Numa tela
## deitada, metade da largura seria moldura vazia e o número da pontuação
## ficaria pequeno justamente para quem está a três metros de distância.
## Em pé, a leitura desce em coluna -- marca, número, veredito -- que é a
## ordem em que a pessoa procura.
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

## O tamanho da tela, em pé. Todo desenho deste arquivo se apoia nele.
const TELA := Vector2(1080.0, 1920.0)
## O centro da arena: o alvo, o mostrador e o número nascem daqui.
const ARENA := Vector2(540.0, 720.0)

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

## OS BOTÕES DA CENTRAL TÉCNICA MORAM AQUI, e não em dois lugares.
##
## Antes cada retângulo era escrito duas vezes: uma no desenho e outra na
## conferência do clique. Bastava mover um botão e o toque continuava
## caindo onde ele estava antes -- o tipo de defeito que ninguém vê no
## código e todo mundo sente no balcão. Com a tela em pé, TODOS mudaram
## de lugar de uma vez; num dicionário só, mudar é mexer numa linha.
const BOTOES := {
	"fechar": Rect2(918, 138, 72, 64),
	"modo_livre": Rect2(110, 336, 400, 72),
	"modo_ficha": Rect2(570, 336, 400, 72),
	"com_menos": Rect2(150, 566, 72, 72),
	"com_mais": Rect2(858, 566, 72, 72),
	"min_menos": Rect2(120, 810, 66, 66),
	"min_mais": Rect2(360, 810, 66, 66),
	"max_menos": Rect2(620, 810, 66, 66),
	"max_mais": Rect2(860, 810, 66, 66),
	"fraco_menos": Rect2(120, 1064, 66, 66),
	"fraco_mais": Rect2(360, 1064, 66, 66),
	"forte_menos": Rect2(620, 1064, 66, 66),
	"forte_mais": Rect2(860, 1064, 66, 66),
	"testar": Rect2(110, 1224, 400, 78),
	"zerar": Rect2(570, 1224, 400, 78),
	"aprender_start": Rect2(110, 1320, 400, 78),
	"aprender_select": Rect2(570, 1320, 400, 78),
	"padroes": Rect2(110, 1690, 400, 78),
	"reconectar": Rect2(570, 1690, 400, 78),
	"salvar": Rect2(110, 1786, 860, 82),
}

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
					fx.onda(ARENA, 60.0, 340.0, Color(0.35, 0.9, 1.0, 0.5), 6.0, 0.6)
				if countdown_left <= 0.0:
					state = GameState.ARMED
					state_time = 0.0
					armed_left = JANELA_DO_SOCO
					_tocar(sound_go)
					fx.onda(ARENA, 40.0, 560.0, Color(1.0, 0.25, 0.55, 0.55), 10.0, 0.8)
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
			Vector2(randf_range(120.0, 960.0), TELA.y + 40.0),
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
					Vector2(randf_range(180.0, 900.0), randf_range(280.0, 900.0)),
					CORES_FESTA,
				)
			if verdict_time < 2.6 and randf() < delta * 26.0:
				fx.chuva_de_confete(TELA.x, 3, CORES_FESTA)
		Verdict.MEDIO:
			if verdict_time >= proximo_fogo:
				proximo_fogo = verdict_time + 0.85
				fx.onda(ARENA, 90.0, 450.0, Color(1.0, 0.72, 0.2, 0.4), 7.0, 0.85)
		Verdict.FRACO:
			if verdict_time < 2.2 and randf() < delta * 9.0:
				fx.estilhacos(Vector2(randf_range(180.0, 900.0), 380.0), 2, Color("2a3350"))

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
	fx.onda(TELA * 0.5, 40.0, 1100.0, Color(0.35, 0.92, 1.0, 0.6), 14.0, 0.85)
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
	fx.faiscas(Vector2(540, 1400), 22, Color("52f2a4"), 420.0)
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
	fx.onda(ARENA, 30.0, 700.0, Color(1.0, 0.3, 0.55, 0.6), 16.0, 0.7)
	fx.faiscas(ARENA, 60, Color("ffd23f"), 1250.0)
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
		fx.confete(Vector2(540, 900), 130, CORES_FESTA, 1250.0)
		fx.chuva_de_confete(TELA.x, 90, CORES_FESTA)
		fx.onda(ARENA, 60.0, 1100.0, Color(1.0, 0.85, 0.25, 0.55), 18.0, 1.0)
	elif result_score >= limite_fraco:
		verdict = Verdict.MEDIO
		_tocar(sound_medium)
		tremor = 14.0
		fx.faiscas(ARENA, 46, Color("ffb648"), 700.0)
		fx.onda(ARENA, 60.0, 560.0, Color(1.0, 0.72, 0.25, 0.5), 12.0, 0.9)
	else:
		verdict = Verdict.FRACO
		_tocar(sound_lose)
		tremor = 9.0
		fx.estilhacos(Vector2(540, 520), 34, Color("222b47"))
		fx.poeira(Vector2(540, 760), 26, Color(0.55, 0.16, 0.26, 0.5), 260.0)

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
	## Um clique, um botão. Os retângulos são os mesmos que a tela desenha
	## (`BOTOES`), então mover um botão move o toque junto.
	if BOTOES["fechar"].has_point(p) or BOTOES["salvar"].has_point(p):
		_close_settings()
	elif BOTOES["modo_livre"].has_point(p):
		game_mode = "free"
	elif BOTOES["modo_ficha"].has_point(p):
		game_mode = "credit"
	elif BOTOES["com_menos"].has_point(p):
		com_number = maxi(1, com_number - 1)
		_start_serial_bridge()
	elif BOTOES["com_mais"].has_point(p):
		com_number = mini(99, com_number + 1)
		_start_serial_bridge()
	elif BOTOES["min_menos"].has_point(p):
		min_speed = maxf(0.1, min_speed - 0.1)
	elif BOTOES["min_mais"].has_point(p):
		min_speed = minf(max_speed - 0.5, min_speed + 0.1)
	elif BOTOES["max_menos"].has_point(p):
		max_speed = maxf(min_speed + 0.5, max_speed - 0.5)
	elif BOTOES["max_mais"].has_point(p):
		max_speed = minf(40.0, max_speed + 0.5)
	elif BOTOES["fraco_menos"].has_point(p):
		limite_fraco = maxi(50, limite_fraco - 10)
	elif BOTOES["fraco_mais"].has_point(p):
		limite_fraco = mini(limite_forte - 50, limite_fraco + 10)
	elif BOTOES["forte_menos"].has_point(p):
		limite_forte = maxi(limite_fraco + 50, limite_forte - 10)
	elif BOTOES["forte_mais"].has_point(p):
		limite_forte = mini(990, limite_forte + 10)
	elif BOTOES["testar"].has_point(p):
		last_raw_frequency = randf_range(80.0, 350.0)
		last_sensor_ms = Time.get_ticks_msec()
		_show_notice("TESTE VISUAL ATIVADO")
	elif BOTOES["zerar"].has_point(p):
		credits = 0
		plays = 0
		best_score = 0
		_show_notice("CONTADORES ZERADOS")
	elif BOTOES["aprender_start"].has_point(p):
		aprendendo = "start"
		_show_notice("APERTE O BOTÃO START DA MÁQUINA")
	elif BOTOES["aprender_select"].has_point(p):
		aprendendo = "select"
		_show_notice("APERTE O BOTÃO SELECT DA MÁQUINA")
	elif BOTOES["padroes"].has_point(p):
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
	elif BOTOES["reconectar"].has_point(p):
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
	## alguém atravessar o corredor para jogar. Na tela em pé a leitura
	## desce em coluna: marca, nome do jogo, convite, números. Por isso a
	## logo da casa ocupa o terço de cima inteiro -- de longe, é ela que
	## se enxerga primeiro.
	var entrada := clampf(state_time / 1.05, 0.0, 1.0)
	var suave := ease(entrada, 0.35)

	draw_rect(Rect2(Vector2.ZERO, TELA), Color("04060f"))
	_draw_grade_de_fundo()

	var centro := Vector2(540, 580)
	# Raios girando atrás da marca: dão movimento sem competir com ela.
	for i in range(16):
		var angulo := animation_time * 0.22 + i * TAU / 16.0
		var comprimento := 900.0 + sin(animation_time * 1.4 + i) * 50.0
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
		var raio := 320.0 + i * 82.0 + sin(animation_time * 1.1 + i * 0.7) * 14.0
		draw_arc(centro, raio * suave, 0.0, TAU, 120, Color(0.3, 0.8, 1.0, 0.12 * suave), 2.0)

	_draw_glow_circle(centro, 380.0 * suave, Color(0.08, 0.45, 0.95, 0.10 * suave))
	var flutuar := sin(animation_time * 1.6) * 14.0
	_draw_marca(centro + Vector2(0, flutuar), 900.0 * lerpf(0.84, 1.0, suave), suave)
	_draw_varredura_de_luz(centro + Vector2(0, flutuar), 900.0, 320.0)

	# Título com sombra colorida dos dois lados: é o truque barato que dá
	# cara de letreiro de néon sem carregar fonte nenhuma.
	var titulo_y := 1162.0
	_text("PUNCH CHALLENGE", Vector2(-4, titulo_y + 3), 78, Color(1.0, 0.17, 0.45, 0.55 * suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("PUNCH CHALLENGE", Vector2(4, titulo_y - 3), 78, Color(0.25, 0.85, 1.0, 0.55 * suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("PUNCH CHALLENGE", Vector2(0, titulo_y), 78, Color(1, 1, 1, suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("MEDIDOR DE POTÊNCIA", Vector2(0, titulo_y + 46), 24, Color(0.44, 0.56, 0.78, suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("LAZER & SPORT BRINQUEDOS", Vector2(0, titulo_y + 82), 20, Color(0.34, 0.44, 0.64, suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

	# O convite pisca; sem crédito, ele troca de texto em vez de sumir --
	# quem chegou perto precisa saber o que fazer, não ficar no escuro.
	var piscada := 0.55 + 0.45 * sin(animation_time * 4.2)
	var convite := "PRESSIONE  START"
	var cor_convite := Color(1.0, 0.85, 0.25)
	if game_mode == "credit" and credits <= 0:
		convite = "INSIRA 1 FICHA  •  SELECT"
		cor_convite = Color(0.35, 0.92, 1.0)
	var caixa := Rect2(140, 1320, 800, 110)
	_panel(caixa, Color(0.05, 0.09, 0.2, 0.85 * suave), Color(cor_convite.r, cor_convite.g, cor_convite.b, 0.5 * piscada * suave), 55)
	_text(convite, Vector2(140, 1392), 40, Color(cor_convite.r, cor_convite.g, cor_convite.b, piscada * suave), HORIZONTAL_ALIGNMENT_CENTER, 800)

	_draw_rodape_da_abertura(suave)

func _draw_rodape_da_abertura(alpha: float) -> void:
	## Os quatro números da máquina, em dois pares. Na tela em pé cabem
	## lado a lado sem espremer o rótulo -- e quem opera lê o crédito e o
	## modo de longe, sem entrar na Central Técnica.
	var itens := [
		["RECORDE", "%03d" % best_score, Color("58e8ff")],
		["PARTIDAS", str(plays), Color("a978ff")],
		["CRÉDITOS", "∞" if game_mode == "free" else "%02d" % credits, Color("ff4c9b")],
		["MODO", "LIVRE" if game_mode == "free" else "FICHA", Color("52f2a4")],
	]
	for i in range(itens.size()):
		var coluna := i % 2
		var linha := i / 2
		var rect := Rect2(60.0 + coluna * 490.0, 1530.0 + linha * 150.0, 470.0, 130.0)
		var accent: Color = itens[i][2]
		_panel(rect, Color(0.04, 0.07, 0.16, 0.75 * alpha), Color(accent.r, accent.g, accent.b, 0.28 * alpha), 20)
		_text(str(itens[i][0]), rect.position + Vector2(0, 48), 17, Color(0.44, 0.53, 0.71, alpha), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		_text(str(itens[i][1]), rect.position + Vector2(0, 104), 40, Color(accent.r, accent.g, accent.b, alpha), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

	var status_cor := Color("52f2a4") if "CONECTADO" in serial_status else Color("ffbd4a")
	draw_circle(Vector2(56, 66), 8.0, Color(status_cor.r, status_cor.g, status_cor.b, alpha))
	_text(serial_status, Vector2(78, 74), 17, Color(0.55, 0.64, 0.82, alpha), HORIZONTAL_ALIGNMENT_LEFT)
	_text("F9  •  CENTRAL TÉCNICA", Vector2(580, 74), 17, Color(0.4, 0.49, 0.68, alpha), HORIZONTAL_ALIGNMENT_RIGHT, 440)
	_text("SISTEMA DE MEDIÇÃO POR ENCODER ÓPTICO", Vector2(0, 1870), 16, Color(0.29, 0.36, 0.5, alpha), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

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
	var inclinacao := 90.0
	var faixa := PackedVector2Array([
		Vector2(x - 40.0, centro.y - altura),
		Vector2(x + 40.0, centro.y - altura),
		Vector2(x + 40.0 + inclinacao, centro.y + altura),
		Vector2(x - 40.0 + inclinacao, centro.y + altura),
	])
	var forca := sin(ciclo * PI)
	draw_colored_polygon(faixa, Color(1, 1, 1, 0.10 * forca))

func _draw_entrada() -> void:
	## A transição do START: a marca vem para a frente e some no clarão.
	var t := clampf(state_time / ENTRADA_DURACAO, 0.0, 1.0)
	var escala := lerpf(1.0, 2.4, ease(t, 0.3))
	var alpha := 1.0 - ease(t, 2.2)
	draw_rect(Rect2(Vector2.ZERO, TELA), Color(0.02, 0.03, 0.08, 1.0 - t * 0.35))
	_draw_marca(Vector2(540, 780), 900.0 * escala, alpha)
	_text("PREPARE O PUNHO", Vector2(0, 1440), 52, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

# ---------------------------------------------------------------- partida
func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, TELA), Color("050817"))
	for i in range(9):
		var radius := 200.0 + i * 110.0 + sin(animation_time * 0.35 + i) * 8.0
		draw_arc(ARENA, radius, -2.8, 0.34, 80, Color(0.12, 0.25, 0.55, 0.07), 2.0)
	for i in range(20):
		var x := 40.0 + fmod(float(i * 271), 1000.0)
		var y := fmod(float(i * 397) + animation_time * (10.0 + i * 0.3), 1900.0)
		draw_circle(Vector2(x, y), 1.5 + (i % 3), Color(0.25, 0.85, 1.0, 0.22))
	_draw_glow_circle(Vector2(160, 300), 260, Color(0.02, 0.72, 0.95, 0.08))
	_draw_glow_circle(Vector2(930, 1420), 320, Color(0.74, 0.12, 0.56, 0.08))

	# O fundo responde ao veredito: a tela inteira vira o clima do golpe.
	if state == GameState.RESULT and verdict_time >= 0.0:
		match verdict:
			Verdict.FORTE:
				_draw_raios_dourados(ARENA)
			Verdict.MEDIO:
				draw_rect(Rect2(Vector2.ZERO, TELA), Color(0.6, 0.4, 0.05, 0.05 + 0.02 * sin(animation_time * 3.0)))
			Verdict.FRACO:
				_draw_vinheta_vermelha()

func _draw_grade_de_fundo() -> void:
	## Piso em perspectiva: dá profundidade ao fundo sem custar textura.
	## Na tela em pé o horizonte desce -- fica logo abaixo da marca, e as
	## linhas correm até a borda de baixo.
	# O HORIZONTE FICA ABAIXO DO TEXTO. Subindo mais, as linhas passavam
	# por cima do nome do jogo e do subtítulo -- e texto sobre grade é
	# texto que ninguém lê de longe, que é justamente a distância de onde
	# esta tela precisa funcionar.
	for i in range(18):
		var y := 1250.0 + pow(float(i) / 18.0, 2.2) * 670.0
		draw_line(Vector2(0, y), Vector2(TELA.x, y), Color(0.16, 0.42, 0.85, 0.075), 1.0)
	for i in range(-10, 11):
		var x := 540.0 + i * 230.0
		draw_line(Vector2(540 + i * 26.0, 1250.0), Vector2(x, TELA.y), Color(0.16, 0.42, 0.85, 0.06), 1.0)

func _draw_raios_dourados(centro: Vector2) -> void:
	for i in range(20):
		var angulo := -animation_time * 0.5 + i * TAU / 20.0
		draw_colored_polygon(
			PackedVector2Array([
				centro,
				centro + Vector2(cos(angulo - 0.05), sin(angulo - 0.05)) * 2000.0,
				centro + Vector2(cos(angulo + 0.05), sin(angulo + 0.05)) * 2000.0,
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
	draw_rect(Rect2(40, 152, 1000, 1), Color(0.3, 0.75, 1.0, 0.18))
	# A marca do cabeçalho é pequena de propósito: aqui ela identifica, e
	# quem manda na tela é a arena.
	_draw_marca(Vector2(126, 86), 150.0, 1.0)
	_text("PUNCH", Vector2(216, 80), 26, Color("f4f7ff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("CHALLENGE", Vector2(326, 80), 26, Color("55e7ff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("ARCADE POWER SYSTEM", Vector2(216, 108), 13, Color("7182ad"), HORIZONTAL_ALIGNMENT_LEFT)
	var status_color := Color("52f2a4") if "CONECTADO" in serial_status else Color("ffbd4a")
	draw_circle(Vector2(620, 78), 7.0, status_color)
	_text(serial_status, Vector2(638, 84), 14, Color("aab5d1"), HORIZONTAL_ALIGNMENT_LEFT)
	var mode_text := "MODO LIVRE" if game_mode == "free" else "MODO FICHA"
	_pill(Rect2(860, 56, 180, 48), mode_text, Color("1b2b52"), Color("69e9ff"))

func _draw_main_stage() -> void:
	## A arena ocupa o miolo da tela em pé; os números da máquina descem
	## para o rodapé, onde não disputam atenção com o soco.
	_panel(Rect2(40, 180, 1000, 1090), Color(0.025, 0.04, 0.105, 0.72), Color(0.16, 0.32, 0.68, 0.28), 36)
	_draw_arena_center()

	_stat_card(Rect2(40, 1300, 320, 130), "RECORDE", "%03d" % best_score, Color("58e8ff"))
	_stat_card(Rect2(380, 1300, 320, 130), "PARTIDAS", str(plays), Color("a978ff"))
	_stat_card(Rect2(720, 1300, 320, 130), "CRÉDITOS", "∞" if game_mode == "free" else "%02d" % credits, Color("ff4c9b"))

	_key_hint(Rect2(40, 1470, 490, 66), "START", "INICIAR")
	_key_hint(Rect2(550, 1470, 490, 66), "SELECT", "+1 CRÉDITO")
	_text("F9  •  CENTRAL TÉCNICA", Vector2(0, 1590), 16, Color("7385ad"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

func _draw_arena_center() -> void:
	for i in range(4):
		var pulse := fmod(animation_time * (95.0 + i * 7.0) + i * 85.0, 420.0)
		draw_arc(ARENA, 150.0 + pulse, 0, TAU, 120, Color(0.14, 0.82, 1.0, 0.11 * (1.0 - pulse / 460.0)), 3.0)

	match state:
		GameState.INTRO:
			_draw_power_core(ARENA, 150.0)
		GameState.COUNTDOWN:
			var count := clampi(int(ceil(countdown_left)), 1, 3)
			# O número nasce grande e encolhe até o próximo: é a batida do
			# relógio que se vê, e não só se lê.
			var fracao := fmod(countdown_left, 1.0)
			var scale_pulse := 1.0 + fracao * 0.16
			_draw_glow_circle(ARENA, 200.0 * scale_pulse, Color(0.18, 0.77, 1.0, 0.11))
			draw_arc(ARENA, 250.0, -PI * 0.5, -PI * 0.5 + TAU * fracao, 96, Color("4beaff"), 10.0)
			_text(str(count), Vector2(0, 830), int(280 * scale_pulse), Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
			_text("PREPARE-SE", Vector2(0, 1010), 36, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
		GameState.ARMED:
			_draw_target(ARENA)
			_text("SOQUE AGORA!", Vector2(0, 1080), 78, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
			_text("Aguardando impacto  •  %.1fs" % armed_left, Vector2(0, 1140), 24, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
		GameState.RESULT:
			_draw_resultado()

func _draw_resultado() -> void:
	_draw_score_gauge(ARENA, displayed_score / 999.0)

	# O número da contagem vibra enquanto sobe e assenta no fim.
	var vibra := 1.0
	if verdict_time < 0.0:
		vibra = 1.0 + 0.05 * sin(animation_time * 26.0)
	_text("%03d" % int(round(displayed_score)), Vector2(0, 790), int(180 * vibra), Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("PONTOS DE POTÊNCIA", Vector2(0, 858), 24, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

	if verdict_time < 0.0:
		_text("MEDINDO O IMPACTO…", Vector2(0, 1080), 22, Color("8092b9"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
		return

	match verdict:
		Verdict.FORTE:
			_draw_carimbo("NOCAUTE!", "VOCÊ VENCEU O DESAFIO", Color("ffd23f"), Color("52f2a4"))
		Verdict.MEDIO:
			_draw_carimbo("BOM GOLPE", "QUASE LÁ — TENTE MAIS UMA", Color("ffb648"), Color("ffd8a1"))
		Verdict.FRACO:
			_draw_carimbo("FRACO!", "NÃO FOI DESSA VEZ", Color("ff4c6a"), Color("ff9aa9"))

	_text("Velocidade medida: %.2f m/s" % result_speed, Vector2(0, 1180), 20, Color("8092b9"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	if verdict_time > 1.0:
		var piscada := 0.55 + 0.45 * sin(animation_time * 3.6)
		_text("START PARA JOGAR NOVAMENTE", Vector2(0, 1230), 20, Color(0.73, 0.77, 0.87, piscada), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

func _draw_carimbo(titulo: String, linha: String, cor: Color, cor_linha: Color) -> void:
	## O CARIMBO CAI NA TELA, não aparece.
	##
	## Entra grande, passa do lugar e volta -- o mesmo gesto de um carimbo
	## batendo no papel. É meio segundo de animação que faz o veredito
	## parecer uma decisão, e não um texto que estava lá o tempo todo.
	var t := clampf(verdict_time / 0.45, 0.0, 1.0)
	var escala := 1.0
	if t < 1.0:
		escala = lerpf(2.4, 1.0, ease(t, 0.28)) + sin(t * PI) * 0.12
	var alpha := clampf(verdict_time / 0.2, 0.0, 1.0)
	var balanco := 0.0
	if verdict == Verdict.FRACO:
		# O carimbo do soco fraco escorrega para baixo, cansado.
		balanco = minf(verdict_time * 16.0, 14.0)
	elif verdict == Verdict.FORTE:
		balanco = -sin(verdict_time * 5.0) * 7.0

	var tamanho := int(clampf(104.0 * escala, 20.0, 260.0))
	_text(titulo, Vector2(0, 1010 + balanco), tamanho, Color(cor.r, cor.g, cor.b, alpha), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	if verdict_time > 0.35:
		var alpha_linha := clampf((verdict_time - 0.35) / 0.35, 0.0, 1.0)
		_text(linha, Vector2(0, 1072 + balanco), 28, Color(cor_linha.r, cor_linha.g, cor_linha.b, alpha_linha), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

func _draw_footer() -> void:
	_text("LAZER & SPORT BRINQUEDOS", Vector2(0, 1880), 15, Color("536488"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

# ---------------------------------------------------------------- central
func _draw_settings() -> void:
	draw_rect(Rect2(Vector2.ZERO, TELA), Color(0.005, 0.009, 0.025, 0.91))
	_panel(Rect2(40, 90, 1000, 1790), Color("0d142c"), Color(0.22, 0.55, 0.95, 0.52), 34)
	_text("CENTRAL TÉCNICA", Vector2(110, 190), 38, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("Configuração, diagnóstico e calibração", Vector2(110, 228), 18, Color("7e90b8"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["fechar"], "×", false, Color("ff568f"), 32)

	_panel(Rect2(80, 260, 920, 180), Color("111d3b"), Color(0.19, 0.42, 0.78, 0.4), 22)
	_text("MODO DE OPERAÇÃO", Vector2(120, 306), 16, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["modo_livre"], "LIVRE", game_mode == "free", Color("55e7ff"), 20)
	_button(BOTOES["modo_ficha"], "1 FICHA", game_mode == "credit", Color("ff4c9b"), 20)

	_panel(Rect2(80, 480, 920, 190), Color("111d3b"), Color(0.19, 0.42, 0.78, 0.4), 22)
	_text("CONEXÃO DO SENSOR", Vector2(120, 526), 16, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	var dot_color := Color("4ff0a2") if "CONECTADO" in serial_status else Color("ffba46")
	draw_circle(Vector2(560, 518), 7.0, dot_color)
	_text(serial_status, Vector2(578, 524), 15, dot_color, HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["com_menos"], "−", false, Color("55e7ff"), 27)
	_button(BOTOES["com_mais"], "+", false, Color("55e7ff"), 27)
	_text("COM%d" % com_number, Vector2(240, 616), 32, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 600)

	_panel(Rect2(80, 710, 920, 200), Color("0e1935"), Color(0.19, 0.42, 0.78, 0.4), 22)
	_text("CALIBRAÇÃO DA VELOCIDADE", Vector2(120, 756), 16, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("MÍNIMA", Vector2(120, 796), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["min_menos"], "−", false, Color("55e7ff"), 25)
	_text("%.1f m/s" % min_speed, Vector2(186, 852), 24, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 174)
	_button(BOTOES["min_mais"], "+", false, Color("55e7ff"), 25)
	_text("MÁXIMA", Vector2(620, 796), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["max_menos"], "−", false, Color("a978ff"), 25)
	_text("%.1f m/s" % max_speed, Vector2(686, 852), 24, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 174)
	_button(BOTOES["max_mais"], "+", false, Color("a978ff"), 25)

	# AS FAIXAS DO VEREDITO. É aqui que o operador decide o que a máquina
	# dele chama de fraco e de forte -- a mecânica de cada uma responde
	# diferente, e uma faixa errada faz todo mundo perder (ou todo mundo
	# ganhar), que é o jeito mais rápido de esvaziar a fila.
	_panel(Rect2(80, 960, 920, 208), Color("0e1935"), Color(0.19, 0.42, 0.78, 0.4), 22)
	_text("FAIXAS DO RESULTADO", Vector2(120, 1006), 16, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("ATÉ AQUI É FRACO", Vector2(120, 1048), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["fraco_menos"], "−", false, Color("ff4c6a"), 25)
	_text("%03d" % limite_fraco, Vector2(186, 1106), 24, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 174)
	_button(BOTOES["fraco_mais"], "+", false, Color("ff4c6a"), 25)
	_text("DAQUI É FORTE", Vector2(620, 1048), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["forte_menos"], "−", false, Color("52f2a4"), 25)
	_text("%03d" % limite_forte, Vector2(686, 1106), 24, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 174)
	_button(BOTOES["forte_mais"], "+", false, Color("52f2a4"), 25)

	_button(BOTOES["testar"], "TESTAR SENSOR", false, Color("55e7ff"), 19)
	_button(BOTOES["zerar"], "ZERAR DADOS", false, Color("ff568f"), 19)
	_button(BOTOES["aprender_start"], "APERTE START…" if aprendendo == "start" else "APRENDER START", aprendendo == "start", Color("55e7ff"), 19)
	_button(BOTOES["aprender_select"], "APERTE SELECT…" if aprendendo == "select" else "APRENDER SELECT", aprendendo == "select", Color("a978ff"), 19)

	var sensor_on := last_sensor_ms >= 0 and Time.get_ticks_msec() - last_sensor_ms < 850
	draw_circle(Vector2(120, 1446), 8.0, Color("4ff0a2") if sensor_on else Color("3d4b70"))
	_text(
		"ENTRADA %s  •  %.1f Hz" % ["ATIVA" if sensor_on else "INATIVA", last_raw_frequency],
		Vector2(142, 1452), 16, Color("8fa1c4"), HORIZONTAL_ALIGNMENT_LEFT
	)
	_text(
		"BOTÕES: START %d / SELECT %d" % [botao_start, botao_select],
		Vector2(560, 1452), 16, Color("8fa1c4"), HORIZONTAL_ALIGNMENT_RIGHT, 420
	)

	_panel(Rect2(80, 1490, 920, 160), Color(0.055, 0.1, 0.19, 0.8), Color(0.17, 0.37, 0.65, 0.3), 18)
	_text("SALDO", Vector2(130, 1540), 14, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("%02d créditos" % credits, Vector2(130, 1578), 24, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("PARTIDAS", Vector2(430, 1540), 14, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text(str(plays), Vector2(430, 1578), 24, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("RECORDE", Vector2(710, 1540), 14, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("%03d" % best_score, Vector2(710, 1578), 24, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("T simula um soco  •  F9 ou ESC fecha", Vector2(130, 1622), 15, Color("7084ad"), HORIZONTAL_ALIGNMENT_LEFT)

	_button(BOTOES["padroes"], "RESTAURAR PADRÕES", false, Color("8094bd"), 19)
	_button(BOTOES["reconectar"], "RECONECTAR", false, Color("a978ff"), 19)
	_button(BOTOES["salvar"], "SALVAR E VOLTAR", true, Color("55e7ff"), 21)

	# Aqui o aviso mora no alto, ao lado do título: embaixo é lugar de
	# botão. É o mesmo recado que aparece na partida, noutro endereço.
	if notice != "":
		_draw_notice(Rect2(470, 146, 420, 68), 16)

func _draw_notice(rect := Rect2(160, 1690, 760, 74), tamanho := 18) -> void:
	## O RECADO NÃO PODE COBRIR BOTÃO.
	##
	## Na partida ele fica no rodapé, onde não há nada. Na Central Técnica
	## aquele mesmo lugar é dos botões de salvar e restaurar -- e um aviso
	## por cima do botão que a pessoa está tentando apertar é pior do que
	## aviso nenhum. Por isso o retângulo vem de fora: cada tela diz onde
	## sobra espaço na dela.
	var alpha := clampf(notice_left * 2.0, 0.0, 1.0)
	_panel(rect, Color(0.05, 0.11, 0.22, 0.94 * alpha), Color(0.23, 0.82, 1.0, 0.55 * alpha), 20)
	_text(
		notice,
		Vector2(rect.position.x + 16.0, rect.position.y + rect.size.y * 0.63 + tamanho * 0.35),
		tamanho,
		Color(0.82, 0.96, 1.0, alpha),
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 32.0,
	)

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

func _button(rect: Rect2, label: String, active: bool, accent: Color, size: int = 18) -> void:
	var fill := Color(accent.r, accent.g, accent.b, 0.19 if active else 0.065)
	var border := Color(accent.r, accent.g, accent.b, 0.92 if active else 0.32)
	_panel(rect, fill, border, 14)
	_text(label, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.64), size, accent if active else Color("c2cce2"), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _pill(rect: Rect2, label: String, fill: Color, color: Color) -> void:
	_panel(rect, fill, Color(color.r, color.g, color.b, 0.3), int(rect.size.y / 2.0))
	_text(label, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.64), 15, color, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _stat_card(rect: Rect2, label: String, value: String, accent: Color) -> void:
	_panel(rect, Color(0.055, 0.09, 0.18, 0.76), Color(accent.r, accent.g, accent.b, 0.24), 18)
	draw_rect(Rect2(rect.position.x, rect.position.y + 22, 4, rect.size.y - 44), accent)
	_text(label, rect.position + Vector2(28, 44), 14, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text(value, rect.position + Vector2(28, 102), 42, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)

func _key_hint(rect: Rect2, key: String, action: String) -> void:
	_panel(rect, Color(0.04, 0.075, 0.15, 0.72), Color(0.16, 0.32, 0.58, 0.28), 14)
	_text(key, rect.position + Vector2(24, 42), 17, Color("63e9ff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text(action, rect.position + Vector2(200, 42), 16, Color("aab6cf"), HORIZONTAL_ALIGNMENT_LEFT)

func _draw_power_core(center: Vector2, radius: float) -> void:
	_draw_glow_circle(center, radius + 50.0, Color(0.15, 0.7, 1.0, 0.09))
	draw_circle(center, radius, Color("101b3b"))
	draw_arc(center, radius, 0, TAU, 96, Color("4beaff"), 5.0)
	draw_arc(center, radius + 26, animation_time, animation_time + 4.6, 72, Color("8d62ff"), 5.0)
	_draw_marca(center, radius * 2.6, 1.0)

func _draw_target(center: Vector2) -> void:
	_draw_glow_circle(center, 230.0, Color(0.95, 0.15, 0.52, 0.12))
	for radius in [220.0, 165.0, 108.0]:
		draw_arc(center, radius, 0, TAU, 90, Color(1.0, 0.25, 0.55, 0.78), 5.0)
	draw_circle(center, 54.0 + sin(animation_time * 8.0) * 6.0, Color("ff2d78"))
	draw_line(center - Vector2(280, 0), center + Vector2(280, 0), Color(0.3, 0.9, 1.0, 0.28), 2.0)
	draw_line(center - Vector2(0, 280), center + Vector2(0, 280), Color(0.3, 0.9, 1.0, 0.28), 2.0)

func _draw_score_gauge(center: Vector2, amount: float) -> void:
	_draw_glow_circle(center, 300.0, Color(0.25, 0.2, 0.95, 0.08))
	draw_arc(center, 300, -2.55, 0.41, 130, Color(0.12, 0.18, 0.35, 0.9), 28.0)
	var end_angle := lerpf(-2.55, 0.41, clampf(amount, 0.0, 1.0))
	# A cor do arco é o próprio veredito: vermelho, âmbar ou verde,
	# acompanhando as faixas que o operador ajustou.
	var cor := Color("ff4c6a")
	if displayed_score >= float(limite_forte):
		cor = Color("52f2a4")
	elif displayed_score >= float(limite_fraco):
		cor = Color("ffb648")
	draw_arc(center, 300, -2.55, end_angle, 130, cor, 28.0)
	# As marcas das faixas, para quem joga saber onde precisa chegar.
	for limite in [limite_fraco, limite_forte]:
		var angulo := lerpf(-2.55, 0.41, float(limite) / 999.0)
		var direcao := Vector2(cos(angulo), sin(angulo))
		draw_line(center + direcao * 280.0, center + direcao * 320.0, Color(1, 1, 1, 0.5), 3.0)

func _draw_glow_circle(center: Vector2, radius: float, color: Color) -> void:
	for i in range(5, 0, -1):
		var c := color
		c.a *= float(6 - i) / 12.0
		draw_circle(center, radius * float(i) / 5.0, c)

func _text(value: String, baseline: Vector2, size: int, color: Color, align: HorizontalAlignment, width: float = -1.0) -> void:
	draw_string(font, baseline, value, align, width, size, color)
