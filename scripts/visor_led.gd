class_name VisorLed
extends RefCounted

## O visor de sete segmentos da máquina.
##
## POR QUE NÃO É UMA FONTE. Numa máquina de fliperama o placar não é
## texto impresso: é um painel de LED atrás de um vidro escuro. O que faz
## o olho reconhecer isso não é o formato dos algarismos — é o SEGMENTO
## APAGADO. Num visor de verdade os sete traços de cada dígito estão
## sempre lá; os que não fazem parte do número ficam visíveis, escuros,
## como um fantasma. Nenhuma fonte dá isso, e é por isso que aqui os
## dígitos são desenhados segmento a segmento.
##
## Cada segmento é um hexágono achatado, com as pontas em bisel — o
## desenho clássico de display, e o que evita que dois traços vizinhos
## pareçam um traço só.
##
##      ── a ──
##     │       │
##     f       b
##     │       │
##      ── g ──
##     │       │
##     e       c
##     │       │
##      ── d ──

## Quais segmentos cada caractere acende.
const MAPA := {
	"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
	"5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg",
	"-": "g", " ": "", "A": "abcefg", "E": "adefg", "F": "aefg",
}

## Proporção largura/altura de um dígito, e espaço entre dígitos.
const PROPORCAO := 0.58
const ESPACO := 0.16

## Desenha `texto` centrado em `centro`, com `altura` de dígito.
## `cor` acende os segmentos ligados; os desligados ficam na mesma cor,
## bem apagados, porque é essa sombra que denuncia o painel de LED.
static func desenhar(
	ci: CanvasItem, texto: String, centro: Vector2, altura: float,
	cor: Color, brilho := true
) -> void:
	var largura := altura * PROPORCAO
	var passo := largura * (1.0 + ESPACO)
	var total := passo * float(texto.length()) - largura * ESPACO
	var x := centro.x - total * 0.5
	for i in range(texto.length()):
		_digito(ci, texto[i], Vector2(x, centro.y - altura * 0.5), largura, altura, cor, brilho)
		x += passo

static func _digito(
	ci: CanvasItem, caractere: String, canto: Vector2,
	w: float, h: float, cor: Color, brilho: bool
) -> void:
	var ligados: String = MAPA.get(caractere, "")
	var t := h * 0.155             ## espessura do traço
	var folga := t * 0.30          ## respiro entre dois segmentos vizinhos
	var meio := canto.y + h * 0.5
	# O fantasma tem de existir e NÃO competir. Quanto mais escuro o vidro
	# atrás, mais o traço apagado salta: no tema claro 0.09 bastava, no
	# vermelho escuro o mesmo valor fazia o 1 ler como 8.
	var apagado := Color(cor, 0.055)

	for seg: String in ["a", "b", "c", "d", "e", "f", "g"]:
		var aceso: bool = ligados.contains(seg)
		var tom := cor if aceso else apagado
		var forma := _forma(seg, canto, w, h, t, folga, meio)
		if aceso and brilho:
			# Halo do LED aceso: o vidro espalha um pouco a luz em volta.
			Traco.poligono(ci, _inflar(forma, t * 0.70), Color(cor, 0.30))
		Traco.poligono(ci, forma, tom)
		if aceso:
			# MIOLO CLARO. Um LED aceso não é um traço de cor chapada: o
			# centro estoura quase branco e a cor fica só na borda. Sem
			# isso o algarismo lê como adesivo, e some contra o vidro.
			Traco.poligono(ci, _inflar(forma, -t * 0.30), cor.lightened(0.55))

## Os pontos de um segmento. Horizontais e verticais são o mesmo hexágono
## girado, então a conta mora num lugar só.
static func _forma(
	seg: String, canto: Vector2, w: float, h: float,
	t: float, folga: float, meio: float
) -> PackedVector2Array:
	var esq := canto.x
	var dir := canto.x + w
	var topo := canto.y
	var base := canto.y + h
	match seg:
		"a":
			return _horizontal(esq + folga, dir - folga, topo + t * 0.5, t)
		"g":
			return _horizontal(esq + folga, dir - folga, meio, t)
		"d":
			return _horizontal(esq + folga, dir - folga, base - t * 0.5, t)
		"f":
			return _vertical(esq + t * 0.5, topo + folga, meio - folga, t)
		"b":
			return _vertical(dir - t * 0.5, topo + folga, meio - folga, t)
		"e":
			return _vertical(esq + t * 0.5, meio + folga, base - folga, t)
		"c":
			return _vertical(dir - t * 0.5, meio + folga, base - folga, t)
	return PackedVector2Array()

static func _horizontal(x0: float, x1: float, y: float, t: float) -> PackedVector2Array:
	var m := t * 0.5
	return PackedVector2Array([
		Vector2(x0, y), Vector2(x0 + m, y - m), Vector2(x1 - m, y - m),
		Vector2(x1, y), Vector2(x1 - m, y + m), Vector2(x0 + m, y + m),
	])

static func _vertical(x: float, y0: float, y1: float, t: float) -> PackedVector2Array:
	var m := t * 0.5
	return PackedVector2Array([
		Vector2(x, y0), Vector2(x + m, y0 + m), Vector2(x + m, y1 - m),
		Vector2(x, y1), Vector2(x - m, y1 - m), Vector2(x - m, y0 + m),
	])

## Cresce um polígono a partir do próprio centro. Serve para o halo do
## segmento aceso sem precisar de um segundo conjunto de contas.
static func _inflar(pontos: PackedVector2Array, folga: float) -> PackedVector2Array:
	var centro := Vector2.ZERO
	for p in pontos:
		centro += p
	centro /= float(pontos.size())
	var fora := PackedVector2Array()
	for p in pontos:
		fora.append(p + (p - centro).normalized() * folga)
	return fora
