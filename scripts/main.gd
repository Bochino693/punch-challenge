extends Control

## Punch Challenge — a máquina de soco da Lazer & Sport.
##
## TELA EM PÉ, 1080 × 1920, LIDA EM BANDAS. Quem joga está a dois ou três
## metros do gabinete e olha para cima. A tela é dividida em faixas
## horizontais fixas (`BANDA_*`), e cada coisa desenhada mora dentro da
## sua: cabeçalho, palco (saco e medidor), leitura (número e veredito),
## cartões e rodapé. Enquanto tudo respeitar a sua banda, nada se
## sobrepõe — que é a diferença entre um placar que se lê de longe e um
## amontoado de texto por cima de texto.
##
## O nó raiz desenha textos, placar e a Central Técnica; o cenário vivo
## fica nos filhos: `PunchBackground` (fundo), `PunchBag` (saco),
## `PowerMeter` (coluna de potência), `LedFrame` (moldura de LEDs) e
## `AudioBank` (sons). O que voa — confete, faísca, estilhaço — mora em
## `fx.gd`.
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

# ======================================================================
# AS BANDAS DA TELA
# ======================================================================
## Cabeçalho: marca do jogo e modo de operação.
const BANDA_TOPO := 150.0
## Palco: o saco e o medidor. Nada de texto entra aqui.
const PALCO_TOPO := 168.0
const PALCO_BASE := 1104.0
## Leitura: o número, o veredito e o convite. É a banda que o cliente
## procura com os olhos quando o soco acaba.
const LEITURA_TOPO := 1124.0
const LEITURA_BASE := 1580.0
## Cartões de recorde/partidas/créditos.
const CARTOES_Y := 1608.0
const CARTOES_ALTURA := 132.0
## Rodapé: assinatura da casa e, só na bancada, as teclas de teste.
const RODAPE_Y := 1876.0
## Margem lateral livre de moldura de LED.
const MARGEM := 60.0
const LARGURA_UTIL := TELA.x - MARGEM * 2.0

const CORES_FESTA := [
	Color("ff2d78"), Color("ffd23f"), Color("4beaff"),
	Color("8d62ff"), Color("52f2a4"), Color("ffffff"),
]

