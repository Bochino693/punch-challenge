extends Control

## Punch Challenge — a máquina de soco da Lazer & Sport.
##
## TELA EM PÉ, 1080 × 1920, LIDA EM BANDAS. Quem joga está a dois ou três
## metros do gabinete e olha para cima. A tela é dividida em faixas
## horizontais fixas (`BANDA_*`), e cada coisa desenhada mora dentro da
## sua: cabeçalho, alvo do soco, leitura (número e veredito),
## cartões e rodapé. Enquanto tudo respeitar a sua banda, nada se
## sobrepõe — que é a diferença entre um placar que se lê de longe e um
## amontoado de texto por cima de texto.
##
## O nó raiz desenha textos, placar e a Central Técnica; o cenário vivo
## fica nos filhos: `PunchBackground` (fundo), `LedFrame` (moldura de LEDs) e
## `AudioBank` (sons). O que voa — confete, faísca, estilhaço — mora em
## `fx.gd`.
##
## O CAMINHO DE QUEM JOGA:
##
##   ABERTURA → (START) → 3, 2, 1 → SENSOR ARMADO → IMPACTO → RESULTADO
##
## Dois jeitos de socar: o MPU-6050 do alvo manda HIT pela serial
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
## Alvo do soco: de onde saem ondas, faíscas e clarão.
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
## O ALVO NA TELA. É o centro do visor — o mesmo lugar em que o farol
## chama o soco e em que o número nasce logo depois.
const ALVO_DO_SOCO := Vector2(540.0, 930.0)
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
	"vmin": Rect2(110, 470, 400, LADO_BOTAO),
	"vmax": Rect2(570, 470, 400, LADO_BOTAO),
	"curva": Rect2(110, 592, 400, 58),
	"zona": Rect2(570, 592, 400, 58),
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
var hit_min_speed := ScoreCurve.DEFAULT_MIN_SPEED
var hit_max_speed := ScoreCurve.DEFAULT_MAX_SPEED
## O expoente é o botão de dificuldade da casa: quanto maior, mais tarde
## a nota sobe e mais raro fica o topo da escala. Os oito níveis têm
## faixas FIXAS, então é aqui — e só aqui — que se decide quanta gente
## chega a cada um deles.
var score_exponent := ScoreCurve.DEFAULT_EXPONENT
var score_dead_zone := ScoreCurve.DEFAULT_DEAD_ZONE
## Configuração enviada ao firmware (CONFIG,eixo,raio,vmin,amin).
var sensor_eixo := "X"
var sensor_raio := 0.45
var sensor_vmin := 0.8
var sensor_amin := 3.5
## Porta serial configurada; "" = automática (primeira disponível).
var porta_configurada := ""

var countdown_left := 3.0
var last_count := 3
var espera_left := GameDef.ESPERA_DO_SOCO
## Se a rodada em curso debitou uma ficha. É o que autoriza a devolução
## quando a espera acaba sem soco — e, sendo consumido na devolução,
## impede que a mesma ficha volte duas vezes.
var credito_gasto := false
## Marcado quando `_carregar` converteu marcas da escala antiga. `_ready`
## grava logo em seguida, e é isso que torna a conversão de uma vez só.
var _converteu_esquema := false
## A ESTRELA DE PANCADA: quanto tempo desde o golpe, e com que força.
## Negativo quer dizer que não há pancada no ar.
var pancada_tempo := -1.0
var pancada_forca := 0.0
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
@onready var moldura: LedFrame = $Moldura
@onready var sons: AudioBank = $Audio

func _ready() -> void:
	fonte = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/Bungee-Regular.ttf"):
		fonte = load("res://assets/fonts/Bungee-Regular.ttf")
	if ResourceLoader.exists("res://assets/logo_lazersport.png"):
		logo = load("res://assets/logo_lazersport.png")
	_carregar()
	camera_service = CameraService.new()
	camera_service.enabled = camera_enabled
	camera_service.mirrored = camera_mirrored
	add_child(camera_service)
	_aplicar_faixas()
	if _converteu_esquema:
		_converteu_esquema = false
		_salvar()
		_show_notice("MARCAS CONVERTIDAS PARA A ESCALA 0000 – 9999")
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

## Um lugar só onde os parâmetros da curva são saneados.
##
## Os oito níveis têm faixas fixas, então não há mais limite ajustável
## para arrumar: o que precisa de saneamento é a curva, e ela é a mesma
## que a Central desenha, que o placar usa e que o firmware recebe. Uma
## passagem só por `ScoreCurve.sanitize` mantém as três concordando.
func _aplicar_faixas() -> void:
	var cfg := ScoreCurve.sanitize(hit_min_speed, hit_max_speed, score_exponent, score_dead_zone)
	hit_min_speed = cfg["min_speed"]
	hit_max_speed = cfg["max_speed"]
	score_exponent = cfg["exponent"]
	score_dead_zone = cfg["dead_zone"]

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

