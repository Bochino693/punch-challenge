extends RefCounted
## Cenografia e abertura. Não controla créditos, câmera ou pontuação.
const EMBLEM = preload("res://assets/branding/punch_emblem.svg")
const Icones = preload("res://scripts/icones.gd")
const RED := Color("ff1934")
const GOLD := Color("ffdc27")
const WHITE := Color("fff9ef")
const FLOOR := Color("19060d")
const PANEL := Color("330c16")
## A ENTRADA É UM FILME CURTO, NÃO UM LOGOTIPO APARECENDO.
##
## Cada tempo abaixo é o INÍCIO de um trecho. Eles estão aqui em cima,
## juntos e nomeados, porque a entrada é a única parte do jogo em que
## imagem, som e tremor precisam cair no mesmo quadro: com os números
## espalhados pelo código, acertar isso vira tentativa e erro.
const T_VARRER := 0.00   ## dois facões de luz cruzam o escuro
const T_VOO := 0.35      ## a luva entra voando, deixando rastro
const T_SOCO := 1.05     ## o impacto: clarão, ondas e tremor
const T_EMBLEMA := 1.10  ## o emblema nasce do ponto do soco
const T_TITULO := 1.80   ## PUNCH desce batendo
const T_SUBTITULO := 2.15
const T_ASSINATURA := 2.60
const T_BRILHO := 2.75    ## a luz que varre o letreiro no trecho parado
const T_MORPH := 3.90    ## a cena vira, sem corte, a tela de abertura
const INTRO_SECONDS := 5.10

## O ponto onde a luva bate e de onde tudo nasce.
const SOCO := Vector2(540.0, 760.0)

## Onde o emblema e o letreiro TERMINAM: exatamente onde a tela de
## abertura os desenha. É essa coincidência que faz a entrada virar
## abertura sem piscada — sem ela o corte aparece.
const POUSO_EMBLEMA := Vector2(540.0, 560.0)
const POUSO_EMBLEMA_TAM := 440.0
const POUSO_PUNCH := 910.0
const POUSO_PUNCH_TAM := 144
const POUSO_CHALLENGE := 1010.0
const POUSO_CHALLENGE_TAM := 80

## O SOM DA ENTRADA, na mesma tabela dos tempos.
##
## Devolvido a quem chama para tocar; a entrada não conhece o
## AudioBank, e não deve conhecer — quem sabe silenciar a máquina é o
## jogo, não a cenografia.
const TRILHA := [
	{"t": T_VARRER, "cue": "menu", "db": -10.0},
	{"t": T_VOO, "cue": "charge", "db": -14.0},
	{"t": T_SOCO, "cue": "hit", "db": -2.0},
	{"t": T_EMBLEMA + 0.45, "cue": "record", "db": -8.0},
	{"t": T_TITULO, "cue": "start", "db": -6.0},
	{"t": T_SUBTITULO, "cue": "tick", "db": -12.0},
	{"t": T_ASSINATURA, "cue": "credit", "db": -14.0},
	{"t": T_BRILHO, "cue": "menu", "db": -18.0},
	{"t": T_MORPH, "cue": "go", "db": -9.0},
]

## As deixas sonoras cruzadas entre dois instantes. Percorrer a tabela
## por intervalo, e não por "passou de", é o que garante que nenhuma
## deixa se perca num quadro longo nem toque duas vezes num curto.
static func intro_cues(de: float, ate: float) -> Array:
	var saida := []
	for marca in TRILHA:
		var t: float = marca["t"]
		if t > de and t <= ate:
			saida.append(marca)
	return saida

## Aceleração com passada do ponto: o emblema chega, passa um pouco e
## volta. Sem esse excesso ele parece colar na tela em vez de assentar.
static func _passar_do_ponto(t: float, forca := 1.9) -> float:
	var p := t - 1.0
	return p * p * ((forca + 1.0) * p + forca) + 1.0

static func _janela(tempo: float, inicio: float, duracao: float) -> float:
	return clampf((tempo - inicio) / duracao, 0.0, 1.0)

