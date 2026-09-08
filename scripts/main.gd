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
## mais tempo segura, mais forte o soco (ScoreCurve.points_from_charge).

const TELA := Vector2(1080.0, 1920.0)
const ArcadeStage = preload("res://scripts/presentation/arcade_stage.gd")

# ======================================================================
# AS BANDAS DA TELA
# ======================================================================
## Cabeçalho: marca do jogo e modo de operação.
const BANDA_TOPO := 150.0
## Palco: o saco e o medidor. Nada de texto entra aqui.
const PALCO_TOPO := 162.0
const PALCO_BASE := 1032.0
## O MEDALHÃO: o visor da máquina. Uma máquina de fliperama tem UM
## painel de placar, e é ele que a pessoa olha em todo momento do jogo —
## na contagem, na carga, no impacto e no resultado. Por isso o medalhão
## não é "a tela do resultado": é o visor, e cada estado só troca o que
## está escrito dentro dele.
const MEDALHAO_CENTRO := Vector2(540.0, 1245.0)
const MEDALHAO_RAIO := 186.0
## Leitura: o veredito e o convite, embaixo do visor.
const LEITURA_TOPO := 1450.0
const LEITURA_BASE := 1600.0
## Cartões de recorde/partidas/créditos.
const CARTOES_Y := 1622.0
const CARTOES_ALTURA := 122.0
## Rodapé: assinatura da casa e, só na bancada, as teclas de teste.
const RODAPE_Y := 1876.0
## Margem lateral livre de moldura de LED.
const MARGEM := 60.0
const LARGURA_UTIL := TELA.x - MARGEM * 2.0

## As cores que voam. Saem da paleta porque confete branco, que num
## fundo preto era o mais vistoso, é justamente o que some num fundo claro.
const CORES_FESTA := Paleta.FESTA

## Quantas marcas a máquina guarda.
const RANKING_TAMANHO := 20

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
## NENHUM RETÂNGULO PODE ENCOSTAR NO OUTRO.
##
## `curva` foi acrescentada em cima de `vmin` e `vmax` (x 340–740 contra
## 110–510 e 570–970, todos na mesma altura). Como `_click_central`
## percorre esta tabela em ordem, o clique no γ caía primeiro em `vmin`
## ou `vmax`: mexer na dificuldade mudava a velocidade, e a tela inteira
## parecia não responder. Cada passo tem agora a sua própria linha.
const PASSOS := {
	"limiar_fraco": Rect2(110, 522, 400, LADO_BOTAO),
	"limiar_forte": Rect2(570, 522, 400, LADO_BOTAO),
	"vmin": Rect2(110, 740, 400, LADO_BOTAO),
	"vmax": Rect2(570, 740, 400, LADO_BOTAO),
	"curva": Rect2(340, 856, 400, 58),
	"porta": Rect2(110, 1036, 400, LADO_BOTAO),
	"raio": Rect2(110, 1150, 400, LADO_BOTAO),
	"amin": Rect2(570, 1150, 400, LADO_BOTAO),
}
## Botões simples: chave -> retângulo.
const BOTOES_SIMPLES := {
	"fechar": Rect2(920, 140, 68, 64),
	"modo_livre": Rect2(110, 318, 400, 68),
	"modo_ficha": Rect2(570, 318, 400, 68),
	"eixo": Rect2(620, 1036, 280, LADO_BOTAO),
	# A câmera ganhou seção própria: estava dentro de "AÇÕES NO
	# FIRMWARE", que é do sensor de soco e não tem nada com webcam.
	"camera": Rect2(110, 1322, 260, 60),
	"trocar_camera": Rect2(390, 1322, 260, 60),
	"foto_teste": Rect2(670, 1322, 300, 60),
	"enviar_config": Rect2(110, 1484, 400, 60),
	"testar": Rect2(570, 1484, 400, 60),
	"zerar": Rect2(110, 1716, 207, 60),
	"zerar_stats": Rect2(327, 1716, 207, 60),
	"zerar_ranking": Rect2(544, 1716, 207, 60),
	"reconectar": Rect2(761, 1716, 209, 60),
	"padroes": Rect2(110, 1782, 400, 68),
	"salvar": Rect2(570, 1782, 400, 68),
}

var state: GameDef.State = GameDef.State.IDLE
var central_aberta := false
var game_mode := "credit"
var credits := 0
var plays := 0
## AS CINCO MELHORES MARCAS, em ordem decrescente.
##
## Guardar cinco em vez de uma só não é enfeite: com um recorde único,
## quem não bate o recorde não ganha nada, e o recorde de uma máquina
## movimentada fica inalcançável em uma semana. Com uma lista, entrar em
## quinto ainda é entrar — e é essa pequena vitória que faz a pessoa
## pagar a segunda ficha.
var ranking: Array[Dictionary] = []
## Faixa de velocidade (m/s) que vira pontos no placar.
var hit_min_speed := 0.8
var hit_max_speed := 12.0
## Expoente 2 torna os pontos altos raros; o valor anterior (0.8)
## inflava os golpes médios e fazia a máquina parecer fácil demais.
var score_exponent := ScoreCurve.DEFAULT_EXPONENT
var score_dead_zone := ScoreCurve.DEFAULT_DEAD_ZONE
## Os dois limites que separam fraco, médio e forte no placar.
var limiar_fraco := GameDef.LIMIAR_FRACO_PADRAO
var limiar_forte := GameDef.LIMIAR_FORTE_PADRAO
## Configuração enviada ao firmware (CONFIG,eixo,raio,vmin,amin).
var sensor_eixo := "X"
var sensor_raio := 0.45
var sensor_vmin := 0.8
var sensor_amin := 3.5
## Porta serial configurada; "" = automática (primeira disponível).
var porta_configurada := ""

var countdown_left := 3.0
var last_count := 3
var armed_left := GameDef.JANELA_DO_SOCO
var result_score := 0
var result_speed := 0.0
var result_simulado := false
## Posição conquistada no ranking (1 a 5), ou 0 se o golpe não entrou.
var posicao_no_ranking := 0
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
var confirm_action := ""
var confirm_until := 0.0

## Carga da simulação: >= 0 enquanto a barra de espaço está pressionada.
var carga_tempo := -1.0
## Quanto a carga VALE agora, em pontos. É o mesmo número que
## `ScoreCurve.points_from_charge` vai devolver se a barra for solta neste
## instante — o visor não mostra "quanto tempo você segurou", mostra o
## placar que você leva.
var carga_pontos := 0

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

## Câmera e dados locais do proprietário. Nenhum deles depende da rede.
var camera_service: CameraService
var camera_enabled := true
var camera_mirrored := true
var statistics: Dictionary = {}
var result_photo_path := ""
var pose_finished := false
var photo_retained := false
var ranking_announced := false
var intro_active := true
var intro_time := 0.0
## O QUANTO A ABERTURA JÁ CHEGOU, de 0 a 1.
##
## A entrada termina pousando o emblema e o letreiro exatamente onde a
## abertura os desenha, e por isso esses dois não podem esmaecer de novo.
## Mas o resto da abertura — o cabeçalho, o convite, os créditos — não
## existe na entrada e apareceria de um quadro para o outro. Este número
## faz só essa mobília entrar suave, sem tocar no que já estava na tela.
var abertura_chegada := 1.0
var _photo_cache: Dictionary = {}

var fx := PunchFX.new()
## Deslocamento do tremor no quadro atual. Fica guardado porque o texto
## curvo troca a transformação do canvas e precisa devolvê-la exatamente
## como estava — senão o tremor some do resto da tela a partir dali.
var _deslocamento := Vector2.ZERO
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
	camera_service = CameraService.new()
	camera_service.enabled = camera_enabled
	camera_service.mirrored = camera_mirrored
	add_child(camera_service)
	_aplicar_faixas()
	_iniciar_serial()
	_entrar_em_abertura()
	# A música entra baixa por baixo da entrada e sobe na virada para a
	# abertura: a trilha crescendo é o que faz a entrada terminar em vez
	# de simplesmente parar. As deixas da entrada tocam por cima.
	sons.music(-30.0)
	set_process(true)

func _exit_tree() -> void:
	if link != null:
		link.close_port()
	_photo_cache.clear()

## Um lugar só onde as faixas chegam a quem as desenha. Régua do medidor,
## cor da moldura e veredito passam a concordar por construção.
func _aplicar_faixas() -> void:
	var lim := GameDef.limiares(limiar_fraco, limiar_forte)
	limiar_fraco = lim.x
	limiar_forte = lim.y
	medidor.set_faixas(limiar_fraco, limiar_forte)
	medidor.recorde = _melhor()

## A melhor marca da casa. Sai do topo do ranking, e não de uma variável
## paralela — duas fontes para o mesmo número é como elas divergem.
func _melhor() -> int:
	return RankingStore.best(ranking)

## Insere uma pontuação e devolve a posição conquistada (1 a 5), ou 0 se
## ela não foi boa o bastante para entrar na lista.
func _entrar_no_ranking(pontos: int, foto := "", origem := "SENSOR") -> int:
	var inserted := RankingStore.insert(ranking, pontos, foto, origem)
	ranking.assign(inserted["entries"])
	for path in inserted["dropped_photos"]:
		RankingStore.delete_photo(path)
	return int(inserted["position"])

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
	if not confirm_action.is_empty() and animation_time > confirm_until:
		confirm_action = ""

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
	if intro_active:
		var antes := intro_time
		intro_time += delta
		# As deixas sonoras vêm da mesma tabela que desenha a entrada.
		# Ler o intervalo (antes, agora] em vez de "passou de" é o que
		# impede uma deixa de sumir num quadro longo ou tocar duas vezes.
		for marca in ArcadeStage.intro_cues(antes, intro_time):
			sons.play(marca["cue"], marca["db"])
		# O soco da entrada sacode a máquina e cospe faíscas de verdade,
		# com o mesmo sistema do soco do jogador: uma entrada que promete
		# um impacto tem de entregar o impacto.
		if antes < ArcadeStage.T_SOCO and intro_time >= ArcadeStage.T_SOCO:
			tremor = 34.0
			clarao = 0.60
			fx.faiscas(ArcadeStage.SOCO, 26, Paleta.AMBAR, 1250.0)
			fx.onda(ArcadeStage.SOCO, 60.0, 620.0, Paleta.CREME, 12.0, 0.55)
			fx.poeira(ArcadeStage.SOCO + Vector2(0.0, 180.0), 14, Color(Paleta.AMBAR, 0.35), 380.0)
		if antes < ArcadeStage.T_MORPH and intro_time >= ArcadeStage.T_MORPH:
			sons.music(-16.0)
		if intro_time >= ArcadeStage.INTRO_SECONDS:
			intro_active = false
			# A abertura ENTRA JÁ NO AR, e não esmaecendo do zero. A
			# entrada acaba de pousar o emblema e o letreiro exatamente
			# onde a abertura os desenha; se ela ainda por cima começasse
			# com o seu próprio esmaecer, o quadro seguinte à entrada
			# seria um piscar — a única emenda visível do filme.
			state_time = 0.7
			abertura_chegada = 0.0
		return
	abertura_chegada = minf(1.0, abertura_chegada + delta * 2.2)
	if randf() < delta * 4.0:
		fx.poeira(
			Vector2(randf_range(120.0, 960.0), TELA.y + 40.0),
			1, Color(Paleta.AMBAR, 0.30), 120.0
		)

