extends Control

## Punch Challenge — a máquina de soco da Lazer & Sport.
##
## TELA EM PÉ, 1080 × 1920, leitura em coluna: marca, saco, número,
## veredito. O nó raiz desenha textos, placar e a Central Técnica; o
## cenário vivo fica nos filhos: `PunchBackground` (fundo), `PunchBag`
## (saco pendurado), `PowerMeter` (coluna de potência), `LedFrame`
## (moldura de LEDs) e `AudioBank` (sons). O que voa — confete, faísca,
## estilhaço — mora em `fx.gd`.
##
## O CAMINHO DE QUEM JOGA:
##
##   ABERTURA → (START) → 3, 2, 1 → SENSOR ARMADO → IMPACTO → RESULTADO
##
## Dois jeitos de socar: o MPU-6050 no saco manda HIT pela serial
## (protocolo V2, ver docs/PROTOCOLO_SERIAL.md), ou a simulação —
## SEGURAR a barra de espaço carrega o golpe e SOLTAR desfere. Quanto
## mais tempo segura, mais forte o soco (GameDef.pontos_da_carga).

const TELA := Vector2(1080.0, 1920.0)
## Ponto do saco onde o golpe aterrissa, em coordenadas da tela.
const ALVO := Vector2(540.0, 538.0)

const CORES_FESTA := [
	Color("ff2d78"), Color("ffd23f"), Color("4beaff"),
	Color("8d62ff"), Color("52f2a4"), Color("ffffff"),
]

## OS BOTÕES DA CENTRAL TÉCNICA MORAM AQUI, e não em dois lugares: o
## mesmo retângulo desenha o botão e confere o clique. Mover um botão
## é mexer numa linha só.
const BOTOES := {
	"fechar": Rect2(918, 138, 72, 64),
	"modo_livre": Rect2(110, 336, 400, 72),
	"modo_ficha": Rect2(570, 336, 400, 72),
	"porta_menos": Rect2(150, 566, 72, 72),
	"porta_mais": Rect2(858, 566, 72, 72),
	"vmin_menos": Rect2(120, 810, 66, 66),
	"vmin_mais": Rect2(360, 810, 66, 66),
	"vmax_menos": Rect2(620, 810, 66, 66),
	"vmax_mais": Rect2(860, 810, 66, 66),
	"eixo": Rect2(110, 1064, 280, 66),
	"raio_menos": Rect2(430, 1064, 66, 66),
	"raio_mais": Rect2(560, 1064, 66, 66),
	"amin_menos": Rect2(700, 1064, 66, 66),
	"amin_mais": Rect2(860, 1064, 66, 66),
	"enviar_config": Rect2(110, 1210, 400, 78),
	"testar": Rect2(570, 1210, 400, 78),
	"zerar": Rect2(110, 1470, 400, 78),
	"reconectar": Rect2(570, 1470, 400, 78),
	"padroes": Rect2(110, 1690, 400, 78),
	"salvar": Rect2(570, 1690, 400, 78),
}

var state: GameDef.State = GameDef.State.IDLE
var central_aberta := false
var game_mode := "credit"
var credits := 0
var plays := 0
var best_score := 0
## Faixa de velocidade (m/s) que vira pontos no placar.
var hit_min_speed := 0.8
var hit_max_speed := 12.0
## Configuração enviada ao firmware (CONFIG,eixo,raio,vmin,amin).
var sensor_eixo := "X"
var sensor_raio := 0.45
var sensor_vmin := 0.5
var sensor_amin := 2.5
## Porta serial configurada; "" = automática (primeira disponível).
var porta_configurada := ""

var countdown_left := 3.0
var last_count := 3
var armed_left := GameDef.JANELA_DO_SOCO
var result_score := 0
var result_speed := 0.0
var result_simulado := false
var novo_recorde := false
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

## Carga da simulação: >= 0 enquanto a barra de espaço está pressionada.
var carga_tempo := -1.0

## Serial.
var link: SerialLink
var serial_status := "INICIANDO"
var porta_atual := ""
var ultimo_sinal_ms := -1
var proxima_tentativa := 0.0
var proximo_ping := 0.0
## Última telemetria, exibida na Central Técnica.
var telemetria := ""
var portas_visiveis: PackedStringArray = []

var fx := PunchFX.new()
var fonte: Font
var logo: Texture2D = null

@onready var fundo: PunchBackground = $Fundo
@onready var saco: PunchBag = $Saco
@onready var medidor: PowerMeter = $Medidor
@onready var moldura: LedFrame = $Moldura
@onready var sons: AudioBank = $Audio

func _ready() -> void:
	fonte = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/Bungee-Regular.ttf"):
		fonte = load("res://assets/fonts/Bungee-Regular.ttf")
	medidor.fonte = fonte
	if ResourceLoader.exists("res://assets/logo_lazersport.png"):
		logo = load("res://assets/logo_lazersport.png")
	_carregar()
	_iniciar_serial()
	_entrar_em_abertura()
	set_process(true)

func _exit_tree() -> void:
	if link != null:
		link.close_port()

# ======================================================================
# CICLO
# ======================================================================
func _process(delta: float) -> void:
	animation_time += delta
	state_time += delta
	_poll_serial(delta)
	fx.atualizar(delta)
	tremor = maxf(0.0, tremor - delta * 26.0)
	clarao = maxf(0.0, clarao - delta * 2.6)

	if notice_left > 0.0:
		notice_left -= delta
	else:
		notice = ""

	if not central_aberta:
		match state:
			GameDef.State.IDLE:
				_processar_abertura(delta)
			GameDef.State.COUNTDOWN:
				_processar_contagem(delta)
			GameDef.State.ARMED:
				_processar_armado(delta)
			GameDef.State.MEASURING:
				if state_time >= GameDef.IMPACTO_DURACAO:
					_entrar_em_resultado()
			GameDef.State.RESULT:
				_processar_resultado(delta)
	queue_redraw()