static func background(canvas: CanvasItem, time: float) -> void:
	canvas.draw_rect(Rect2(0, 0, 1080, 1920), FLOOR)
	# Grandes planos vermelhos, centro livre para a leitura a distância.
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1080, 0), Vector2(1080, 290), Vector2(0, 550)]), Color("9f0a20"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(780, 0), Vector2(0, 430)]), Color("d00c29"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, 1650), Vector2(1080, 1400), Vector2(1080, 1920), Vector2(0, 1920)]), Color("85091d"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(230, 1920), Vector2(1080, 1630), Vector2(1080, 1920)]), Color("cc102a"))
	for side in [0.0, 1.0]:
		var x := lerpf(28.0, 1052.0, side)
		for layer in range(9):
			canvas.draw_line(Vector2(x, 320), Vector2(x, 1590), Color(RED, 0.035), 8.0 + layer * 5.0, true)
		canvas.draw_line(Vector2(x, 320), Vector2(x, 1590), RED, 4.0, true)
		for i in range(12):
			var y := 455.0 + i * 86.0
			var light := 0.25 + 0.75 * pow(0.5 + 0.5 * sin(time * 3.2 - i * 0.65), 3.0)
			canvas.draw_line(Vector2(x - 9, y), Vector2(x + 9, y - 7), Color(GOLD, light), 5.0, true)
	for i in range(22):
		var speed := 26.0 + float(i % 4) * 16.0
		var y := fposmod(float(i) * 97.0 - time * speed, 1860.0)
		var x := 65.0 + fposmod(float(i) * 157.0, 950.0)
		canvas.draw_line(Vector2(x, y), Vector2(x + 3, y - 10), Color(GOLD, 0.12), 2.0, true)
	canvas.draw_line(Vector2(0, 552), Vector2(1080, 292), Color(GOLD, 0.55), 2.0, true)
	canvas.draw_line(Vector2(0, 1652), Vector2(1080, 1402), Color(GOLD, 0.55), 2.0, true)

static func emblem(canvas: CanvasItem, center: Vector2, size: float, alpha := 1.0) -> void:
	canvas.draw_texture_rect(EMBLEM, Rect2(center - Vector2.ONE * size * 0.5, Vector2.ONE * size), false, Color(1, 1, 1, alpha))

## A ENTRADA, TRECHO A TRECHO.
##
## Desenhada por cima da cenografia, que já está no lugar: a entrada
## começa apagando essa cenografia com um véu escuro e a devolve à medida
## que os trechos avançam. É a mesma varredura que uma máquina chinesa faz
## com fita de LED — só que aqui em pixels.
static func intro(canvas: Control, time: float) -> void:
	_intro_veu(canvas, time)
	_intro_varredura(canvas, time)
	_intro_voo(canvas, time)
	_intro_impacto(canvas, time)
	var morph := _janela(time, T_MORPH, INTRO_SECONDS - T_MORPH)
	_intro_emblema(canvas, time, morph)
	_intro_letreiro(canvas, time, morph)
	_intro_assinatura(canvas, time, morph)
	_intro_brilho(canvas, time, morph)

## O VÉU. Começa fechado e abre no soco: é ele que dá ao clarão do
## impacto alguma coisa de escuro para rasgar. Num fundo já claro o
## flash não teria contra o que brilhar.
static func _intro_veu(canvas: Control, time: float) -> void:
	var fechado := 0.92
	if time >= T_SOCO:
		fechado = lerpf(0.92, 0.0, _janela(time, T_SOCO, 0.85))
	if fechado <= 0.01:
		return
	canvas.draw_rect(Rect2(0, 0, 1080, 1920), Color(FLOOR, fechado))