func _processar_contagem(delta: float) -> void:
	countdown_left -= delta
	if not pose_finished and countdown_left <= 0.0:
		pose_finished = true
		result_photo_path = camera_service.capture_photo() if camera_service != null else ""
		if not result_photo_path.is_empty():
			_photo_texture(result_photo_path)
		clarao = 0.65
		sons.play("shutter", -5.0)
		return
	var atual := maxi(0, int(ceil(countdown_left)))
	if atual > 0 and atual < last_count:
		last_count = atual
		sons.play("count")
	if countdown_left <= -1.2:
		state = GameDef.State.ARMED
		state_time = 0.0
		armed_left = GameDef.JANELA_DO_SOCO
		carga_tempo = -1.0
		sons.play("go")
		sons.music(-19.0)
		moldura.set_estado(LedFrame.ARMADA)
		saco.set_alvo(true)

func _processar_armado(delta: float) -> void:
	armed_left -= delta
	if carga_tempo >= 0.0:
		# Simulação carregando. O MEDIDOR RECEBE O VALOR EXATO, não a
		# fração do tempo: a conversão tempo → pontos é uma curva, então
		# uma barra proporcional ao tempo mostraria 60 % quando o golpe
		# valeria 640. Quem carrega vê o número que vai tirar.
		carga_tempo = minf(carga_tempo + delta, ScoreCurve.CHARGE_MAX_SECONDS)
		carga_pontos = ScoreCurve.points_from_charge(
			carga_tempo, hit_min_speed, hit_max_speed, score_exponent, score_dead_zone
		)
		medidor.set_carga(float(carga_pontos) / float(GameDef.SCORE_MAX))
		# O saco, esse sim, tensiona conforme o tempo: é o gesto de tomar
		# distância, e não a nota.
		saco.set_carga(carga_tempo / ScoreCurve.CHARGE_MAX_SECONDS)
	if armed_left <= 0.0:
		# A janela fechou sem soco. Precisa de som: uma rodada que acaba
		# em silêncio deixa a pessoa achando que a máquina travou, e ela
		# fica esperando em vez de apertar START de novo.
		_cancelar_carga()
		sons.play("error", -4.0)
		_entrar_em_abertura()
		_show_notice("TEMPO ESGOTADO — PRESSIONE START")

func _entrar_em_resultado() -> void:
	sons.start_score_loop()
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

	sons.score_progress(avanco)

	if verdict_time < 0.0 and avanco >= 1.0:
		_disparar_veredito()
	elif verdict_time >= 0.0:
		verdict_time += delta
		_manter_festa(delta)
		if verdict_time >= 2.5 and not ranking_announced:
			ranking_announced = true
			sons.play("ranking", -5.0)
			sons.music(-24.0)

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
				fx.onda(_alvo(), 90.0, 450.0, Color(Paleta.AMBAR, 0.45), 7.0, 0.85)
		_:
			if verdict_time < 2.2 and randf() < delta * 9.0:
				fx.estilhacos(Vector2(randf_range(180.0, 900.0), 420.0), 2, Color("6b7b98"))

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
	# A MESMA conta que o visor vinha mostrando. Um segundo caminho aqui
	# faria o número prometido e o número pago divergirem.
	var velocidade := ScoreCurve.speed_from_charge(tempo_carga, hit_min_speed, hit_max_speed)
	_processar_golpe(velocidade, true)

func _cancelar_carga() -> void:
	if carga_tempo >= 0.0:
		sons.stop("charge")
	carga_tempo = -1.0
	carga_pontos = 0
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
	_discard_round_photo()
	intro_active = false
	sons.stop("score_loop")
	state = GameDef.State.COUNTDOWN
	posicao_no_ranking = 0
	saco.visible = false
	medidor.visible = false
	state_time = 0.0
	countdown_left = 3.0
	last_count = 3
	result_score = 0
	result_photo_path = ""
	pose_finished = false
	photo_retained = false
	ranking_announced = false
	displayed_score = 0.0
	fx.limpar()
	medidor.reset()
	medidor.recorde = _melhor()
	clarao = 1.0
	tremor = 14.0
	sons.play("start")
	sons.music(-24.0)
	moldura.set_estado(LedFrame.CONTAGEM)
	fundo.matiz = Color(0, 0, 0, 0)
	_salvar()

func _entrar_em_abertura() -> void:
	_discard_round_photo()
	abertura_chegada = 1.0
	# Corta os efeitos da rodada e deixa a música da abertura no ar. Antes
	# aqui era `silence()`, que também matava a música: a tela que fica
	# ligada o dia inteiro chamando gente era a única muda do jogo.
	sons.attract(-16.0)
	state = GameDef.State.IDLE
	state_time = 0.0
	verdict_time = -1.0
	result_time = 0.0
	posicao_no_ranking = 0
	result_photo_path = ""
	_photo_cache.clear()
	fx.limpar()
	medidor.reset()
	saco.visible = false
	medidor.visible = false
	saco.set_alvo(false)
	saco.set_carga(-1.0)
	moldura.set_estado(LedFrame.PARADA)
	fundo.matiz = Color(0, 0, 0, 0)

func _discard_round_photo() -> void:
	if not photo_retained and not result_photo_path.is_empty():
		RankingStore.delete_photo(result_photo_path)
	result_photo_path = ""
	photo_retained = false

func _add_credit() -> void:
	credits = mini(credits + 1, GameDef.CREDITOS_MAX)
	sons.play("credit")
	fx.faiscas(Vector2(540, 1300), 22, Paleta.VERDE, 420.0)
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
	sons.stop("charge")
	sons.music(-32.0)
	tremor = 10.0 + forca * 22.0
	clarao = 0.25 + forca * 0.45
	fx.onda(alvo, 30.0, 500.0 + forca * 400.0, Color(Paleta.VERMELHO, 0.6), 16.0, 0.7)
	fx.faiscas(alvo, 30 + int(forca * 50.0), Paleta.AMBAR, 700.0 + forca * 600.0)
	plays += 1
	var origem := "SIMULAÇÃO" if simulado else "MPU-6050"
	posicao_no_ranking = _entrar_no_ranking(result_score, result_photo_path, origem)
	photo_retained = posicao_no_ranking > 0
	statistics = StatisticsStore.record(
		statistics, result_score,
		GameDef.faixa_de(result_score, limiar_fraco, limiar_forte),
		posicao_no_ranking > 0
	)
	medidor.recorde = _melhor()
	_salvar()

func _disparar_veredito() -> void:
	sons.stop("score_loop")
	sons.music(-28.0)
	## O momento em que a máquina diz quanto valeu o soco. Um por golpe.
	verdict_time = 0.0
	proximo_fogo = 0.0
	var classe := GameDef.classificar(result_score, limiar_fraco, limiar_forte)
	var cor: Color = classe["cor_faixa"]
	moldura.set_estado(LedFrame.RESULTADO, cor)
	# A tela inteira toma a cor da faixa, de leve: o veredito chega ao
	# canto do olho antes de a pessoa terminar de ler a palavra.
	fundo.matiz = Color(cor, 0.10)
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
			fx.onda(alvo, 60.0, 1100.0, Color(Paleta.AMBAR, 0.6), 18.0, 1.0)
		GameDef.Faixa.MEDIA:
			sons.play("medium")
			tremor = 14.0
			fx.faiscas(alvo, 46, Paleta.AMBAR, 700.0)
			fx.onda(alvo, 60.0, 560.0, Color(Paleta.AMBAR, 0.55), 12.0, 0.9)
		_:
			sons.play("lose")
			tremor = 9.0
			fx.estilhacos(alvo, 34, Color("6b7b98"))
			fx.poeira(alvo + Vector2(0, 240.0), 26, Color(0.45, 0.50, 0.62, 0.45), 260.0)

	if posicao_no_ranking == 1:
		for sound in ["win", "medium", "lose", "legendary"]:
			sons.stop(sound)
		sons.play("record", -2.0)

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
	_processar_golpe(speed, false)

## Sensor e teclado passam obrigatoriamente por esta única porta. Assim a
## régua mostrada na Central é a mesma que decide o resultado real.
func _processar_golpe(speed: float, simulado: bool) -> void:
	var pontos := ScoreCurve.points_from_speed(
		speed, hit_min_speed, hit_max_speed, score_exponent, score_dead_zone
	)
	if pontos <= 0:
		_show_notice("MOVIMENTO ABAIXO DA ZONA DE PONTUAÇÃO")
		return
	_registrar_impacto(pontos, speed, simulado)

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
		sons.silence()
		if link != null and link.available():
			portas_visiveis = link.list_ports()
		sons.play("menu", -4.0)

func _fechar_central() -> void:
	central_aberta = false
	if state == GameDef.State.RESULT:
		sons.music(-28.0)
		if verdict_time < 0.0:
			sons.start_score_loop()
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
	elif BOTOES_SIMPLES["camera"].has_point(p):
		camera_enabled = not camera_enabled
		camera_service.set_enabled(camera_enabled)
		_show_notice(camera_service.status)
	elif BOTOES_SIMPLES["trocar_camera"].has_point(p):
		camera_service.cycle_camera()
		_show_notice(camera_service.status)
	elif BOTOES_SIMPLES["foto_teste"].has_point(p):
		var test_path := camera_service.capture_photo()
		if test_path.is_empty():
			_show_notice(camera_service.status)
		else:
			RankingStore.delete_photo(test_path)
			_show_notice("CAPTURA DA CÂMERA APROVADA")
	elif BOTOES_SIMPLES["zerar"].has_point(p):
		if not _confirmar("contadores"):
			return
		credits = 0
		plays = 0
		_show_notice("CONTADORES ZERADOS")
	elif BOTOES_SIMPLES["zerar_stats"].has_point(p):
		if not _confirmar("estatisticas"):
			return
		statistics = {}
		_show_notice("ESTATÍSTICAS ZERADAS")
	elif BOTOES_SIMPLES["zerar_ranking"].has_point(p):
		if not _confirmar("ranking"):
			return
		RankingStore.clear_photos(ranking)
		ranking.clear()
		_photo_cache.clear()
		medidor.recorde = 0
		_show_notice("RANKING E FOTOS ZERADOS")
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
		score_exponent = ScoreCurve.DEFAULT_EXPONENT
		score_dead_zone = ScoreCurve.DEFAULT_DEAD_ZONE
		limiar_fraco = GameDef.LIMIAR_FRACO_PADRAO
		limiar_forte = GameDef.LIMIAR_FORTE_PADRAO
		sensor_eixo = "X"
		sensor_raio = 0.45
		sensor_vmin = 0.8
		sensor_amin = 3.5
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
		"curva":
			score_exponent = clampf(score_exponent + direcao * 0.05, ScoreCurve.EXPONENT_MIN, ScoreCurve.EXPONENT_MAX)
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

func _confirmar(action: String) -> bool:
	if confirm_action == action and animation_time <= confirm_until:
		confirm_action = ""
		return true
	confirm_action = action
	confirm_until = animation_time + 4.0
	_show_notice("CONFIRME: CLIQUE NOVAMENTE EM ATÉ 4 SEGUNDOS")
	return false

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
	# MIGRAÇÃO: instalações antigas guardavam um recorde só. Ele vira a
	# primeira linha do ranking, para o dono não perder a marca da casa
	# ao atualizar o software.
	var antigo := int(data.get("best_score", 0))
	ranking = RankingStore.migrate(data.get("ranking", []), antigo)
	porta_configurada = str(data.get("port", porta_configurada))
	hit_min_speed = float(data.get("hit_min_speed", hit_min_speed))
	hit_max_speed = float(data.get("hit_max_speed", hit_max_speed))
	score_exponent = float(data.get("score_exponent", score_exponent))
	score_dead_zone = float(data.get("score_dead_zone", score_dead_zone))
	limiar_fraco = int(data.get("limiar_fraco", limiar_fraco))
	limiar_forte = int(data.get("limiar_forte", limiar_forte))
	sensor_eixo = str(data.get("sensor_eixo", sensor_eixo))
	sensor_raio = float(data.get("sensor_raio", sensor_raio))
	sensor_vmin = float(data.get("sensor_vmin", sensor_vmin))
	sensor_amin = float(data.get("sensor_amin", sensor_amin))
	camera_enabled = bool(data.get("camera_enabled", camera_enabled))
	camera_mirrored = bool(data.get("camera_mirrored", camera_mirrored))
	statistics = StatisticsStore.sanitize(data.get("statistics", {}))

