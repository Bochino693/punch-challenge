extends RefCounted
## Cenografia e abertura. Não controla créditos, câmera ou pontuação.
const EMBLEM = preload("res://assets/branding/punch_emblem.svg")
const RED := Color("ff1934")
const GOLD := Color("ffdc27")
const WHITE := Color("fff9ef")
const FLOOR := Color("19060d")
const PANEL := Color("330c16")
const INTRO_SECONDS := 4.2

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

static func intro(canvas: Control, time: float) -> void:
	var enter := clampf(time / 0.85, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - enter, 3.0)
	var size := lerpf(880.0, 620.0, eased)
	var center := Vector2(540, lerpf(670.0, 790.0, eased))
	emblem(canvas, center, size, enter)
	var burst := clampf((time - 0.8) / 0.65, 0.0, 1.0)
	if time >= 0.8 and burst < 1.0:
		for i in range(18):
			var direction := Vector2.from_angle(float(i) * TAU / 18.0)
			var radius := 220.0 + burst * 470.0
			canvas.draw_line(center + direction * radius, center + direction * (radius + 90.0), Color(GOLD, 1.0 - burst), 5.0, true)
	var title_alpha := clampf((time - 1.0) / 0.5, 0.0, 1.0)
	canvas._texto_arcade("PUNCH", 1260.0, 134, Color(WHITE, title_alpha), 960.0)
	canvas._texto_arcade("CHALLENGE", 1385.0, 93, Color(GOLD, title_alpha), 960.0)
	canvas._texto("LAZER & SPORT", 1535.0, 27, Color(WHITE, title_alpha))
	if time > 3.75:
		canvas.draw_rect(Rect2(0, 0, 1080, 1920), Color(FLOOR, clampf((time - 3.75) / 0.45, 0, 1)))