func _processar_abertura(delta: float) -> void:
	if randf() < delta * 4.0:
		fx.poeira(
			Vector2(randf_range(120.0, 960.0), TELA.y + 40.0),
			1, Color(0.35, 0.85, 1.0, 0.35), 120.0
		)

func _processar_contagem(delta: float) -> void:
	countdown_left -= delta
	var atual := maxi(0, int(ceil(countdown_left)))
	if atual > 0 and atual < last_count:
		last_count = atual
		sons.play("count")
		fx.onda(ALVO, 60.0, 340.0, Color(0.35, 0.9, 1.0, 0.5), 6.0, 0.6)
	if countdown_left <= 0.0:
		state = GameDef.State.ARMED
		state_time = 0.0
		armed_left = GameDef.JANELA_DO_SOCO
		carga_tempo = -1.0
		sons.play("go")
		moldura.set_estado(LedFrame.ARMADA)
		saco.set_alvo(true)
		fx.onda(ALVO, 40.0, 560.0, Color(1.0, 0.25, 0.55, 0.55), 10.0, 0.8)
		_show_notice("SENSOR ARMADO")

func _processar_armado(delta: float) -> void:
	armed_left -= delta
	if carga_tempo >= 0.0:
		# Simulação carregando: a barra de espaço está pressionada.
		carga_tempo = minf(carga_tempo + delta, GameDef.CARGA_MAX_S)
		var frac := carga_tempo / GameDef.CARGA_MAX_S
		medidor.set_carga(frac)
		saco.set_carga(frac)
	if armed_left <= 0.0:
		_cancelar_carga()
		_entrar_em_abertura()
		_show_notice("TEMPO ESGOTADO — PRESSIONE START")

func _entrar_em_resultado() -> void:
	state = GameDef.State.RESULT
	state_time = 0.0
	result_time = 0.0
	displayed_score = 0.0
	proximo_tique = 0
	proximo_fogo = 0.0
	verdict_time = -1.0

func _processar_resultado(delta: float) -> void:
	result_time += delta
	var avanco := clampf(result_time / GameDef.CONTAGEM_DURACAO, 0.0, 1.0)
	# O número dispara e vai freando — o suspense que um placar de
	# arcade precisa ter. O veredito só entra quando a contagem termina.
	displayed_score = float(result_score) * ease(avanco, 0.42)
	medidor.set_pontos(displayed_score)

	if avanco < 1.0 and int(displayed_score) >= proximo_tique:
		proximo_tique = int(displayed_score) + 11
		sons.play("tick", -12.0)

	if verdict_time < 0.0 and avanco >= 1.0:
		_disparar_veredito()
	elif verdict_time >= 0.0:
		verdict_time += delta
		_manter_festa(delta)

	if result_time > GameDef.RESULTADO_TIMEOUT:
		_entrar_em_abertura()

func _manter_festa(delta: float) -> void:
	if result_score >= 800:
		if verdict_time < 5.0 and verdict_time >= proximo_fogo:
			proximo_fogo = verdict_time + 0.55
			fx.fogos(
				Vector2(randf_range(180.0, 900.0), randf_range(280.0, 900.0)),
				CORES_FESTA
			)
		if verdict_time < 2.6 and randf() < delta * 26.0:
			fx.chuva_de_confete(TELA.x, 3, CORES_FESTA)
	elif result_score >= 400:
		if verdict_time >= proximo_fogo:
			proximo_fogo = verdict_time + 0.85
			fx.onda(ALVO, 90.0, 450.0, Color(1.0, 0.72, 0.2, 0.4), 7.0, 0.85)
	else:
		if verdict_time < 2.2 and randf() < delta * 9.0:
			fx.estilhacos(Vector2(randf_range(180.0, 900.0), 380.0), 2, Color("2a3350"))

# ======================================================================
# ENTRADA DE COMANDOS
# ======================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			_toggle_central()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			if central_aberta:
				_fechar_central()
			elif state != GameDef.State.IDLE:
				_cancelar_carga()
				_entrar_em_abertura()
				_show_notice("RODADA CANCELADA")
			get_viewport().set_input_as_handled()
			return
		if central_aberta:
			if event.keycode == KEY_T:
				_teste_de_golpe()
			return
		if event.keycode in [KEY_5, KEY_C]:
			_add_credit()
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_1, KEY_ENTER, KEY_KP_ENTER]:
			_pressionou_start()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SPACE:
			_apertou_espaco()
			get_viewport().set_input_as_handled()
			return

	# Soltar a barra de espaço desfere o golpe carregado.
	if event is InputEventKey and not event.pressed and event.keycode == KEY_SPACE:
		if carga_tempo >= 0.0:
			_soltou_espaco()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventJoypadButton and event.pressed and not central_aberta:
		if event.is_action_pressed("input_credito"):
			_add_credit()
		elif event.is_action_pressed("input_start"):
			_pressionou_start()
		return

	if central_aberta and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click_central(event.position)

func _apertou_espaco() -> void:
	## Na janela do soco, a barra de espaço CARREGA; fora dela, é START.
	if state == GameDef.State.ARMED:
		carga_tempo = 0.0
		sons.play("charge")
	else:
		_pressionou_start()

