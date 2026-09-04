extends Control

enum GameState { IDLE, COUNTDOWN, ARMED, RESULT }

const SETTINGS_PATH := "user://punch_challenge_settings.json"
const UDP_PORT := 4242
const MAX_CREDITS := 99

var state: GameState = GameState.IDLE
var settings_open := false
var game_mode := "credit"
var credits := 0
var plays := 0
var best_score := 0
var com_number := 3
var min_speed := 1.0
var max_speed := 12.0
var score_curve := 0.78

var countdown_left := 3.0
var last_count := 3
var armed_left := 8.0
var result_score := 0
var result_speed := 0.0
var displayed_score := 0.0
var animation_time := 0.0
var notice := ""
var notice_left := 0.0
var serial_status := "AGUARDANDO"
var last_sensor_ms := -1
var last_raw_frequency := 0.0
var bridge_pid := -1
var udp := PacketPeerUDP.new()
var font: Font

@onready var sound_count: AudioStreamPlayer = $SoundCount
@onready var sound_go: AudioStreamPlayer = $SoundGo
@onready var sound_hit: AudioStreamPlayer = $SoundHit
@onready var sound_credit: AudioStreamPlayer = $SoundCredit

func _ready() -> void:
	font = ThemeDB.fallback_font
	_load_settings()
	var bind_error := udp.bind(UDP_PORT, "127.0.0.1")
	if bind_error != OK:
		serial_status = "PORTA UDP OCUPADA"
	else:
		call_deferred("_start_serial_bridge")
	set_process(true)
	queue_redraw()

func _exit_tree() -> void:
	_stop_serial_bridge()
	udp.close()

func _process(delta: float) -> void:
	animation_time += delta
	_read_udp()
	if notice_left > 0.0:
		notice_left -= delta
	else:
		notice = ""
	if last_sensor_ms >= 0 and Time.get_ticks_msec() - last_sensor_ms > 1800:
		last_raw_frequency = 0.0

	if not settings_open:
		match state:
			GameState.COUNTDOWN:
				countdown_left -= delta
				var current_count := maxi(0, int(ceil(countdown_left)))
				if current_count > 0 and current_count < last_count:
					last_count = current_count
					sound_count.play()
				if countdown_left <= 0.0:
					state = GameState.ARMED
					armed_left = 8.0
					sound_go.play()
					notice = "SENSOR ARMADO"
					notice_left = 1.2
			GameState.ARMED:
				armed_left -= delta
				if armed_left <= 0.0:
					state = GameState.IDLE
					_show_notice("TEMPO ESGOTADO — PRESSIONE START")
			GameState.RESULT:
				displayed_score = lerpf(displayed_score, float(result_score), minf(delta * 5.5, 1.0))
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			_toggle_settings()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			if settings_open:
				_close_settings()
			elif state != GameState.IDLE:
				state = GameState.IDLE
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
		if event.keycode in [KEY_1, KEY_ENTER, KEY_SPACE]:
			_start_round()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventJoypadButton and event.pressed and not settings_open:
		if event.button_index == 6:
			_add_credit()
		elif event.button_index == 7:
			_start_round()
		return
	if settings_open:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_settings_click(event.position)
		return

func _start_round() -> void:
	if state == GameState.COUNTDOWN or state == GameState.ARMED:
		return
	if game_mode == "credit":
		if credits <= 0:
			_show_notice("INSIRA 1 CRÉDITO — PRESSIONE SELECT")
			return
		credits -= 1
	countdown_left = 3.0
	last_count = 3
	displayed_score = 0.0
	result_score = 0
	state = GameState.COUNTDOWN
	sound_count.play()
	_save_settings()

func _add_credit() -> void:
	credits = mini(credits + 1, MAX_CREDITS)
	sound_credit.play()
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
	sound_hit.play()
	plays += 1
	best_score = maxi(best_score, result_score)
	state = GameState.RESULT
	_save_settings()

func _simulate_hit() -> void:
	var speed := randf_range(min_speed + 1.2, max_speed * 0.86)
	last_raw_frequency = randf_range(90.0, 420.0)
	last_sensor_ms = Time.get_ticks_msec()
	if state == GameState.ARMED:
		_finish_hit(speed, last_raw_frequency)
	else:
		_show_notice("PULSO DE TESTE RECEBIDO  •  %.1f Hz" % last_raw_frequency)

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