## ONDE O SOCO ATERRISSA NA TELA.
##
## Antes era o saco de pancadas desenhado que dizia o ponto. Sem ele, o
## alvo é o próprio visor: é dele que saem as ondas, as faíscas e o
## clarão, e é para ele que a tela de espera chama o punho. Um lugar só,
## para que efeito e imagem nunca discordem.
func _alvo() -> Vector2:
	return ALVO_DO_SOCO

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
	if pancada_tempo >= 0.0:
		pancada_tempo += delta
		if pancada_tempo > PANCADA_DURACAO:
			pancada_tempo = -1.0

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
		espera_left = GameDef.ESPERA_DO_SOCO
		carga_tempo = -1.0
		sons.play("go")
		sons.music(-19.0)
		moldura.set_estado(LedFrame.ARMADA)

func _processar_armado(delta: float) -> void:
	espera_left -= delta
	if carga_tempo >= 0.0:
		# Simulação carregando. O VISOR MOSTRA O VALOR EXATO, e não a
		# fração do tempo: a conversão tempo → pontos é uma curva, então
		# uma barra proporcional ao tempo mostraria 60 % quando o golpe
		# valeria 640. Quem carrega vê o número que vai tirar.
		carga_tempo = minf(carga_tempo + delta, ScoreCurve.CHARGE_MAX_SECONDS)
		carga_pontos = ScoreCurve.points_from_charge(
			carga_tempo, hit_min_speed, hit_max_speed, score_exponent, score_dead_zone
		)
	if espera_left <= 0.0:
		# A ESPERA ACABOU SEM SOCO — E A FICHA VOLTA.
		#
		# Antes a rodada simplesmente morria, com o crédito já debitado:
		# quem hesitou oito segundos pagou e não jogou, e é isso que
		# fazia o saldo evaporar sozinho. O limite continua existindo,
		# senão a máquina passa a tarde armada se a pessoa foi embora,
		# mas agora ele devolve em vez de cobrar.
		_cancelar_carga()
		sons.play("error", -4.0)
		_devolver_credito()
		_entrar_em_abertura()

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
	## dela é o da faixa — as mesmas três faixas da régua da Central.
	match GameDef.faixa_de(result_score):
		GameDef.Faixa.FORTE:
			# Estouros pela tela, sempre a partir de um ponto: cada um é
			# um eco do soco, e não um fogo de artifício solto no ar.
			if verdict_time < 5.0 and verdict_time >= proximo_fogo:
				proximo_fogo = verdict_time + 0.55
				var ponto := Vector2(randf_range(180.0, 900.0), randf_range(280.0, 900.0))
				fx.onda(ponto, 6.0, randf_range(150.0, 260.0), Color(Paleta.AMBAR, 0.5), 6.0, 0.5)
				fx.explosao(ponto, 22, CORES_FESTA, 820.0)
				fx.raios(ponto, 3, Paleta.CREME, 520.0)
			if verdict_time < 3.0 and randf() < delta * 22.0:
				fx.chuva_de_brasas(TELA.x, 2, CORES_FESTA)
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
		credito_gasto = true
	_discard_round_photo()
	intro_active = false
	sons.stop("score_loop")
	state = GameDef.State.COUNTDOWN
	posicao_no_ranking = 0
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
	clarao = 1.0
	tremor = 14.0
	sons.play("start")
	sons.music(-24.0)
	moldura.set_estado(LedFrame.CONTAGEM)
	fundo.matiz = Color(0, 0, 0, 0)
	_salvar()

