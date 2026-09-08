extends SceneTree

## Ferramenta de desenvolvimento: abre a cena principal, força cada
## momento do jogo e salva um PNG de cada um em user://telas/.
## Uso: godot --path . --script tools/capturar_telas.gd

const TELA := Vector2i(1080, 1920)
var jogo: Control
var passos: Array = []
var indice := 0
var espera := 0
var destino := ""

func _initialize() -> void:
	destino = OS.get_environment("PUNCH_SHOTS")
	if destino.is_empty():
		destino = "res://.telas"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destino))
	DisplayServer.window_set_size(TELA)
	get_root().content_scale_size = TELA
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var cena: PackedScene = load("res://scenes/main.tscn")
	jogo = cena.instantiate()
	get_root().add_child(jogo)
	passos = [
		{"nome": "01_abertura", "fn": _abertura},
		{"nome": "01b_recordes", "fn": _abertura_recordes},
		{"nome": "01c_como_jogar", "fn": _abertura_como_jogar},
		{"nome": "02_contagem", "fn": _contagem},
		{"nome": "03_armado", "fn": _armado},
		{"nome": "04_carga", "fn": _carga},
		{"nome": "05_impacto", "fn": _impacto},
		{"nome": "06_contando", "fn": _contando},
		{"nome": "07_lendario", "fn": _lendario},
		{"nome": "08_forte", "fn": _forte},
		{"nome": "09_leve", "fn": _leve},
		{"nome": "10_central", "fn": _central},
	]

func _process(_delta: float) -> bool:
	if indice >= passos.size():
		return true
	if espera == 0:
		passos[indice]["fn"].call()
		espera = 8
		return false
	espera -= 1
	if espera > 0:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png("%s/%s.png" % [destino, passos[indice]["nome"]])
	indice += 1
	espera = 0
	return false

# --------------------------------------------------------------- momentos
func _preparar(estado: int) -> void:
	# A cutscene de entrada roda uma vez ao ligar a máquina e engole a
	# abertura enquanto está no ar. Sem desligá-la aqui, TODA captura de
	# IDLE fotografava a entrada e não a tela que se quer conferir.
	jogo.intro_active = false
	jogo.central_aberta = false
	jogo.state = estado
	jogo.state_time = 1.4
	jogo.animation_time = 3.0
	jogo.saco.visible = estado != GameDef.State.IDLE
	jogo.medidor.visible = estado != GameDef.State.IDLE

func _abertura() -> void:
	jogo.ranking = RankingStore.migrate([872, 705, 640, 512, 388])
	jogo.plays = 431
	jogo.credits = 3
	jogo.medidor.recorde = 872
	_preparar(GameDef.State.IDLE)
	jogo.state_time = 2.0

## O rodízio da abertura é por tempo, então cada página é capturada
## colocando o relógio dentro da janela dela.
func _abertura_recordes() -> void:
	_abertura()
	jogo.state_time = jogo.ABERTURA_DURACAO + 2.0

func _abertura_como_jogar() -> void:
	_abertura()
	jogo.state_time = jogo.ABERTURA_DURACAO * 2.0 + 2.0

func _contagem() -> void:
	_preparar(GameDef.State.COUNTDOWN)
	jogo.countdown_left = 2.4
	jogo.moldura.set_estado(LedFrame.CONTAGEM)

func _armado() -> void:
	_preparar(GameDef.State.ARMED)
	jogo.armed_left = 5.7
	jogo.carga_tempo = -1.0
	jogo.saco.set_alvo(true)
	jogo.moldura.set_estado(LedFrame.ARMADA)

func _carga() -> void:
	_preparar(GameDef.State.ARMED)
	jogo.armed_left = 4.2
	jogo.carga_tempo = 0.9
	jogo.medidor.set_carga(0.6)
	jogo.saco.set_carga(0.6)

func _impacto() -> void:
	jogo.carga_tempo = -1.0
	jogo.medidor.set_carga(-1.0)
	jogo.saco.set_carga(-1.0)
	_preparar(GameDef.State.MEASURING)
	jogo.state_time = 0.25
	jogo.result_score = 903
	jogo.saco.golpear(0.9)

func _resultado(pontos: int, veredito: float) -> void:
	_preparar(GameDef.State.RESULT)
	jogo.saco.set_alvo(false)
	jogo.fx.limpar()
	jogo.result_score = pontos
	jogo.result_speed = 9.4
	jogo.result_simulado = false
	jogo.posicao_no_ranking = 1 if pontos > 900 else (3 if pontos > 600 else 0)
	jogo.displayed_score = float(pontos) if veredito >= 0.0 else float(pontos) * 0.55
	jogo.medidor.set_pontos(jogo.displayed_score)
	jogo.medidor.nivel_visivel = jogo.medidor.nivel_alvo
	jogo.verdict_time = veredito
	jogo.result_time = 1.9 if veredito >= 0.0 else 1.0
	if veredito >= 0.0:
		jogo.moldura.set_estado(LedFrame.RESULTADO, GameDef.classificar(pontos, jogo.limiar_fraco, jogo.limiar_forte)["cor_faixa"])

func _contando() -> void:
	_resultado(903, -1.0)

func _lendario() -> void:
	_resultado(961, 1.6)

func _forte() -> void:
	_resultado(645, 1.6)

func _leve() -> void:
	_resultado(148, 1.6)

func _central() -> void:
	_preparar(GameDef.State.IDLE)
	jogo.central_aberta = true
