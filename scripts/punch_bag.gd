class_name PunchBag
extends Control

## O saco de pancadas da máquina.
##
## VOLUME SEM TEXTURA. O saco é desenhado como um cilindro visto de
## frente: tiras verticais finas, cada uma com o seu tom, cobrindo a
## silhueta de uma cápsula. A altura de cada tira sai da equação da
## elipse (`sqrt(1 - u²)`), então a borda arredondada é exata e não uma
## aproximação desenhada à mão. É a mesma conta que dá o brilho: uma
## curva de luz sobre `u` acende o lado esquerdo e apaga o direito. Sem
## imagem, sem shader, sem arquivo que possa faltar na máquina.
##
## O BALANÇO É PRESO DE PROPÓSITO. Um pêndulo solto com a energia de um
## soco de nocaute gira quase 110° e joga o saco para fora da tela —
## exatamente o que não pode acontecer num gabinete em pé, onde o saco é
## a única coisa que o cliente olha. `LIMITE_ANGULO` segura o balanço em
## 20°, e a energia que sobra vira amassado e tremor, que é onde ela
## rende mais.

var tempo := 0.0
var angulo := 0.0
var vel_angular := 0.0
## Carga da simulação (0..1); negativo desliga o tremor de preparação.
var carga := -1.0
## Anel de mira, mostrado enquanto o sensor espera o soco.
var alvo_visivel := false
var _impacto := 0.0 ## brilho e amassado do golpe, decaem sozinhos
var _forca_impacto := 0.0

const MOLA := 26.0
const AMORTECIMENTO := 3.1
## Balanço máximo, em radianos. Vinte graus: o saco reage com clareza e
## continua inteiro dentro do enquadramento.
const LIMITE_ANGULO := 0.35
## Quantas tiras verticais formam o corpo. Acima disso o ganho visual
## some e o custo por quadro não — a máquina do salão não é uma estação
## de trabalho.
const TIRAS := 60

const COR_BASE := Color("9c2244")
const COR_COURO := Color("2b1420")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1

## O soco. `forca` de 0 (encostou) a 1 (lendário).
func golpear(forca: float) -> void:
	var f := clampf(forca, 0.0, 1.0)
	vel_angular += lerpf(1.4, 3.4, f) * (1.0 if randf() > 0.08 else -1.0)
	_impacto = 1.0
	_forca_impacto = f

func set_carga(valor: float) -> void:
	carga = clampf(valor, 0.0, 1.0) if valor >= 0.0 else -1.0

func set_alvo(visivel: bool) -> void:
	alvo_visivel = visivel

## Onde o soco aterrissa, em coordenadas do pai. O resto da tela — onda
## de choque, faíscas, clarão — pergunta ao saco em vez de repetir um
## número mágico que sai do lugar assim que o saco muda de tamanho.
func ponto_de_impacto() -> Vector2:
	return position + Vector2(size.x * 0.5, _altura_do_alvo())

func _altura_do_alvo() -> float:
	return size.y * 0.16 + size.y * 0.70 * 0.42

func _process(delta: float) -> void:
	tempo += delta
	_impacto = maxf(0.0, _impacto - delta * 2.4)
	# Pêndulo: mola puxando para o centro, amortecimento tirando energia.
	var acel := -MOLA * angulo - AMORTECIMENTO * vel_angular
	vel_angular += acel * delta
	angulo += vel_angular * delta
	# Batente: no limite o saco para de abrir e devolve parte da energia,
	# como um saco de verdade encontrando o fim do curso da corrente.
	if absf(angulo) > LIMITE_ANGULO:
		angulo = clampf(angulo, -LIMITE_ANGULO, LIMITE_ANGULO)
		vel_angular *= -0.35
	queue_redraw()

# ======================================================================
# DESENHO
# ======================================================================
func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var corrente := h * 0.16
	var saco_altura := h * 0.70
	var saco_largura := w * 0.62
	var pivot := Vector2(w * 0.5, h * 0.012)

	var inclinacao := angulo
	if carga >= 0.0:
		# Recua e treme conforme a carga: quem carrega o soco vê o saco
		# se preparar para levar.
		inclinacao += -0.05 * carga + sin(tempo * (20.0 + 30.0 * carga)) * 0.010 * carga

	_desenhar_sombra(w, h, saco_largura, inclinacao, corrente)
	_desenhar_suporte(pivot, w)

	draw_set_transform(pivot, inclinacao)
	_desenhar_corrente(corrente)
	_desenhar_corpo(corrente, saco_altura, saco_largura)
	_desenhar_mira(corrente, saco_altura, saco_largura)
	draw_set_transform(Vector2.ZERO, 0.0)

