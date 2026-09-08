class_name PowerMeter
extends Control

## A coluna de potência, ao lado do saco.
##
## NÃO É UMA BARRA DE PROGRESSO. É a régua que explica o número: as três
## zonas coloridas mostram, ANTES do soco, onde ficam fraco, médio e
## forte nesta máquina, e o traço do recorde mostra até onde alguém já
## chegou. Depois do soco, a coluna sobe até o ponto e o cursor marca o
## resultado sobre a mesma régua — o cliente não precisa decorar faixa
## nenhuma para entender se foi bem.
##
## Os limites das zonas vêm da Central Técnica (`set_faixas`); a coluna
## não guarda regra própria, para que régua, moldura e veredito nunca
## discordem sobre o que é um golpe forte.

var nivel_alvo := 0.0 ## 0..1
var nivel_visivel := 0.0
var carga := -1.0 ## >= 0 mostra carga da simulação (0..1)
var tempo := 0.0
var fonte: Font = null
## Recorde da máquina, em pontos; <= 0 esconde o traço.
var recorde := 0

var _limiar_fraco := GameDef.LIMIAR_FRACO_PADRAO
var _limiar_forte := GameDef.LIMIAR_FORTE_PADRAO

## Marcas numeradas da régua.
const MARCAS := [0, 250, 500, 750, 999]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	tempo += delta
	nivel_visivel = lerpf(nivel_visivel, nivel_alvo, 1.0 - pow(0.0001, delta))
	queue_redraw()

func set_pontos(pontos: float) -> void:
	nivel_alvo = clampf(pontos / float(GameDef.SCORE_MAX), 0.0, 1.0)

func set_carga(valor: float) -> void:
	carga = clampf(valor, 0.0, 1.0) if valor >= 0.0 else -1.0

func set_faixas(fraco: int, forte: int) -> void:
	var lim := GameDef.limiares(fraco, forte)
	_limiar_fraco = lim.x
	_limiar_forte = lim.y

func reset() -> void:
	nivel_alvo = 0.0
	nivel_visivel = 0.0
	carga = -1.0

## Cor de um nível (0..1) segundo a faixa em que ele cai — a mesma cor
## que o veredito vai usar quando a contagem terminar.
func cor_do_nivel(n: float) -> Color:
	var pontos := int(round(clampf(n, 0.0, 1.0) * GameDef.SCORE_MAX))
	return GameDef.cor_da_faixa(GameDef.faixa_de(pontos, _limiar_fraco, _limiar_forte))

# ======================================================================
# DESENHO
# ======================================================================
func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var rotulo_altura := 50.0
	var trilho := Rect2(w * 0.46, 38.0, w * 0.40, h - rotulo_altura - 54.0)

	_moldura(trilho, w, rotulo_altura, h)
	_zonas(trilho)
	_escala(trilho)
	_coluna(trilho)
	_recorde(trilho)
	_rotulo(w, h, rotulo_altura)

## O medidor é um cartão branco com sombra, como as outras peças da tela.
## O trilho vazio é levemente mais escuro que o cartão: num tema claro é
## a coluna colorida que salta, e não a caixa em volta dela.
func _moldura(trilho: Rect2, w: float, rotulo_altura: float, h: float) -> void:
	var caixa := Rect2(0.0, 0.0, w, h)
	draw_rect(Rect2(caixa.position + Vector2(0.0, 6.0), caixa.size), Paleta.SOMBRA)
	draw_rect(caixa, Paleta.CARTAO)
	# BISEL MARINHO, igual ao do visor do medalhão: as duas peças de
	# instrumento da tela têm de parecer o mesmo equipamento.
	draw_rect(caixa, Paleta.MARINHO, false, 5.0)
	# Verniz: um reflexo claro na parte de cima da chapa.
	draw_rect(Rect2(5.0, 5.0, w - 10.0, h * 0.14), Color(1, 1, 1, 0.55))
	draw_line(
		Vector2(10.0, h - rotulo_altura), Vector2(w - 10.0, h - rotulo_altura),
		Paleta.CARTAO_BORDA, 1.5
	)
	draw_rect(trilho.grow(6.0), Paleta.MARINHO)
	draw_rect(trilho, Paleta.VAZIO)

## As três zonas, pintadas atrás do trilho: a régua da máquina. Num tema
## claro elas podem ser bem mais fortes do que num escuro sem virar
## borrão, e é isso que deixa a régua legível a três metros.
func _zonas(trilho: Rect2) -> void:
	var faixas := [
		[0.0, float(_limiar_fraco) / GameDef.SCORE_MAX, GameDef.COR_FRACA],
		[float(_limiar_fraco) / GameDef.SCORE_MAX, float(_limiar_forte) / GameDef.SCORE_MAX, GameDef.COR_MEDIA],
		[float(_limiar_forte) / GameDef.SCORE_MAX, 1.0, GameDef.COR_FORTE],
	]
	for f in faixas:
		var de: float = f[0]
		var ate: float = f[1]
		var cor: Color = f[2]
		var y0 := trilho.end.y - trilho.size.y * ate
		var y1 := trilho.end.y - trilho.size.y * de
		draw_rect(Rect2(trilho.position.x, y0, trilho.size.x, y1 - y0), Paleta.tinta_clara(cor, 0.30))
		if ate < 1.0:
			draw_line(
				Vector2(trilho.position.x - 7.0, y0), Vector2(trilho.end.x + 7.0, y0),
				cor, 2.5
			)