func _toggle_settings() -> void:
	if settings_open:
		_close_settings()
	else:
		if state == GameState.COUNTDOWN or state == GameState.ARMED:
			state = GameState.IDLE
		settings_open = true

func _close_settings() -> void:
	settings_open = false
	_save_settings()

func _handle_settings_click(p: Vector2) -> void:
	if Rect2(1530, 122, 70, 60).has_point(p) or Rect2(1325, 894, 235, 62).has_point(p):
		_close_settings()
	elif Rect2(370, 353, 235, 58).has_point(p):
		game_mode = "free"
		_save_settings()
	elif Rect2(620, 353, 235, 58).has_point(p):
		game_mode = "credit"
		_save_settings()
	elif Rect2(1080, 353, 56, 58).has_point(p):
		com_number = maxi(1, com_number - 1)
		_start_serial_bridge()
		_save_settings()
	elif Rect2(1460, 353, 56, 58).has_point(p):
		com_number = mini(99, com_number + 1)
		_start_serial_bridge()
		_save_settings()
	elif Rect2(376, 632, 52, 52).has_point(p):
		min_speed = maxf(0.1, min_speed - 0.1)
	elif Rect2(590, 632, 52, 52).has_point(p):
		min_speed = minf(max_speed - 0.5, min_speed + 0.1)
	elif Rect2(697, 632, 52, 52).has_point(p):
		max_speed = maxf(min_speed + 0.5, max_speed - 0.5)
	elif Rect2(910, 632, 52, 52).has_point(p):
		max_speed = minf(40.0, max_speed + 0.5)
	elif Rect2(1035, 620, 240, 70).has_point(p):
		last_raw_frequency = randf_range(80.0, 350.0)
		last_sensor_ms = Time.get_ticks_msec()
		_show_notice("TESTE VISUAL ATIVADO")
	elif Rect2(1295, 620, 240, 70).has_point(p):
		credits = 0
		plays = 0
		best_score = 0
		_show_notice("CONTADORES ZERADOS")
	elif Rect2(360, 894, 270, 62).has_point(p):
		game_mode = "credit"
		com_number = 3
		min_speed = 1.0
		max_speed = 12.0
		score_curve = 0.78
		_show_notice("PADRÕES RESTAURADOS")
	elif Rect2(650, 894, 270, 62).has_point(p):
		_start_serial_bridge()
		_show_notice("RECONEXÃO SOLICITADA")
	_save_settings()

func _show_notice(message: String) -> void:
	notice = message
	notice_left = 2.8

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

func _save_settings() -> void:
	var data := {
		"mode": game_mode,
		"credits": credits,
		"plays": plays,
		"best_score": best_score,
		"com_number": com_number,
		"min_speed": min_speed,
		"max_speed": max_speed,
		"score_curve": score_curve
	}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))

func _draw() -> void:
	_draw_background()
	_draw_header()
	_draw_main_stage()
	_draw_footer()
	if notice != "":
		_draw_notice()
	if settings_open:
		_draw_settings()

func _draw_background() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color("050817"))
	for i in range(9):
		var radius := 180.0 + i * 95.0 + sin(animation_time * 0.35 + i) * 8.0
		draw_arc(Vector2(960, 555), radius, -2.8, 0.34, 80, Color(0.12, 0.25, 0.55, 0.07), 2.0)
	for i in range(20):
		var x := fmod(float(i * 389) + animation_time * (6.0 + i * 0.15), 2020.0) - 50.0
		var y := 110.0 + fmod(float(i * 173), 850.0)
		draw_circle(Vector2(x, y), 1.5 + (i % 3), Color(0.25, 0.85, 1.0, 0.22))
	_draw_glow_circle(Vector2(250, 250), 240, Color(0.02, 0.72, 0.95, 0.08))
	_draw_glow_circle(Vector2(1690, 710), 310, Color(0.74, 0.12, 0.56, 0.08))