## Sombra no chão: acompanha o pêndulo para o lado oposto e encolhe
## quando o saco se afasta do centro.
func _desenhar_sombra(w: float, h: float, saco_largura: float, inclinacao: float, corrente: float) -> void:
	var cx := w * 0.5 - sin(inclinacao) * corrente * 1.4
	var cy := h * 0.955
	var rx := saco_largura * (0.62 - 0.14 * absf(sin(inclinacao)))
	for i in range(3):
		var k := 1.0 - float(i) * 0.30
		draw_colored_polygon(
			_elipse(Vector2(cx, cy), rx * k, rx * 0.15 * k, 40),
			Color(0.0, 0.0, 0.0, 0.20)
		)

## O ponto onde a corrente encontra o teto do gabinete: chapa, parafusos
## e manilha. Não gira com o saco — é ele que está preso, não o teto.
func _desenhar_suporte(pivot: Vector2, w: float) -> void:
	var chapa := Rect2(w * 0.5 - 62.0, pivot.y - 22.0, 124.0, 22.0)
	draw_rect(chapa, Color("28324c"))
	draw_rect(Rect2(chapa.position.x, chapa.position.y, chapa.size.x, 5.0), Color("3d4a68"))
	for i in range(4):
		draw_circle(Vector2(chapa.position.x + 16.0 + i * 30.0, chapa.position.y + 11.0), 3.5, Color("161d2f"))
	# Manilha em U segurando o primeiro elo.
	draw_arc(Vector2(w * 0.5, pivot.y + 2.0), 11.0, PI, TAU, 20, Color("5a6c94"), 5.0, true)

## Corrente: elos de verdade, alternando o plano — um de frente, um de
## perfil. É a alternância que faz o olho ler "corrente" e não "linha".
func _desenhar_corrente(corrente: float) -> void:
	var elos := 6
	var passo := corrente / float(elos)
	for i in range(elos):
		var cy := passo * (float(i) + 0.5)
		var de_frente := i % 2 == 0
		var rx := 8.5 if de_frente else 4.0
		var ry := passo * 0.62
		var cor := Color("6b7ea8") if de_frente else Color("46557a")
		draw_polyline(_elipse(Vector2(0.0, cy), rx, ry, 22), cor, 4.5, true)
		# Realce de metal na lateral esquerda do elo.
		draw_line(
			Vector2(-rx * 0.55, cy - ry * 0.45), Vector2(-rx * 0.55, cy + ry * 0.35),
			Color(1, 1, 1, 0.22), 2.0, true
		)