## DEVOLVE A FICHA DA RODADA QUE NÃO ACONTECEU.
##
## Só em modo ficha, e só uma vez: quem jogou de graça não tem o que
## receber de volta, e devolver duas vezes seria fabricar crédito.
func _devolver_credito() -> void:
	if not credito_gasto:
		return
	credito_gasto = false
	if game_mode != "credit":
		return
	credits = mini(credits + 1, GameDef.CREDITOS_MAX)
	_salvar()
	_show_notice("TEMPO ESGOTADO — CRÉDITO DEVOLVIDO  •  SALDO %02d" % credits)

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
	# A ficha foi usada de verdade: daqui em diante não há o que devolver.
	credito_gasto = false
	result_score = clampi(pontos, 0, GameDef.SCORE_MAX)
	result_speed = maxf(velocidade, 0.0)
	result_simulado = simulado
	state = GameDef.State.MEASURING
	state_time = 0.0
	var forca := float(result_score) / float(GameDef.SCORE_MAX)
	var alvo := _alvo()
	moldura.impacto(0.4 + forca * 0.6)
	sons.play("hit", 1.5)
	sons.stop("charge")
	sons.music(-32.0)
	tremor = 10.0 + forca * 22.0
	clarao = 0.25 + forca * 0.45
	fx.onda(alvo, 30.0, 500.0 + forca * 400.0, Color(Paleta.VERMELHO, 0.6), 16.0, 0.7)
	fx.onda(alvo, 20.0, 300.0 + forca * 260.0, Color(Paleta.CREME, 0.75), 9.0, 0.38)
	fx.faiscas(alvo, 30 + int(forca * 50.0), Paleta.AMBAR, 700.0 + forca * 600.0)
	fx.explosao(alvo, 18 + int(forca * 26.0), CORES_FESTA, 900.0 + forca * 700.0)
	# A ESTRELA DE PANCADA precisa saber a hora exata do golpe: ela dura
	# um terço de segundo e é o desenho que diz "bateu", antes de
	# qualquer número aparecer.
	pancada_tempo = 0.0
	pancada_forca = forca
	plays += 1
	var origem := "SIMULAÇÃO" if simulado else "MPU-6050"
	posicao_no_ranking = _entrar_no_ranking(result_score, result_photo_path, origem)
	photo_retained = posicao_no_ranking > 0
	statistics = StatisticsStore.record(
		statistics, result_score,
		GameDef.faixa_de(result_score),
		posicao_no_ranking > 0
	)
	_salvar()

func _disparar_veredito() -> void:
	sons.stop("score_loop")
	sons.music(-28.0)
	## O momento em que a máquina diz quanto valeu o soco. Um por golpe.
	verdict_time = 0.0
	proximo_fogo = 0.0
	var classe := GameDef.classificar(result_score)
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
			# O QUE SAI DE UM SOCO NÃO É CONFETE. Brasas explodindo do
			# ponto do impacto, raios girando junto e três anéis em
			# sequência: a comemoração passa a ter a mesma linguagem da
			# pancada que a provocou, e não a de uma festa de aniversário.
			fx.explosao(alvo, 120, CORES_FESTA, 1500.0)
			fx.raios(alvo, 16, Paleta.AMBAR, 900.0)
			fx.chuva_de_brasas(TELA.x, 70, CORES_FESTA)
			for i in range(3):
				fx.onda(alvo, 60.0 + float(i) * 90.0, 900.0 + float(i) * 220.0,
					Color(Paleta.AMBAR if i != 1 else Paleta.CREME, 0.60 - float(i) * 0.14),
					18.0 - float(i) * 4.0, 0.9 + float(i) * 0.25)
		GameDef.Faixa.MEDIA:
			sons.play("medium")
			tremor = 14.0
			fx.explosao(alvo, 46, CORES_FESTA, 900.0)
			fx.faiscas(alvo, 40, Paleta.AMBAR, 700.0)
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
		_show_notice("RANKING E FOTOS ZERADOS")
	elif BOTOES_SIMPLES["reconectar"].has_point(p):
		if link != null:
			link.close_port()
		_tentar_conectar()
		_show_notice("RECONEXÃO SOLICITADA")
	elif BOTOES_SIMPLES["padroes"].has_point(p):
		game_mode = "credit"
		porta_configurada = ""
		hit_min_speed = ScoreCurve.DEFAULT_MIN_SPEED
		hit_max_speed = ScoreCurve.DEFAULT_MAX_SPEED
		score_exponent = ScoreCurve.DEFAULT_EXPONENT
		score_dead_zone = ScoreCurve.DEFAULT_DEAD_ZONE
		sensor_eixo = "X"
		sensor_raio = 0.45
		sensor_vmin = ScoreCurve.DEFAULT_MIN_SPEED
		sensor_amin = 3.5
		_show_notice("PADRÕES RESTAURADOS")
	else:
		return
	_aplicar_faixas()
	_salvar()