func _draw_header() -> void:
	draw_rect(Rect2(70, 38, 1780, 1), Color(0.3, 0.75, 1.0, 0.18))
	_draw_logo(Vector2(94, 69), 34.0)
	_text("PUNCH", Vector2(145, 86), 26, Color("f4f7ff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("CHALLENGE", Vector2(255, 86), 26, Color("55e7ff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("ARCADE POWER SYSTEM", Vector2(145, 112), 13, Color("7182ad"), HORIZONTAL_ALIGNMENT_LEFT)
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
		GameState.IDLE:
			_draw_power_core(center, 122.0)
			_text("PRONTO PARA O DESAFIO?", Vector2(735, 735), 42, Color("f3f6ff"), HORIZONTAL_ALIGNMENT_CENTER, 890)
			var prompt := "PRESSIONE START PARA JOGAR"
			if game_mode == "credit" and credits <= 0:
				prompt = "PRESSIONE SELECT PARA INSERIR CRÉDITO"
			_pill(Rect2(895, 782, 570, 64), prompt, Color(0.07, 0.15, 0.28, 0.92), Color("63e9ff"))
		GameState.COUNTDOWN:
			var count := clampi(int(ceil(countdown_left)), 1, 3)
			var scale_pulse := 1.0 + fmod(countdown_left, 1.0) * 0.16
			_draw_glow_circle(center, 165.0 * scale_pulse, Color(0.18, 0.77, 1.0, 0.11))
			_text(str(count), Vector2(880, 630), int(245 * scale_pulse), Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 600)
			_text("PREPARE-SE", Vector2(880, 764), 30, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, 600)
		GameState.ARMED:
			_draw_target(center)
			_text("SOQUE AGORA!", Vector2(770, 760), 70, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 820)
			_text("Aguardando impacto  •  %.1fs" % armed_left, Vector2(770, 812), 22, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, 820)
		GameState.RESULT:
			_draw_score_gauge(center, displayed_score / 999.0)
			_text("%03d" % int(round(displayed_score)), Vector2(825, 590), 150, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 710)
			_text("PONTOS DE POTÊNCIA", Vector2(825, 665), 22, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, 710)
			var rank := _rank_for_score(result_score)
			_pill(Rect2(1015, 705, 330, 58), rank, Color(0.1, 0.08, 0.27, 0.95), Color("d3b0ff"))
			_text("Velocidade medida: %.2f m/s" % result_speed, Vector2(825, 815), 18, Color("8092b9"), HORIZONTAL_ALIGNMENT_CENTER, 710)
			_text("START PARA JOGAR NOVAMENTE", Vector2(825, 865), 17, Color("bac5dd"), HORIZONTAL_ALIGNMENT_CENTER, 710)

func _draw_footer() -> void:
	_text("LAZER & SPORT BRINQUEDOS", Vector2(95, 1004), 14, Color("536488"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("SISTEMA DE MEDIÇÃO POR ENCODER ÓPTICO", Vector2(1310, 1004), 14, Color("536488"), HORIZONTAL_ALIGNMENT_RIGHT, 515)

func _draw_settings() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.005, 0.009, 0.025, 0.91))
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

	_panel(Rect2(330, 480, 1260, 255), Color("0e1935"), Color(0.19, 0.42, 0.78, 0.4), 22)
	_text("CALIBRAÇÃO E TESTE", Vector2(370, 530), 15, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("Ajuste o ponto mínimo e o máximo conforme a mecânica da máquina", Vector2(370, 559), 14, Color("5f7199"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("VELOCIDADE MÍNIMA", Vector2(376, 612), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(Rect2(376, 632, 52, 52), "−", false, Color("55e7ff"), 23)
	_text("%.1f m/s" % min_speed, Vector2(430, 668), 23, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 160)
	_button(Rect2(590, 632, 52, 52), "+", false, Color("55e7ff"), 23)
	_text("VELOCIDADE MÁXIMA", Vector2(697, 612), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(Rect2(697, 632, 52, 52), "−", false, Color("a978ff"), 23)
	_text("%.1f m/s" % max_speed, Vector2(750, 668), 23, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 160)
	_button(Rect2(910, 632, 52, 52), "+", false, Color("a978ff"), 23)
	_button(Rect2(1035, 620, 240, 70), "TESTAR SENSOR", false, Color("55e7ff"))
	_button(Rect2(1295, 620, 240, 70), "ZERAR DADOS", false, Color("ff568f"))
	var sensor_on := last_sensor_ms >= 0 and Time.get_ticks_msec() - last_sensor_ms < 850
	draw_circle(Vector2(1050, 711), 7.0, Color("4ff0a2") if sensor_on else Color("3d4b70"))
	_text("ENTRADA: %s   •   FREQUÊNCIA: %.1f Hz" % ["ATIVA" if sensor_on else "INATIVA", last_raw_frequency], Vector2(1070, 717), 14, Color("8fa1c4"), HORIZONTAL_ALIGNMENT_LEFT)

	_panel(Rect2(330, 765, 1260, 92), Color(0.055, 0.1, 0.19, 0.8), Color(0.17, 0.37, 0.65, 0.3), 18)
	_text("SALDO", Vector2(370, 803), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("%02d créditos" % credits, Vector2(370, 834), 22, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("PARTIDAS", Vector2(650, 803), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text(str(plays), Vector2(650, 834), 22, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("RECORDE", Vector2(900, 803), 13, Color("7185af"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("%03d" % best_score, Vector2(900, 834), 22, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("F9 ou ESC fecha esta tela", Vector2(1190, 824), 15, Color("7084ad"), HORIZONTAL_ALIGNMENT_LEFT)

	_button(Rect2(360, 894, 270, 62), "RESTAURAR PADRÕES", false, Color("8094bd"))
	_button(Rect2(650, 894, 270, 62), "RECONECTAR", false, Color("a978ff"))
	_button(Rect2(1325, 894, 235, 62), "SALVAR E VOLTAR", true, Color("55e7ff"))

func _draw_notice() -> void:
	var alpha := clampf(notice_left * 2.0, 0.0, 1.0)
	var rect := Rect2(650, 955, 620, 62)
	_panel(rect, Color(0.05, 0.11, 0.22, 0.94 * alpha), Color(0.23, 0.82, 1.0, 0.55 * alpha), 18)
	_text(notice, Vector2(670, 994), 16, Color(0.82, 0.96, 1.0, alpha), HORIZONTAL_ALIGNMENT_CENTER, 580)

func _rank_for_score(score: int) -> String:
	if score >= 930: return "LENDÁRIO"
	if score >= 800: return "PESO-PESADO"
	if score >= 620: return "IMPACTO BRUTAL"
	if score >= 400: return "GOLPE FORTE"
	if score >= 180: return "BOM GOLPE"
	return "CONTINUE TREINANDO"

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
	_draw_logo(center, 62.0)

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
	draw_arc(center, 235, -2.55, end_angle, 130, Color("55e7ff") if amount < 0.75 else Color("ff4c9b"), 24.0)

func _draw_logo(center: Vector2, radius: float) -> void:
	var c := center
	var r := radius
	draw_circle(c, r, Color(0.05, 0.1, 0.23, 0.96))
	draw_arc(c, r, 0, TAU, 48, Color("57e9ff"), maxf(2.0, r * 0.07))
	var fist := PackedVector2Array([
		c + Vector2(-0.48, 0.10) * r, c + Vector2(-0.34, -0.34) * r,
		c + Vector2(-0.08, -0.48) * r, c + Vector2(0.06, -0.31) * r,
		c + Vector2(0.23, -0.45) * r, c + Vector2(0.34, -0.23) * r,
		c + Vector2(0.47, -0.12) * r, c + Vector2(0.34, 0.42) * r,
		c + Vector2(-0.12, 0.50) * r
	])
	draw_colored_polygon(fist, Color("f7f9ff"))

func _draw_glow_circle(center: Vector2, radius: float, color: Color) -> void:
	for i in range(5, 0, -1):
		var c := color
		c.a *= float(6 - i) / 12.0
		draw_circle(center, radius * float(i) / 5.0, c)

func _text(value: String, baseline: Vector2, size: int, color: Color, align: HorizontalAlignment, width: float = -1.0) -> void:
	draw_string(font, baseline, value, align, width, size, color)