func _soltou_espaco() -> void:
	if state != GameDef.State.ARMED:
		_cancelar_carga()
		return
	var tempo_carga := carga_tempo
	_cancelar_carga()
	var pontos := GameDef.pontos_da_carga(tempo_carga)
	# Velocidade equivalente, só para o visor do resultado.
	var frac := float(pontos) / float(GameDef.SCORE_MAX)
	_registrar_impacto(pontos, lerpf(hit_min_speed, hit_max_speed, pow(frac, 1.25)), true)

func _cancelar_carga() -> void:
	if carga_tempo >= 0.0:
		sons.stop("charge")
	carga_tempo = -1.0
	medidor.set_carga(-1.0)
	saco.set_carga(-1.0)

func _pressionou_start() -> void:
	## START faz uma coisa só em cada tela, e é sempre "seguir em frente".
	match state:
		GameDef.State.IDLE:
			_iniciar_rodada()
		GameDef.State.RESULT:
			# Só depois do veredito: apertar no meio da contagem cortaria
			# justamente o momento pelo qual o cliente pagou.
			if verdict_time >= 0.0:
				_iniciar_rodada()

func _iniciar_rodada() -> void:
	if game_mode == "credit":
		if credits <= 0:
			_show_notice("INSIRA 1 CRÉDITO — SELECT OU TECLA C")
			sons.play("error", -6.0)
			return
		credits -= 1
	state = GameDef.State.COUNTDOWN
	novo_recorde = false
	saco.visible = true
	medidor.visible = true
	state_time = 0.0
	countdown_left = 3.0
	last_count = 3
	result_score = 0
	displayed_score = 0.0
	fx.limpar()
	medidor.reset()
	clarao = 1.0
	tremor = 14.0
	sons.play("start")
	moldura.set_estado(LedFrame.CONTAGEM)
	fundo.matiz = Color(0, 0, 0, 0)
	fx.onda(TELA * 0.5, 40.0, 1100.0, Color(0.35, 0.92, 1.0, 0.6), 14.0, 0.85)
	_salvar()

func _entrar_em_abertura() -> void:
	state = GameDef.State.IDLE
	state_time = 0.0
	verdict_time = -1.0
	result_time = 0.0
	novo_recorde = false
	fx.limpar()
	medidor.reset()
	saco.visible = false
	medidor.visible = false
	saco.set_alvo(false)
	saco.set_carga(-1.0)
	moldura.set_estado(LedFrame.PARADA)
	fundo.matiz = Color(0, 0, 0, 0)

func _add_credit() -> void:
	credits = mini(credits + 1, GameDef.CREDITOS_MAX)
	sons.play("credit")
	fx.faiscas(Vector2(540, 1500), 22, Color("52f2a4"), 420.0)
	_show_notice("CRÉDITO ADICIONADO  •  SALDO %02d" % credits)
	_salvar()

# ======================================================================
# IMPACTO E VEREDITO
# ======================================================================
func _registrar_impacto(pontos: int, velocidade: float, simulado: bool) -> void:
	## O soco aterrissou: meio segundo de impacto puro, e só então o
	## placar começa a subir. Sem esse intervalo o golpe e o número
	## chegam juntos e nenhum dos dois brilha.
	result_score = clampi(pontos, 0, GameDef.SCORE_MAX)
	result_speed = maxf(velocidade, 0.0)
	result_simulado = simulado
	state = GameDef.State.MEASURING
	state_time = 0.0
	saco.set_alvo(false)
	var forca := float(result_score) / float(GameDef.SCORE_MAX)
	saco.golpear(forca)
	moldura.impacto(0.4 + forca * 0.6)
	sons.play("hit", 1.5)
	tremor = 10.0 + forca * 22.0
	clarao = 0.25 + forca * 0.45
	fx.onda(ALVO, 30.0, 500.0 + forca * 400.0, Color(1.0, 0.3, 0.55, 0.6), 16.0, 0.7)
	fx.faiscas(ALVO, 30 + int(forca * 50.0), Color("ffd23f"), 700.0 + forca * 600.0)
	plays += 1
	novo_recorde = result_score > best_score
	if novo_recorde:
		best_score = result_score
	_salvar()

func _disparar_veredito() -> void:
	## O momento em que a máquina diz quanto valeu o soco. Um por golpe.
	verdict_time = 0.0
	proximo_fogo = 0.0
	var classe := GameDef.classificar(result_score)
	var cor: Color = classe["color"]
	moldura.set_estado(LedFrame.RESULTADO, cor)

	if result_score >= 800:
		if result_score >= 930:
			sons.play("legendary", 0.5)
		else:
			sons.play("win", 0.5)
		tremor = 30.0
		clarao = 0.85
		fx.confete(Vector2(540, 900), 130, CORES_FESTA, 1250.0)
		fx.chuva_de_confete(TELA.x, 90, CORES_FESTA)
		fx.onda(ALVO, 60.0, 1100.0, Color(1.0, 0.85, 0.25, 0.55), 18.0, 1.0)
	elif result_score >= 400:
		sons.play("medium")
		tremor = 14.0
		fx.faiscas(ALVO, 46, Color("ffb648"), 700.0)
		fx.onda(ALVO, 60.0, 560.0, Color(1.0, 0.72, 0.25, 0.5), 12.0, 0.9)
	else:
		sons.play("lose")
		tremor = 9.0
		fx.estilhacos(Vector2(540, 520), 34, Color("222b47"))
		fx.poeira(Vector2(540, 760), 26, Color(0.55, 0.16, 0.26, 0.5), 260.0)

	if novo_recorde:
		sons.play("record", 2.0)

# ======================================================================
# SERIAL (MPU-6050 via GdSerial — protocolo V2)
# ======================================================================
func _iniciar_serial() -> void:
	link = SerialLink.create_best()
	link.line_received.connect(_on_serial_line)
	link.opened.connect(_on_serial_opened)
	link.closed.connect(_on_serial_closed)
	if not link.available():
		serial_status = "SIMULAÇÃO — SEM EXTENSÃO SERIAL"
		return
	_tentar_conectar()