## Um clique num − ou + . Cada valor tem o seu passo e os seus limites,
## e o saneamento fica com `ScoreCurve.sanitize`, chamado por
## `_aplicar_faixas` logo depois de qualquer ajuste.
func _ajustar(chave: String, direcao: int) -> void:
	match chave:
		"vmin":
			hit_min_speed = clampf(
				hit_min_speed + direcao * 0.1,
				ScoreCurve.MIN_SPEED_MIN, minf(ScoreCurve.MIN_SPEED_MAX, hit_max_speed - 0.5)
			)
		"vmax":
			hit_max_speed = clampf(
				hit_max_speed + direcao * 0.5,
				maxf(ScoreCurve.MAX_SPEED_MIN, hit_min_speed + 0.5), ScoreCurve.MAX_SPEED_MAX
			)
		"curva":
			score_exponent = clampf(score_exponent + direcao * 0.05, ScoreCurve.EXPONENT_MIN, ScoreCurve.EXPONENT_MAX)
		"zona":
			score_dead_zone = clampf(score_dead_zone + direcao * 0.01, 0.0, ScoreCurve.DEAD_ZONE_MAX)
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
	# A versão gravada decide se as marcas ainda estão na escala antiga.
	# Ausente quer dizer "arquivo de antes de existir versão", ou seja,
	# escala 0 a 999 — e é essa a única vez que a conversão acontece.
	var esquema := int(data.get("ranking_schema", RankingStore.ESQUEMA_LEGADO))
	ranking = RankingStore.migrate(data.get("ranking", []), antigo, esquema)
	if esquema < RankingStore.ESQUEMA:
		# Grava a nova versão já, e não só no próximo `_salvar`: uma queda
		# de energia entre a conversão e o primeiro salvamento converteria
		# tudo de novo no religar.
		# Grava a versão nova AGORA, e não só no próximo `_salvar`: uma
		# queda de energia entre a conversão e o primeiro salvamento
		# converteria tudo outra vez no religar.
		_converteu_esquema = true
	porta_configurada = str(data.get("port", porta_configurada))
	hit_min_speed = float(data.get("hit_min_speed", hit_min_speed))
	hit_max_speed = float(data.get("hit_max_speed", hit_max_speed))
	score_exponent = float(data.get("score_exponent", score_exponent))
	score_dead_zone = float(data.get("score_dead_zone", score_dead_zone))
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
		"ranking_schema": RankingStore.ESQUEMA,
		# Mantido para uma eventual volta a uma versão anterior do jogo.
		"best_score": _melhor(),
		"port": porta_configurada,
		"hit_min_speed": hit_min_speed,
		"hit_max_speed": hit_max_speed,
		"score_exponent": score_exponent,
		"score_dead_zone": score_dead_zone,
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
	fundo.visible = true
	moldura.visible = false
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
	_draw_pancada()
	_draw_clarao()

	if notice != "" and not central_aberta:
		_draw_notice()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if central_aberta:
		_draw_central()

## A ESTRELA DE PANCADA.
##
## O desenho que diz "BATEU" antes de qualquer número: um estrelão
## irregular abrindo no ponto do golpe, com rachaduras saindo dele e um
## anel de riscos convergindo. É a gramática de história em quadrinhos, e
## ela existe porque anel e faísca sozinhos dizem "alguma coisa
## aconteceu" — não dizem "levou um soco".
##
## As pontas NÃO são sorteadas por quadro: um estrelão que muda de forma
## a cada quadro vira ruído. O molde é fixo e só a escala se move.
const PANCADA_DURACAO := 0.40
const PANCADA_PONTAS := 14
func _draw_pancada() -> void:
	if pancada_tempo < 0.0:
		return
	var t := clampf(pancada_tempo / PANCADA_DURACAO, 0.0, 1.0)
	var centro := _alvo()
	var escala := lerpf(0.35, 1.0, ease(t, 0.28)) * (0.75 + pancada_forca * 0.55)
	var some := pow(1.0 - t, 1.6)

	# Riscos convergindo: chegam de fora e morrem no ponto do impacto.
	for i in range(20):
		var ang := float(i) * TAU / 20.0 + 0.17
		var de := 420.0 + (1.0 - t) * 420.0
		var ate := de - lerpf(220.0, 40.0, t)
		draw_line(
			centro + Vector2.from_angle(ang) * de, centro + Vector2.from_angle(ang) * ate,
			Color(Paleta.AMBAR, some * 0.55), lerpf(8.0, 2.0, t), true
		)

	var fora := PackedVector2Array()
	var dentro := PackedVector2Array()
	for i in range(PANCADA_PONTAS * 2):
		var ang := float(i) * TAU / float(PANCADA_PONTAS * 2) - PI * 0.5
		# O denteado alterna longo/curto e ainda varia de ponta a ponta,
		# porque um estrelão perfeitamente regular lê como engrenagem.
		var longo := i % 2 == 0
		var variacao := 0.82 + 0.18 * sin(float(i) * 2.7)
		var raio := (330.0 if longo else 170.0) * variacao * escala
		fora.append(centro + Vector2.from_angle(ang) * raio)
		dentro.append(centro + Vector2.from_angle(ang) * raio * 0.72)
	draw_colored_polygon(fora, Color(Paleta.VERMELHO, some * 0.85))
	draw_colored_polygon(dentro, Color(Paleta.AMBAR, some * 0.95))
	draw_polyline(fora + PackedVector2Array([fora[0]]), Color(Paleta.CREME, some), 5.0, true)

	# Rachaduras: três traços quebrados saindo do miolo.
	for i in range(3):
		var ang := float(i) * TAU / 3.0 + 0.6
		var ponta := centro
		var caminho := PackedVector2Array([centro])
		for k in range(3):
			ponta += Vector2.from_angle(ang + sin(float(k) * 2.1 + float(i)) * 0.45) * (110.0 * escala)
			caminho.append(ponta)
		draw_polyline(caminho, Color(Paleta.CREME, some * 0.8), lerpf(9.0, 2.0, t), true)

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
			_texto("%04d" % RankingStore.score_at(ranking, i), meio, 44, Color(Paleta.TINTA, alpha), HORIZONTAL_ALIGNMENT_RIGHT, linha.position.x, linha.size.x - 40.0)
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

