class_name PunchBackground
extends Control

## Fundo premium: preto profundo, piso em perspectiva, brilhos neon
## flutuando e poeira subindo. Tudo desenhado em escala relativa ao
## tamanho real do controle, então nada corta em outras resoluções.

var tempo := 0.0
var fx := PunchFX.new()
## Tonalidade do veredito: tingem a tela inteira após o golpe.
var matiz := Color(0, 0, 0, 0)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	tempo += delta
	fx.atualizar(delta)
	if randf() < delta * 5.0:
		fx.poeira(
			Vector2(randf_range(0.1, 0.9) * size.x, size.y + 30.0),
			1, Color(0.35, 0.85, 1.0, 0.30), 110.0
		)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("04060f"))

	# Brilhos grandes e lentos: profundidade sem textura.
	_glow(Vector2(w * 0.15, h * 0.16), w * 0.28, Color(0.02, 0.60, 0.95, 0.07))
	_glow(Vector2(w * 0.86, h * 0.72), w * 0.33, Color(0.66, 0.10, 0.55, 0.07))
	_glow(Vector2(w * 0.5, h * 0.42), w * 0.22 + sin(tempo * 0.8) * w * 0.02, Color(0.10, 0.30, 0.85, 0.05))

	# Piso em perspectiva correndo para a borda inferior.
	var horizonte := h * 0.62
	for i in range(16):
		var t := float(i) / 16.0
		var y := horizonte + pow(t, 2.2) * (h - horizonte)
		draw_line(Vector2(0, y), Vector2(w, y), Color(0.16, 0.42, 0.85, 0.07), 1.0)
	for i in range(-9, 10):
		draw_line(
			Vector2(w * 0.5 + i * w * 0.024, horizonte),
			Vector2(w * 0.5 + i * w * 0.21, h),
			Color(0.16, 0.42, 0.85, 0.055), 1.0
		)

	# Poeira de LED subindo, parallax leve.
	for i in range(22):
		var x := fmod(float(i * 271), w)
		var y := fmod(float(i * 397) + tempo * (9.0 + i * 0.35), h)
		draw_circle(Vector2(x, y), 1.5 + float(i % 3), Color(0.25, 0.85, 1.0, 0.18))

	fx.desenhar(self)

	if matiz.a > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), matiz)

func _glow(centro: Vector2, raio: float, cor: Color) -> void:
	for i in range(3):
		var c := cor
		c.a *= 1.0 - float(i) / 3.0
		draw_circle(centro, raio * (1.0 - i * 0.28), c)