func _salvar() -> void:
	SettingsStore.save_data({
		"mode": game_mode,
		"credits": credits,
		"plays": plays,
		"ranking": ranking,
		# Mantido para uma eventual volta a uma versão anterior do jogo.
		"best_score": _melhor(),
		"port": porta_configurada,
		"hit_min_speed": hit_min_speed,
		"hit_max_speed": hit_max_speed,
		"score_exponent": score_exponent,
		"score_dead_zone": score_dead_zone,
		"limiar_fraco": limiar_fraco,
		"limiar_forte": limiar_forte,
		"sensor_eixo": sensor_eixo,
		"sensor_raio": sensor_raio,
		"sensor_vmin": sensor_vmin,
		"sensor_amin": sensor_amin,
		"camera_enabled": camera_enabled,
		"camera_mirrored": camera_mirrored,
		"statistics": statistics,
	})

# ======================================================================
# DESENHO
# ======================================================================
func _draw() -> void:
	# O PALCO APARECE NA JANELA DO SOCO, E SÓ NELA. É o único momento em
	# que a pessoa está olhando para o saco de verdade; na pose quem manda
	# é a câmera, e no resultado é o anel do placar — os três disputariam
	# o mesmo espaço se ficassem juntos.
	var no_palco := state == GameDef.State.ARMED and not central_aberta
	fundo.visible = true
	moldura.visible = false
	saco.visible = no_palco
	medidor.visible = no_palco
	# O TREMOR SACODE A TELA INTEIRA: um deslocamento só, antes de tudo.
	_deslocamento = Vector2.ZERO
	if tremor > 0.1:
		_deslocamento = Vector2(randf_range(-tremor, tremor), randf_range(-tremor, tremor))
		draw_set_transform(_deslocamento, 0.0, Vector2.ONE)

	if state == GameDef.State.IDLE:
		if intro_active:
			ArcadeStage.intro(self, intro_time)
		else:
			_draw_show_idle()
	elif state == GameDef.State.RESULT and verdict_time >= 2.5:
		_draw_ranking_reveal()
	else:
		_draw_partida()

	fx.desenhar(self)
	_draw_clarao()

	if notice != "" and not central_aberta:
		_draw_notice()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if central_aberta:
		_draw_central()

## O CLARÃO DO SOCO NUM FUNDO CLARO. Lavar a tela de branco não funciona
## aqui — branco sobre quase-branco não é clarão, é nada. O golpe acende
## em ÂMBAR e escurece as bordas ao mesmo tempo: é o contraste que o olho
## lê como flash, não o brilho absoluto.
func _draw_clarao() -> void:
	if clarao <= 0.01:
		return
	draw_rect(Rect2(Vector2.ZERO, TELA), Color(Paleta.LUZ, clarao * 0.70))
	var borda := 150.0 * clarao
	var escuro := Color(Paleta.MARINHO, clarao * 0.30)
	draw_rect(Rect2(0.0, 0.0, TELA.x, borda), escuro)
	draw_rect(Rect2(0.0, TELA.y - borda, TELA.x, borda), escuro)
	draw_rect(Rect2(0.0, 0.0, borda, TELA.y), escuro)
	draw_rect(Rect2(TELA.x - borda, 0.0, borda, TELA.y), escuro)
	# Dois ecos deslocados por poucos pixels criam a separação cromática
	# curta do impacto sem exigir shader ou deixar o placar ilegível.
	if clarao > 0.18 and state == GameDef.State.MEASURING:
		var alvo := _alvo()
		var raio := 100.0 + (1.0 - clarao) * 120.0
		draw_arc(alvo + Vector2(-9.0, 0.0), raio, 0.0, TAU, 72, Color(Paleta.CIANO, clarao * 0.65), 7.0, true)
		draw_arc(alvo + Vector2(9.0, 0.0), raio, 0.0, TAU, 72, Color(Paleta.VERMELHO, clarao * 0.60), 7.0, true)

# ---------------------------------------------------------------- abertura
## A ABERTURA NÃO É UMA TELA SÓ.
##
## Uma máquina de fliperama parada não fica repetindo o mesmo cartaz: ela
## conta o jogo em capítulos, e é o rodízio que segura quem está passando
## no corredor por tempo suficiente para a pessoa decidir jogar. Três
## páginas alternando sozinhas — a marca, os melhores da casa e como
## jogar — e, fixos em todas, o convite e os números da máquina, porque
## esses dois não podem depender de a pessoa ter chegado na página certa.
const ABERTURA_PAGINAS := 4
const ABERTURA_SEGUNDOS := 7.0

func _pagina_da_abertura() -> int:
	return int(state_time / ABERTURA_SEGUNDOS) % ABERTURA_PAGINAS

func _draw_abertura() -> void:
	# Cada página entra com o seu próprio esmaecer, e não o da rodada:
	# senão só a primeira apareceria com entrada e as outras dariam um
	# salto seco.
	var no_ar := fmod(state_time, ABERTURA_SEGUNDOS)
	var suave := ease(clampf(no_ar / 0.55, 0.0, 1.0), 0.35)
	var pagina := _pagina_da_abertura()

	_fundo_da_abertura(suave)
	match pagina:
		0:
			_pagina_marca(suave)
		1:
			_pagina_recordes(suave)
		2:
			_pagina_como_jogar(suave)
		_:
			_pagina_camera(suave)

	_draw_convite(suave)
	_pontinhos_da_pagina(pagina, suave)
	_draw_placar_abertura(suave)
	_draw_rodape(suave)

## Raios e anéis girando atrás de qualquer página. Num fundo claro eles
## são MAIS ESCUROS que o céu, não mais claros — a leitura é a mesma, a
## conta é a inversa.
func _fundo_da_abertura(alpha: float) -> void:
	var centro := Vector2(540, 620)
	for i in range(16):
		var angulo := animation_time * 0.22 + i * TAU / 16.0
		var comprimento := 1000.0 + sin(animation_time * 1.4 + i) * 50.0
		var cor := Color(Paleta.CIANO, 0.055 * alpha)
		if i % 2 == 0:
			cor = Color(Paleta.VERMELHO, 0.045 * alpha)
		draw_colored_polygon(
			PackedVector2Array([
				centro,
				centro + Vector2(cos(angulo - 0.055), sin(angulo - 0.055)) * comprimento,
				centro + Vector2(cos(angulo + 0.055), sin(angulo + 0.055)) * comprimento,
			]),
			cor
		)
	for i in range(3):
		var raio := 320.0 + i * 84.0 + sin(animation_time * 1.1 + i * 0.7) * 14.0
		draw_arc(centro, raio * alpha, 0.0, TAU, 120, Color(Paleta.MARINHO, 0.08 * alpha), 2.0)

## Página 1 — a marca da casa e o recorde a bater.
func _pagina_marca(alpha: float) -> void:
	var flutuar := sin(animation_time * 1.6) * 12.0
	_draw_marca(Vector2(540, 470) + Vector2(0, flutuar), 690.0 * lerpf(0.9, 1.0, alpha), alpha)
	_texto_arcade("PUNCH CHALLENGE", 872.0, 86, Color(Paleta.VERMELHO, alpha), LARGURA_UTIL)
	_texto("QUAL É A FORÇA DO SEU SOCO?", 918.0, 27, Color(Paleta.MARINHO, alpha))
	_draw_medalhao("%03d" % _melhor(), Paleta.AMBAR, 1.0, alpha, Vector2(540, 1160), 122.0)
	_texto("RECORDE DA CASA  •  BATA ESSA MARCA", 1332.0, 22, Color(Paleta.TINTA_FRACA, alpha))

## Página 2 — as cinco melhores marcas.
func _pagina_recordes(alpha: float) -> void:
	_texto_arcade("TOP 20 • MELHORES", 392.0, 62, Color(Paleta.CIANO, alpha), LARGURA_UTIL)
	if ranking.is_empty():
		_texto("AINDA NINGUÉM SOCOU ESTA MÁQUINA", 780.0, 32, Color(Paleta.TINTA_FRACA, alpha))
		_texto("O PRIMEIRO NOME DA LISTA PODE SER O SEU", 832.0, 24, Color(Paleta.TINTA_LEVE, alpha))
		return
	var page := int(state_time / 16.0) % 4
	for row in range(5):
		var i := page * 5 + row
		var y := 466.0 + row * 116.0
		var cor := _cor_da_posicao(i + 1)
		var linha := Rect2(MARGEM + 40.0, y, LARGURA_UTIL - 80.0, 98.0)
		var vazia := i >= ranking.size()
		_cartao(linha, Paleta.CARTAO if not vazia else Paleta.VAZIO, Paleta.CARTAO_BORDA, alpha, 2.0)
		# Tarja lateral colorida: identifica a posição sem pintar a linha.
		draw_rect(Rect2(linha.position, Vector2(9.0, linha.size.y)), Color(cor, alpha))
		var meio := linha.position.y + 64.0
		_texto("%dº" % (i + 1), meio, 34, Color(cor, alpha), HORIZONTAL_ALIGNMENT_CENTER, linha.position.x + 30.0, 90.0)
		if i < 3:
			Icones.trofeu(self, Vector2(linha.position.x + 168.0, meio - 11.0), 19.0, Color(cor, alpha))
		if vazia:
			_texto("—", meio, 34, Color(Paleta.TINTA_LEVE, alpha), HORIZONTAL_ALIGNMENT_RIGHT, linha.position.x, linha.size.x - 40.0)
		else:
			_draw_player_photo(Rect2(linha.position + Vector2(210.0, 11.0), Vector2(76.0, 76.0)), str(ranking[i].get("photo_path", "")), alpha)
			_texto("%03d" % RankingStore.score_at(ranking, i), meio, 44, Color(Paleta.TINTA, alpha), HORIZONTAL_ALIGNMENT_RIGHT, linha.position.x, linha.size.x - 40.0)
			_texto("PONTOS", meio, 18, Color(Paleta.TINTA_LEVE, alpha), HORIZONTAL_ALIGNMENT_RIGHT, linha.position.x, linha.size.x - 190.0)
	_texto("POSIÇÕES %02d–%02d" % [page * 5 + 1, page * 5 + 5], 1152.0, 26, Color(Paleta.CIANO, alpha))

## Página 3 — os três passos, do tamanho de quem lê de longe.
func _pagina_como_jogar(alpha: float) -> void:
	_texto_arcade("COMO JOGAR", 392.0, 62, Color(Paleta.CIANO, alpha), LARGURA_UTIL)
	var passos := [
		["ficha", "INSIRA A FICHA" if game_mode == "credit" else "MÁQUINA LIBERADA", Paleta.ROSA],
		["botao", "APERTE START", Paleta.VERDE],
		["alvo", "SOQUE O ALVO COM FORÇA", Paleta.VERMELHO],
	]
	for i in range(passos.size()):
		var y := 428.0 + i * 236.0
		var cor: Color = passos[i][2]
		var centro := Vector2(MARGEM + 110.0, y + 60.0)
		draw_circle(centro, 62.0, Paleta.tinta_clara(cor, 0.20))
		draw_arc(centro, 62.0, 0.0, TAU, 60, Color(cor, 0.55 * alpha), 4.0)
		_icone(str(passos[i][0]), centro, 38.0, Color(Paleta.para_texto(cor), alpha))
		_texto(
			"%d." % (i + 1), centro.y - 4.0, 26, Color(cor, alpha),
			HORIZONTAL_ALIGNMENT_LEFT, MARGEM + 210.0, 80.0
		)
		# Alinhados à ESQUERDA e não centrados: três frases de comprimentos
		# diferentes, centradas cada uma na sua caixa, não formam uma
		# coluna — e é a coluna que faz a lista ser lida como três passos.
		var texto := str(passos[i][1])
		_texto(
			texto, centro.y + 14.0, _tamanho_que_cabe(texto, 44, LARGURA_UTIL - 340.0),
			Color(Paleta.TINTA, alpha), HORIZONTAL_ALIGNMENT_LEFT,
			MARGEM + 270.0, LARGURA_UTIL - 340.0
		)