func _tentar_conectar() -> void:
	if link == null or not link.available():
		return
	portas_visiveis = link.list_ports()
	var porta := porta_configurada
	if porta.is_empty():
		if portas_visiveis.is_empty():
			serial_status = "PROCURANDO ARDUINO…"
			proxima_tentativa = animation_time + 4.0
			return
		porta = portas_visiveis[0]
	serial_status = "CONECTANDO %s" % porta
	if link.open_port(porta, GameDef.SERIAL_BAUD):
		porta_atual = porta
		ultimo_sinal_ms = -1
		proximo_ping = animation_time + 1.0
	else:
		serial_status = "FALHA AO ABRIR %s" % porta
		proxima_tentativa = animation_time + 4.0

func _poll_serial(_delta: float) -> void:
	if link == null or not link.available():
		return
	link.poll()
	if not link.is_open():
		if animation_time >= proxima_tentativa:
			_tentar_conectar()
		return
	if ultimo_sinal_ms < 0 and animation_time >= proximo_ping:
		# Ainda não vimos o READY: cutuca a placa.
		link.send_line("PING")
		proximo_ping = animation_time + 2.0
	elif ultimo_sinal_ms >= 0 and animation_time >= proximo_ping:
		link.send_line("PING")
		proximo_ping = animation_time + 5.0
	if ultimo_sinal_ms >= 0 and Time.get_ticks_msec() - ultimo_sinal_ms > 9000:
		serial_status = "SEM RESPOSTA — %s" % porta_atual

func _on_serial_opened(porta: String) -> void:
	porta_atual = porta
	serial_status = "AGUARDANDO READY — %s" % porta

func _on_serial_closed(_porta: String) -> void:
	serial_status = "DESCONECTADO"
	porta_atual = ""
	ultimo_sinal_ms = -1
	proxima_tentativa = animation_time + 3.0
	sons.play("error", -8.0)

func _on_serial_line(line: String) -> void:
	var msg := ArduinoProtocol.parse(line)
	if msg.is_empty() or str(msg.get("type", "")) == "":
		return
	ultimo_sinal_ms = Time.get_ticks_msec()
	match str(msg["type"]):
		"READY":
			serial_status = "CONECTADO %s" % porta_atual
			_enviar_config()
		"PONG":
			if not porta_atual.is_empty() and "CONECTADO" not in serial_status:
				serial_status = "CONECTADO %s" % porta_atual
		"CALIBRATING":
			serial_status = "CALIBRANDO %d%%" % int(msg["percent"])
		"CALIBRATED":
			serial_status = "CONECTADO %s" % porta_atual
			_show_notice("SENSOR CALIBRADO")
		"BUTTON":
			if central_aberta:
				return
			if str(msg["button"]) == "CREDIT":
				_add_credit()
			else:
				_pressionou_start()
		"HIT":
			_receber_hit(msg)
		"TELEMETRY":
			telemetria = "a=(%.1f, %.1f, %.1f)g  g=(%.0f, %.0f, %.0f)°/s  pico %.1fg" % [
				msg["accel"].x, msg["accel"].y, msg["accel"].z,
				msg["gyro"].x, msg["gyro"].y, msg["gyro"].z,
				msg["peak_g"],
			]
		"SATURATION":
			_show_notice("SATURAÇÃO NO %s — GOLPE ACIMA DA ESCALA" % str(msg["source"]))
		"ERROR":
			_show_notice("ERRO DO FIRMWARE: %s" % str(msg["code"]))
			sons.play("error", -8.0)

func _receber_hit(msg: Dictionary) -> void:
	var speed := float(msg["speed"])
	if state != GameDef.State.ARMED:
		# Golpe fora de hora: registra na telemetria, não vira ponto.
		telemetria = "último golpe: %.2f m/s, %.1fg, eixo %s" % [
			speed, float(msg["accel"]), str(msg["axis"])
		]
		return
	_cancelar_carga()
	var span := maxf(hit_max_speed - hit_min_speed, 0.1)
	var normalizado := clampf((speed - hit_min_speed) / span, 0.0, 1.0)
	var pontos := clampi(int(round(pow(normalizado, 0.8) * GameDef.SCORE_MAX)), 0, GameDef.SCORE_MAX)
	if speed > 0.0 and pontos < 10:
		pontos = 10
	_registrar_impacto(pontos, speed, false)

func _enviar_config() -> void:
	if link != null and link.is_open():
		link.send_line(ArduinoProtocol.build_config(sensor_eixo, sensor_raio, sensor_vmin, sensor_amin))

func _teste_de_golpe() -> void:
	## Na Central Técnica (tecla T ou botão TESTAR): se a placa está
	## ligada, pede um golpe sintético a ela; senão, simula um aqui.
	if link != null and link.is_open():
		link.send_line("TEST")
		_show_notice("TESTE SOLICITADO AO ARDUINO")
	else:
		var speed := randf_range(hit_min_speed + 1.0, hit_max_speed * 0.9)
		_show_notice("GOLPE SIMULADO — %.1f m/s" % speed)
		if state == GameDef.State.ARMED:
			_receber_hit({"speed": speed, "accel": 8.0, "axis": sensor_eixo})

# ======================================================================
# CENTRAL TÉCNICA (F9)
# ======================================================================
func _toggle_central() -> void:
	if central_aberta:
		_fechar_central()
	else:
		_cancelar_carga()
		if state != GameDef.State.IDLE and state != GameDef.State.RESULT:
			_entrar_em_abertura()
		central_aberta = true
		if link != null and link.available():
			portas_visiveis = link.list_ports()
		sons.play("menu", -4.0)

