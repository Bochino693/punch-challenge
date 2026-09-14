class_name LedFrame
extends Control

## A fieira de lâmpadas que corre pela borda da tela, como no letreiro de
## um parque.
##
## LÂMPADA, NÃO PONTO DE LUZ. Num tema claro, um LED desenhado como
## brilho difuso simplesmente some: clarão sobre fundo claro não aparece.
## Cada bulbo aqui tem corpo pintado e ARO ESCURO, então a apagada
## também se vê — e é a fieira inteira, acesa e apagada junto, que faz o
## olho ler "letreiro" mesmo antes de a luz começar a correr.
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

## O TETO DE QUALIDADE, vindo do mesmo vigia de `main.gd`.
##
## Esta moldura é a única enfeite do jogo que corria sempre no detalhe
## máximo, em toda tela, o tempo inteiro — mesmo o `ArcadeStage.enfeite`
## e as partículas de `PunchFX` já encolhem sozinhos quando a máquina
## aperta. Cem e tantos pontos, três desenhos cada, sem nunca abaixar,
## numa moldura que está na tela do início ao fim: é peso constante por
## pura decoração, exatamente o tipo de gasto que sobra numa máquina
## fraca de verdade.
var qualidade := 1.0

var tempo := 0.0
var estado := PARADA
## Cor do veredito, usada quando `estado` é RESULTADO.
var cor_resultado := Paleta.AMBAR
var _flash := 0.0
var _cor_flash := Paleta.AMBAR

## Espaçamento entre os pontos da moldura, em pixels.
const PASSO := 52.0
const MARGEM := 24.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4

func set_estado(nome: String, cor: Color = Paleta.AMBAR) -> void:
	estado = nome
	if nome == RESULTADO:
		cor_resultado = cor

## Clarão instantâneo do soco. `forca` de 0 a 1.
func impacto(forca: float, cor: Color = Paleta.AMBAR) -> void:
	_flash = maxf(_flash, clampf(forca, 0.0, 1.0))
	_cor_flash = cor

func _process(delta: float) -> void:
	tempo += delta
	_flash = maxf(0.0, _flash - delta * 3.2)
	queue_redraw()

func _cor_base() -> Color:
	match estado:
		CONTAGEM:
			return Paleta.CIANO
		ARMADA:
			return Paleta.AMBAR
		RESULTADO:
			return cor_resultado
	return Paleta.MARINHO

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
	var apagada := Paleta.CARTAO_BORDA

	# Percurso da moldura: retângulo percorrido no sentido horário.
	var perimetro := 2.0 * (w + h - 4.0 * MARGEM)
	var total := int(perimetro / PASSO)
	if total < 8:
		return
	var cabeca := fmod(tempo * _velocidade(), float(total))
	# SÓ A LÂMPADA ACESA GANHA O DETALHE INTEIRO quando a máquina aperta.
	#
	# É ela que o olho de fato acompanha correndo pela borda; as apagadas
	# são só o traço da fieira. Cortar o contorno e o reflexo de vidro
	# das apagadas tira dois terços dos desenhos desta moldura sem que a
	# corrida de luz perca nada — e é exatamente o detalhe que ninguém
	# nota faltando numa lâmpada parada.
	var detalhe_total := qualidade > 0.7

	for i in range(total):
		var p := _ponto_do_percurso(i, total, w, h)
		# A cauda atrás da cabeça apaga devagar; o resto fica de reserva.
		var dist := fmod(cabeca - float(i) + total, float(total))
		var acesa := maxf(0.0, 1.0 - dist / 10.0)
		if estado == ARMADA:
			acesa *= 0.75 + 0.25 * sin(tempo * 9.0)
		var cor := apagada.lerp(base, acesa)
		var raio := 5.0 + 2.4 * acesa
		# Halo quente só na lâmpada acesa: é o que sobra de "luz" quando o
		# fundo já é claro.
		if acesa > 0.05:
			draw_circle(p, raio + 7.0, Color(base, acesa * 0.22), true, -1.0, true)
		draw_circle(p, raio, cor, true, -1.0, true)
		if detalhe_total or acesa > 0.05:
			draw_arc(p, raio, 0.0, TAU, 16, Color(Paleta.MARINHO, 0.30 + 0.35 * acesa), 1.6, true)
			# Reflexo no vidro do bulbo, sempre no mesmo canto.
			draw_circle(p + Vector2(-raio * 0.30, -raio * 0.30), raio * 0.26, Color(1, 1, 1, 0.55), true, -1.0, true)

	if _flash > 0.01:
		# O clarão acende a fieira inteira de uma vez só.
		for i in range(total):
			var p := _ponto_do_percurso(i, total, w, h)
			draw_circle(p, 9.0, Color(_cor_flash, _flash * 0.85), true, -1.0, true)
		draw_rect(
			Rect2(MARGEM - 8.0, MARGEM - 8.0, w - 2.0 * (MARGEM - 8.0), h - 2.0 * (MARGEM - 8.0)),
			Color(_cor_flash, _flash * 0.22), false, 10.0
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