## O corpo. Tiras verticais sobre a silhueta de uma cápsula: a altura de
## cada tira vem da elipse, o tom vem da curva de luz. As tampas de couro
## das pontas são desenhadas do MESMO jeito, com a mesma curva de luz e
## a mesma silhueta — é o que impede que elas leiam como dois blocos
## escuros colados num tubo vermelho.
func _desenhar_corpo(topo: float, altura: float, largura: float) -> void:
	var meia := largura * 0.5
	var raio := meia * 0.62 ## abaulamento das pontas

	# Amassado: o soco achata o saco na horizontal e o estica um pouco na
	# vertical, e isso passa em meio segundo.
	var amasso := _impacto * _impacto * _forca_impacto
	var meia_x := meia * (1.0 - amasso * 0.13)
	var raio_y := raio * (1.0 + amasso * 0.05)

	var corpo_topo := topo + raio_y
	var corpo_base := topo + altura - raio_y
	var tampa_cima := corpo_topo + altura * 0.055
	var tampa_baixo := corpo_base - altura * 0.055

	var base := COR_BASE
	if carga >= 0.0:
		base = base.lerp(Color("d4384f"), carga * 0.5)

	# As duas bordas da cápsula, e as duas curvas que separam as tampas.
	var borda_cima := func(u: float) -> float: return corpo_topo - raio_y * _perfil(u)
	var borda_baixo := func(u: float) -> float: return corpo_base + raio_y * _perfil(u)
	var corte_cima := func(u: float) -> float: return tampa_cima + raio_y * 0.34 * _perfil(u)
	var corte_baixo := func(u: float) -> float: return tampa_baixo + raio_y * 0.34 * _perfil(u)

	# Contorno escuro: separa o saco do preto do gabinete.
	_tiras(
		meia_x + 5.0,
		func(u: float) -> float: return corpo_topo - (raio_y + 5.0) * _perfil(u) - 5.0,
		func(u: float) -> float: return corpo_base + (raio_y + 5.0) * _perfil(u) + 5.0,
		func(_u: float) -> Color: return Color("0d1120")
	)

	# Vinil do corpo.
	_tiras(meia_x, borda_cima, borda_baixo, func(u: float) -> Color: return _tom(base, u))

	# Costuras: anéis do cilindro, que aparecem curvados para baixo.
	for i in range(1, 4):
		var y := tampa_cima + (tampa_baixo - tampa_cima) * float(i) / 4.0
		_curva_do_anel(y, meia_x, raio_y * 0.30, Color(0.10, 0.02, 0.06, 0.55), 3.0)
		_curva_do_anel(y - 3.0, meia_x, raio_y * 0.30, Color(1.0, 0.75, 0.80, 0.10), 2.0)

	# Tampas de couro, com a luz do mesmo lado do corpo.
	_tiras(meia_x, borda_cima, corte_cima, func(u: float) -> Color: return _tom(COR_COURO, u, false, 0.45))
	_tiras(meia_x, corte_baixo, borda_baixo, func(u: float) -> Color: return _tom(COR_COURO, u, false, 0.45))
	_curva_do_anel(tampa_cima, meia_x, raio_y * 0.34, Color(0, 0, 0, 0.45), 3.0)
	_curva_do_anel(tampa_baixo, meia_x, raio_y * 0.34, Color(0, 0, 0, 0.45), 3.0)
	_rebites(tampa_cima - altura * 0.028, meia_x, raio_y)
	_rebites(tampa_baixo + altura * 0.028, meia_x, raio_y)

	# Contorno suavizado por cima: as tiras deixam degraus na curva das
	# pontas, e uma linha antisserrilhada na silhueta exata os apaga.
	draw_polyline(_capsula(corpo_topo, corpo_base, meia_x, raio_y), Color("0d1120"), 5.0, true)

	# Alvo impresso no vinil, na altura em que o soco deve chegar.
	var alvo_y := topo + altura * 0.42
	_marca_do_alvo(alvo_y, meia_x)

	# Clarão do golpe, por cima de tudo.
	if _impacto > 0.01:
		var centro := Vector2(0.0, alvo_y)
		for i in range(4):
			draw_circle(
				centro, (30.0 + i * 34.0) * (1.5 - _impacto * 0.5),
				Color(1.0, 0.90, 0.62, _impacto * _forca_impacto * (0.40 - i * 0.09))
			)

## Meia-altura da cápsula em `u`: a equação da elipse, e a razão de a
## borda arredondada ser exata em vez de desenhada no olho.
func _perfil(u: float) -> float:
	return sqrt(maxf(0.0, 1.0 - u * u))

## O tom de uma tira: a cor base acesa pela curva de luz, com contraluz
## na borda direita e o calor do soco por cima.
## `amplitude` encolhe o intervalo entre a sombra e a luz. O vinil do
## corpo usa a escala inteira; o couro das tampas usa metade, senão o
## realce lava o preto e a tampa vira uma peça de madeira clara.
func _tom(base: Color, u: float, contraluz := true, amplitude := 1.0) -> Color:
	var cor: Color = base.darkened(0.52 * amplitude).lerp(base.lightened(0.38 * amplitude), _luz(u))
	if contraluz and u > 0.72:
		cor = cor.lerp(Color("ff8fa8"), (u - 0.72) / 0.28 * 0.30)
	if _impacto > 0.01:
		cor = cor.lerp(Color("ffcf8a"), _impacto * _forca_impacto * 0.35 * (1.0 - absf(u) * 0.5))
	return cor