## A câmera transforma uma tentativa em lembrança e dá rosto ao ranking.
## Sem webcam a mesma página vira demonstração com avatar, nunca erro.
func _pagina_camera(alpha: float) -> void:
	_texto_arcade("VOCÊ NO RANKING", 304.0, 60, Color(Paleta.MARINHO, alpha), LARGURA_UTIL)
	_draw_camera_card(Rect2(230.0, 360.0, 620.0, 700.0), alpha, "CÂMERA AO VIVO")
	_texto("DÊ O SEU MELHOR SOCO", 1132.0, 34, Color(Paleta.VERMELHO, alpha))
	_texto("SUA FOTO FICA AO LADO DA SUA MARCA NO TOP 5", 1186.0, 22, Color(Paleta.TINTA_FRACA, alpha))
	_texto("FOTOS SALVAS SOMENTE NESTA MÁQUINA", 1234.0, 17, Color(Paleta.TINTA_LEVE, alpha))

## O convite fica no MESMO lugar em todas as páginas. É o único elemento
## que a pessoa precisa achar sem procurar, e um botão que muda de lugar
## a cada sete segundos é um botão que ninguém acha.
func _draw_convite(alpha: float) -> void:
	var piscada := 0.6 + 0.4 * sin(animation_time * 4.2)
	var convite := "PRESSIONE  START"
	var cor := Paleta.VERDE
	if game_mode == "credit" and credits <= 0:
		convite = "INSIRA 1 FICHA"
		cor = Paleta.CIANO
	var caixa := Rect2(MARGEM + 80.0, 1400.0, LARGURA_UTIL - 160.0, 118.0)
	_placa(Rect2(caixa.position + Vector2(0.0, 7.0), caixa.size), 22.0, Color(Paleta.SOMBRA, alpha))
	_placa(caixa, 22.0, Color(cor.darkened(0.22), alpha))
	_placa(Rect2(caixa.position, caixa.size - Vector2(0.0, 7.0)), 22.0, Color(cor, alpha))
	_texto_arcade(convite, 1476.0, 46, Color(Paleta.CREME, alpha * piscada), caixa.size.x - 60.0, caixa.position.x + 30.0)

## Quantas páginas existem e em qual delas estamos. Sem isso o rodízio
## parece a tela trocando sozinha por defeito.
func _pontinhos_da_pagina(pagina: int, alpha: float) -> void:
	var largura := float(ABERTURA_PAGINAS) * 26.0
	var x := 540.0 - largura * 0.5 + 13.0
	for i in range(ABERTURA_PAGINAS):
		var atual := i == pagina
		draw_circle(Vector2(x + i * 26.0, 1560.0), 7.0 if atual else 5.0,
			Color(Paleta.MARINHO if atual else Paleta.TINTA_LEVE, alpha))

## Os quatro números da casa, numa fileira só, presentes em toda página.
func _draw_placar_abertura(alpha: float) -> void:
	var itens := [
		["RECORDE", "%03d" % _melhor(), Paleta.AMBAR, "trofeu"],
		["PARTIDAS", str(plays), Paleta.ROXO, "luva"],
		["CRÉDITOS", "∞" if game_mode == "free" else "%02d" % credits, Paleta.ROSA, "ficha"],
		["MODO", "LIVRE" if game_mode == "free" else "FICHA", Paleta.VERDE, "raio"],
	]
	var largura := (LARGURA_UTIL - 3.0 * 16.0) / 4.0
	for i in range(itens.size()):
		_stat_card(
			Rect2(MARGEM + i * (largura + 16.0), CARTOES_Y, largura, CARTOES_ALTURA),
			str(itens[i][0]), str(itens[i][1]), itens[i][2] as Color, str(itens[i][3]), alpha
		)

# ---------------------------------------------------------------- partida
## Todos os momentos da partida compartilham o mesmo visor. O que muda é
## o que está escrito nele, a cor do anel e quanto do anel está aceso.
func _draw_partida() -> void:
	_texto("PUNCH CHALLENGE", 145.0, 34, Color("ffffff"))
	match state:
		GameDef.State.COUNTDOWN:
			_texto_arcade("FAÇA SUA POSE", 340.0, 72, Paleta.CIANO, LARGURA_UTIL)
			var rect := Rect2(180, 470, 720, 720)
			_cartao(Rect2(170, 460, 740, 740), Color("330c16"), Paleta.CIANO, 1.0, 4.0)
			if pose_finished:
				_draw_player_photo(rect, result_photo_path, 1.0)
			elif camera_service != null and camera_service.available():
				_draw_texture_cover(camera_service.preview_texture(), rect, 1.0, camera_mirrored)
			else:
				_draw_avatar(rect, 1.0)
			if not pose_finished:
				_texto(str(clampi(int(ceil(countdown_left)), 1, 3)), 1400.0, 150, Color.WHITE)
				_texto("OLHE PARA A CÂMERA", 1510.0, 30, Paleta.CIANO)
			else:
				_texto("FOTO PRONTA" if not result_photo_path.is_empty() else "SEM CÂMERA • VAMOS JOGAR", 1390.0, 32, Paleta.CIANO)
				_texto("PREPARE O SOCO", 1500.0, 46, Color.WHITE)
		GameDef.State.ARMED:
			_draw_janela_do_soco()
		GameDef.State.MEASURING, GameDef.State.RESULT:
			_draw_score_hero()

## A JANELA DO SOCO. O saco e o medidor são desenhados pelos nós filhos,
## atrás desta camada; aqui entram só as letras, e elas ficam ABAIXO do
## palco de propósito — quem está com o punho erguido olha para o saco,
## não para o texto, e o texto que cobre o saco só atrapalha a mira.
func _draw_janela_do_soco() -> void:
	var carregando := carga_tempo >= 0.0
	var restante := clampf(armed_left / GameDef.JANELA_DO_SOCO, 0.0, 1.0)

	if carregando:
		# CARREGANDO: o número exato que sai se soltar agora, no mesmo
		# formato em que ele vai aparecer no resultado.
		var cor := GameDef.classificar(carga_pontos, limiar_fraco, limiar_forte)["cor_faixa"] as Color
		_texto_arcade("%03d" % carga_pontos, 1310.0, 128, cor, LARGURA_UTIL)
		_texto("PONTOS SE SOLTAR AGORA", 1362.0, 26, Color.WHITE)
		var piscada := 0.6 + 0.4 * sin(animation_time * 9.0)
		_texto_arcade("SOLTE!", 1452.0, 66, Color(Paleta.AMBAR, piscada), LARGURA_UTIL)
	else:
		_texto_arcade("SOQUE AGORA!", 1300.0, 104, Color.WHITE, LARGURA_UTIL)
		var dica := "ACERTE O ALVO COM FORÇA" if _sensor_ligado() \
			else "SEGURE E SOLTE ESPAÇO"
		_texto(dica, 1370.0, 28, Paleta.CIANO)

	# O relógio dos oito segundos: esvazia da direita e vira vermelho no
	# fim, sem número para ninguém precisar ler.
	var trilho := Rect2(220, 1470, 640, 16)
	draw_rect(trilho, Color("5c2530"))
	draw_rect(
		Rect2(trilho.position, Vector2(trilho.size.x * restante, trilho.size.y)),
		Paleta.CIANO if restante > 0.35 else Paleta.VERMELHO
	)
	draw_rect(trilho, Color(Paleta.AMBAR, 0.5), false, 2.0)

func _draw_show_background() -> void:
	ArcadeStage.background(self, animation_time)

## A ABERTURA GIRA EM TRÊS CAPÍTULOS.
##
## Uma máquina de fliperama parada não fica repetindo o mesmo cartaz: ela
## conta o jogo em partes, e é o rodízio que segura quem passa no
## corredor por tempo suficiente para decidir jogar. A marca, os melhores
## da casa e como jogar — e, FIXOS nos três, o convite e os créditos,
## porque um botão que muda de lugar a cada oito segundos é um botão que
## ninguém acha.
const ABERTURA_CAPITULOS := 3
const ABERTURA_DURACAO := 8.0

func _draw_show_idle() -> void:
	var chegada := ease(abertura_chegada, 0.4)
	_texto("LAZER & SPORT", 220.0, 28, Color(Paleta.CIANO, chegada))
	var capitulo := int(state_time / ABERTURA_DURACAO) % ABERTURA_CAPITULOS
	# Cada capítulo entra com o seu próprio esmaecer; sem isso só o
	# primeiro teria entrada e os outros dariam um salto seco.
	var entrada := ease(clampf(fmod(state_time, ABERTURA_DURACAO) / 0.5, 0.0, 1.0), 0.35)
	match capitulo:
		1:
			_pagina_recordes(entrada)
		2:
			_pagina_como_jogar(entrada)
		_:
			_capitulo_da_marca(entrada)
	_pontos_do_capitulo(capitulo, chegada)
	var pulse := 0.8 + 0.2 * sin(animation_time * 2.6)
	_cartao(Rect2(140, 1560, 800, 112), Color("d9122d"), Color(Paleta.AMBAR, pulse), chegada, 3.0)
	_texto("PRESSIONE START", 1635.0, 46, Color(Color.WHITE, chegada))
	_texto(
		"JOGO LIVRE" if game_mode == "free" else "CRÉDITOS  %02d" % credits,
		1740.0, 26, Color(Paleta.CIANO, chegada)
	)
	# CARIMBO DA BUILD. Discreto, mas na tela que fica ligada o dia
	# inteiro: é ele que responde "atualizei e não mudou nada" sem
	# ninguém precisar abrir terminal.
	_texto(Versao.curta(), 1876.0, 15, Color(1, 1, 1, 0.55 * chegada))

func _capitulo_da_marca(alpha: float) -> void:
	ArcadeStage.emblem(self, Vector2(540, 560 + sin(animation_time * 1.4) * 8), 440.0, alpha)
	_texto_arcade("PUNCH", 910.0, 144, Color(Color.WHITE, alpha), LARGURA_UTIL)
	_texto_arcade("CHALLENGE", 1010.0, 80, Color(Paleta.AMBAR, alpha), LARGURA_UTIL)
	_texto("QUAL É A SUA FORÇA?", 1120.0, 32, Color(Color.WHITE, alpha))
	_texto("RECORDE DA CASA", 1270.0, 24, Color(Color("d8b6a6"), alpha))
	_texto("%03d" % _melhor(), 1400.0, 98, Color(Paleta.AMBAR, alpha))

## Quantos capítulos existem e em qual estamos. Sem isso o rodízio parece
## a tela trocando sozinha por defeito.
func _pontos_do_capitulo(capitulo: int, alpha := 1.0) -> void:
	var largura := float(ABERTURA_CAPITULOS) * 30.0
	for i in range(ABERTURA_CAPITULOS):
		var atual := i == capitulo
		var centro := Vector2(540.0 - largura * 0.5 + 15.0 + i * 30.0, 1500.0)
		var cor: Color = Paleta.AMBAR if atual else Color("6d2835")
		draw_circle(centro, 8.0 if atual else 5.0, Color(cor, alpha))