## Dois facões de luz cruzam a tela antes de qualquer coisa aparecer.
## É o equivalente visual do "atenção" que vem antes do anúncio.
static func _intro_varredura(canvas: Control, time: float) -> void:
	var t := _janela(time, T_VARRER, 0.62)
	if t >= 1.0:
		return
	var forca := sin(t * PI)
	for lado in [-1.0, 1.0]:
		var x := lerpf(540.0 + lado * 1700.0, 540.0, ease(t, 0.35))
		var faixa := PackedVector2Array([
			Vector2(x - 190.0, 0.0), Vector2(x + 190.0, 0.0),
			Vector2(x + 420.0, 1920.0), Vector2(x + 40.0, 1920.0),
		])
		canvas.draw_colored_polygon(faixa, Color(GOLD, 0.34 * forca))
		canvas.draw_line(Vector2(x, 0.0), Vector2(x + 230.0, 1920.0), Color(WHITE, 0.95 * forca), 7.0, true)
	# A linha do horizonte que abre junto: sem ela os dois facões passam
	# por um retângulo preto e a máquina parece que ainda não ligou.
	var abertura := ease(t, 0.3)
	var meia := 1080.0 * abertura
	canvas.draw_line(
		Vector2(540.0 - meia, 960.0), Vector2(540.0 + meia, 960.0),
		Color(WHITE, forca * 0.8), lerpf(2.0, 26.0, 1.0 - t), true
	)

## A LUVA ENTRA VOANDO, e o rastro é o que vende a velocidade: uma luva
## só, por mais rápida que se mova, é uma luva parada em cada quadro.
static func _intro_voo(canvas: Control, time: float) -> void:
	if time < T_VOO or time >= T_SOCO + 0.10:
		return
	var t := _janela(time, T_VOO, T_SOCO - T_VOO)
	var avanco := ease(t, 0.32)
	var partida := Vector2(-360.0, 1500.0)
	for i in range(7):
		var atras := clampf(avanco - float(i) * 0.055, 0.0, 1.0)
		var centro := partida.lerp(SOCO, atras)
		var raio := lerpf(150.0, 250.0, atras)
		var forca := (1.0 - float(i) / 7.0) * (1.0 - t * 0.35)
		if i > 0:
			Icones.luva_vulto(canvas, centro, raio, Color(RED, forca * 0.26))
			continue
		# A LUVA DA FRENTE, montada aqui e não pelo ícone: os brilhos do
		# ícone são duas barras brancas grossas, pensadas para um botão de
		# 40 px. A 250 px de raio elas cobrem a luva inteira e o que voa
		# pela tela deixa de parecer uma luva.
		Icones.luva_vulto(canvas, centro + Vector2(0.0, raio * 0.09), raio, Color("6d0a18"))
		Icones.luva_vulto(canvas, centro, raio, Color("ef1f38"))
		Icones.luva_vulto(canvas, centro - Vector2(raio * 0.05, raio * 0.09), raio * 0.86, Color("ff5f6f"))
		canvas.draw_line(
			centro + Vector2(-raio * 0.06, -raio * 0.62),
			centro + Vector2(raio * 0.42, -raio * 0.50),
			Color(WHITE, 0.85), raio * 0.07, true
		)
	# Riscas de velocidade atrás da luva, na direção do voo.
	var direcao := (SOCO - partida).normalized()
	var atual := partida.lerp(SOCO, avanco)
	for i in range(14):
		var desvio := Vector2(-direcao.y, direcao.x) * randf_range(-230.0, 230.0)
		var origem := atual - direcao * randf_range(280.0, 900.0) + desvio
		canvas.draw_line(origem, origem - direcao * randf_range(90.0, 220.0), Color(GOLD, 0.30), 3.0, true)