## Marcas numeradas à esquerda do trilho.
func _escala(trilho: Rect2) -> void:
	for valor in MARCAS:
		var t := float(valor) / float(GameDef.SCORE_MAX)
		var y := trilho.end.y - trilho.size.y * t
		draw_line(
			Vector2(trilho.position.x - 13.0, y), Vector2(trilho.position.x - 3.0, y),
			Paleta.TINTA_LEVE, 2.0
		)
		if fonte != null:
			draw_string(
				fonte, Vector2(0.0, y + 6.0), str(valor), HORIZONTAL_ALIGNMENT_RIGHT,
				trilho.position.x - 19.0, 17, Paleta.TINTA_FRACA
			)
	for i in range(1, 10):
		var y := trilho.end.y - trilho.size.y * (float(i) / 10.0)
		draw_line(
			Vector2(trilho.end.x - 6.0, y), Vector2(trilho.end.x, y),
			Color(Paleta.TINTA_LEVE, 0.55), 1.0
		)

## A coluna que sobe, e o cursor que marca onde ela parou.
##
## A CARGA MOSTRA O VALOR EXATO. Enquanto a barra de espaço está
## pressionada, `carga` já vem convertido em pontos pelo jogo — não é
## "quanto tempo você segurou", é "quanto vale se você soltar agora".
## Por isso ela usa a cor da faixa e o mesmo cursor do resultado: o que
## a coluna promete durante a carga é exatamente o que o placar vai dar.
func _coluna(trilho: Rect2) -> void:
	var nivel := nivel_visivel
	var carregando := carga >= 0.0
	if carregando:
		nivel = carga
	if nivel <= 0.003:
		return

	var cor := cor_do_nivel(nivel)
	var topo_y := trilho.end.y - trilho.size.y * nivel
	var preenchido := Rect2(trilho.position.x, topo_y, trilho.size.x, trilho.end.y - topo_y)
	draw_rect(preenchido, cor)
	# Brilho na lateral esquerda e sombra na direita: a coluna ganha volume.
	draw_rect(
		Rect2(preenchido.position.x, preenchido.position.y, preenchido.size.x * 0.30, preenchido.size.y),
		Color(1, 1, 1, 0.26)
	)
	draw_rect(
		Rect2(preenchido.end.x - preenchido.size.x * 0.18, preenchido.position.y,
			preenchido.size.x * 0.18, preenchido.size.y),
		Color(0, 0, 0, 0.10)
	)
	# Fio de luz no topo da coluna. Durante a carga ele pulsa, para a
	# coluna parecer viva sem mentir sobre o número.
	var brilho := 1.0 if not carregando else 0.55 + 0.45 * sin(tempo * 16.0)
	draw_rect(Rect2(preenchido.position, Vector2(preenchido.size.x, 5.0)), Color(1, 1, 1, 0.55 + 0.35 * brilho))
	draw_line(
		Vector2(preenchido.position.x, topo_y), Vector2(preenchido.end.x, topo_y),
		cor.darkened(0.25), 2.5
	)

	# Cursor: a seta que aponta o valor sobre a régua.
	var x := trilho.end.x + 8.0
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(x, topo_y), Vector2(x + 14.0, topo_y - 10.0), Vector2(x + 14.0, topo_y + 10.0),
		]),
		cor.darkened(0.15)
	)

## Traço do recorde da casa: a linha que o cliente quer passar.
func _recorde(trilho: Rect2) -> void:
	if recorde <= 0:
		return
	var t := clampf(float(recorde) / float(GameDef.SCORE_MAX), 0.0, 1.0)
	var y := trilho.end.y - trilho.size.y * t
	var cor := Paleta.MARINHO
	# Tracejado, para não ser confundido com o topo da coluna.
	var x := trilho.position.x - 4.0
	while x < trilho.end.x + 4.0:
		draw_line(Vector2(x, y), Vector2(minf(x + 7.0, trilho.end.x + 4.0), y), cor, 2.5)
		x += 12.0
	Icones.trofeu(self, Vector2(trilho.position.x - 15.0, y), 9.0, cor)

func _rotulo(w: float, h: float, rotulo_altura: float) -> void:
	if fonte == null:
		return
	draw_string(
		fonte, Vector2(0.0, h - rotulo_altura * 0.55), "POTÊNCIA",
		HORIZONTAL_ALIGNMENT_CENTER, w, 19, Paleta.TINTA
	)
	draw_string(
		fonte, Vector2(0.0, h - rotulo_altura * 0.16), "0 – 999",
		HORIZONTAL_ALIGNMENT_CENTER, w, 14, Paleta.TINTA_LEVE
	)