func _draw_score_hero() -> void:
	var center := Vector2(540, 930)
	var measuring := state == GameDef.State.MEASURING
	# O ANEL MEDE A FORÇA, NÃO O RELÓGIO.
	#
	# Ele enchia com `result_time / CONTAGEM_DURACAO`, ou seja, com o
	# tempo da animação: um soco de 120 pontos fechava o anel inteiro
	# igualzinho a um de 961, porque os dois levavam os mesmos dois
	# segundos para contar. A pessoa batia fraco e via a barra encostar
	# no fim — e aí nada na tela combinava com o que ela tinha feito.
	# Ligado à pontuação, o anel vira o retrato do golpe: fraco fecha um
	# pedaço, nocaute fecha quase tudo. E continua animando, porque
	# `displayed_score` é o número subindo.
	var progress := 0.0 if measuring else clampf(displayed_score / float(GameDef.SCORE_MAX), 0.0, 1.0)
	# A cor também é a da faixa conquistada, e não uma só para todo mundo:
	# o anel de um golpe fraco não pode ser igual ao de um nocaute.
	var color := Paleta.CIANO
	if verdict_time >= 0.0:
		color = GameDef.classificar(result_score, limiar_fraco, limiar_forte)["cor_faixa"] as Color
	for i in range(12):
		draw_arc(center, 335.0 + float(i) * 3.0, 0, TAU, 192, Color(color, 0.02), 9.0, true)
	draw_circle(center, 326.0, Color("250911"))
	draw_arc(center, 327, 0, TAU, 192, Color("6d2835"), 4.0, true)
	for i in range(60):
		var angle := float(i) / 60.0 * TAU - PI * 0.5
		var lit := float(i) / 60.0 <= progress
		draw_arc(center, 347, angle, angle + 0.065, 5, color if lit else Color("57212c"), 14.0, true)
	draw_arc(center, 302, animation_time * 0.5, animation_time * 0.5 + 1.2, 64, Color(color, 0.55), 2.0, true)
	_texto("IMPACTO" if measuring else ("SUA PONTUAÇÃO" if verdict_time >= 0.0 else "CALCULANDO"), 785.0, 25, color)
	# VISOR DE SETE SEGMENTOS, e não texto. Numa máquina de fliperama o
	# placar é um painel de LED atrás de um vidro, e o que o olho
	# reconhece não é o formato do algarismo: é o SEGMENTO APAGADO, que
	# continua visível atrás do número. Nenhuma fonte dá isso.
	VisorLed.desenhar(
		self, "---" if measuring else "%03d" % int(round(displayed_score)),
		center + Vector2(0.0, 20.0), 168.0, Color.WHITE if not measuring else color
	)
	if verdict_time >= 0.0:
		_texto("PONTOS", 1110.0, 26, color)
		var title := "%dº LUGAR" % posicao_no_ranking if posicao_no_ranking > 0 else "BOM SOCO!"
		_texto_arcade(title, 1430.0, 64, color, LARGURA_UTIL)

## A JANELA DO SOCO, E O VALOR EXATO DA CARGA.
##
## Enquanto a barra de espaço está pressionada, o visor deixa de mostrar
## traços e passa a mostrar O NÚMERO — o mesmo visor, no mesmo lugar, com
## os mesmos algarismos que vão aparecer no resultado. Quem carrega não
## precisa adivinhar quanto tempo vale quanto: solta quando o número que
## está vendo serve. E o anel do medalhão é o relógio dos oito segundos,
## então tempo e valor ficam no mesmo objeto.
func _draw_armado() -> void:
	var carregando := carga_tempo >= 0.0
	var restante := clampf(armed_left / GameDef.JANELA_DO_SOCO, 0.0, 1.0)
	var cor_anel := Paleta.AMBAR if restante > 0.35 else Paleta.VERMELHO

	if carregando:
		var cor := GameDef.classificar(carga_pontos, limiar_fraco, limiar_forte)["cor_faixa"] as Color
		_draw_medalhao("%03d" % carga_pontos, cor, restante, 1.0)
		_texto_arcade("SOLTE PARA SOCAR", 1516.0, 50, Paleta.AMBAR, LARGURA_UTIL)
		_texto("PONTOS SE SOLTAR AGORA", 1562.0, 22, Paleta.TINTA_FRACA)
	else:
		_draw_medalhao("---", cor_anel, restante, 1.0)
		_texto_arcade("SOQUE AGORA!", 1520.0, 70, Paleta.VERMELHO, LARGURA_UTIL)
		var dica := "O SENSOR ESTÁ ESPERANDO O SEU GOLPE" if _sensor_ligado() \
			else "SEGURE ESPAÇO PARA CARREGAR O GOLPE"
		_texto(dica, 1566.0, 22, Paleta.TINTA_FRACA)

func _draw_arena_lights() -> void:
	# Luzes varrem o palco continuamente; trajetórias determinísticas
	# evitam o aspecto de flashes aleatórios trocando a cada frame.
	var impact := clampf(1.0 - state_time / 0.7, 0.0, 1.0) if state == GameDef.State.MEASURING else 0.0
	for side in [-1.0, 1.0]:
		var origin := Vector2(540.0 + side * 460.0, 188.0)
		var sweep := sin(animation_time * 0.55 + side) * 120.0
		var end := Vector2(540.0 + side * 140.0 + sweep, 980.0)
		var color := Paleta.CIANO if side < 0.0 else Paleta.ROSA
		draw_colored_polygon(PackedVector2Array([origin, end + Vector2(-80, 0), end + Vector2(80, 0)]), Color(color, 0.06 + impact * 0.1))
		draw_line(origin, end, Color(color, 0.14), 2.0, true)
		for k in range(9):
			var y := 320.0 + float(k) * 72.0
			var pulse := 0.3 + 0.7 * (0.5 + 0.5 * sin(animation_time * 3.0 - float(k) * 0.6))
			var x: float = 540.0 + side * 465.0
			draw_line(Vector2(x, y), Vector2(x - side * 18.0, y + 24.0), Color(color, pulse), 5.0, true)
	if impact > 0.0:
		var center := _alvo()
		for i in range(18):
			var angle := float(i) * TAU / 18.0
			var direction := Vector2.from_angle(angle)
			var radius := 100.0 + (1.0 - impact) * 420.0
			draw_line(center + direction * radius, center + direction * (radius + 90.0 * impact), Color(Paleta.AMBAR, impact * 0.7), 3.0, true)

func _draw_resultado() -> void:
	var classe := GameDef.classificar(result_score, limiar_fraco, limiar_forte)
	var cor_faixa: Color = classe["cor_faixa"]
	# Enquanto conta, o anel enche junto com o número.
	var avanco := clampf(result_time / GameDef.CONTAGEM_DURACAO, 0.0, 1.0)
	var cor_visor: Color = cor_faixa if verdict_time >= 0.0 else Paleta.CIANO
	_draw_medalhao("%03d" % int(round(displayed_score)), cor_visor, avanco, 1.0)
	_draw_player_photo(Rect2(62.0, 1112.0, 218.0, 218.0), result_photo_path, 1.0)

	if verdict_time < 0.0:
		_texto("MEDINDO O IMPACTO…", 1516.0, 26, Paleta.TINTA_LEVE)
		return

	_draw_carimbo(str(classe["label"]), Paleta.para_texto(classe["color"] as Color))

	# A CONQUISTA entra ABAIXO do veredito, e não por cima dele — foi
	# assim que a palavra ficava ilegível justamente quando havia mais
	# motivo para lê-la. E ela fala do RANKING, não de um recorde só:
	# entrar em quinto também é uma vitória, e é a que faz a maioria das
	# pessoas pagar a segunda ficha.
	var origem := "SIMULAÇÃO" if result_simulado else "SENSOR"
	var detalhe := "%s  •  %.2f m/s" % [origem, result_speed]
	if posicao_no_ranking > 0:
		var brilho := 0.65 + 0.35 * sin(animation_time * 6.0)
		var cor_pos := _cor_da_posicao(posicao_no_ranking)
		var faixa := Rect2(MARGEM + 190.0, 1536.0, LARGURA_UTIL - 380.0, 44.0)
		_cartao(faixa, Paleta.tinta_clara(cor_pos, 0.24), Color(cor_pos, brilho), 1.0, 3.0)
		Icones.trofeu(self, Vector2(faixa.position.x + 28.0, faixa.position.y + 22.0), 13.0, cor_pos)
		Icones.trofeu(self, Vector2(faixa.end.x - 28.0, faixa.position.y + 22.0), 13.0, cor_pos)
		var frase := "NOVO RECORDE DA CASA" if posicao_no_ranking == 1 \
			else "ENTROU NO TOP %d  •  %dº LUGAR" % [RANKING_TAMANHO, posicao_no_ranking]
		_texto_cabendo(frase, 1565.0, 23, Paleta.para_texto(cor_pos), faixa.size.x - 86.0, faixa.position.x + 43.0)
	else:
		_texto_cabendo(detalhe, 1556.0, 21, Paleta.TINTA_LEVE, LARGURA_UTIL)
		if verdict_time > 1.0:
			var piscada := 0.55 + 0.45 * sin(animation_time * 3.6)
			_texto("START PARA JOGAR NOVAMENTE", 1596.0, 20, Color(Paleta.TINTA_FRACA, piscada))

## Ouro, prata e bronze nos três primeiros; azul da casa nos demais. É a
## convenção que todo mundo já lê sem legenda.
func _cor_da_posicao(posicao: int) -> Color:
	match posicao:
		1:
			return Paleta.AMBAR
		2:
			return Color("8fa3bd")
		3:
			return Color("c1783a")
	return Paleta.CIANO

## Resultado encerra em uma cerimônia: a lista se move até a colocação
## conquistada, sem reduzir vinte fotos a miniaturas ilegíveis.
func _draw_ranking_reveal() -> void:
	saco.visible = false
	medidor.visible = false
	var progress := clampf((verdict_time - 2.5) / 1.6, 0.0, 1.0)
	var eased := progress * progress * (3.0 - 2.0 * progress)
	var position_index := maxi(posicao_no_ranking - 1, 0)
	var target := clampi(position_index - 2, 0, 15)
	var offset := float(target) * 164.0 * eased
	_texto_arcade("TOP 20", 220.0, 110, Paleta.CIANO, LARGURA_UTIL)
	var title := "%dº LUGAR • VOCÊ ENTROU!" % posicao_no_ranking if posicao_no_ranking > 0 else "TENTE SUPERAR ESSAS MARCAS"
	_texto_cabendo(title, 312.0, 38, Paleta.AMBAR, LARGURA_UTIL)
	# AS VINTE VAGAS, e não só as ocupadas. Numa máquina nova a lista tem
	# uma linha e dezenove buracos; desenhando só o que existe, a tela
	# vira um cartão solto num vazio preto. Desenhando a vaga aberta, o
	# mesmo vazio passa a dizer "sobrou lugar para você".
	for i in range(RANKING_TAMANHO):
		var y := 430.0 + float(i) * 164.0 - offset
		if y < 425.0 or y > 1150.0:
			continue
		var vazia := i >= ranking.size()
		var selected := posicao_no_ranking == i + 1
		var color := Paleta.AMBAR if selected else _cor_da_posicao(i + 1)
		var shift := (1.0 - eased) * (80.0 + float(i % 5) * 30.0)
		var card := Rect2(90.0 + shift, y, 900.0, 144.0)
		if vazia:
			_cartao(card, Color("1c060c"), Color("4a1420"), 1.0, 1.5)
			_texto("%02d" % (i + 1), y + 91.0, 45, Color("4a1420"), HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 22.0)
			_texto("VAGA ABERTA", y + 91.0, 30, Color("6d2835"), HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 270.0)
			continue
		_cartao(card, Color("b21029") if selected else Color("300b16"), color, 1.0, 4.0 if selected else 1.5)
		_draw_player_photo(Rect2(card.position + Vector2(124, 12), Vector2(120, 120)), str(ranking[i].get("photo_path", "")), 1.0)
		_texto("%02d" % (i + 1), y + 91.0, 45, color, HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 22.0)
		_texto("VOCÊ" if selected else "JOGADOR", y + 64.0, 26, color, HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 270.0)
		_texto("%03d" % RankingStore.score_at(ranking, i), y + 106.0, 62, Paleta.TINTA, HORIZONTAL_ALIGNMENT_RIGHT, card.position.x, card.size.x - 35.0)
	_texto("SEU SOCO", 1400.0, 25, Paleta.TINTA_FRACA)
	_texto("%03d" % result_score, 1520.0, 100, Paleta.TINTA)
	_texto("START • JOGAR NOVAMENTE", 1710.0, 32, Paleta.CIANO)

