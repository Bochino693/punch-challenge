class_name PowerMeter
extends Control

## Medidor vertical de potência (0..999). Enche de baixo para cima,
## muda de cor conforme a força e tem um rastro suave (o nível visível
## persegue o alvo). Também exibe a carga da simulação, sem revelar a
## pontuação final.

var nivel_alvo := 0.0 ## 0..1
var nivel_visivel := 0.0
var carga := -1.0 ## >= 0 mostra carga da simulação (0..1)
var tempo := 0.0
var fonte: Font = null

const CORES := [
	Color("39c6ff"), # ciano — leve
	Color("52f2a4"), # verde
	Color("ffd23f"), # âmbar
	Color("ff7a1a"), # laranja
	Color("ff2d55"), # vermelho
	Color("b45cff"), # roxo — lendário
]

func _ready() -> void:
	custom_minimum_size = Vector2(96, 100)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	tempo += delta
	nivel_visivel = lerpf(nivel_visivel, nivel_alvo, 1.0 - pow(0.0001, delta))
	queue_redraw()

func set_pontos(pontos: float) -> void:
	nivel_alvo = clampf(pontos / float(GameDef.SCORE_MAX), 0.0, 1.0)

func set_carga(valor: float) -> void:
	carga = clampf(valor, 0.0, 1.0) if valor >= 0.0 else -1.0

func reset() -> void:
	nivel_alvo = 0.0
	nivel_visivel = 0.0
	carga = -1.0

func cor_do_nivel(n: float) -> Color:
	var pos := clampf(n, 0.0, 0.999) * CORES.size()
	var i := int(pos)
	return CORES[i].lerp(CORES[mini(i + 1, CORES.size() - 1)], pos - i)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var barra := Rect2(w * 0.30, h * 0.04, w * 0.40, h * 0.90)
	draw_rect(barra.grow(6), Color(0.05, 0.08, 0.17, 0.9))
	draw_rect(barra, Color(0.015, 0.025, 0.06, 1.0))

	# Marcas de 100 em 100 pontos.
	for i in range(1, 10):
		var y := barra.end.y - barra.size.y * (i / 10.0)
		draw_line(Vector2(barra.position.x - 5, y), Vector2(barra.position.x + 7, y), Color(0.4, 0.5, 0.7, 0.5), 2.0)
		draw_line(Vector2(barra.end.x - 7, y), Vector2(barra.end.x + 5, y), Color(0.4, 0.5, 0.7, 0.5), 2.0)

	var nivel := nivel_visivel
	if carga >= 0.0:
		nivel = carga
	if nivel > 0.003:
		var cor := cor_do_nivel(nivel)
		if carga >= 0.0:
			# Carga pulsando: energia acumulando, não resultado.
			var pulso := 0.75 + 0.25 * sin(tempo * 18.0)
			cor = Color(cor.r, cor.g, cor.b, pulso)
		var preenchido := Rect2(
			barra.position + Vector2(0, barra.size.y * (1.0 - nivel)),
			Vector2(barra.size.x, barra.size.y * nivel)
		)
		draw_rect(preenchido, cor)
		# Fio de brilho no topo da coluna.
		draw_rect(Rect2(preenchido.position, Vector2(preenchido.size.x, 5)), Color(1, 1, 1, 0.65))
		_glow(Vector2(barra.get_center().x, preenchido.position.y), 26.0, Color(cor.r, cor.g, cor.b, 0.25))

	if fonte != null:
		draw_string(
			fonte, Vector2(0, h - 6), "POTÊNCIA",
			HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.16), Color(0.55, 0.65, 0.85, 0.8)
		)

func _glow(centro: Vector2, raio: float, cor: Color) -> void:
	for i in range(3):
		var c := cor
		c.a *= 1.0 - float(i) / 3.0
		draw_circle(centro, raio * (1.0 + i * 0.6), c)