# ---------------------------------------------------------------- partida
## Todos os momentos da partida compartilham o mesmo visor. O que muda é
## o que está escrito nele, a cor do anel e quanto do anel está aceso.
func _draw_partida() -> void:
	# O cabeçalho da rodada é o MESMO letreiro do cabeçalho da abertura,
	# no mesmo corpo: são a mesma máquina, e a pessoa não deve sentir que
	# trocou de programa ao apertar START.
	_letreiro_centrado("PUNCH CHALLENGE", 145.0, 32, Paleta.CREME)
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
				_texto_arcade(str(clampi(int(ceil(countdown_left)), 1, 3)), 1400.0, 150, Color.WHITE, LARGURA_UTIL)
				_rotulo("OLHE PARA A CÂMERA", 1490.0, Paleta.AMBAR)
			else:
				_rotulo(
					"FOTO PRONTA" if not result_photo_path.is_empty() else "SEM CÂMERA • VAMOS JOGAR",
					1390.0, Paleta.AMBAR
				)
				_texto_arcade("PREPARE O SOCO", 1480.0, 56, Color.WHITE, LARGURA_UTIL)
		GameDef.State.ARMED:
			_draw_espera_do_soco()
		GameDef.State.MEASURING, GameDef.State.RESULT:
			_draw_score_hero()

## A TELA QUE ESPERA O SOCO.
##
## Não há mais saco desenhado nem barra de tempo. O saco de pancadas é a
## peça FÍSICA que a pessoa tem na frente do corpo; desenhar um segundo
## saco na tela dividia a atenção entre dois alvos, e o de pixel não é o
## que se acerta. E a barra que esvaziava contava um tempo que ninguém
## pediu — com o crédito já debitado, ela só servia para apressar.
##
## No lugar entra um FAROL: o mesmo visor que vai mostrar a pontuação,
## piscando e mandando anéis para fora, dizendo "estou armado, pode
## vir". Quem soca vê o número nascer exatamente onde o farol estava.
func _draw_espera_do_soco() -> void:
	var carregando := carga_tempo >= 0.0
	# ÂMBAR, E NÃO VERMELHO, ENQUANTO ESPERA. O painel já é vermelho
	# sobre vermelho; um farol vermelho dentro dele desaparece a três
	# metros, que é exatamente a distância de quem ainda está decidindo
	# se soca. Assim que a carga começa, a cor passa a ser a da faixa.
	var cor := Paleta.AMBAR
	if carregando:
		cor = GameDef.classificar(carga_pontos)["cor_faixa"] as Color

	_draw_farol(cor, carregando)

	if carregando:
		# CARREGANDO (teclado, sem sensor): o número exato que sai se
		# soltar agora, no mesmo visor e no mesmo formato em que ele vai
		# aparecer no resultado. Quem carrega não adivinha quanto vale
		# quanto: solta quando o número que está vendo serve.
		_rotulo("PONTOS SE SOLTAR AGORA", 785.0, cor)
		VisorLed.desenhar(self, "%04d" % carga_pontos, ALVO_DO_SOCO + Vector2(0.0, 20.0), 168.0, Color.WHITE)
		var piscada := 0.6 + 0.4 * sin(animation_time * 9.0)
		_texto_arcade("SOLTE!", 1430.0, 72, Color(Paleta.AMBAR, piscada), LARGURA_UTIL)
	else:
		_rotulo("ESTOU PRONTO", 785.0, cor)
		VisorLed.desenhar(self, "---", ALVO_DO_SOCO + Vector2(0.0, 20.0), 168.0, cor)
		var piscada := 0.78 + 0.22 * sin(animation_time * 4.4)
		_texto_arcade("SOQUE AGORA!", 1400.0, 96, Color(Color.WHITE, piscada), LARGURA_UTIL)
		var dica := "ACERTE O ALVO COM TODA A FORÇA" if _sensor_ligado() \
			else "SEGURE E SOLTE ESPAÇO PARA SIMULAR"
		_rotulo(dica, 1468.0, Color.WHITE)
		# A MARCA A BATER FICA DENTRO DO VISOR, não embaixo dele: a faixa
		# vermelha do fundo começa perto de 1500 px e engole qualquer
		# texto miúdo que caia ali. Dentro do vidro escuro ela é legível
		# e, de quebra, fica ao lado do número que vai substituí-la.
		_rotulo("RECORDE DA CASA  %04d" % _melhor(), 1105.0, Paleta.AMBAR)

	# O RELÓGIO SÓ APARECE NO FIM, e vem acompanhado da promessa.
	#
	# Nos primeiros setenta e cinco segundos não há relógio nenhum: a
	# máquina espera calada, que é o que se pediu. Só quando ela vai
	# mesmo desistir é que avisa — e avisa dizendo que a ficha volta,
	# senão o aviso vira ameaça.
	if espera_left <= GameDef.AVISO_DE_VOLTA:
		var segundos := maxi(0, int(ceil(espera_left)))
		_apoio("VOLTANDO EM %02d  •  O CRÉDITO É DEVOLVIDO" % segundos, 1660.0, Color.WHITE)