# ---------------------------------------------------------------- medalhão
## O VISOR DA MÁQUINA, do jeito que uma máquina de fliperama o monta:
## raios girando por fora, anel de faixa, bisel e, no miolo, o vidro
## escuro com os algarismos de LED.
##
## Por que os raios giram e o anel enche: são as duas únicas peças
## animadas, e cada uma diz uma coisa. Os raios giram sempre, devagar —
## é o "a máquina está viva". O anel é o RELÓGIO: enche na contagem do
## placar e esvazia nos oito segundos do soco. Uma pessoa a três metros
## não lê um número de tempo, mas vê um anel fechando.
##
## `energia` (0..1) é quanto do anel está aceso; `intensidade` escurece
## tudo de uma vez, para o visor poder "apagar" sem cada peça precisar
## saber disso.
func _draw_medalhao(
	texto: String, cor: Color, energia: float, intensidade: float,
	centro := MEDALHAO_CENTRO, raio := MEDALHAO_RAIO
) -> void:
	var c := centro
	var r := raio
	var a := intensidade

	# AS QUATRO FAIXAS, de fora para dentro, sem uma invadir a outra:
	#   raios      0.80 … 1.00
	#   anel       0.66 … 0.80   (o relógio, e o rótulo curvo)
	#   bisel      0.60 … 0.66
	#   vidro      0.00 … 0.60
	var r_vidro := r * 0.60
	var r_bisel := r * 0.66
	var r_anel := r * 0.73          ## linha média da faixa
	var esp_anel := r * 0.14

	draw_circle(c + Vector2(0.0, 7.0), r, Color(Paleta.SOMBRA, Paleta.SOMBRA.a * a))
	_raios_do_medalhao(c, r, a)

	# Anel de faixa: fundo CREME e, por cima, o trecho aceso. Creme e não
	# cinza porque os raios em volta já são vermelho e âmbar — um fundo
	# frio faria a faixa sumir dentro deles, e é justamente ela que
	# marca o tempo.
	draw_arc(c, r_anel, 0.0, TAU, 96, Color(Paleta.CREME, a), esp_anel)
	if energia > 0.001:
		draw_arc(
			c, r_anel, -PI * 0.5, -PI * 0.5 + TAU * clampf(energia, 0.0, 1.0),
			96, Color(cor, a), esp_anel, true
		)
	draw_arc(c, r_anel + esp_anel * 0.5, 0.0, TAU, 96, Color(Paleta.MARINHO, a), 3.0, true)
	draw_arc(c, r_anel - esp_anel * 0.5, 0.0, TAU, 96, Color(Paleta.MARINHO, a), 3.0, true)

	# Rótulo curvo na faixa: é o que faz a peça parecer serigrafada no
	# painel da máquina, e não um anel de progresso de aplicativo.
	# O corpo do rótulo acompanha o tamanho da peça: o mesmo medalhão
	# aparece grande na partida e pequeno na abertura.
	_texto_curvo("PONTOS DE POTÊNCIA", c, r_anel, -PI * 0.5, int(r * 0.091), Color(Paleta.CONTORNO, 0.75 * a))
	_texto_curvo("LAZER & SPORT", c, r_anel, PI * 0.5, int(r * 0.086), Color(Paleta.CONTORNO, 0.6 * a), true)

	# Bisel e vidro do visor.
	draw_circle(c, r_bisel, Color(Paleta.MARINHO, a))
	draw_circle(c, r_vidro, Color(Paleta.VISOR_FUNDO, a))

	VisorLed.desenhar(self, texto, c, r * 0.52, Color(cor, a))

	# Reflexo do vidro: um crescente claro no alto, à esquerda. Sem ele o
	# miolo escuro parece um buraco em vez de um vidro.
	draw_arc(c, r_vidro * 0.86, PI * 1.06, PI * 1.60, 32, Color(Paleta.VISOR_VIDRO, 0.40 * a), 10.0, true)

## Raios do medalhão: cunhas alternadas girando devagar atrás do anel.
func _raios_do_medalhao(c: Vector2, r: float, a: float) -> void:
	var giro := animation_time * 0.16
	var r0 := r * 0.80
	for i in range(24):
		var ang := giro + float(i) / 24.0 * TAU
		var meia := TAU / 48.0 * 0.84
		var cor: Color = Paleta.VERMELHO if i % 2 == 0 else Paleta.AMBAR
		draw_colored_polygon(
			PackedVector2Array([
				c + Vector2(cos(ang - meia), sin(ang - meia)) * r0,
				c + Vector2(cos(ang - meia), sin(ang - meia)) * r,
				c + Vector2(cos(ang + meia), sin(ang + meia)) * r,
				c + Vector2(cos(ang + meia), sin(ang + meia)) * r0,
			]),
			Color(cor, a)
		)
	draw_arc(c, r, 0.0, TAU, 96, Color(Paleta.MARINHO, a), 5.0, true)
	draw_arc(c, r0, 0.0, TAU, 80, Color(Paleta.MARINHO, a), 4.0, true)