func _fechar_central() -> void:
	central_aberta = false
	_salvar()
	_enviar_config()
	sons.play("menu", -8.0)

func _click_central(p: Vector2) -> void:
	if BOTOES["fechar"].has_point(p) or BOTOES["salvar"].has_point(p):
		_fechar_central()
	elif BOTOES["modo_livre"].has_point(p):
		game_mode = "free"
	elif BOTOES["modo_ficha"].has_point(p):
		game_mode = "credit"
	elif BOTOES["porta_menos"].has_point(p):
		_girar_porta(-1)
	elif BOTOES["porta_mais"].has_point(p):
		_girar_porta(1)
	elif BOTOES["vmin_menos"].has_point(p):
		hit_min_speed = maxf(0.2, hit_min_speed - 0.1)
	elif BOTOES["vmin_mais"].has_point(p):
		hit_min_speed = minf(hit_max_speed - 0.5, hit_min_speed + 0.1)
	elif BOTOES["vmax_menos"].has_point(p):
		hit_max_speed = maxf(hit_min_speed + 0.5, hit_max_speed - 0.5)
	elif BOTOES["vmax_mais"].has_point(p):
		hit_max_speed = minf(40.0, hit_max_speed + 0.5)
	elif BOTOES["eixo"].has_point(p):
		var eixos := ["X", "Y", "Z"]
		sensor_eixo = eixos[(eixos.find(sensor_eixo) + 1) % 3]
	elif BOTOES["raio_menos"].has_point(p):
		sensor_raio = maxf(0.05, sensor_raio - 0.05)
	elif BOTOES["raio_mais"].has_point(p):
		sensor_raio = minf(1.50, sensor_raio + 0.05)
	elif BOTOES["amin_menos"].has_point(p):
		sensor_amin = maxf(0.5, sensor_amin - 0.5)
	elif BOTOES["amin_mais"].has_point(p):
		sensor_amin = minf(15.0, sensor_amin + 0.5)
	elif BOTOES["enviar_config"].has_point(p):
		_enviar_config()
		_show_notice("CONFIG ENVIADA AO ARDUINO")
	elif BOTOES["testar"].has_point(p):
		_teste_de_golpe()
	elif BOTOES["zerar"].has_point(p):
		credits = 0
		plays = 0
		best_score = 0
		_show_notice("CONTADORES ZERADOS")
	elif BOTOES["reconectar"].has_point(p):
		if link != null:
			link.close_port()
		_tentar_conectar()
		_show_notice("RECONEXÃO SOLICITADA")
	elif BOTOES["padroes"].has_point(p):
		game_mode = "credit"
		porta_configurada = ""
		hit_min_speed = 0.8
		hit_max_speed = 12.0
		sensor_eixo = "X"
		sensor_raio = 0.45
		sensor_vmin = 0.5
		sensor_amin = 2.5
		_show_notice("PADRÕES RESTAURADOS")
	else:
		return
	_salvar()

func _girar_porta(direcao: int) -> void:
	var opcoes := PackedStringArray(["AUTO"])
	opcoes.append_array(portas_visiveis)
	var atual := opcoes.find(porta_configurada if not porta_configurada.is_empty() else "AUTO")
	atual = (atual + direcao + opcoes.size()) % opcoes.size()
	var escolha := opcoes[atual]
	porta_configurada = "" if escolha == "AUTO" else escolha

func _show_notice(message: String) -> void:
	notice = message
	notice_left = 2.8

# ======================================================================
# ESTADO EM DISCO
# ======================================================================
func _carregar() -> void:
	var data := SettingsStore.load_data()
	if data.is_empty():
		return
	game_mode = str(data.get("mode", game_mode))
	credits = int(data.get("credits", credits))
	plays = int(data.get("plays", plays))
	best_score = int(data.get("best_score", best_score))
	porta_configurada = str(data.get("port", porta_configurada))
	hit_min_speed = float(data.get("hit_min_speed", hit_min_speed))
	hit_max_speed = float(data.get("hit_max_speed", hit_max_speed))
	sensor_eixo = str(data.get("sensor_eixo", sensor_eixo))
	sensor_raio = float(data.get("sensor_raio", sensor_raio))
	sensor_vmin = float(data.get("sensor_vmin", sensor_vmin))
	sensor_amin = float(data.get("sensor_amin", sensor_amin))

func _salvar() -> void:
	SettingsStore.save_data({
		"mode": game_mode,
		"credits": credits,
		"plays": plays,
		"best_score": best_score,
		"port": porta_configurada,
		"hit_min_speed": hit_min_speed,
		"hit_max_speed": hit_max_speed,
		"sensor_eixo": sensor_eixo,
		"sensor_raio": sensor_raio,
		"sensor_vmin": sensor_vmin,
		"sensor_amin": sensor_amin,
	})

# ======================================================================
# DESENHO
# ======================================================================
func _draw() -> void:
	# O TREMOR SACODE A TELA INTEIRA: um deslocamento só, antes de tudo.
	if tremor > 0.1:
		draw_set_transform(
			Vector2(randf_range(-tremor, tremor), randf_range(-tremor, tremor)),
			0.0, Vector2.ONE
		)

	if state == GameDef.State.IDLE:
		_draw_abertura()
	else:
		_draw_partida()

	fx.desenhar(self)

	if clarao > 0.01:
		draw_rect(Rect2(Vector2.ZERO, TELA), Color(1, 1, 1, clarao * 0.55))
	if notice != "" and not central_aberta:
		_draw_notice()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if central_aberta:
		_draw_central()