# ======================================================================
# A CENTRAL TÉCNICA, DESCRITA UMA VEZ SÓ
# ======================================================================
## Os retângulos dos botões NÃO são escritos à mão. Um par de − / + com o
## valor no meio é um "passo" (`_passo`), e é ele que decide onde ficam
## os dois botões e onde sobra espaço para o número. Foi um número
## escrito por cima de um botão que motivou isso: com a conta num lugar
## só, o texto não tem como invadir a área de clique.
const LADO_BOTAO := 64.0
## Passos: chave -> retângulo total (botões nas pontas, valor no meio).
const PASSOS := {
	"limiar_fraco": Rect2(110, 546, 400, LADO_BOTAO),
	"limiar_forte": Rect2(570, 546, 400, LADO_BOTAO),
	"vmin": Rect2(110, 780, 400, LADO_BOTAO),
	"vmax": Rect2(570, 780, 400, LADO_BOTAO),
	"porta": Rect2(110, 1020, 400, LADO_BOTAO),
	"raio": Rect2(110, 1140, 400, LADO_BOTAO),
	"amin": Rect2(570, 1140, 400, LADO_BOTAO),
}
## Botões simples: chave -> retângulo.
const BOTOES_SIMPLES := {
	"fechar": Rect2(920, 140, 68, 64),
	"modo_livre": Rect2(110, 320, 400, 72),
	"modo_ficha": Rect2(570, 320, 400, 72),
	"eixo": Rect2(620, 1020, 280, LADO_BOTAO),
	"enviar_config": Rect2(110, 1350, 400, 72),
	"testar": Rect2(570, 1350, 400, 72),
	"zerar": Rect2(110, 1620, 400, 72),
	"reconectar": Rect2(570, 1620, 400, 72),
	"padroes": Rect2(110, 1750, 400, 76),
	"salvar": Rect2(570, 1750, 400, 76),
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
## Os dois limites que separam fraco, médio e forte no placar.
var limiar_fraco := GameDef.LIMIAR_FRACO_PADRAO
var limiar_forte := GameDef.LIMIAR_FORTE_PADRAO
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
	_aplicar_faixas()
	_iniciar_serial()
	_entrar_em_abertura()
	set_process(true)

func _exit_tree() -> void:
	if link != null:
		link.close_port()

## Um lugar só onde as faixas chegam a quem as desenha. Régua do medidor,
## cor da moldura e veredito passam a concordar por construção.
func _aplicar_faixas() -> void:
	var lim := GameDef.limiares(limiar_fraco, limiar_forte)
	limiar_fraco = lim.x
	limiar_forte = lim.y
	medidor.set_faixas(limiar_fraco, limiar_forte)
	medidor.recorde = best_score

## Onde o soco aterrissa. Pergunta ao saco em vez de repetir a conta: o
## saco pode mudar de tamanho ou de posição sem levar junto a onda de
## choque, as faíscas e o clarão.
func _alvo() -> Vector2:
	return saco.ponto_de_impacto()

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
		fx.onda(_alvo(), 60.0, 340.0, Color(0.35, 0.9, 1.0, 0.5), 6.0, 0.6)
	if countdown_left <= 0.0:
		state = GameDef.State.ARMED
		state_time = 0.0
		armed_left = GameDef.JANELA_DO_SOCO
		carga_tempo = -1.0
		sons.play("go")
		moldura.set_estado(LedFrame.ARMADA)
		saco.set_alvo(true)
		fx.onda(_alvo(), 40.0, 560.0, Color(1.0, 0.25, 0.55, 0.55), 10.0, 0.8)
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
	## A festa continua enquanto o veredito está na tela, e o tamanho
	## dela é o da faixa — as mesmas três faixas da régua do medidor.
	match GameDef.faixa_de(result_score, limiar_fraco, limiar_forte):
		GameDef.Faixa.FORTE:
			if verdict_time < 5.0 and verdict_time >= proximo_fogo:
				proximo_fogo = verdict_time + 0.55
				fx.fogos(
					Vector2(randf_range(180.0, 900.0), randf_range(280.0, 900.0)),
					CORES_FESTA
				)
			if verdict_time < 2.6 and randf() < delta * 26.0:
				fx.chuva_de_confete(TELA.x, 3, CORES_FESTA)
		GameDef.Faixa.MEDIA:
			if verdict_time >= proximo_fogo:
				proximo_fogo = verdict_time + 0.85
				fx.onda(_alvo(), 90.0, 450.0, Color(1.0, 0.72, 0.2, 0.4), 7.0, 0.85)
		_:
			if verdict_time < 2.2 and randf() < delta * 9.0:
				fx.estilhacos(Vector2(randf_range(180.0, 900.0), 420.0), 2, Color("2a3350"))

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
	medidor.recorde = best_score
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
	fx.faiscas(Vector2(540, 1300), 22, Color("52f2a4"), 420.0)
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
	var alvo := _alvo()
	saco.golpear(forca)
	moldura.impacto(0.4 + forca * 0.6)
	sons.play("hit", 1.5)
	tremor = 10.0 + forca * 22.0
	clarao = 0.25 + forca * 0.45
	fx.onda(alvo, 30.0, 500.0 + forca * 400.0, Color(1.0, 0.3, 0.55, 0.6), 16.0, 0.7)
	fx.faiscas(alvo, 30 + int(forca * 50.0), Color("ffd23f"), 700.0 + forca * 600.0)
	plays += 1
	novo_recorde = result_score > best_score
	if novo_recorde:
		best_score = result_score
	_salvar()

func _disparar_veredito() -> void:
	## O momento em que a máquina diz quanto valeu o soco. Um por golpe.
	verdict_time = 0.0
	proximo_fogo = 0.0
	var classe := GameDef.classificar(result_score, limiar_fraco, limiar_forte)
	var cor: Color = classe["cor_faixa"]
	moldura.set_estado(LedFrame.RESULTADO, cor)
	# A tela inteira toma a cor da faixa, de leve: o veredito chega ao
	# canto do olho antes de a pessoa terminar de ler a palavra.
	fundo.matiz = Color(cor.r, cor.g, cor.b, 0.07)
	var alvo := _alvo()

	match classe["faixa"] as GameDef.Faixa:
		GameDef.Faixa.FORTE:
			if str(classe["label"]) == "LENDÁRIO":
				sons.play("legendary", 0.5)
			else:
				sons.play("win", 0.5)
			tremor = 30.0
			clarao = 0.85
			fx.confete(Vector2(540, 900), 130, CORES_FESTA, 1250.0)
			fx.chuva_de_confete(TELA.x, 90, CORES_FESTA)
			fx.onda(alvo, 60.0, 1100.0, Color(1.0, 0.85, 0.25, 0.55), 18.0, 1.0)
		GameDef.Faixa.MEDIA:
			sons.play("medium")
			tremor = 14.0
			fx.faiscas(alvo, 46, Color("ffb648"), 700.0)
			fx.onda(alvo, 60.0, 560.0, Color(1.0, 0.72, 0.25, 0.5), 12.0, 0.9)
		_:
			sons.play("lose")
			tremor = 9.0
			fx.estilhacos(alvo, 34, Color("222b47"))
			fx.poeira(alvo + Vector2(0, 240.0), 26, Color(0.55, 0.16, 0.26, 0.5), 260.0)

	if novo_recorde:
		sons.play("record", 2.0)
		medidor.recorde = best_score

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

## O sensor está falando com a máquina? Decide o que o cliente vê: com o
## Arduino ligado, a tela não mostra tecla nenhuma; na bancada, mostra.
func _sensor_ligado() -> bool:
	return link != null and link.is_open() and "CONECTADO" in serial_status

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
	_aplicar_faixas()
	_salvar()
	_enviar_config()
	sons.play("menu", -8.0)

## Retângulo do botão "−" de um passo.
func _passo_menos(chave: String) -> Rect2:
	var r: Rect2 = PASSOS[chave]
	return Rect2(r.position, Vector2(LADO_BOTAO, r.size.y))

## Retângulo do botão "+" de um passo.
func _passo_mais(chave: String) -> Rect2:
	var r: Rect2 = PASSOS[chave]
	return Rect2(Vector2(r.end.x - LADO_BOTAO, r.position.y), Vector2(LADO_BOTAO, r.size.y))

## Espaço livre entre os dois botões — onde o valor cabe sem encostar.
func _passo_visor(chave: String) -> Rect2:
	var r: Rect2 = PASSOS[chave]
	return Rect2(
		Vector2(r.position.x + LADO_BOTAO + 8.0, r.position.y),
		Vector2(r.size.x - LADO_BOTAO * 2.0 - 16.0, r.size.y)
	)

func _click_central(p: Vector2) -> void:
	# Passos primeiro: são a maioria dos cliques.
	for chave in PASSOS:
		if _passo_menos(chave).has_point(p):
			_ajustar(chave, -1)
			_salvar()
			return
		if _passo_mais(chave).has_point(p):
			_ajustar(chave, 1)
			_salvar()
			return

	if BOTOES_SIMPLES["fechar"].has_point(p) or BOTOES_SIMPLES["salvar"].has_point(p):
		_fechar_central()
		return
	elif BOTOES_SIMPLES["modo_livre"].has_point(p):
		game_mode = "free"
	elif BOTOES_SIMPLES["modo_ficha"].has_point(p):
		game_mode = "credit"
	elif BOTOES_SIMPLES["eixo"].has_point(p):
		var eixos := ["X", "Y", "Z"]
		sensor_eixo = eixos[(eixos.find(sensor_eixo) + 1) % 3]
	elif BOTOES_SIMPLES["enviar_config"].has_point(p):
		_enviar_config()
		_show_notice("CONFIG ENVIADA AO ARDUINO")
	elif BOTOES_SIMPLES["testar"].has_point(p):
		_teste_de_golpe()
	elif BOTOES_SIMPLES["zerar"].has_point(p):
		credits = 0
		plays = 0
		best_score = 0
		medidor.recorde = 0
		_show_notice("CONTADORES ZERADOS")
	elif BOTOES_SIMPLES["reconectar"].has_point(p):
		if link != null:
			link.close_port()
		_tentar_conectar()
		_show_notice("RECONEXÃO SOLICITADA")
	elif BOTOES_SIMPLES["padroes"].has_point(p):
		game_mode = "credit"
		porta_configurada = ""
		hit_min_speed = 0.8
		hit_max_speed = 12.0
		limiar_fraco = GameDef.LIMIAR_FRACO_PADRAO
		limiar_forte = GameDef.LIMIAR_FORTE_PADRAO
		sensor_eixo = "X"
		sensor_raio = 0.45
		sensor_vmin = 0.5
		sensor_amin = 2.5
		_show_notice("PADRÕES RESTAURADOS")
	else:
		return
	_aplicar_faixas()
	_salvar()

## Um clique num − ou + . Cada valor tem o seu passo e os seus limites,
## e o saneamento das faixas fica com `GameDef.limiares`.
func _ajustar(chave: String, direcao: int) -> void:
	match chave:
		"limiar_fraco":
			limiar_fraco = limiar_fraco + direcao * 10
		"limiar_forte":
			limiar_forte = limiar_forte + direcao * 10
		"vmin":
			hit_min_speed = clampf(hit_min_speed + direcao * 0.1, 0.2, hit_max_speed - 0.5)
		"vmax":
			hit_max_speed = clampf(hit_max_speed + direcao * 0.5, hit_min_speed + 0.5, 40.0)
		"porta":
			_girar_porta(direcao)
		"raio":
			sensor_raio = clampf(sensor_raio + direcao * 0.05, 0.05, 1.50)
		"amin":
			sensor_amin = clampf(sensor_amin + direcao * 0.5, 0.5, 15.0)
	_aplicar_faixas()

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
	limiar_fraco = int(data.get("limiar_fraco", limiar_fraco))
	limiar_forte = int(data.get("limiar_forte", limiar_forte))
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
		"limiar_fraco": limiar_fraco,
		"limiar_forte": limiar_forte,
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
	var centro := Vector2(540, 470)

	# Raios girando atrás da marca: movimento sem competir com ela.
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
		var raio := 300.0 + i * 78.0 + sin(animation_time * 1.1 + i * 0.7) * 14.0
		draw_arc(centro, raio * suave, 0.0, TAU, 120, Color(0.3, 0.8, 1.0, 0.12 * suave), 2.0)

	var flutuar := sin(animation_time * 1.6) * 12.0
	_draw_marca(centro + Vector2(0, flutuar), 740.0 * lerpf(0.86, 1.0, suave), suave)

	# Título em néon: sombra rosa e sombra ciano abrindo o branco.
	_texto("PUNCH CHALLENGE", 873.0, 80, Color(1.0, 0.17, 0.45, 0.55 * suave), HORIZONTAL_ALIGNMENT_CENTER, MARGEM - 4.0)
	_texto("PUNCH CHALLENGE", 867.0, 80, Color(0.25, 0.85, 1.0, 0.55 * suave), HORIZONTAL_ALIGNMENT_CENTER, MARGEM + 4.0)
	_texto("PUNCH CHALLENGE", 870.0, 80, Color(1, 1, 1, suave))
	# A segunda linha não repete a marca (a logo acima já a diz): ela faz
	# a pergunta que traz alguém do outro lado do salão até aqui.
	_texto("QUAL É A FORÇA DO SEU SOCO?", 918.0, 26, Color(0.52, 0.64, 0.86, suave))
	_texto("MEDIDOR DE POTÊNCIA  •  0 A 999 PONTOS", 954.0, 18, Color(0.34, 0.44, 0.64, suave))

	# O convite pisca; sem crédito, troca de texto em vez de sumir. Quem
	# atravessou o salão precisa saber o que fazer, não ver a frase sumir.
	var piscada := 0.55 + 0.45 * sin(animation_time * 4.2)
	var convite := "PRESSIONE  START"
	var cor_convite := Color(1.0, 0.85, 0.25)
	if game_mode == "credit" and credits <= 0:
		convite = "INSIRA 1 FICHA"
		cor_convite = Color(0.35, 0.92, 1.0)
	var caixa := Rect2(MARGEM + 80.0, 1020, LARGURA_UTIL - 160.0, 118.0)
	_panel(caixa, Color(0.05, 0.09, 0.2, 0.85 * suave), Color(cor_convite.r, cor_convite.g, cor_convite.b, 0.5 * piscada * suave))
	_texto_cabendo(convite, 1094.0, 42, Color(cor_convite.r, cor_convite.g, cor_convite.b, piscada * suave), caixa.size.x - 60.0, caixa.position.x + 30.0)

	_draw_placar_abertura(suave)
	_draw_como_jogar(suave)
	_draw_rodape(suave)

## Os quatro números da casa, numa fileira só: recorde, partidas,
## créditos e modo. Em fileira e não em bloco 2×2 porque o olho de quem
## está longe varre a tela em linha.
func _draw_placar_abertura(alpha: float) -> void:
	var itens := [
		["RECORDE", "%03d" % best_score, Color("58e8ff")],
		["PARTIDAS", str(plays), Color("a978ff")],
		["CRÉDITOS", "∞" if game_mode == "free" else "%02d" % credits, Color("ff4c9b")],
		["MODO", "LIVRE" if game_mode == "free" else "FICHA", Color("52f2a4")],
	]
	var largura := (LARGURA_UTIL - 3.0 * 16.0) / 4.0
	for i in range(itens.size()):
		_stat_card(
			Rect2(MARGEM + i * (largura + 16.0), 1230.0, largura, 130.0),
			str(itens[i][0]), str(itens[i][1]), itens[i][2] as Color, alpha
		)

## Três passos, numerados, do tamanho de quem lê de longe. É o que
## transforma alguém parado na frente da máquina em alguém jogando.
func _draw_como_jogar(alpha: float) -> void:
	_texto("COMO JOGAR", 1432.0, 22, Color(0.44, 0.55, 0.76, alpha))
	var passos := [
		["1", "INSIRA A FICHA" if game_mode == "credit" else "MÁQUINA LIBERADA", Color("52f2a4")],
		["2", "APERTE START", Color("ffd23f")],
		["3", "SOQUE O ALVO COM FORÇA", Color("ff4c9b")],
	]
	for i in range(passos.size()):
		var y := 1466.0 + i * 86.0
		var cor: Color = passos[i][2]
		var centro := Vector2(MARGEM + 46.0, y + 32.0)
		draw_circle(centro, 27.0, Color(cor.r, cor.g, cor.b, 0.16 * alpha))
		draw_arc(centro, 27.0, 0.0, TAU, 40, Color(cor.r, cor.g, cor.b, 0.75 * alpha), 2.5)
		_texto(str(passos[i][0]), centro.y + 10.0, 26, Color(cor.r, cor.g, cor.b, alpha), HORIZONTAL_ALIGNMENT_CENTER, centro.x - 40.0, 80.0)
		_texto(str(passos[i][1]), centro.y + 11.0, 30, Color(0.82, 0.88, 0.98, alpha), HORIZONTAL_ALIGNMENT_LEFT, MARGEM + 108.0, LARGURA_UTIL - 108.0)

# ---------------------------------------------------------------- partida
func _draw_partida() -> void:
	_draw_header()

	match state:
		GameDef.State.COUNTDOWN:
			_draw_contagem()
		GameDef.State.ARMED:
			_draw_armado()
		GameDef.State.MEASURING:
			_texto_cabendo("IMPACTO!", 1320.0, 116, Color("ffd23f"), LARGURA_UTIL)
		GameDef.State.RESULT:
			_draw_resultado()

	_draw_cartoes()
	_draw_rodape(1.0)

func _draw_contagem() -> void:
	var count := clampi(int(ceil(countdown_left)), 1, 3)
	var fracao := fmod(countdown_left, 1.0)
	var centro := Vector2(540, 1300)
	# O anel esvazia junto com o segundo: o tempo é visto, não lido.
	draw_arc(centro, 148.0, 0.0, TAU, 96, Color(0.20, 0.42, 0.70, 0.30), 9.0)
	draw_arc(centro, 148.0, -PI * 0.5, -PI * 0.5 + TAU * fracao, 96, Color("4beaff"), 9.0, true)
	var pulso := 1.0 + fracao * 0.14
	_texto(str(count), 1362.0, int(190 * pulso), Color("ffffff"))
	_texto("PREPARE-SE", 1540.0, 34, Color("63e9ff"))

func _draw_armado() -> void:
	_texto_cabendo("SOQUE AGORA!", 1268.0, 88, Color("ffffff"), LARGURA_UTIL)
	# Barra do tempo restante: some da direita para a esquerda e fica
	# vermelha no fim, sem número para ninguém precisar ler.
	var trilho := Rect2(MARGEM + 120.0, 1306.0, LARGURA_UTIL - 240.0, 22.0)
	var restante := clampf(armed_left / GameDef.JANELA_DO_SOCO, 0.0, 1.0)
	draw_rect(trilho, Color(0.05, 0.09, 0.18, 0.9))
	draw_rect(trilho, Color(0.25, 0.45, 0.75, 0.35), false, 2.0)
	var cor := Color("4beaff") if restante > 0.35 else Color("ff4c6a")
	draw_rect(Rect2(trilho.position, Vector2(trilho.size.x * restante, trilho.size.y)), cor)

	if carga_tempo >= 0.0:
		_texto("SOLTE PARA SOCAR", 1382.0, 28, Color("ffd23f"))
	elif _sensor_ligado():
		_texto("O SENSOR ESTÁ ESPERANDO O SEU GOLPE", 1382.0, 24, Color("63e9ff"))
	else:
		_texto("SEGURE ESPAÇO PARA SIMULAR O GOLPE", 1382.0, 24, Color("63e9ff"))

func _draw_resultado() -> void:
	# LINHA 1: o número. Sozinho na sua altura, do tamanho que der.
	var vibra := 1.0
	if verdict_time < 0.0:
		vibra = 1.0 + 0.05 * sin(animation_time * 26.0)
	var numero := "%03d" % int(round(displayed_score))
	_texto(numero, 1304.0, int(196 * vibra), Color(0.05, 0.1, 0.2, 0.8), HORIZONTAL_ALIGNMENT_CENTER, MARGEM + 6.0)
	_texto(numero, 1300.0, int(196 * vibra), Color("ffffff"))
	_texto("PONTOS DE POTÊNCIA", 1344.0, 23, Color("63e9ff"))

	# LINHA 2: enquanto conta, só a promessa; depois, o veredito.
	if verdict_time < 0.0:
		_texto("MEDINDO O IMPACTO…", 1462.0, 26, Color("8092b9"))
		return

	var classe := GameDef.classificar(result_score, limiar_fraco, limiar_forte)
	_draw_carimbo(str(classe["label"]), classe["color"] as Color)

	# LINHA 3: o detalhe do golpe. O recorde entra AQUI, e não por cima
	# do veredito — foi assim que a palavra ficava ilegível justamente
	# quando havia mais motivo para lê-la.
	var origem := "SIMULAÇÃO" if result_simulado else "SENSOR"
	var detalhe := "%s  •  %.2f m/s" % [origem, result_speed]
	var cor_detalhe := Color("8092b9")
	if novo_recorde:
		detalhe = "★ NOVO RECORDE DA CASA  •  %s" % detalhe
		cor_detalhe = Color(0.35, 0.95, 0.65, 0.6 + 0.4 * sin(animation_time * 6.0))
	_texto_cabendo(detalhe, 1514.0, 22, cor_detalhe, LARGURA_UTIL)

	# LINHA 4: o convite para a próxima ficha, depois de o veredito assentar.
	if verdict_time > 1.0:
		var piscada := 0.55 + 0.45 * sin(animation_time * 3.6)
		_texto("START PARA JOGAR NOVAMENTE", 1562.0, 21, Color(0.73, 0.77, 0.87, piscada))

func _draw_carimbo(titulo: String, cor: Color) -> void:
	## O CARIMBO CAI NA TELA, não aparece: entra grande, passa do lugar e
	## volta — o gesto de um carimbo batendo no papel. O tamanho final
	## sai de `_texto_cabendo`, então "PESO-PESADO" não estoura a tela do
	## mesmo jeito que "FRACO!" não fica pequeno.
	var t := clampf(verdict_time / 0.45, 0.0, 1.0)
	var escala := 1.0
	if t < 1.0:
		escala = lerpf(2.2, 1.0, ease(t, 0.28)) + sin(t * PI) * 0.10
	var alpha := clampf(verdict_time / 0.2, 0.0, 1.0)
	var base := _tamanho_que_cabe(titulo, 96, LARGURA_UTIL - 40.0)
	var tamanho := int(clampf(float(base) * escala, 20.0, 230.0))
	# Sem largura de caixa: durante a entrada o carimbo é MAIOR que a
	# tela de propósito, e uma caixa o cortaria em vez de deixá-lo passar.
	var medida := fonte.get_string_size(titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
	draw_string(
		fonte, Vector2((TELA.x - medida.x) * 0.5, 1468.0), titulo,
		HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, Color(cor.r, cor.g, cor.b, alpha)
	)

## Cabeçalho: só a marca do jogo e o modo. O estado da serial é assunto
## do técnico, e vive na Central Técnica — na tela do cliente ele vira,
## no máximo, um ponto âmbar quando há problema.
func _draw_header() -> void:
	draw_rect(Rect2(MARGEM, BANDA_TOPO, LARGURA_UTIL, 1.0), Color(0.3, 0.75, 1.0, 0.18))
	_texto("PUNCH", 92.0, 32, Color("f4f7ff"), HORIZONTAL_ALIGNMENT_LEFT, MARGEM)
	var largura_punch := fonte.get_string_size("PUNCH ", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	_texto("CHALLENGE", 92.0, 32, Color("55e7ff"), HORIZONTAL_ALIGNMENT_LEFT, MARGEM + largura_punch)
	if not _sensor_ligado() and link != null and link.available():
		draw_circle(Vector2(MARGEM + 500.0, 82.0), 8.0, Color("ffbd4a"))
	var mode_text := "MODO LIVRE" if game_mode == "free" else "MODO FICHA"
	_pill(Rect2(TELA.x - MARGEM - 176.0, 56.0, 176.0, 50.0), mode_text, Color("1b2b52"), Color("69e9ff"))

func _draw_cartoes() -> void:
	var largura := (LARGURA_UTIL - 2.0 * 16.0) / 3.0
	_stat_card(Rect2(MARGEM, CARTOES_Y, largura, CARTOES_ALTURA), "RECORDE", "%03d" % best_score, Color("58e8ff"), 1.0)
	_stat_card(Rect2(MARGEM + largura + 16.0, CARTOES_Y, largura, CARTOES_ALTURA), "PARTIDAS", str(plays), Color("a978ff"), 1.0)
	_stat_card(
		Rect2(MARGEM + (largura + 16.0) * 2.0, CARTOES_Y, largura, CARTOES_ALTURA),
		"CRÉDITOS", "∞" if game_mode == "free" else "%02d" % credits, Color("ff4c9b"), 1.0
	)

## Rodapé: a assinatura da casa. As teclas só aparecem quando o sensor
## NÃO está ligado — ou seja, na bancada de montagem. Com o Arduino no
## lugar, o cliente nunca vê instrução de teclado numa máquina de ficha.
func _draw_rodape(alpha: float) -> void:
	if notice != "":
		return
	if not _sensor_ligado():
		_texto(
			"BANCADA  •  ESPAÇO: START / GOLPE   C: CRÉDITO   F9: CENTRAL TÉCNICA",
			1812.0, 17, Color(0.36, 0.44, 0.60, alpha)
		)
	_texto("LAZER & SPORT BRINQUEDOS", RODAPE_Y, 16, Color(0.33, 0.40, 0.53, alpha))

# ---------------------------------------------------------------- central
func _draw_central() -> void:
	draw_rect(Rect2(Vector2.ZERO, TELA), Color(0.005, 0.009, 0.025, 0.97))
	_panel(Rect2(40, 96, 1000, 1790), Color("0d142c"), Color(0.22, 0.55, 0.95, 0.52))
	_texto("CENTRAL TÉCNICA", 196.0, 38, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT, 110.0)
	_texto("Configuração, diagnóstico e calibração", 234.0, 18, Color("7e90b8"), HORIZONTAL_ALIGNMENT_LEFT, 110.0)
	_botao(BOTOES_SIMPLES["fechar"], "×", false, Color("ff568f"), 32)

	# ---- modo de operação
	_secao(Rect2(80, 262, 920, 150), "MODO DE OPERAÇÃO")
	_botao(BOTOES_SIMPLES["modo_livre"], "LIVRE", game_mode == "free", Color("55e7ff"), 22)
	_botao(BOTOES_SIMPLES["modo_ficha"], "1 FICHA", game_mode == "credit", Color("ff4c9b"), 22)

	# ---- faixas do placar
	_secao(Rect2(80, 432, 920, 250), "FAIXAS DO PLACAR (0 – 999)")
	_regua_das_faixas(Rect2(110, 482, 860, 30))
	_stepper("limiar_fraco", "%03d" % limiar_fraco, "ATÉ AQUI É FRACO", Color("7c88a8"))
	_stepper("limiar_forte", "%03d" % limiar_forte, "DAQUI É FORTE", Color("ff2d55"))

	# ---- faixa de velocidade
	_secao(Rect2(80, 702, 920, 210), "VELOCIDADE QUE VIRA PONTO (m/s)")
	_stepper("vmin", "%.1f" % hit_min_speed, "MÍNIMA  =  0 PONTOS", Color("55e7ff"))
	_stepper("vmax", "%.1f" % hit_max_speed, "MÁXIMA  =  999 PONTOS", Color("55e7ff"))

	# ---- sensor e firmware
	_secao(Rect2(80, 932, 920, 330), "SENSOR E FIRMWARE (MPU-6050)")
	var dot := Color("4ff0a2") if _sensor_ligado() else Color("ffba46")
	draw_circle(Vector2(560, 968.0), 7.0, dot)
	_texto(serial_status, 974.0, 15, dot, HORIZONTAL_ALIGNMENT_LEFT, 578.0, 400.0)
	_stepper("porta", porta_configurada if not porta_configurada.is_empty() else "AUTO", "PORTA SERIAL", Color("55e7ff"))
	_botao(BOTOES_SIMPLES["eixo"], "EIXO  %s" % sensor_eixo, false, Color("b45cff"), 20)
	_texto("EIXO DO GOLPE", 1112.0, 15, Color("7e90b8"), HORIZONTAL_ALIGNMENT_CENTER, BOTOES_SIMPLES["eixo"].position.x, BOTOES_SIMPLES["eixo"].size.x)
	_stepper("raio", "%.2f m" % sensor_raio, "RAIO DO BRAÇO", Color("55e7ff"))
	_stepper("amin", "%.1f g" % sensor_amin, "SENSIBILIDADE", Color("55e7ff"))

	# ---- ações no firmware
	_secao(Rect2(80, 1282, 920, 190), "AÇÕES NO FIRMWARE")
	_botao(BOTOES_SIMPLES["enviar_config"], "ENVIAR CONFIG", false, Color("52f2a4"), 19)
	_botao(BOTOES_SIMPLES["testar"], "TESTAR SENSOR", false, Color("ffd23f"), 19)

	# ---- diagnóstico
	_secao(Rect2(80, 1492, 920, 230), "DIAGNÓSTICO")
	_texto(
		telemetria if telemetria != "" else "sem telemetria ainda",
		1566.0, 15, Color("7e90b8"), HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_texto(
		"recorde %03d  •  %d partidas  •  %02d créditos" % [best_score, plays, credits],
		1594.0, 15, Color("5f7099"), HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_botao(BOTOES_SIMPLES["zerar"], "ZERAR CONTADORES", false, Color("ff568f"), 17)
	_botao(BOTOES_SIMPLES["reconectar"], "RECONECTAR", false, Color("55e7ff"), 17)

	_botao(BOTOES_SIMPLES["padroes"], "RESTAURAR PADRÕES", false, Color("ffba46"), 19)
	_botao(BOTOES_SIMPLES["salvar"], "SALVAR E FECHAR", true, Color("52f2a4"), 21)
	_texto("Tecla T: golpe de teste  •  ESC: fechar sem sair da rodada", 1856.0, 15, Color("6a7ba3"))

## Uma seção da Central: moldura e título, sempre no mesmo lugar em
## relação à caixa. Nenhuma seção precisa saber onde fica o seu rótulo.
func _secao(rect: Rect2, titulo: String) -> void:
	_panel(rect, Color("111d3b"), Color(0.19, 0.42, 0.78, 0.4))
	_texto(titulo, rect.position.y + 40.0, 16, Color("8094bd"), HORIZONTAL_ALIGNMENT_LEFT, rect.position.x + 40.0, rect.size.x - 80.0)

## Um par − / + com o valor no meio e a legenda embaixo. Os retângulos
## saem de `PASSOS`, os mesmos que o clique consulta — texto e área de
## toque não têm como divergir.
func _stepper(chave: String, valor: String, legenda: String, accent: Color) -> void:
	var visor := _passo_visor(chave)
	_botao(_passo_menos(chave), "−", false, accent, 26)
	_botao(_passo_mais(chave), "+", false, accent, 26)
	_texto_cabendo(valor, visor.position.y + visor.size.y * 0.68, 30, Color("ffffff"), visor.size.x, visor.position.x)
	var r: Rect2 = PASSOS[chave]
	_texto(legenda, r.end.y + 28.0, 15, Color("7e90b8"), HORIZONTAL_ALIGNMENT_CENTER, r.position.x, r.size.x)

## A régua das três faixas, do jeito que o cliente vai ver no medidor.
## Mexer num limite muda esta barra na hora: o técnico regula olhando o
## resultado, não imaginando o resultado.
func _regua_das_faixas(rect: Rect2) -> void:
	var lim := GameDef.limiares(limiar_fraco, limiar_forte)
	var faixas := [
		[0.0, float(lim.x) / GameDef.SCORE_MAX, GameDef.COR_FRACA, "FRACO"],
		[float(lim.x) / GameDef.SCORE_MAX, float(lim.y) / GameDef.SCORE_MAX, GameDef.COR_MEDIA, "MÉDIO"],
		[float(lim.y) / GameDef.SCORE_MAX, 1.0, GameDef.COR_FORTE, "FORTE"],
	]
	for f in faixas:
		var x0 := rect.position.x + rect.size.x * float(f[0])
		var x1 := rect.position.x + rect.size.x * float(f[1])
		var cor: Color = f[2]
		draw_rect(Rect2(x0, rect.position.y, x1 - x0, rect.size.y), Color(cor.r, cor.g, cor.b, 0.55))
		if x1 - x0 > 90.0:
			_texto(str(f[3]), rect.position.y + rect.size.y * 0.72, 15, Color(0.03, 0.05, 0.1), HORIZONTAL_ALIGNMENT_CENTER, x0, x1 - x0)
	draw_rect(rect, Color(0.35, 0.55, 0.85, 0.5), false, 2.0)

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
		_texto_cabendo("LAZER & SPORT", centro.y, 64, Color(1, 1, 1, alpha), LARGURA_UTIL)

## O aviso de operação ocupa o rodapé, e não o topo: no topo ele cairia
## em cima do cabeçalho, e no meio disputaria com o número.
func _draw_notice() -> void:
	var caixa := Rect2(MARGEM + 60.0, 1800.0, LARGURA_UTIL - 120.0, 64.0)
	draw_rect(caixa, Color(0.02, 0.05, 0.12, 0.92))
	draw_rect(caixa, Color(0.35, 0.85, 1.0, 0.5), false, 2.0)
	_texto_cabendo(notice, caixa.position.y + 41.0, 20, Color("cfe6ff"), caixa.size.x - 40.0, caixa.position.x + 20.0)

func _panel(rect: Rect2, fundo_c: Color, borda: Color) -> void:
	draw_rect(rect, fundo_c)
	draw_rect(rect, borda, false, 2.0)

func _pill(rect: Rect2, texto: String, fundo_c: Color, frente: Color) -> void:
	draw_rect(rect, fundo_c)
	draw_rect(rect, Color(frente.r, frente.g, frente.b, 0.5), false, 2.0)
	_texto_cabendo(texto, rect.position.y + rect.size.y * 0.66, 17, frente, rect.size.x - 20.0, rect.position.x + 10.0)

func _botao(rect: Rect2, texto: String, ativo: bool, accent: Color, tamanho: int) -> void:
	var fundo_c := Color(accent.r, accent.g, accent.b, 0.22) if ativo else Color("131f3f")
	draw_rect(rect, fundo_c)
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.85 if ativo else 0.45), false, 2.0)
	_texto_cabendo(
		texto, rect.position.y + rect.size.y * 0.68, tamanho,
		Color("ffffff") if ativo else accent, rect.size.x - 20.0, rect.position.x + 10.0
	)

func _stat_card(rect: Rect2, rotulo: String, valor: String, accent: Color, alpha: float) -> void:
	_panel(rect, Color(0.04, 0.07, 0.16, 0.78 * alpha), Color(accent.r, accent.g, accent.b, 0.3 * alpha))
	_texto(rotulo, rect.position.y + 46.0, 16, Color(0.56, 0.63, 0.78, alpha), HORIZONTAL_ALIGNMENT_CENTER, rect.position.x, rect.size.x)
	_texto_cabendo(valor, rect.position.y + 104.0, 40, Color(accent.r, accent.g, accent.b, alpha), rect.size.x - 24.0, rect.position.x + 12.0)

# ---------------------------------------------------------------- texto
## Todo texto da tela passa por aqui. `y` é a LINHA DE BASE, que é como o
## Godot desenha — e é por isso que as bandas do topo do arquivo falam em
## linha de base e não em topo de caixa.
func _texto(
	texto: String, y: float, tamanho: int, cor: Color,
	alinhamento := HORIZONTAL_ALIGNMENT_CENTER, x := MARGEM, largura := LARGURA_UTIL
) -> void:
	draw_string(fonte, Vector2(x, y), texto, alinhamento, largura, tamanho, cor)

## O maior corpo, até `tamanho_max`, em que o texto ainda cabe na
## largura. Sem isso, "PESO-PESADO" a 96 px sai pelos dois lados da tela
## e "FRACO!" fica pequeno demais no mesmo lugar.
func _tamanho_que_cabe(texto: String, tamanho_max: int, largura: float) -> int:
	var tamanho := tamanho_max
	while tamanho > 10:
		if fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho).x <= largura:
			break
		tamanho -= 2
	return tamanho

func _texto_cabendo(texto: String, y: float, tamanho_max: int, cor: Color, largura: float, x := MARGEM) -> void:
	draw_string(
		fonte, Vector2(x, y), texto, HORIZONTAL_ALIGNMENT_CENTER, largura,
		_tamanho_que_cabe(texto, tamanho_max, largura), cor
	)