## O SOCO. Clarão, três ondas e um leque de riscas saindo do ponto.
static func _intro_impacto(canvas: Control, time: float) -> void:
	if time < T_SOCO:
		return
	# Curto de propósito: o clarão do jogo (`_draw_clarao`) já lava a tela
	# de âmbar por cima deste. Os dois no volume cheio deixavam a tela
	# amarela por meio segundo, o que não é um flash, é um apagão claro.
	var t := _janela(time, T_SOCO, 0.30)
	if t < 1.0:
		canvas.draw_rect(Rect2(0, 0, 1080, 1920), Color(WHITE, pow(1.0 - t, 2.0) * 0.55))
	for i in range(3):
		var onda := _janela(time, T_SOCO + float(i) * 0.09, 0.62)
		if onda <= 0.0 or onda >= 1.0:
			continue
		var raio := lerpf(40.0, 780.0 + float(i) * 130.0, ease(onda, 0.35))
		var cor: Color = [WHITE, GOLD, RED][i]
		canvas.draw_arc(SOCO, raio, 0.0, TAU, 96, Color(cor, (1.0 - onda) * 0.75), 10.0 - float(i) * 2.0, true)
	var leque := _janela(time, T_SOCO, 0.7)
	if leque < 1.0:
		for i in range(26):
			var direcao := Vector2.from_angle(float(i) * TAU / 26.0 + 0.12)
			var perto := 180.0 + leque * 620.0
			canvas.draw_line(
				SOCO + direcao * perto, SOCO + direcao * (perto + lerpf(230.0, 40.0, leque)),
				Color(GOLD, (1.0 - leque) * 0.9), lerpf(9.0, 2.0, leque), true
			)

## O EMBLEMA NASCE DO PONTO DO SOCO e, no fim, caminha até o lugar exato
## em que a tela de abertura o desenha.
static func _intro_emblema(canvas: Control, time: float, morph: float) -> void:
	if time < T_EMBLEMA:
		return
	var abre := _janela(time, T_EMBLEMA, 0.50)
	var escala := _passar_do_ponto(abre) if abre < 1.0 else 1.0
	var tamanho := lerpf(620.0 * escala, POUSO_EMBLEMA_TAM, ease(morph, 0.4))
	var centro := SOCO.lerp(POUSO_EMBLEMA, ease(morph, 0.4))
	# Anel de luz que gira em volta enquanto o emblema assenta; some no
	# morph para não sobrar na abertura, que não tem esse anel.
	var anel := (1.0 - morph) * clampf(abre * 1.4, 0.0, 1.0)
	if anel > 0.01:
		var raio := tamanho * 0.62
		for i in range(24):
			var ang := float(i) * TAU / 24.0 + time * 1.6
			var brilho := 0.35 + 0.65 * pow(0.5 + 0.5 * sin(ang * 3.0 - time * 5.0), 2.0)
			canvas.draw_line(
				centro + Vector2.from_angle(ang) * raio,
				centro + Vector2.from_angle(ang) * (raio + 26.0),
				Color(GOLD, anel * brilho * 0.8), 5.0, true
			)
	# Opacidade cheia quase de imediato: o emblema NASCE do clarão, não
	# aparece esmaecendo. Quem cresce é o tamanho, não a tinta — um
	# emblema meio transparente sobre o escuro sai cinza, e cinza é a
	# única cor que esta marca não tem.
	emblem(canvas, centro, tamanho, _janela(time, T_EMBLEMA, 0.12))

