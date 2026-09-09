class_name Traco
extends RefCounted

## BORDA LISA NUM DESENHO QUE NÃO TEM ANTISSERRILHADO.
##
## O projeto roda no renderizador "GL Compatibility", que é o que garante
## a máquina ligar em qualquer PC de gabinete — inclusive nos que não têm
## Vulkan. O preço é que o Godot ignora o MSAA 2D nesse renderizador: ele
## avisa "2D MSAA is not yet supported for GLES3" e desenha tudo com a
## borda em degrau. Com o jogo inteiro desenhado à mão, em polígonos e
## faixas diagonais, o degrau aparece em cada aresta.
##
## O conserto é por chamada, não por configuração:
##
##   * círculo e retângulo têm `antialiased` na própria função do Godot,
##     e passar `true` já resolve;
##   * `draw_colored_polygon` NÃO tem — então a borda é desenhada por
##     cima, como um contorno de um pixel na mesma cor, que é onde o
##     antisserrilhado da linha entra e come o degrau.
##
## Um pixel é o número certo: mais que isso engorda a figura, menos que
## isso não cobre a escada inteira.
const BORDA := 1.0

## CHAVE DE MEDIÇÃO. Desligada, `poligono` vira `draw_colored_polygon`
## puro — é o que permite medir quanto custa o antisserrilhado sem
## desfazer o código todo. Nunca fica falsa numa build de salão.
static var suavizar := true

## Polígono cheio com a aresta lisa.
static func poligono(ci: CanvasItem, pontos: PackedVector2Array, cor: Color) -> void:
	ci.draw_colored_polygon(pontos, cor)
	if suavizar:
		contorno(ci, pontos, cor)

## Só o contorno — para quem já desenhou o miolo de outro jeito.
static func contorno(ci: CanvasItem, pontos: PackedVector2Array, cor: Color, espessura := BORDA) -> void:
	if pontos.size() < 3:
		return
	var fecho := pontos.duplicate()
	fecho.append(pontos[0])
	ci.draw_polyline(fecho, cor, espessura, true)
