class_name PunchBackground
extends Control

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
const FOCO := Vector2(0.481, 0.34)
## Altura do piso, em fração da tela.
const HORIZONTE := 0.625
## Em quantas faixas o céu é pintado. Bastante para o degradê não
## mostrar bandas, pouco o suficiente para não pesar num PC de salão.
const FAIXAS_DO_CEU := 64

var tempo := 0.0
var fx := PunchFX.new()
## Tonalidade do veredito: tinge a tela inteira após o golpe.
var matiz := Color(0, 0, 0, 0)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	tempo += delta
	fx.atualizar(delta)
	if randf() < delta * 2.5:
		# Poeira brilhando dentro do cone de luz, subindo devagar.
		fx.poeira(
			Vector2(randf_range(0.25, 0.75) * size.x, size.y * HORIZONTE),
			1, Color(1.0, 0.86, 0.55, 0.40), 60.0
		)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	_ceu(w, h)
	_piso(w, h)
	_refletor(w, h)
	_bolhas(w, h)

	fx.desenhar(self)

	if matiz.a > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), matiz)

## Degradê do céu, em faixas horizontais. Sem shader e sem textura: numa
## máquina de salão o computador costuma ser modesto, e sessenta e quatro
## retângulos custam menos que qualquer das duas alternativas.
func _ceu(w: float, h: float) -> void:
	var altura := h / float(FAIXAS_DO_CEU)
	for i in range(FAIXAS_DO_CEU):
		var t := float(i) / float(FAIXAS_DO_CEU - 1)
		draw_rect(
			Rect2(0.0, float(i) * altura, w, altura + 1.0),
			Paleta.CEU_TOPO.lerp(Paleta.CEU_BASE, ease(t, 1.6))
		)

## Piso em perspectiva, com o ponto de fuga alinhado ao refletor: as
## linhas do chão apontam para o saco em vez de para o meio da tela.
func _piso(w: float, h: float) -> void:
	var horizonte := h * HORIZONTE
	var fuga := w * FOCO.x
	draw_rect(Rect2(0.0, horizonte, w, h - horizonte), Paleta.PISO)
	for i in range(20):
		var t := float(i) / 20.0
		var y := horizonte + pow(t, 2.2) * (h - horizonte)
		draw_line(Vector2(0, y), Vector2(w, y), Color(Paleta.PISO_LINHA, 0.55), 1.0)
	for i in range(-10, 11):
		draw_line(
			Vector2(fuga + i * w * 0.022, horizonte),
			Vector2(fuga + i * w * 0.20, h),
			Color(Paleta.PISO_LINHA, 0.45), 1.0
		)
	# Linha do horizonte, para o piso encostar no céu e não flutuar.
	draw_line(Vector2(0, horizonte), Vector2(w, horizonte), Color(Paleta.PISO_LINHA, 0.5), 2.0)

## O cone de luz e a poça no chão. Num fundo claro a luz é ADITIVA e
## quente: clarear o que já é claro só funciona se a cor mudar de
## temperatura junto, senão o cone some.
func _refletor(w: float, h: float) -> void:
	var alvo := Vector2(w * FOCO.x, h * FOCO.y)
	var topo := -h * 0.02
	var piso := h * 0.68
	var respiro := 1.0 + sin(tempo * 0.7) * 0.03
	for i in range(4):
		var k := (1.0 - float(i) * 0.22) * respiro
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(alvo.x - w * 0.07 * k, topo),
				Vector2(alvo.x + w * 0.07 * k, topo),
				Vector2(alvo.x + w * 0.34 * k, piso),
				Vector2(alvo.x - w * 0.34 * k, piso),
			]),
			Color(Paleta.LUZ, 0.16)
		)
	# Poça de luz no chão, achatada pela perspectiva.
	var centro_piso := Vector2(alvo.x, h * 0.64)
	for i in range(4):
		var k := 1.0 - float(i) * 0.22
		draw_colored_polygon(
			_elipse(centro_piso, w * 0.32 * k, h * 0.050 * k, 48),
			Color(Paleta.LUZ, 0.13)
		)

## Bolhas de festa flutuando: dão movimento sem competir com o saco, e
## brilham mais dentro do cone de luz do que fora dele.
func _bolhas(w: float, h: float) -> void:
	for i in range(18):
		var x := fmod(float(i * 271), w)
		var y := fmod(float(i * 397) + tempo * (10.0 + i * 0.4), h)
		var perto := 1.0 - clampf(absf(x - w * FOCO.x) / (w * 0.45), 0.0, 1.0)
		var r := 4.0 + float(i % 4) * 3.0
		var cor: Color = Paleta.FESTA[i % Paleta.FESTA.size()]
		draw_circle(Vector2(x, y), r, Color(cor, 0.06 + 0.07 * perto))
		draw_arc(Vector2(x, y), r, 0.0, TAU, 18, Color(cor, 0.10 + 0.12 * perto), 1.5, true)

func _elipse(centro: Vector2, rx: float, ry: float, passos: int) -> PackedVector2Array:
	var pontos := PackedVector2Array()
	for i in range(passos + 1):
		var a := float(i) / float(passos) * TAU
		pontos.append(centro + Vector2(cos(a) * rx, sin(a) * ry))
	return pontos