## Texto seguindo uma circunferência, uma letra por vez. `de_cabeca` vira
## a palavra para dentro, que é como se lê a metade de baixo de um selo.
func _texto_curvo(
	texto: String, centro: Vector2, raio: float, angulo: float,
	tamanho: int, cor: Color, de_cabeca := false
) -> void:
	var larguras: Array[float] = []
	var total := 0.0
	for i in range(texto.length()):
		var w := fonte.get_string_size(texto[i], HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho).x
		larguras.append(w)
		total += w
	var passo_total := total / raio
	var direcao := -1.0 if de_cabeca else 1.0
	var atual := angulo - direcao * passo_total * 0.5
	for i in range(texto.length()):
		var passo := larguras[i] / raio * direcao
		var meio := atual + passo * 0.5
		var p := centro + Vector2(cos(meio), sin(meio)) * raio
		draw_set_transform(_deslocamento + p, meio + (PI * 0.5 if not de_cabeca else -PI * 0.5))
		draw_string(
			fonte, Vector2(-larguras[i] * 0.5, tamanho * 0.36), texto[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, cor
		)
		atual += passo
	draw_set_transform(_deslocamento, 0.0, Vector2.ONE)

func _draw_carimbo(titulo: String, cor: Color) -> void:
	## O CARIMBO CAI NA TELA, não aparece: entra grande, passa do lugar e
	## volta — o gesto de um carimbo batendo no papel. O tamanho final
	## sai de `_tamanho_que_cabe`, então "PESO-PESADO" não estoura a tela
	## do mesmo jeito que "FRACO!" não fica pequeno.
	var t := clampf(verdict_time / 0.45, 0.0, 1.0)
	var escala := 1.0
	if t < 1.0:
		escala = lerpf(2.2, 1.0, ease(t, 0.28)) + sin(t * PI) * 0.10
	var alpha := clampf(verdict_time / 0.2, 0.0, 1.0)
	var base := _tamanho_que_cabe(titulo, 82, LARGURA_UTIL - 60.0)
	var tamanho := int(clampf(float(base) * escala, 20.0, 190.0))
	# Sem largura de caixa: durante a entrada o carimbo é MAIOR que a
	# tela de propósito, e uma caixa o cortaria em vez de deixá-lo passar.
	var medida := fonte.get_string_size(titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
	_letreiro(titulo, Vector2((TELA.x - medida.x) * 0.5, 1520.0), tamanho, Color(cor, alpha))

## Cabeçalho: só a marca do jogo e o modo. O estado da serial é assunto
## do técnico, e vive na Central Técnica — na tela do cliente ele vira,
## no máximo, um ponto âmbar quando há problema.
func _draw_header() -> void:
	draw_rect(Rect2(MARGEM, BANDA_TOPO, LARGURA_UTIL, 2.0), Paleta.CARTAO_BORDA)
	_texto("PUNCH", 92.0, 32, Paleta.TINTA, HORIZONTAL_ALIGNMENT_LEFT, MARGEM)
	var largura_punch := fonte.get_string_size("PUNCH ", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	_texto("CHALLENGE", 92.0, 32, Paleta.VERMELHO, HORIZONTAL_ALIGNMENT_LEFT, MARGEM + largura_punch)
	if not _sensor_ligado() and link != null and link.available():
		draw_circle(Vector2(MARGEM + 500.0, 82.0), 8.0, Paleta.AMBAR)
	var mode_text := "MODO LIVRE" if game_mode == "free" else "MODO FICHA"
	_pill(Rect2(TELA.x - MARGEM - 180.0, 54.0, 180.0, 52.0), mode_text, Paleta.MARINHO)

func _draw_cartoes() -> void:
	_texto("RECORDE %03d     •     %s" % [_melhor(), "LIVRE" if game_mode == "free" else "CRÉDITOS %02d" % credits], 1692.0, 27, Paleta.TINTA_FRACA)

## Rodapé: a assinatura da casa. As teclas só aparecem quando o sensor
## NÃO está ligado — ou seja, na bancada de montagem. Com o Arduino no
## lugar, o cliente nunca vê instrução de teclado numa máquina de ficha.
func _draw_rodape(alpha: float) -> void:
	_texto("LAZER & SPORT", RODAPE_Y, 18, Color(Paleta.TINTA_LEVE, alpha))

# ---------------------------------------------------------------- central
func _draw_central() -> void:
	# Véu sobre o jogo: a Central cobre a tela, mas o técnico continua
	# vendo que a máquina está ligada por trás.
	draw_rect(Rect2(Vector2.ZERO, TELA), Color("120409", 0.94))
	var caixa := Rect2(40, 96, 1000, 1790)
	_placa(Rect2(caixa.position + Vector2(0.0, 8.0), caixa.size), 22.0, Paleta.SOMBRA)
	# Borda DOURADA e miolo mais claro que o fundo. Com a moldura em
	# marinho, que neste tema é quase o preto da tela, o painel não se
	# separava do jogo atrás e a Central parecia colada por cima.
	_placa(caixa, 22.0, Paleta.AMBAR)
	_placa(caixa.grow(-5.0), 19.0, Color("2b0a13"))
	_letreiro("CENTRAL TÉCNICA", Vector2(110.0, 204.0), 44, Paleta.CREME)
	_texto("Configuração, diagnóstico e calibração", 240.0, 18, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, 110.0)
	_botao(BOTOES_SIMPLES["fechar"], "×", false, Paleta.VERMELHO, 32)

	# ---- modo de operação
	_secao(Rect2(80, 262, 920, 138), "MODO DE OPERAÇÃO", Paleta.ROSA)
	_botao(BOTOES_SIMPLES["modo_livre"], "LIVRE", game_mode == "free", Paleta.CIANO, 22)
	_botao(BOTOES_SIMPLES["modo_ficha"], "1 FICHA", game_mode == "credit", Paleta.ROSA, 22)

	# ---- faixas do placar
	_secao(Rect2(80, 416, 920, 244), "FAIXAS DO PLACAR (0 – 999)", Paleta.AMBAR)
	_regua_das_faixas(Rect2(110, 470, 860, 28))
	_stepper("limiar_fraco", "%03d" % limiar_fraco, "ATÉ AQUI É FRACO", GameDef.COR_FRACA)
	_stepper("limiar_forte", "%03d" % limiar_forte, "DAQUI É FORTE", GameDef.COR_FORTE)

	# ---- velocidade e dificuldade, cada uma na sua linha
	_secao(Rect2(80, 676, 920, 284), "VELOCIDADE E DIFICULDADE", Paleta.CIANO)
	_stepper("vmin", "%.1f m/s" % hit_min_speed, "MÍNIMA  =  0 PONTOS", Paleta.CIANO)
	_stepper("vmax", "%.1f m/s" % hit_max_speed, "MÁXIMA  =  999 PONTOS", Paleta.CIANO)
	_stepper(
		"curva", "γ %.2f" % score_exponent,
		"CURVA %s  •  ZONA MORTA %.0f%%" % [ScoreCurve.difficulty_name(score_exponent), score_dead_zone * 100.0],
		Paleta.ROXO
	)

	# ---- sensor e firmware
	_secao(Rect2(80, 976, 920, 274), "SENSOR DE SOCO (MPU-6050)", Paleta.ROXO)
	var dot := Paleta.VERDE if _sensor_ligado() else Paleta.AMBAR
	draw_circle(Vector2(560, 1010.0), 7.0, dot)
	_texto(serial_status, 1016.0, 15, Paleta.para_texto(dot), HORIZONTAL_ALIGNMENT_LEFT, 578.0, 400.0)
	_stepper("porta", porta_configurada if not porta_configurada.is_empty() else "AUTO", "PORTA SERIAL", Paleta.CIANO)
	_botao(BOTOES_SIMPLES["eixo"], "EIXO  %s" % sensor_eixo, false, Paleta.ROXO, 20)
	_texto("EIXO DO GOLPE", 1128.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_CENTER, BOTOES_SIMPLES["eixo"].position.x, BOTOES_SIMPLES["eixo"].size.x)
	_stepper("raio", "%.2f m" % sensor_raio, "RAIO DO BRAÇO", Paleta.CIANO)
	_stepper("amin", "%.1f g" % sensor_amin, "SENSIBILIDADE", Paleta.CIANO)

	# ---- câmera, em seção própria
	_secao(Rect2(80, 1266, 920, 154), "CÂMERA DAS FOTOS DO RANKING", Paleta.ROSA)
	_botao(BOTOES_SIMPLES["camera"], "CÂMERA ON" if camera_enabled else "CÂMERA OFF", camera_enabled, Paleta.ROXO, 16)
	_botao(BOTOES_SIMPLES["trocar_camera"], "TROCAR CÂMERA", false, Paleta.CIANO, 16)
	_botao(BOTOES_SIMPLES["foto_teste"], "TESTAR FOTO", false, Paleta.ROSA, 16)
	var cam_status := camera_service.status if camera_service != null else "SEM SERVIÇO"
	_texto(cam_status, 1404.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0)

	# ---- ações no firmware
	_secao(Rect2(80, 1436, 920, 120), "AÇÕES NO FIRMWARE", Paleta.VERDE)
	_botao(BOTOES_SIMPLES["enviar_config"], "ENVIAR CONFIG", false, Paleta.VERDE, 19)
	_botao(BOTOES_SIMPLES["testar"], "TESTAR SENSOR", false, Paleta.AMBAR, 19)

	# ---- ranking e diagnóstico
	_secao(Rect2(80, 1572, 920, 214), "MELHORES DA CASA E DIAGNÓSTICO", Paleta.VERMELHO)
	# A faixa começa ABAIXO da linha de base do título. Antes ela subia
	# até 1508 com o título em 1512, e as células cobriam o nome da seção.
	_lista_do_ranking(Rect2(110, 1618, 860, 42))
	_texto(
		telemetria if telemetria != "" else "sem telemetria ainda",
		1684.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	var resumo := StatisticsStore.summary(statistics)
	_texto(
		"Hoje %d  •  7 dias %d  •  média %03d  •  Top 5: %d" % [resumo["today"], resumo["last7"], resumo["average"], resumo["top5_entries"]],
		1706.0, 14, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_botao(BOTOES_SIMPLES["zerar"], "CONTADORES", false, Paleta.VERMELHO, 14)
	_botao(BOTOES_SIMPLES["zerar_stats"], "ESTATÍSTICAS", false, Paleta.ROXO, 14)
	_botao(BOTOES_SIMPLES["zerar_ranking"], "RANKING + FOTOS", false, Paleta.VERMELHO, 13)
	_botao(BOTOES_SIMPLES["reconectar"], "RECONECTAR", false, Paleta.CIANO, 14)

	_botao(BOTOES_SIMPLES["padroes"], "RESTAURAR PADRÕES", false, Paleta.AMBAR, 19)
	_botao(BOTOES_SIMPLES["salvar"], "SALVAR E FECHAR", true, Paleta.VERDE, 21)
	# Uma linha só: entre a última fileira de botões e a borda do painel
	# sobram poucos pixels, e duas linhas aí se atropelam. O carimbo da
	# build entra junto porque quem abre a Central é justamente quem
	# acabou de instalar a atualização e precisa confirmar que pegou.
	_texto(
		"%s     Tecla T: golpe de teste  •  ESC: fecha sem sair da rodada" % Versao.curta(),
		1872.0, 14, Paleta.TINTA_LEVE
	)

## As cinco marcas em uma linha só: o técnico precisa VER o que vai
## apagar antes de apertar ZERAR RANKING.
func _lista_do_ranking(rect: Rect2) -> void:
	var largura := (rect.size.x - 4.0 * 10.0) / 5.0
	for i in range(5):
		var celula := Rect2(rect.position + Vector2(i * (largura + 10.0), 0.0), Vector2(largura, rect.size.y))
		var cor := _cor_da_posicao(i + 1)
		var tem := i < ranking.size()
		_cartao(celula, Paleta.tinta_clara(cor, 0.14) if tem else Paleta.VAZIO, Paleta.CARTAO_BORDA, 1.0, 0.0)
		_texto("%dº" % (i + 1), celula.position.y + 20.0, 13, Color(Paleta.para_texto(cor)), HORIZONTAL_ALIGNMENT_CENTER, celula.position.x, celula.size.x)
		_texto(
			"%03d" % RankingStore.score_at(ranking, i) if tem else "—", celula.position.y + 44.0, 22,
			Paleta.TINTA if tem else Paleta.TINTA_LEVE,
			HORIZONTAL_ALIGNMENT_CENTER, celula.position.x, celula.size.x
		)

## Uma seção da Central: moldura e título, sempre no mesmo lugar em
## relação à caixa. Nenhuma seção precisa saber onde fica o seu rótulo.
func _secao(rect: Rect2, titulo: String, cor := Paleta.MARINHO) -> void:
	_cartao(rect, Paleta.tinta_clara(Paleta.MARINHO, 0.045), Paleta.CARTAO_BORDA, 1.0, 0.0)
	# Tarja colorida na lateral: com sete seções empilhadas, é o que deixa
	# o técnico achar a que procura sem ler todos os títulos.
	draw_rect(Rect2(rect.position, Vector2(8.0, rect.size.y)), cor)
	_texto(titulo, rect.position.y + 40.0, 16, Paleta.para_texto(cor), HORIZONTAL_ALIGNMENT_LEFT, rect.position.x + 40.0, rect.size.x - 80.0)

## Um par − / + com o valor no meio e a legenda embaixo. Os retângulos
## saem de `PASSOS`, os mesmos que o clique consulta — texto e área de
## toque não têm como divergir.
func _stepper(chave: String, valor: String, legenda: String, accent: Color) -> void:
	var visor := _passo_visor(chave)
	_cartao(visor, Paleta.CARTAO, Paleta.CARTAO_BORDA, 1.0, 0.0)
	_botao(_passo_menos(chave), "−", false, accent, 26)
	_botao(_passo_mais(chave), "+", false, accent, 26)
	_texto_cabendo(valor, visor.position.y + visor.size.y * 0.68, 30, Paleta.TINTA, visor.size.x - 12.0, visor.position.x + 6.0)
	var r: Rect2 = PASSOS[chave]
	_texto(legenda, r.end.y + 28.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_CENTER, r.position.x, r.size.x)

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
		draw_rect(Rect2(x0, rect.position.y, x1 - x0, rect.size.y), cor)
		if x1 - x0 > 90.0:
			_texto(str(f[3]), rect.position.y + rect.size.y * 0.70, 15, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, x0, x1 - x0)
	draw_rect(rect, Paleta.CARTAO_BORDA, false, 2.0)

# ---------------------------------------------------------------- peças
## A MARCA DA CASA COMO LETREIRO DE PARQUE, e não como uma figura solta
## no meio da tela.
##
## POR QUE A PLACA EXISTE. A logo é uma arte clara — plaqueta branca com
## contorno preto — e num céu claro ela não tem em que se apoiar: fica
## boiando, do jeito que qualquer figura colada fica. A placa resolve
## isso do jeito que um parque resolve: miolo creme para a marca
## descansar, moldura marinho em volta para separá-la do céu, e a fieira
## de lâmpadas correndo na moldura.
##
## AS LÂMPADAS PRECISAM DA MOLDURA. Numa primeira versão elas ficavam
## direto sobre o céu, e a lâmpada APAGADA sumia — sobrava um pedacinho
## de luz correndo no vazio, que não lê como letreiro. Sobre o marinho,
## acesa e apagada aparecem as duas, e é a fieira inteira que dá o
## desenho.
func _draw_marca(centro: Vector2, largura: float, alpha: float) -> void:
	if logo == null:
		_texto_cabendo("LAZER & SPORT", centro.y, 64, Color(Paleta.TINTA, alpha), LARGURA_UTIL)
		return

	var tamanho := logo.get_size()
	var escala := largura / tamanho.x
	var altura := tamanho.y * escala
	var destino := Rect2(centro - Vector2(largura, altura) * 0.5, Vector2(largura, altura))

	var banda := 34.0
	var placa := destino.grow(46.0)
	var canto := 46.0

	# Halo quente atrás de tudo: a luz do refletor batendo no letreiro.
	for i in range(4):
		draw_circle(centro, largura * (0.66 - i * 0.11), Color(Paleta.LUZ, 0.11 * alpha))

	_placa(Rect2(placa.position + Vector2(0.0, 12.0), placa.size), canto, Color(Paleta.SOMBRA, 0.9 * alpha))
	_placa(placa, canto, Color(Paleta.MARINHO, alpha))
	_placa(placa.grow(-banda), canto - banda * 0.55, Color(Paleta.CREME, alpha))

	draw_texture_rect(logo, destino, false, Color(1, 1, 1, alpha))

	_lampadas_do_letreiro(placa.grow(-banda * 0.5), alpha)

## As lâmpadas do letreiro, distribuídas pelo perímetro, com a luz
## correndo. Mesma ideia da moldura da tela, em escala de marca.
func _lampadas_do_letreiro(caixa: Rect2, alpha: float) -> void:
	var passo := 54.0
	var perimetro := 2.0 * (caixa.size.x + caixa.size.y)
	var total := maxi(12, int(perimetro / passo))
	var cabeca := fmod(animation_time * 9.0, float(total))
	for i in range(total):
		var p := _ponto_do_retangulo(caixa, float(i) / float(total) * perimetro)
		var dist := fmod(cabeca - float(i) + total, float(total))
		var acesa := maxf(0.0, 1.0 - dist / 5.0)
		# Apagada é creme sobre o marinho: continua sendo um bulbo de
		# vidro, e não um buraco.
		var cor: Color = Color("93a4c6").lerp(Paleta.LUZ, acesa)
		if acesa > 0.05:
			draw_circle(p, 19.0, Color(Paleta.AMBAR, acesa * 0.45 * alpha))
		draw_circle(p, 9.5, Color(cor, alpha))
		draw_circle(p + Vector2(-2.6, -2.6), 3.2, Color(1, 1, 1, 0.65 * alpha))

## Ponto a `d` de distância ao longo do perímetro de um retângulo, no
## sentido horário a partir do canto superior esquerdo.
func _ponto_do_retangulo(r: Rect2, d: float) -> Vector2:
	var w := r.size.x
	var h := r.size.y
	if d < w:
		return r.position + Vector2(d, 0.0)
	d -= w
	if d < h:
		return r.position + Vector2(w, d)
	d -= h
	if d < w:
		return r.position + Vector2(w - d, h)
	d -= w
	return r.position + Vector2(0.0, h - d)

## Retângulo de cantos redondos. O Godot só desenha retângulo de canto
## vivo, e canto vivo em peça grande destoa do resto da tela — a placa,
## os cartões e os botões todos precisam da mesma família de formas.
func _placa(rect: Rect2, raio: float, cor: Color) -> void:
	draw_colored_polygon(_contorno_arredondado(rect, raio), cor)

func _contorno_arredondado(rect: Rect2, raio: float) -> PackedVector2Array:
	var r := minf(raio, minf(rect.size.x, rect.size.y) * 0.5)
	var pontos := PackedVector2Array()
	var cantos := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	for c in cantos:
		var meio: Vector2 = c[0]
		var a0: float = c[1]
		for i in range(9):
			var a := a0 + float(i) / 8.0 * PI * 0.5
			pontos.append(meio + Vector2(cos(a), sin(a)) * r)
	return pontos

func _photo_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _photo_cache.has(path):
		return _photo_cache[path] as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	_photo_cache[path] = texture
	return texture

func _draw_texture_cover(texture: Texture2D, rect: Rect2, alpha: float, mirror := false) -> void:
	if texture == null:
		return
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var source := Rect2(Vector2.ZERO, source_size)
	var source_aspect := source_size.x / source_size.y
	var target_aspect := rect.size.x / rect.size.y
	if source_aspect > target_aspect:
		var wanted_width := source_size.y * target_aspect
		source.position.x = (source_size.x - wanted_width) * 0.5
		source.size.x = wanted_width
	else:
		var wanted_height := source_size.x / target_aspect
		source.position.y = (source_size.y - wanted_height) * 0.5
		source.size.y = wanted_height
	if mirror:
		draw_set_transform(_deslocamento + Vector2(rect.end.x, rect.position.y), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect_region(texture, Rect2(Vector2.ZERO, rect.size), source, Color(1, 1, 1, alpha))
		draw_set_transform(_deslocamento, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(texture, rect, source, Color(1, 1, 1, alpha))

## O LUGAR DA FOTO QUE AINDA NÃO EXISTE.
##
## Um círculo amarelo sobre um trapézio roxo não lê como pessoa: lê como
## erro de desenho, e ainda por cima em duas cores que não são do tema.
## Aqui é uma silhueta de ombros e cabeça, na cor da moldura, com a
## mira de enquadramento por cima — a mesma que uma câmera mostra.
## Assim o quadro vazio diz "é aqui que o seu rosto vai aparecer".
func _draw_avatar(rect: Rect2, alpha: float) -> void:
	draw_rect(rect, Color("1c060c", 0.94 * alpha))
	var center := rect.get_center()
	var unit := minf(rect.size.x, rect.size.y)
	var tom := Color("7a2a38", alpha)

	Icones.avatar(self, center + Vector2(0.0, unit * 0.06), unit * 0.30, tom)

	# Cantoneiras de enquadramento, como as de um visor de câmera.
	var margem := unit * 0.10
	var braco := unit * 0.14
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var canto := center + Vector2(sx * (rect.size.x * 0.5 - margem), sy * (rect.size.y * 0.5 - margem))
			draw_line(canto, canto - Vector2(sx * braco, 0.0), Color(Paleta.AMBAR, 0.55 * alpha), 4.0, true)
			draw_line(canto, canto - Vector2(0.0, sy * braco), Color(Paleta.AMBAR, 0.55 * alpha), 4.0, true)

func _draw_player_photo(rect: Rect2, path: String, alpha: float) -> void:
	var texture := _photo_texture(path)
	if texture == null:
		_draw_avatar(rect, alpha)
	else:
		_draw_texture_cover(texture, rect, alpha)
	draw_rect(rect, Color(Paleta.CIANO, alpha), false, 3.0)

func _draw_camera_card(rect: Rect2, alpha: float, label: String) -> void:
	_cartao(rect.grow(8.0), Color(Paleta.MARINHO, alpha), Color(Paleta.CIANO, alpha), alpha, 3.0)
	var preview := Rect2(rect.position, Vector2(rect.size.x, rect.size.y - 52.0))
	var texture: Texture2D = camera_service.preview_texture() if camera_service != null else null
	if texture == null:
		_draw_avatar(preview, alpha)
	else:
		_draw_texture_cover(texture, preview, alpha, camera_mirrored)
	draw_rect(preview, Color(Paleta.CIANO, 0.75 * alpha), false, 2.0)
	_texto_cabendo(label, rect.end.y - 15.0, 18, Color(Paleta.CREME, alpha), rect.size.x - 20.0, rect.position.x + 10.0)
	var dot := Paleta.VERDE if camera_service != null and camera_service.available() else Paleta.AMBAR
	draw_circle(rect.position + Vector2(18.0, 18.0), 7.0, Color(dot, alpha))

## O aviso de operação ocupa o rodapé, e não o topo: no topo ele cairia
## em cima do cabeçalho, e no meio disputaria com o número.
func _draw_notice() -> void:
	var caixa := Rect2(MARGEM + 60.0, 1798.0, LARGURA_UTIL - 120.0, 66.0)
	_cartao(caixa, Paleta.CARTAO, Paleta.CIANO, 1.0, 3.0)
	_texto_cabendo(notice, caixa.position.y + 42.0, 20, Paleta.TINTA, caixa.size.x - 40.0, caixa.position.x + 20.0)

## A peça padrão da tela: retângulo branco com sombra e borda. Todo painel
## do jogo passa por aqui, então a "altura" das peças é a mesma em toda
## parte — e mudar a sombra do jogo inteiro é mudar uma função.
func _cartao(rect: Rect2, fundo_c: Color, borda: Color, alpha := 1.0, largura_borda := 2.0) -> void:
	draw_rect(Rect2(rect.position + Vector2(0, 4.0), rect.size), Color(Paleta.SOMBRA, Paleta.SOMBRA.a * alpha))
	draw_rect(rect, Color(fundo_c, fundo_c.a * alpha))
	if largura_borda > 0.0:
		draw_rect(rect, Color(borda, borda.a * alpha), false, largura_borda)

func _pill(rect: Rect2, texto: String, cor: Color) -> void:
	draw_rect(Rect2(rect.position + Vector2(0, 3.0), rect.size), Paleta.SOMBRA)
	draw_rect(rect, cor)
	_texto_cabendo(texto, rect.position.y + rect.size.y * 0.66, 18, Paleta.CARTAO, rect.size.x - 20.0, rect.position.x + 10.0)

## Botão: colorido e cheio quando ativo, branco com borda colorida quando
## não. Num tema claro é o PREENCHIMENTO que marca o estado ligado —
## borda mais grossa sozinha não se lê de longe.
func _botao(rect: Rect2, texto: String, ativo: bool, accent: Color, tamanho: int) -> void:
	var fundo_c := accent if ativo else Paleta.CARTAO
	var tinta := Paleta.CARTAO if ativo else Paleta.para_texto(accent)
	draw_rect(Rect2(rect.position + Vector2(0, 3.0), rect.size), Paleta.SOMBRA)
	draw_rect(rect, fundo_c)
	draw_rect(rect, Color(accent, 0.9), false, 2.0)
	_texto_cabendo(
		texto, rect.position.y + rect.size.y * 0.68, tamanho, tinta,
		rect.size.x - 20.0, rect.position.x + 10.0
	)

## Cartão de número, com ícone. O ícone é o que deixa o cartão legível de
## relance: a três metros, a pessoa reconhece o troféu antes de conseguir
## ler "RECORDE".
func _stat_card(rect: Rect2, rotulo: String, valor: String, accent: Color, icone: String, alpha: float) -> void:
	_cartao(rect, Paleta.CARTAO, Paleta.CARTAO_BORDA, alpha, 2.0)
	# Tarja colorida no topo: identifica o cartão sem pintá-lo inteiro.
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 6.0)), Color(accent, alpha))
	_icone(icone, rect.position + Vector2(rect.size.x * 0.5, 42.0), 17.0, Color(Paleta.para_texto(accent), alpha))
	_texto(rotulo, rect.position.y + 74.0, 15, Color(Paleta.TINTA_FRACA, alpha), HORIZONTAL_ALIGNMENT_CENTER, rect.position.x, rect.size.x)
	_texto_cabendo(valor, rect.position.y + 118.0, 38, Color(Paleta.TINTA, alpha), rect.size.x - 24.0, rect.position.x + 12.0)

## Despacha o ícone pelo nome. Um `match` num lugar só evita que cada
## chamada precise saber de qual arquivo o desenho vem.
func _icone(nome: String, centro: Vector2, raio: float, cor: Color) -> void:
	match nome:
		"trofeu":
			Icones.trofeu(self, centro, raio, cor)
		"luva":
			Icones.luva(self, centro, raio, cor)
		"ficha":
			Icones.ficha(self, centro, raio, cor)
		"raio":
			Icones.raio_eletrico(self, centro, raio, cor)
		"alvo":
			Icones.alvo(self, centro, raio, cor)
		"botao":
			Icones.botao(self, centro, raio, cor)
		"estrela":
			Icones.estrela(self, centro, raio, cor)

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

## LETRA DE FLIPERAMA. Três passadas sobre a mesma palavra:
##
##   1. um contorno MUITO grosso, quase preto — é ele que segura a letra
##      sobre qualquer fundo, e é o que separa um letreiro de arcade de
##      um texto colorido qualquer;
##   2. a mesma palavra alguns pixels ACIMA, num tom claro: o que sobra
##      aparecendo por cima da borda vira o brilho do topo da letra, o
##      truque que dá volume sem precisar de degradê (o Godot desenha
##      texto de uma cor só);
##   3. o preenchimento, na cor da vez.
##
## Com `halo`, entra antes de tudo um contorno largo e transparente na
## cor de destaque — a luz que a letra joga no que está atrás dela.
func _letreiro(texto: String, pos: Vector2, tamanho: int, cor: Color, halo := Color(0, 0, 0, 0)) -> void:
	if halo.a > 0.001:
		draw_string_outline(fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, int(tamanho * 0.34), halo)
	draw_string_outline(
		fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho,
		maxi(6, int(tamanho * 0.17)), Color(Paleta.CONTORNO, cor.a)
	)
	var realce := Color(cor.lightened(0.42), cor.a)
	draw_string(fonte, pos - Vector2(0.0, tamanho * 0.055), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, realce)
	draw_string(fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, cor)

## Letreiro centrado numa largura, encolhendo até caber.
func _texto_arcade(texto: String, y: float, tamanho_max: int, cor: Color, largura: float, x := MARGEM) -> void:
	var tamanho := _tamanho_que_cabe(texto, tamanho_max, largura * 0.94)
	var medida := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
	_letreiro(texto, Vector2(x + (largura - medida.x) * 0.5, y), tamanho, cor, Color(cor, 0.28))

func _texto_cabendo(texto: String, y: float, tamanho_max: int, cor: Color, largura: float, x := MARGEM) -> void:
	draw_string(
		fonte, Vector2(x, y), texto, HORIZONTAL_ALIGNMENT_CENTER, largura,
		_tamanho_que_cabe(texto, tamanho_max, largura), cor
	)