## Preenche uma faixa da cápsula com tiras verticais. `de` e `ate` dizem,
## para cada `u`, onde a tira começa e termina; `tom` diz de que cor ela é.
func _tiras(meia: float, de: Callable, ate: Callable, tom: Callable) -> void:
	var passo := meia * 2.0 / float(TIRAS)
	for i in range(TIRAS):
		var u := (float(i) + 0.5) / float(TIRAS) * 2.0 - 1.0
		var y0: float = de.call(u)
		var y1: float = ate.call(u)
		if y1 <= y0:
			continue
		# Meio pixel de sobra evita a costura clara entre tiras vizinhas.
		draw_rect(Rect2(-meia + float(i) * passo, y0, passo + 0.6, y1 - y0), tom.call(u))

## Curva de luz do cilindro: pico à esquerda do eixo, queda suave para os
## dois lados. `u` em [-1, 1].
func _luz(u: float) -> float:
	var n := clampf(1.0 - absf(u + 0.42) / 1.15, 0.0, 1.0)
	return pow(n, 1.5)

## Um anel horizontal do cilindro, que o olho vê curvado para baixo.
func _curva_do_anel(y: float, meia: float, curvatura: float, cor: Color, largura: float) -> void:
	var pontos := PackedVector2Array()
	for i in range(25):
		var u := float(i) / 24.0 * 2.0 - 1.0
		pontos.append(Vector2(u * meia, y + curvatura * _perfil(u)))
	draw_polyline(pontos, cor, largura, true)

## Rebites da tampa, acompanhando a mesma curvatura do anel.
func _rebites(y: float, meia: float, raio: float) -> void:
	for i in range(5):
		var u := -0.70 + float(i) * 0.35
		var centro := Vector2(u * meia, y + raio * 0.30 * _perfil(u))
		draw_circle(centro, 3.4, Color("55637f"))
		draw_circle(centro + Vector2(-0.8, -0.8), 1.6, Color(1, 1, 1, 0.35))

## O alvo impresso no saco: anéis achatados, porque estão na superfície
## de um cilindro e não num cartaz plano.
func _marca_do_alvo(y: float, meia: float) -> void:
	var centro := Vector2(0.0, y)
	draw_polyline(_elipse(centro, meia * 0.44, meia * 0.50, 40), Color(1, 1, 1, 0.16), 8.0, true)
	draw_polyline(_elipse(centro, meia * 0.27, meia * 0.31, 34), Color(1, 1, 1, 0.13), 6.0, true)
	draw_colored_polygon(_elipse(centro, meia * 0.10, meia * 0.115, 24), Color(1, 1, 1, 0.14))

## A mira do sensor: cantoneiras pulsando em volta do alvo. Cantoneira,
## e não círculo cheio, porque o cliente precisa continuar vendo o ponto
## que tem de acertar.
func _desenhar_mira(topo: float, altura: float, largura: float) -> void:
	if not alvo_visivel:
		return
	var centro := Vector2(0.0, topo + altura * 0.42)
	var pulso := 0.5 + 0.5 * sin(tempo * 5.0)
	var r := largura * 0.42 + pulso * 12.0
	var cor := Color(1.0, 0.30, 0.42, 0.55 + 0.45 * pulso)
	var braco := r * 0.42
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var canto := centro + Vector2(sx * r, sy * r * 1.06)
			draw_line(canto, canto - Vector2(sx * braco, 0.0), cor, 5.0, true)
			draw_line(canto, canto - Vector2(0.0, sy * braco), cor, 5.0, true)
	draw_polyline(_elipse(centro, r * 0.30, r * 0.33, 28), Color(1, 1, 1, 0.75), 3.0, true)
	draw_circle(centro, 7.0, cor)

## A silhueta exata da cápsula, como linha fechada.
func _capsula(topo: float, base: float, meia: float, raio: float) -> PackedVector2Array:
	var pontos := PackedVector2Array()
	var passos := 40
	for i in range(passos + 1):
		var u := float(i) / float(passos) * 2.0 - 1.0
		pontos.append(Vector2(u * meia, topo - raio * _perfil(u)))
	for i in range(passos + 1):
		var u := 1.0 - float(i) / float(passos) * 2.0
		pontos.append(Vector2(u * meia, base + raio * _perfil(u)))
	pontos.append(pontos[0])
	return pontos

## Elipse fechada como lista de pontos — serve de contorno e de polígono.
func _elipse(centro: Vector2, rx: float, ry: float, passos: int) -> PackedVector2Array:
	var pontos := PackedVector2Array()
	for i in range(passos + 1):
		var a := float(i) / float(passos) * TAU
		pontos.append(centro + Vector2(cos(a) * rx, sin(a) * ry))
	return pontos
