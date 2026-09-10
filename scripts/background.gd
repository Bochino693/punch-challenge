class_name PunchBackground
extends Control

const ArcadeStage = preload("res://scripts/presentation/arcade_stage.gd")

## O salão onde a máquina fica: claro, com o piso em perspectiva e um
## refletor quente caindo sobre o saco.
##
## CLARO POR DECISÃO, NÃO POR DESCUIDO. A máquina trabalha num salão de
## festas iluminado. Fundo preto ali lê como monitor desligado, e o preto
## engole o vermelho da marca da casa, que é justamente o que precisa
## aparecer de longe. O céu é um degradê claro, o chão é mais quente que
## o topo, e o que dá profundidade é a perspectiva do piso — não a
## escuridão.
##
## O REFLETOR NÃO É ENFEITE. Sem ele o saco fica boiando num retângulo
## chapado; com ele há um cone de luz vindo do teto, uma poça quente no
## piso e uma sombra embaixo do saco — três pistas baratas que dizem ao
## olho onde a cena acontece. `FOCO` é a posição do refletor em fração do
## tamanho do controle, então acompanha o palco em qualquer resolução.

## Onde o refletor aponta, em fração da tela. Combina com o centro do
## saco definido em `scenes/main.tscn`.
const FOCO := Vector2(0.481, 0.29)
## Altura do piso, em fração da tela.
const HORIZONTE := 0.58

var tempo := 0.0
var fx := PunchFX.new()
## Tonalidade do veredito: tinge a tela inteira após o golpe.
var matiz := Color(0, 0, 0, 0)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	# O MESMO FREIO DE `main.gd`, com o mesmo teto (ver o comentário lá):
	# só entra numa queda catastrófica de verdade (abaixo de 10 fps), não
	# no simples peso de uma tela cheia de efeito — senão a poeira sobe
	# em câmera lenta bem quando o cenário está mais pesado.
	var passo := minf(delta, 0.1)
	tempo += passo
	fx.atualizar(passo)
	if randf() < passo * 2.5:
		# Poeira brilhando dentro do cone de luz, subindo devagar.
		fx.poeira(
			Vector2(randf_range(0.25, 0.75) * size.x, size.y * HORIZONTE),
			1, Color(1.0, 0.86, 0.55, 0.40), 60.0
		)
	queue_redraw()

func _draw() -> void:
	# O CENÁRIO MORA AQUI, e não no nó raiz.
	#
	# Quando o cenário era pintado pelo `_draw` da raiz, ele saía DEPOIS
	# dos filhos e por cima deles — e foi por isso que o saco e o medidor
	# tiveram de ser escondidos para a tela não virar uma mancha. Só que
	# escondidos eles nunca mais voltaram, e a janela do soco virou texto
	# sobre um vazio preto. Pintando o cenário neste nó (z = -2), a ordem
	# volta a ser a natural: cenário, palco, texto, moldura.
	ArcadeStage.background(self, tempo)
	fx.desenhar(self)
	if matiz.a > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), matiz)
