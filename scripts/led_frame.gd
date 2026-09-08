class_name LedFrame
extends Control

## Moldura de LEDs que corre pela borda da tela.
##
## Cada estado do jogo tem um passo: parada, a luz passeia devagar;
## armada, ela aperta o passo e esquenta; no impacto, a moldura inteira
## pisca de uma vez. O jogo só chama `set_estado` e `impacto` — o
## resto a moldura resolve sozinha, sem pedir nada por fora.

## Estados reconhecidos por `set_estado`.
const PARADA := "parada"
const CONTAGEM := "contagem"
const ARMADA := "armada"
const RESULTADO := "resultado"

var tempo := 0.0
var estado := PARADA
## Cor do veredito, usada quando `estado` é RESULTADO.
var cor_resultado := Color("ffd23f")
var _flash := 0.0
var _cor_flash := Color.WHITE

## Espaçamento entre os pontos da moldura, em pixels.
const PASSO := 46.0
const MARGEM := 22.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4

func set_estado(nome: String, cor: Color = Color("ffd23f")) -> void:
	estado = nome
	if nome == RESULTADO:
		cor_resultado = cor

## Clarão instantâneo do soco. `forca` de 0 a 1.
func impacto(forca: float, cor: Color = Color.WHITE) -> void:
	_flash = maxf(_flash, clampf(forca, 0.0, 1.0))
	_cor_flash = cor

func _process(delta: float) -> void:
	tempo += delta
	_flash = maxf(0.0, _flash - delta * 3.2)
	queue_redraw()

func _cor_base() -> Color:
	match estado:
		CONTAGEM:
			return Color("4beaff")
		ARMADA:
			return Color("ff9d2e")
		RESULTADO:
			return cor_resultado
	return Color("2e9dff")

func _velocidade() -> float:
	## LEDs por segundo percorridos pela luz que corre.
	match estado:
		CONTAGEM:
			return 26.0
		ARMADA:
			return 60.0
	return 12.0

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var base := _cor_base()

	# Percurso da moldura: retângulo percorrido no sentido horário.
	var perimetro := 2.0 * (w + h - 4.0 * MARGEM)
	var total := int(perimetro / PASSO)
	if total < 8:
		return
	var cabeca := fmod(tempo * _velocidade(), float(total))

	for i in range(total):
		var p := _ponto_do_percurso(i, total, w, h)
		# A cauda atrás da cabeça apaga devagar; o resto fica em brasas.
		var dist := fmod(cabeca - float(i) + total, float(total))
		var brilho := 0.16 + 0.84 * maxf(0.0, 1.0 - dist / 10.0)
		if estado == ARMADA:
			brilho *= 0.8 + 0.2 * sin(tempo * 9.0)
		var cor := Color(base.r, base.g, base.b, brilho * 0.9)
		var raio := 3.4 + 2.6 * maxf(0.0, 1.0 - dist / 6.0)
		draw_circle(p, raio + 3.0, Color(cor.r, cor.g, cor.b, cor.a * 0.18))
		draw_circle(p, raio, cor)

	if _flash > 0.01:
		# O clarão cobre a moldura inteira de uma vez só.
		for i in range(total):
			var p := _ponto_do_percurso(i, total, w, h)
			draw_circle(p, 6.5, Color(_cor_flash.r, _cor_flash.g, _cor_flash.b, _flash * 0.9))
		draw_rect(
			Rect2(MARGEM - 8.0, MARGEM - 8.0, w - 2.0 * (MARGEM - 8.0), h - 2.0 * (MARGEM - 8.0)),
			Color(_cor_flash.r, _cor_flash.g, _cor_flash.b, _flash * 0.16), false, 10.0
		)

func _ponto_do_percurso(i: int, total: int, w: float, h: float) -> Vector2:
	## Distribui o índice i pelos quatro lados, no sentido horário,
	## começando no canto superior esquerdo.
	var t := float(i) / float(total)
	var largura := w - 2.0 * MARGEM
	var altura := h - 2.0 * MARGEM
	var perimetro := 2.0 * (largura + altura)
	var d := t * perimetro
	if d < largura:
		return Vector2(MARGEM + d, MARGEM)
	d -= largura
	if d < altura:
		return Vector2(w - MARGEM, MARGEM + d)
	d -= altura
	if d < largura:
		return Vector2(w - MARGEM - d, h - MARGEM)
	d -= largura
	return Vector2(MARGEM, h - MARGEM - d)
