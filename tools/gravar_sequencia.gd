extends SceneTree

## Ferramenta de desenvolvimento: roda o jogo DE VERDADE e fotografa a
## tela em intervalos regulares, para conferir as SEQUÊNCIAS — abertura,
## contagem, golpe, resultado — e não só quadros isolados.
##
## O `capturar_telas.gd` força cada estado e serve para conferir
## enquadramento. Este aqui deixa o jogo correr sozinho: é o único jeito
## de ver se o ritmo da cut scene, das animações e das trocas de tela
## está bom.
##
## Uso: godot --path . --script tools/gravar_sequencia.gd
##   PUNCH_SHOTS  pasta de saída
##   PUNCH_ROTEIRO  "abertura" (padrão) ou "rodada"

const TELA := Vector2i(1080, 1920)
## De quantos em quantos quadros uma foto é tirada.
const PASSO := 6
## Quantas fotos no total.
const FOTOS := 60

var jogo: Control
var destino := ""
var roteiro := "abertura"
var quadro := 0
var tiradas := 0

func _initialize() -> void:
	destino = OS.get_environment("PUNCH_SHOTS")
	if destino.is_empty():
		destino = "res://.telas"
	roteiro = OS.get_environment("PUNCH_ROTEIRO")
	if roteiro.is_empty():
		roteiro = "abertura"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destino))
	DisplayServer.window_set_size(TELA)
	get_root().content_scale_size = TELA
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	jogo = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(jogo)
	jogo.credits = 9
	jogo.game_mode = "credit"

func _process(_delta: float) -> bool:
	quadro += 1
	_dirigir()
	if quadro % PASSO == 0:
		get_root().get_texture().get_image().save_png("%s/q%03d.png" % [destino, tiradas])
		tiradas += 1
	return tiradas >= FOTOS

## O roteiro: em que quadro cada comando entra. Números e não segundos
## porque o quadro aqui é lento (software rendering) e um relógio de
## parede daria capturas em pontos diferentes a cada execução.
func _dirigir() -> void:
	if roteiro != "rodada":
		return
	match quadro:
		30:
			jogo._pressionou_start()
		140:
			# Golpe de nocaute, no meio da janela do soco.
			jogo._registrar_impacto(961, 11.4, true)