## O FAROL: anéis saindo do alvo, em batidas.
##
## Três anéis defasados, sempre no mesmo compasso, e um halo respirando
## por trás. É a única coisa que se move nesta tela, e move sempre para
## FORA — na direção de quem está olhando, chamando o soco. Anéis
## entrando para dentro leriam como contagem regressiva, que é
## exatamente o que esta tela deixou de ter.
func _draw_farol(cor: Color, carregando: bool) -> void:
	var centro := ALVO_DO_SOCO
	var compasso := 1.15
	for i in range(3):
		var fase := fmod(animation_time / compasso + float(i) / 3.0, 1.0)
		var raio := lerpf(330.0, 620.0, ease(fase, 0.45))
		draw_arc(centro, raio, 0.0, TAU, 96, Color(cor, (1.0 - fase) * 0.55), 10.0, true)
	# O anel do visor: correndo em volta enquanto espera, cheio conforme
	# a carga quando alguém está simulando pelo teclado.
	draw_circle(centro, 326.0, Color("250911"))
	draw_arc(centro, 327.0, 0.0, TAU, 192, Color("6d2835"), 4.0, true)
	var carga := clampf(float(carga_pontos) / float(GameDef.SCORE_MAX), 0.0, 1.0)
	for i in range(60):
		var angulo := float(i) / 60.0 * TAU - PI * 0.5
		var aceso := false
		if carregando:
			aceso = float(i) / 60.0 <= carga
		else:
			# Três marcas correndo, do jeito que um letreiro de fliperama
			# fica quando está ligado e ocioso.
			var passo := fmod(animation_time * 0.55, 1.0)
			var d := fmod(float(i) / 60.0 - passo + 1.0, 1.0)
			aceso = d < 0.06 or absf(d - 0.3333) < 0.03 or absf(d - 0.6667) < 0.03
		draw_arc(centro, 347.0, angulo, angulo + 0.065, 5, cor if aceso else Color("57212c"), 14.0, true)

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
	_texto("%04d" % _melhor(), 1400.0, 98, Color(Paleta.AMBAR, alpha))

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
		color = GameDef.classificar(result_score)["cor_faixa"] as Color
	_draw_campo_de_forca(center, color, progress, measuring)
	_draw_colunas_de_forca(color, progress)
	for i in range(12):
		draw_arc(center, 335.0 + float(i) * 3.0, 0, TAU, 192, Color(color, 0.02), 9.0, true)
	draw_circle(center, 326.0, Color("250911"))
	draw_arc(center, 327, 0, TAU, 192, Color("6d2835"), 4.0, true)
	for i in range(60):
		var angle := float(i) / 60.0 * TAU - PI * 0.5
		var lit := float(i) / 60.0 <= progress
		draw_arc(center, 347, angle, angle + 0.065, 5, color if lit else Color("57212c"), 14.0, true)
	draw_arc(center, 302, animation_time * 0.5, animation_time * 0.5 + 1.2, 64, Color(color, 0.55), 2.0, true)
	_rotulo("IMPACTO" if measuring else ("SUA PONTUAÇÃO" if verdict_time >= 0.0 else "CALCULANDO"), 785.0, color)
	# VISOR DE SETE SEGMENTOS, e não texto. Numa máquina de fliperama o
	# placar é um painel de LED atrás de um vidro, e o que o olho
	# reconhece não é o formato do algarismo: é o SEGMENTO APAGADO, que
	# continua visível atrás do número. Nenhuma fonte dá isso.
	VisorLed.desenhar(
		self, "----" if measuring else "%04d" % int(round(displayed_score)),
		center + Vector2(0.0, 20.0), 168.0, Color.WHITE if not measuring else color
	)
	if verdict_time >= 0.0:
		_rotulo("PONTOS", 1110.0, color)
		# A VELOCIDADE MEDIDA, ao lado dos pontos. Os pontos são uma nota
		# que a máquina inventou a partir de uma curva ajustável; a
		# velocidade é o que o sensor de fato viu. Quem duvida do placar
		# ("essa máquina está roubando") tem aqui o número cru.
		_apoio("%.1f m/s no sensor" % result_speed, 1330.0, Paleta.TINTA_FRACA)
		var title := "%dº LUGAR" % posicao_no_ranking if posicao_no_ranking > 0 else "BOM SOCO!"
		_texto_arcade(title, 1430.0, 64, color, LARGURA_UTIL)