## PUNCH desce batendo, CHALLENGE entra deslizando. Os dois nascem com a
## separação de cor de um monitor mal ajustado, que se fecha conforme
## assentam — é o susto que faz o letreiro parecer que CHEGOU.
static func _intro_letreiro(canvas: Control, time: float, morph: float) -> void:
	if time < T_TITULO:
		return
	var desce := _janela(time, T_TITULO, 0.42)
	var punch_y := lerpf(980.0, 1260.0, _passar_do_ponto(desce, 1.4)) if desce < 1.0 else 1260.0
	punch_y = lerpf(punch_y, POUSO_PUNCH, ease(morph, 0.4))
	var punch_tam := int(lerpf(134.0, float(POUSO_PUNCH_TAM), ease(morph, 0.4)))
	var separa := (1.0 - desce) * 26.0
	if separa > 0.5:
		canvas._texto_arcade("PUNCH", punch_y, punch_tam, Color(RED, 0.55), 960.0, 60.0 - separa)
		canvas._texto_arcade("PUNCH", punch_y, punch_tam, Color("2ad4ff", 0.55), 960.0, 60.0 + separa)
	canvas._texto_arcade("PUNCH", punch_y, punch_tam, Color(WHITE, clampf(desce * 2.0, 0.0, 1.0)), 960.0)

	if time < T_SUBTITULO:
		return
	var desliza := _janela(time, T_SUBTITULO, 0.45)
	var sub_y := lerpf(1385.0, POUSO_CHALLENGE, ease(morph, 0.4))
	var sub_tam := int(lerpf(93.0, float(POUSO_CHALLENGE_TAM), ease(morph, 0.4)))
	var entra := lerpf(420.0, 0.0, ease(desliza, 0.28))
	canvas._texto_arcade("CHALLENGE", sub_y, sub_tam, Color(GOLD, desliza), 960.0, 60.0 + entra)
	# O risco de ouro que corre por baixo do subtítulo enquanto ele entra.
	if desliza < 1.0 and morph <= 0.0:
		# Abre do centro para os dois lados, acompanhando o subtítulo que
		# assenta. Crescendo da esquerda parecia uma barra de carregamento.
		var meia := 470.0 * ease(desliza, 0.3)
		canvas.draw_line(
			Vector2(540.0 - meia, sub_y + 28.0), Vector2(540.0 + meia, sub_y + 28.0),
			Color(GOLD, 1.0 - desliza * 0.75), 6.0, true
		)

## A ASSINATURA DA CASA e o recorde. Entram por último porque são a
## informação, e informação depois do espetáculo é informação que fica.
static func _intro_assinatura(canvas: Control, time: float, morph: float) -> void:
	if time < T_ASSINATURA:
		return
	var t := _janela(time, T_ASSINATURA, 0.5)
	# A assinatura APAGA na virada em vez de viajar até o topo. Subindo,
	# ela cruzava por cima de PUNCH e de CHALLENGE no meio do caminho — e
	# a abertura já desenha a sua própria, no lugar certo, logo em
	# seguida.
	var saida := 1.0 - ease(morph, 0.5)
	canvas._texto("LAZER & SPORT", 1535.0, 27, Color(GOLD, t * saida))
	canvas._texto(
		"QUAL É A SUA FORÇA?", 1622.0, 32,
		Color(WHITE, t * saida * (0.82 + 0.18 * sin(time * 5.0)))
	)

## O TRECHO PARADO NÃO PODE FICAR PARADO.
##
## Entre o subtítulo assentar e a virada para a abertura há cerca de um
## segundo em que nada mais entra — e um segundo de imagem congelada, num
## fliperama, é a máquina parecendo travada. Uma luz varre o letreiro e o
## emblema dá uma batida, como um letreiro de metal pegando o refletor.
static func _intro_brilho(canvas: Control, time: float, morph: float) -> void:
	var t := _janela(time, T_BRILHO, 0.85)
	if t <= 0.0 or morph > 0.0:
		return
	if t < 1.0:
		var x := lerpf(-420.0, 1500.0, ease(t, 0.6))
		var alto := 1150.0
		var baixo := 1450.0
		for camada in range(3):
			var meia := 34.0 + float(camada) * 46.0
			var faixa := PackedVector2Array([
				Vector2(x - meia + 150.0, alto), Vector2(x + meia + 150.0, alto),
				Vector2(x + meia - 150.0, baixo), Vector2(x - meia - 150.0, baixo),
			])
			canvas.draw_colored_polygon(faixa, Color(WHITE, 0.16 - float(camada) * 0.045))
	# A batida do emblema: um anel que sai dele e se apaga.
	var batida := _janela(time, T_BRILHO + 0.15, 0.75)
	if batida > 0.0 and batida < 1.0:
		canvas.draw_arc(
			Vector2(540.0, 760.0), lerpf(300.0, 640.0, ease(batida, 0.35)),
			0.0, TAU, 96, Color(GOLD, (1.0 - batida) * 0.5), 5.0, true
		)