# ---------------------------------------------------------------- abertura
func _draw_abertura() -> void:
	var entrada := clampf(state_time / 1.05, 0.0, 1.0)
	var suave := ease(entrada, 0.35)

	# Raios girando atrás da marca: movimento sem competir com ela.
	var centro := Vector2(540, 560)
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
			cor
		)
	for i in range(3):
		var raio := 320.0 + i * 82.0 + sin(animation_time * 1.1 + i * 0.7) * 14.0
		draw_arc(centro, raio * suave, 0.0, TAU, 120, Color(0.3, 0.8, 1.0, 0.12 * suave), 2.0)

	var flutuar := sin(animation_time * 1.6) * 14.0
	_draw_marca(centro + Vector2(0, flutuar), 860.0 * lerpf(0.84, 1.0, suave), suave)

	var titulo_y := 1140.0
	_text("PUNCH CHALLENGE", Vector2(-4, titulo_y + 3), 78, Color(1.0, 0.17, 0.45, 0.55 * suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("PUNCH CHALLENGE", Vector2(4, titulo_y - 3), 78, Color(0.25, 0.85, 1.0, 0.55 * suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("PUNCH CHALLENGE", Vector2(0, titulo_y), 78, Color(1, 1, 1, suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("MEDIDOR DE POTÊNCIA", Vector2(0, titulo_y + 46), 24, Color(0.44, 0.56, 0.78, suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("LAZER & SPORT BRINQUEDOS", Vector2(0, titulo_y + 82), 20, Color(0.34, 0.44, 0.64, suave), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

	# O convite pisca; sem crédito, troca de texto em vez de sumir.
	var piscada := 0.55 + 0.45 * sin(animation_time * 4.2)
	var convite := "PRESSIONE  START"
	var cor_convite := Color(1.0, 0.85, 0.25)
	if game_mode == "credit" and credits <= 0:
		convite = "INSIRA 1 FICHA  •  TECLA C"
		cor_convite = Color(0.35, 0.92, 1.0)
	var caixa := Rect2(140, 1300, 800, 110)
	_panel(caixa, Color(0.05, 0.09, 0.2, 0.85 * suave), Color(cor_convite.r, cor_convite.g, cor_convite.b, 0.5 * piscada * suave))
	_text(convite, Vector2(140, 1372), 40, Color(cor_convite.r, cor_convite.g, cor_convite.b, piscada * suave), HORIZONTAL_ALIGNMENT_CENTER, 800)

	_draw_rodape_abertura(suave)

func _draw_rodape_abertura(alpha: float) -> void:
	var itens := [
		["RECORDE", "%03d" % best_score, Color("58e8ff")],
		["PARTIDAS", str(plays), Color("a978ff")],
		["CRÉDITOS", "∞" if game_mode == "free" else "%02d" % credits, Color("ff4c9b")],
		["MODO", "LIVRE" if game_mode == "free" else "FICHA", Color("52f2a4")],
	]
	for i in range(itens.size()):
		var coluna := i % 2
		var linha := i / 2
		var rect := Rect2(60.0 + coluna * 490.0, 1500.0 + linha * 150.0, 470.0, 130.0)
		var accent: Color = itens[i][2]
		_panel(rect, Color(0.04, 0.07, 0.16, 0.75 * alpha), Color(accent.r, accent.g, accent.b, 0.28 * alpha))
		_text(str(itens[i][0]), rect.position + Vector2(0, 48), 17, Color(0.44, 0.53, 0.71, alpha), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		_text(str(itens[i][1]), rect.position + Vector2(0, 104), 40, Color(accent.r, accent.g, accent.b, alpha), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

	_draw_status_linha(alpha)
	_text("SENSOR MPU-6050  •  SEGURE ESPAÇO PARA SIMULAR", Vector2(0, 1870), 16, Color(0.29, 0.36, 0.5, alpha), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

# ---------------------------------------------------------------- partida
func _draw_partida() -> void:
	_draw_header()

	match state:
		GameDef.State.COUNTDOWN:
			var count := clampi(int(ceil(countdown_left)), 1, 3)
			var fracao := fmod(countdown_left, 1.0)
			var pulso := 1.0 + fracao * 0.16
			draw_arc(Vector2(540, 1180), 200.0, -PI * 0.5, -PI * 0.5 + TAU * fracao, 96, Color("4beaff"), 10.0)
			_text(str(count), Vector2(0, 1260), int(240 * pulso), Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
			_text("PREPARE-SE", Vector2(0, 1420), 36, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
		GameDef.State.ARMED:
			_text("SOQUE AGORA!", Vector2(0, 1220), 78, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
			if carga_tempo >= 0.0:
				_text("CARREGANDO… SOLTE PARA SOCAR", Vector2(0, 1280), 26, Color("ffd23f"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
			else:
				var dica := "Segure ESPAÇO para simular" if link == null or not link.is_open() else "Aguardando impacto no saco"
				_text("%s  •  %.1fs" % [dica, armed_left], Vector2(0, 1280), 24, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
		GameDef.State.MEASURING:
			_text("IMPACTO!", Vector2(0, 1230), 90, Color("ffd23f"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
		GameDef.State.RESULT:
			_draw_resultado()

	_draw_cartoes()

func _draw_resultado() -> void:
	var vibra := 1.0
	if verdict_time < 0.0:
		vibra = 1.0 + 0.05 * sin(animation_time * 26.0)
	_text("%03d" % int(round(displayed_score)), Vector2(0, 1240), int(190 * vibra), Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("PONTOS DE POTÊNCIA", Vector2(0, 1300), 24, Color("63e9ff"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

	if verdict_time < 0.0:
		_text("MEDINDO O IMPACTO…", Vector2(0, 1370), 22, Color("8092b9"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
		return

	var classe := GameDef.classificar(result_score)
	var cor: Color = classe["color"]
	_draw_carimbo(str(classe["label"]), cor)

	var origem := "SIMULAÇÃO" if result_simulado else "MPU-6050"
	_text("%s  •  %.2f m/s" % [origem, result_speed], Vector2(0, 1430), 20, Color("8092b9"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	if novo_recorde:
		var brilho := 0.6 + 0.4 * sin(animation_time * 6.0)
		_text("NOVO RECORDE!", Vector2(0, 1335), 30, Color(0.35, 0.95, 0.65, brilho), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	if verdict_time > 1.0:
		var piscada := 0.55 + 0.45 * sin(animation_time * 3.6)
		_text("START PARA JOGAR NOVAMENTE", Vector2(0, 1480), 20, Color(0.73, 0.77, 0.87, piscada), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

func _draw_carimbo(titulo: String, cor: Color) -> void:
	## O CARIMBO CAI NA TELA, não aparece: entra grande, passa do lugar e
	## volta — o gesto de um carimbo batendo no papel.
	var t := clampf(verdict_time / 0.45, 0.0, 1.0)
	var escala := 1.0
	if t < 1.0:
		escala = lerpf(2.4, 1.0, ease(t, 0.28)) + sin(t * PI) * 0.12
	var alpha := clampf(verdict_time / 0.2, 0.0, 1.0)
	var tamanho := int(clampf(88.0 * escala, 20.0, 220.0))
	_text(titulo, Vector2(0, 1390), tamanho, Color(cor.r, cor.g, cor.b, alpha), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

func _draw_header() -> void:
	draw_rect(Rect2(40, 152, 1000, 1), Color(0.3, 0.75, 1.0, 0.18))
	_text("PUNCH", Vector2(60, 84), 30, Color("f4f7ff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("CHALLENGE", Vector2(176, 84), 30, Color("55e7ff"), HORIZONTAL_ALIGNMENT_LEFT)
	var cor := Color("52f2a4") if "CONECTADO" in serial_status else Color("ffbd4a")
	draw_circle(Vector2(430, 74), 7.0, cor)
	_text(serial_status, Vector2(446, 80), 14, Color("aab5d1"), HORIZONTAL_ALIGNMENT_LEFT, 400)
	var mode_text := "MODO LIVRE" if game_mode == "free" else "MODO FICHA"
	_pill(Rect2(880, 52, 160, 48), mode_text, Color("1b2b52"), Color("69e9ff"))

func _draw_status_linha(alpha: float) -> void:
	var cor := Color("52f2a4") if "CONECTADO" in serial_status else Color("ffbd4a")
	draw_circle(Vector2(56, 62), 7.0, Color(cor.r, cor.g, cor.b, alpha))
	_text(serial_status, Vector2(74, 70), 15, Color(0.55, 0.64, 0.82, alpha), HORIZONTAL_ALIGNMENT_LEFT)
	_text("F9  •  CENTRAL TÉCNICA", Vector2(580, 70), 15, Color(0.4, 0.49, 0.68, alpha), HORIZONTAL_ALIGNMENT_RIGHT, 440)

func _draw_cartoes() -> void:
	_stat_card(Rect2(40, 1560, 320, 130), "RECORDE", "%03d" % best_score, Color("58e8ff"))
	_stat_card(Rect2(380, 1560, 320, 130), "PARTIDAS", str(plays), Color("a978ff"))
	_stat_card(Rect2(720, 1560, 320, 130), "CRÉDITOS", "∞" if game_mode == "free" else "%02d" % credits, Color("ff4c9b"))
	_text("ESPAÇO: START / SIMULAÇÃO    •    C: CRÉDITO    •    F9: CENTRAL TÉCNICA", Vector2(0, 1760), 17, Color("7385ad"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_text("LAZER & SPORT BRINQUEDOS", Vector2(0, 1880), 15, Color("536488"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

# ---------------------------------------------------------------- central
func _draw_central() -> void:
	draw_rect(Rect2(Vector2.ZERO, TELA), Color(0.005, 0.009, 0.025, 0.92))
	_panel(Rect2(40, 90, 1000, 1790), Color("0d142c"), Color(0.22, 0.55, 0.95, 0.52))
	_text("CENTRAL TÉCNICA", Vector2(110, 190), 38, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT)
	_text("Configuração, diagnóstico e calibração", Vector2(110, 228), 18, Color("7e90b8"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["fechar"], "×", false, Color("ff568f"), 32)

	_panel(Rect2(80, 260, 920, 180), Color("111d3b"), Color(0.19, 0.42, 0.78, 0.4))
	_text("MODO DE OPERAÇÃO", Vector2(120, 306), 16, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["modo_livre"], "LIVRE", game_mode == "free", Color("55e7ff"), 20)
	_button(BOTOES["modo_ficha"], "1 FICHA", game_mode == "credit", Color("ff4c9b"), 20)

	_panel(Rect2(80, 480, 920, 190), Color("111d3b"), Color(0.19, 0.42, 0.78, 0.4))
	_text("CONEXÃO DO SENSOR", Vector2(120, 526), 16, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	var dot := Color("4ff0a2") if "CONECTADO" in serial_status else Color("ffba46")
	draw_circle(Vector2(560, 518), 7.0, dot)
	_text(serial_status, Vector2(578, 524), 15, dot, HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["porta_menos"], "−", false, Color("55e7ff"), 27)
	_button(BOTOES["porta_mais"], "+", false, Color("55e7ff"), 27)
	var porta_txt := porta_configurada if not porta_configurada.is_empty() else "AUTO"
	_text(porta_txt, Vector2(240, 616), 32, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 600)

	_panel(Rect2(80, 710, 920, 190), Color("111d3b"), Color(0.19, 0.42, 0.78, 0.4))
	_text("FAIXA DE VELOCIDADE DO PLACAR (m/s)", Vector2(120, 756), 16, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["vmin_menos"], "−", false, Color("55e7ff"), 24)
	_button(BOTOES["vmin_mais"], "+", false, Color("55e7ff"), 24)
	_text("MÍN  %.1f" % hit_min_speed, Vector2(110, 856), 22, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 320)
	_button(BOTOES["vmax_menos"], "−", false, Color("55e7ff"), 24)
	_button(BOTOES["vmax_mais"], "+", false, Color("55e7ff"), 24)
	_text("MÁX  %.1f" % hit_max_speed, Vector2(650, 856), 22, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 320)

	_panel(Rect2(80, 940, 920, 390), Color("111d3b"), Color(0.19, 0.42, 0.78, 0.4))
	_text("CONFIGURAÇÃO DO FIRMWARE (MPU-6050)", Vector2(120, 986), 16, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	_button(BOTOES["eixo"], "EIXO %s" % sensor_eixo, false, Color("b45cff"), 18)
	_button(BOTOES["raio_menos"], "−", false, Color("55e7ff"), 24)
	_button(BOTOES["raio_mais"], "+", false, Color("55e7ff"), 24)
	_button(BOTOES["amin_menos"], "−", false, Color("55e7ff"), 24)
	_button(BOTOES["amin_mais"], "+", false, Color("55e7ff"), 24)
	_text("RAIO %.2f m" % sensor_raio, Vector2(400, 1146), 18, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 260)
	_text("SENSIB. %.1f g" % sensor_amin, Vector2(680, 1146), 18, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, 280)
	_button(BOTOES["enviar_config"], "ENVIAR CONFIG", false, Color("52f2a4"), 18)
	_button(BOTOES["testar"], "TESTAR SENSOR", false, Color("ffd23f"), 18)

	_panel(Rect2(80, 1370, 920, 190), Color("111d3b"), Color(0.19, 0.42, 0.78, 0.4))
	_text("DIAGNÓSTICO", Vector2(120, 1416), 16, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT)
	_text(telemetria if telemetria != "" else "sem telemetria ainda", Vector2(120, 1446), 15, Color("7e90b8"), HORIZONTAL_ALIGNMENT_LEFT, 880)
	_button(BOTOES["zerar"], "ZERAR CONTADORES", false, Color("ff568f"), 16)
	_button(BOTOES["reconectar"], "RECONECTAR", false, Color("55e7ff"), 16)

	_text("Tecla T: golpe de teste  •  ESC: fechar", Vector2(0, 1620), 16, Color("7385ad"), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)
	_button(BOTOES["padroes"], "RESTAURAR PADRÕES", false, Color("ffba46"), 18)
	_button(BOTOES["salvar"], "SALVAR E FECHAR", true, Color("52f2a4"), 20)

# ---------------------------------------------------------------- peças
func _draw_marca(centro: Vector2, largura: float, alpha: float) -> void:
	if logo != null:
		var tamanho := logo.get_size()
		var escala := largura / tamanho.x
		var destino := Rect2(
			centro - Vector2(largura, tamanho.y * escala) * 0.5,
			Vector2(largura, tamanho.y * escala)
		)
		draw_texture_rect(logo, destino, false, Color(1, 1, 1, alpha))
	else:
		# Sem a textura, a marca aparece em texto: a máquina nunca fica
		# em tela preta por causa de um arquivo faltando.
		_text("LAZER & SPORT", Vector2(0, centro.y), 64, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, TELA.x)

func _draw_notice() -> void:
	var caixa := Rect2(140, 96, 800, 56)
	draw_rect(caixa, Color(0.02, 0.05, 0.12, 0.9))
	draw_rect(caixa, Color(0.35, 0.85, 1.0, 0.5), false, 2.0)
	_text(notice, Vector2(140, 132), 19, Color("cfe6ff"), HORIZONTAL_ALIGNMENT_CENTER, 800)

func _panel(rect: Rect2, fundo_c: Color, borda: Color) -> void:
	draw_rect(rect, fundo_c)
	draw_rect(rect, borda, false, 2.0)

func _pill(rect: Rect2, texto: String, fundo_c: Color, frente: Color) -> void:
	draw_rect(rect, fundo_c)
	draw_rect(rect, Color(frente.r, frente.g, frente.b, 0.5), false, 2.0)
	_text(texto, rect.position + Vector2(0, rect.size.y * 0.66), 16, frente, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _button(rect: Rect2, texto: String, ativo: bool, accent: Color, tamanho: int) -> void:
	var fundo_c := Color(accent.r, accent.g, accent.b, 0.22) if ativo else Color("131f3f")
	draw_rect(rect, fundo_c)
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.85 if ativo else 0.45), false, 2.0)
	_text(texto, rect.position + Vector2(0, rect.size.y * 0.68), tamanho, Color("ffffff") if ativo else accent, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _stat_card(rect: Rect2, rotulo: String, valor: String, accent: Color) -> void:
	_panel(rect, Color(0.04, 0.07, 0.16, 0.78), Color(accent.r, accent.g, accent.b, 0.3))
	_text(rotulo, rect.position + Vector2(0, 46), 16, Color("8ea0c8"), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	_text(valor, rect.position + Vector2(0, 104), 38, accent, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _text(texto: String, pos: Vector2, tamanho: int, cor: Color, alinhamento := HORIZONTAL_ALIGNMENT_LEFT, largura := -1.0) -> void:
	draw_string(fonte, pos, texto, alinhamento, largura, tamanho, cor)