## O VAZIO ATRÁS DO PLACAR ERA O MAIOR PEDAÇO DA TELA.
##
## O medalhão ocupa o meio e o painel é alto: sobrava um retângulo preto
## de mais de mil pixels em volta, justamente nos dois segundos em que
## todo mundo está olhando. Agora o placar irradia — e irradia NA MEDIDA
## DA PONTUAÇÃO, para que a tela inteira, e não só o número, diga se o
## soco foi forte.
func _draw_campo_de_forca(centro: Vector2, cor: Color, progresso: float, no_impacto: bool) -> void:
	# No meio segundo do impacto ainda não há pontuação nenhuma para
	# mostrar, então quem manda é o próprio golpe: começa no talo e
	# desinfla enquanto a máquina "calcula".
	var forca := progresso
	if no_impacto:
		forca = 1.0 - clampf(state_time / GameDef.IMPACTO_DURACAO, 0.0, 1.0)
	for i in range(7):
		draw_circle(centro, 380.0 + float(i) * 64.0, Color(cor, 0.013 * forca))
	for i in range(36):
		var ang := float(i) * TAU / 36.0 + animation_time * 0.22
		var onda := 0.5 + 0.5 * sin(float(i) * 1.7 - animation_time * 4.0)
		var perto := 372.0
		var longe := perto + lerpf(24.0, 200.0, forca * onda)
		draw_line(
			centro + Vector2.from_angle(ang) * perto,
			centro + Vector2.from_angle(ang) * longe,
			Color(cor, 0.08 + 0.34 * forca * onda), 6.0, true
		)

