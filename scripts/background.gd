class_name PunchBackground
extends Control

## O fundo do gabinete: preto profundo, piso em perspectiva e uma luz de
## palco caindo sobre o saco.
##
## O REFLETOR NÃO É ENFEITE. Sem ele o saco fica boiando num retângulo
## preto, sem chão e sem lugar; com ele há um cone de luz vindo do teto,
## uma poça iluminada no piso e uma sombra embaixo do saco — três pistas
## baratas que dizem ao olho onde a cena acontece. `FOCO` é a posição
## do refletor em fração do tamanho do controle, então acompanha o palco
## em qualquer resolução.
##
## Tudo é desenhado em escala relativa ao tamanho real do controle, então
## nada corta em telas que não sejam 1080 × 1920.

## Onde o refletor aponta, em fração da tela. Combina com o centro do
## saco definido em `scenes/main.tscn`.
const FOCO := Vector2(0.481, 0.34)
## Altura do piso, em fração da tela.
const HORIZONTE := 0.60

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
	if randf() < delta * 3.0:
		fx.poeira(
			Vector2(randf_range(0.2, 0.8) * size.x, size.y * HORIZONTE),
			1, Color(0.55, 0.75, 1.0, 0.16), 70.0
		)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("04060f"))

	_paredes(w, h)
	_piso(w, h)
	_refletor(w, h)
	_ambiente(w, h)

	fx.desenhar(self)

	if matiz.a > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), matiz)

## Brilhos grandes e lentos ao fundo: profundidade sem textura.
func _paredes(w: float, h: float) -> void:
	_glow(Vector2(w * 0.13, h * 0.14), w * 0.30, Color(0.02, 0.55, 0.95, 0.06))
	_glow(Vector2(w * 0.88, h * 0.70), w * 0.34, Color(0.62, 0.09, 0.52, 0.06))
	_glow(Vector2(w * 0.5, h * 0.44), w * 0.22 + sin(tempo * 0.8) * w * 0.02, Color(0.10, 0.30, 0.85, 0.04))

## Piso em perspectiva, com o ponto de fuga alinhado ao refletor: as
## linhas do chão apontam para o saco em vez de para o meio da tela.
func _piso(w: float, h: float) -> void:
	var horizonte := h * HORIZONTE
	var fuga := w * FOCO.x
	for i in range(18):
		var t := float(i) / 18.0
		var y := horizonte + pow(t, 2.2) * (h - horizonte)
		draw_line(Vector2(0, y), Vector2(w, y), Color(0.16, 0.42, 0.85, 0.075), 1.0)
	for i in range(-10, 11):
		draw_line(
			Vector2(fuga + i * w * 0.022, horizonte),
			Vector2(fuga + i * w * 0.20, h),
			Color(0.16, 0.42, 0.85, 0.06), 1.0
		)

## O cone de luz e a poça no chão. O cone é um trapézio com três camadas
## que vão perdendo alpha — a névoa de um refletor de palco.
func _refletor(w: float, h: float) -> void:
	var alvo := Vector2(w * FOCO.x, h * FOCO.y)
	var topo := -h * 0.02
	var piso := h * 0.66
	var respiro := 1.0 + sin(tempo * 0.7) * 0.03
	for i in range(3):
		var k := (1.0 - float(i) * 0.26) * respiro
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(alvo.x - w * 0.07 * k, topo),
				Vector2(alvo.x + w * 0.07 * k, topo),
				Vector2(alvo.x + w * 0.34 * k, piso),
				Vector2(alvo.x - w * 0.34 * k, piso),
			]),
			Color(0.45, 0.72, 1.0, 0.020)
		)
	# Poça de luz no chão, achatada pela perspectiva.
	var centro_piso := Vector2(alvo.x, h * 0.60)
	for i in range(4):
		var k := 1.0 - float(i) * 0.22
		draw_colored_polygon(
			_elipse(centro_piso, w * 0.30 * k, h * 0.045 * k, 48),
			Color(0.35, 0.62, 1.0, 0.022)
		)
	# Halo em volta do próprio saco: separa o vermelho do preto do fundo.
	_glow(alvo, w * 0.30, Color(0.30, 0.55, 1.0, 0.05))

## Poeira de LED subindo devagar dentro do cone de luz.
func _ambiente(w: float, h: float) -> void:
	for i in range(20):
		var x := fmod(float(i * 271), w)
		var y := fmod(float(i * 397) + tempo * (9.0 + i * 0.35), h)
		var perto := 1.0 - clampf(absf(x - w * FOCO.x) / (w * 0.45), 0.0, 1.0)
		draw_circle(Vector2(x, y), 1.4 + float(i % 3) * 0.6, Color(0.35, 0.80, 1.0, 0.07 + 0.13 * perto))

func _glow(centro: Vector2, raio: float, cor: Color) -> void:
	for i in range(3):
		var c := cor
		c.a *= 1.0 - float(i) / 3.0
		draw_circle(centro, raio * (1.0 - i * 0.28), c)

func _elipse(centro: Vector2, rx: float, ry: float, passos: int) -> PackedVector2Array:
	var pontos := PackedVector2Array()
	for i in range(passos + 1):
		var a := float(i) / float(passos) * TAU
		pontos.append(centro + Vector2(cos(a) * rx, sin(a) * ry))
	return pontos
