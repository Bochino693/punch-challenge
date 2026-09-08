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

	var rotulo_altura := 46.0
	var trilho := Rect2(w * 0.46, 34.0, w * 0.40, h - rotulo_altura - 48.0)

	_moldura(trilho, w, rotulo_altura, h)
	_zonas(trilho)
	_escala(trilho)
	_coluna(trilho)
	_recorde(trilho)
	_rotulo(w, h, rotulo_altura)

## Caixa do medidor: fundo, borda e o vidro escuro do trilho.
func _moldura(trilho: Rect2, w: float, rotulo_altura: float, h: float) -> void:
	var caixa := Rect2(0.0, 0.0, w, h)
	draw_rect(caixa, Color(0.035, 0.055, 0.115, 0.85))
	draw_rect(caixa, Color(0.24, 0.44, 0.78, 0.35), false, 2.0)
	draw_rect(Rect2(0.0, h - rotulo_altura, w, 1.0), Color(0.24, 0.44, 0.78, 0.30))
	draw_rect(trilho.grow(5.0), Color(0.08, 0.12, 0.22, 1.0))
	draw_rect(trilho, Color(0.012, 0.02, 0.05, 1.0))

## As três zonas, pintadas fracas atrás do trilho: a régua da máquina.
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
		draw_rect(Rect2(trilho.position.x, y0, trilho.size.x, y1 - y0), Color(cor.r, cor.g, cor.b, 0.13))
		# Traço divisor no limite superior da zona.
		if ate < 1.0:
			draw_line(
				Vector2(trilho.position.x - 6.0, y0), Vector2(trilho.end.x + 6.0, y0),
				Color(cor.r, cor.g, cor.b, 0.75), 2.0
			)

## Marcas numeradas à esquerda do trilho.
func _escala(trilho: Rect2) -> void:
	for valor in MARCAS:
		var t := float(valor) / float(GameDef.SCORE_MAX)
		var y := trilho.end.y - trilho.size.y * t
		draw_line(Vector2(trilho.position.x - 12.0, y), Vector2(trilho.position.x - 3.0, y), Color(0.45, 0.56, 0.78, 0.8), 2.0)
		if fonte != null:
			draw_string(
				fonte, Vector2(0.0, y + 6.0), str(valor), HORIZONTAL_ALIGNMENT_RIGHT,
				trilho.position.x - 18.0, 17, Color(0.52, 0.62, 0.82, 0.9)
			)
	# Marcas menores de 100 em 100, sem número.
	for i in range(1, 10):
		var y := trilho.end.y - trilho.size.y * (float(i) / 10.0)
		draw_line(Vector2(trilho.end.x - 6.0, y), Vector2(trilho.end.x, y), Color(0.4, 0.5, 0.7, 0.35), 1.0)

## A coluna que sobe, e o cursor que marca onde ela parou.
func _coluna(trilho: Rect2) -> void:
	var nivel := nivel_visivel
	var carregando := carga >= 0.0
	if carregando:
		nivel = carga
	if nivel <= 0.003:
		return

	var cor := cor_do_nivel(nivel)
	if carregando:
		# Carga: energia acumulando, ainda não é resultado. Pulsa e não
		# usa a cor da faixa, para não prometer nota antes da hora.
		cor = Color("4beaff")
		cor.a = 0.70 + 0.30 * sin(tempo * 18.0)

	var topo_y := trilho.end.y - trilho.size.y * nivel
	var preenchido := Rect2(trilho.position.x, topo_y, trilho.size.x, trilho.end.y - topo_y)
	draw_rect(preenchido, Color(cor.r, cor.g, cor.b, 0.92))
	# Brilho interno na lateral esquerda: a coluna ganha volume.
	draw_rect(
		Rect2(preenchido.position.x, preenchido.position.y, preenchido.size.x * 0.32, preenchido.size.y),
		Color(1, 1, 1, 0.16)
	)
	# Fio de luz e halo no topo da coluna.
	draw_rect(Rect2(preenchido.position, Vector2(preenchido.size.x, 5.0)), Color(1, 1, 1, 0.85))
	_glow(Vector2(trilho.get_center().x, topo_y), 22.0, Color(cor.r, cor.g, cor.b, 0.28))

	if not carregando:
		# Cursor: a seta que aponta o resultado sobre a régua.
		var x := trilho.end.x + 8.0
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(x, topo_y), Vector2(x + 13.0, topo_y - 9.0), Vector2(x + 13.0, topo_y + 9.0),
			]),
			cor
		)

## Traço do recorde da casa: a linha que o cliente quer passar.
func _recorde(trilho: Rect2) -> void:
	if recorde <= 0:
		return
	var t := clampf(float(recorde) / float(GameDef.SCORE_MAX), 0.0, 1.0)
	var y := trilho.end.y - trilho.size.y * t
	var cor := Color("58e8ff")
	# Tracejado, para não ser confundido com o topo da coluna.
	var x := trilho.position.x - 4.0
	while x < trilho.end.x + 4.0:
		draw_line(Vector2(x, y), Vector2(minf(x + 7.0, trilho.end.x + 4.0), y), cor, 2.0)
		x += 12.0
	draw_circle(Vector2(trilho.position.x - 9.0, y), 3.5, cor)

func _rotulo(w: float, h: float, rotulo_altura: float) -> void:
	if fonte == null:
		return
	draw_string(
		fonte, Vector2(0.0, h - rotulo_altura * 0.55), "POTÊNCIA",
		HORIZONTAL_ALIGNMENT_CENTER, w, 19, Color(0.62, 0.72, 0.92, 0.95)
	)
	draw_string(
		fonte, Vector2(0.0, h - rotulo_altura * 0.14), "0 – 999",
		HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(0.42, 0.51, 0.70, 0.9)
	)

func _glow(centro: Vector2, raio: float, cor: Color) -> void:
	for i in range(3):
		var c := cor
		c.a *= 1.0 - float(i) / 3.0
		draw_circle(centro, raio * (1.0 + i * 0.6), c)