## AS DUAS COLUNAS, uma de cada lado do painel.
##
## São a mesma pontuação lida de outro jeito, e existem porque o número
## no meio é redondo e o olho não compara redondo com redondo. Coluna
## cheia contra coluna pela metade é a diferença entre dois socos vista
## de longe, sem ler algarismo nenhum.
func _draw_colunas_de_forca(cor: Color, progresso: float) -> void:
	var degraus := 22
	for lado in [0.0, 1.0]:
		var x := lerpf(92.0, 944.0, lado)
		for i in range(degraus):
			var fatia := float(i) / float(degraus)
			var caixa := Rect2(x, 1512.0 - float(i) * 44.0, 44.0, 26.0)
			if fatia < progresso:
				draw_rect(caixa, cor)
				draw_rect(caixa.grow(3.0), Color(cor, 0.18))
			else:
				draw_rect(caixa, Color("3a141d"))

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
		# AS LINHAS ENTRAM PELA ESQUERDA, nunca pela direita.
		#
		# O deslocamento era positivo: cada linha começava até 200 px à
		# direita do lugar dela e, como a largura não mudava, a linha
		# inteira passava dos 1080 px da tela — a pontuação, que fica na
		# ponta direita, ficava cortada durante toda a entrada. Negativo,
		# a linha entra de fora da tela e assenta; nada some.
		var shift := -(1.0 - eased) * (80.0 + float(i % 5) * 30.0)
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
		_texto("%04d" % RankingStore.score_at(ranking, i), y + 106.0, 62, Paleta.TINTA, HORIZONTAL_ALIGNMENT_RIGHT, card.position.x, card.size.x - 35.0)
	_rotulo("SEU SOCO", 1400.0, Paleta.TINTA_FRACA)
	_texto_arcade("%04d" % result_score, 1520.0, 100, Paleta.TINTA, LARGURA_UTIL)
	_rotulo("START • JOGAR NOVAMENTE", 1706.0, Paleta.AMBAR)

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

	# ---- velocidade e dificuldade: é aqui que se regula a máquina
	_secao(Rect2(80, 416, 920, 284), "VELOCIDADE E DIFICULDADE", Paleta.CIANO)
	_stepper("vmin", "%.1f m/s" % hit_min_speed, "MÍNIMA  =  0000 PONTOS", Paleta.CIANO)
	_stepper("vmax", "%.1f m/s" % hit_max_speed, "MÁXIMA  =  9999 PONTOS", Paleta.CIANO)
	_stepper(
		"curva", "γ %.2f" % score_exponent,
		"CURVA  %s" % ScoreCurve.difficulty_name(score_exponent), Paleta.ROXO
	)
	_stepper("zona", "%.0f%%" % (score_dead_zone * 100.0), "ZONA MORTA", Paleta.ROXO)

	# ---- os oito níveis: régua de leitura, não de regulagem
	_secao(Rect2(80, 716, 920, 244), "OS OITO NÍVEIS (0000 – 9999)", Paleta.AMBAR)
	_regua_dos_niveis(Rect2(110, 776, 860, 40))
	_texto(
		"As faixas dos níveis são fixas. Quem decide quanta gente chega a cada uma é a curva acima.",
		880.0, 15, Paleta.TINTA_FRACA
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
		"Hoje %d  •  7 dias %d  •  média %04d  •  Top 5: %d" % [resumo["today"], resumo["last7"], resumo["average"], resumo["top5_entries"]],
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
			"%04d" % RankingStore.score_at(ranking, i) if tem else "—", celula.position.y + 44.0, 22,
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

## A RÉGUA DOS OITO NÍVEIS, na largura de cada um.
##
## Ela é de LEITURA: as faixas são fixas e não há o que arrastar aqui. O
## que ela mostra é a desproporção — os quatro níveis de cima ocupam um
## quinto da escala, e é vendo isso que o técnico entende por que quase
## ninguém chega ao topo, em vez de achar que a máquina está quebrada.
func _regua_dos_niveis(rect: Rect2) -> void:
	var teto := float(GameDef.SCORE_MAX + 1)
	for nivel in ScoreTier.NIVEIS:
		var x0 := rect.position.x + rect.size.x * (float(nivel["min"]) / teto)
		var x1 := rect.position.x + rect.size.x * (float(int(nivel["max"]) + 1) / teto)
		draw_rect(Rect2(x0, rect.position.y, x1 - x0, rect.size.y), nivel["cor"] as Color)
		if x1 - x0 > 96.0:
			# Preto sobre cor clara, branco sobre cor escura. A cor do
			# nível é dado de projeto e vai de creme a azul-acinzentado:
			# um contraste fixo apagaria metade dos nomes.
			var cor: Color = nivel["cor"]
			var tinta := Color.BLACK if cor.get_luminance() > 0.55 else Color.WHITE
			_texto(
				str(nivel["nome"]), rect.position.y + rect.size.y * 0.66, 14, tinta,
				HORIZONTAL_ALIGNMENT_CENTER, x0, x1 - x0
			)
	draw_rect(rect, Paleta.CARTAO_BORDA, false, 2.0)
	# O teto da escala fica marcado à direita: é o único ponto da régua
	# que uma pessoa pode alcançar e não é uma faixa, é um alvo.
	_texto("9999", rect.end.y + 22.0, 15, Paleta.CREME, HORIZONTAL_ALIGNMENT_RIGHT, rect.position.x, rect.size.x)
	_texto("0000", rect.end.y + 22.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, rect.position.x, rect.size.x)

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

## OS TRÊS PAPÉIS DE TEXTO DA TELA DE JOGO.
##
## Antes cada linha escolhia o seu corpo na hora — 25, 26, 30, 32, 34, 46
## — e metade delas era `draw_string` cru, sem contorno, sobre um painel
## que muda de cor a cada faixa. O resultado era uma tela com sete
## tamanhos e dois acabamentos diferentes, e é isso que faz uma tela
## parecer amadora, mesmo quando cada peça sozinha está certa.
##
## Agora há três papéis e nada mais:
##
##   TÍTULO  o que a pessoa lê de longe. Letreiro com contorno e halo,
##           igual ao da abertura — é a mesma tipografia do cartaz.
##   RÓTULO  o que nomeia um número: "CALCULANDO", "PONTOS". Sempre 26,
##           sempre com contorno, porque ele cai sobre o painel escuro,
##           sobre a faixa vermelha e sobre o clarão do soco.
##   APOIO   a letra miúda de quem quiser conferir. Sempre 22.
##
## Todos com o mesmo contorno da abertura: é isso que "uniformiza com as
## iniciais" de verdade, e não só igualar o corpo da letra.
const CORPO_ROTULO := 26
const CORPO_APOIO := 22

func _rotulo(texto: String, y: float, cor: Color) -> void:
	_letreiro_centrado(texto, y, CORPO_ROTULO, cor)

func _apoio(texto: String, y: float, cor: Color) -> void:
	_letreiro_centrado(texto, y, CORPO_APOIO, cor)

## Letreiro centrado na largura útil, sem encolher: o corpo dos rótulos é
## fixo de propósito, e um rótulo que não cabe é um rótulo comprido
## demais, não um rótulo que precisa diminuir.
func _letreiro_centrado(texto: String, y: float, tamanho: int, cor: Color) -> void:
	var medida := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
	_letreiro(texto, Vector2(540.0 - medida.x * 0.5, y), tamanho, cor)

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
