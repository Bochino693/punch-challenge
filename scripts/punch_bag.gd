class_name PunchBag
extends Control

## O saco de pancadas da máquina.
##
## Pendurado por uma corrente no topo do próprio retângulo. O balanço
## é física de pêndulo simples: `golpear` injeta velocidade angular e a
## mola + amortecimento trazem o saco de volta. Enquanto a simulação
## carrega (`set_carga`), o saco treme e inclina para trás, como quem
## toma distância do soco que vem.

var tempo := 0.0
var angulo := 0.0
var vel_angular := 0.0
## Carga da simulação (0..1); negativo desliga o tremor de preparação.
var carga := -1.0
## Anel de mira, mostrado enquanto o sensor espera o soco.
var alvo_visivel := false
var _impacto := 0.0 ## brilho do ponto atingido, decai sozinho

const MOLA := 26.0
const AMORTECIMENTO := 2.6

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1

## O soco. `forca` de 0 (encostou) a 1 (lendário).
func golpear(forca: float) -> void:
	var f := clampf(forca, 0.0, 1.0)
	vel_angular += lerpf(2.2, 9.5, f) * (1.0 if randf() > 0.08 else -1.0)
	_impacto = 1.0

func set_carga(valor: float) -> void:
	carga = clampf(valor, 0.0, 1.0) if valor >= 0.0 else -1.0

func set_alvo(visivel: bool) -> void:
	alvo_visivel = visivel

func _process(delta: float) -> void:
	tempo += delta
	_impacto = maxf(0.0, _impacto - delta * 2.8)
	# Pêndulo: mola puxando para o centro, amortecimento tirando energia.
	var acel := -MOLA * angulo - AMORTECIMENTO * vel_angular
	vel_angular += acel * delta
	angulo += vel_angular * delta
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var pivot := Vector2(w * 0.5, h * 0.03)
	var corrente := h * 0.13
	var saco_altura := h * 0.60
	var saco_largura := w * 0.46

	# Inclinação de preparação: o saco recua um pouco conforme a carga,
	# e treme quando ela está alta.
	var inclinacao := angulo
	if carga >= 0.0:
		inclinacao += -0.06 * carga + sin(tempo * (20.0 + 30.0 * carga)) * 0.012 * carga

	# Sombra no chão acompanha o pêndulo: some para o lado oposto.
	var sombra_x := w * 0.5 - sin(inclinacao) * corrente * 1.6
	var sombra_w := saco_largura * (1.15 - 0.25 * absf(sin(inclinacao)))
	draw_set_transform(Vector2(sombra_x, h * 0.95), 0.0, Vector2(sombra_w / 40.0, 1.0))
	draw_circle(Vector2.ZERO, 19.0, Color(0, 0, 0, 0.4))
	draw_set_transform(Vector2.ZERO, 0.0)

	draw_set_transform(pivot, inclinacao)

	# Corrente: elos alternados, presos ao teto do gabinete.
	var elo_altura := corrente / 5.0
	for i in range(5):
		var y := i * elo_altura
		var cor_elo := Color("5a6c94") if i % 2 == 0 else Color("3d4a68")
		draw_rect(Rect2(-5, y, 10, elo_altura * 0.72), cor_elo, true)
		draw_rect(Rect2(-5, y, 10, elo_altura * 0.72), Color(0.02, 0.03, 0.07, 0.8), false, 2.0)

	# Corpo do saco: cápsula vertical com costuras e brilho lateral.
	var topo := corrente
	var corpo := Rect2(-saco_largura * 0.5, topo, saco_largura, saco_altura)
	var cor_saco := Color("8f1f3d")
	if carga >= 0.0:
		cor_saco = cor_saco.lerp(Color("d4384f"), carga * 0.55)
	if _impacto > 0.0:
		cor_saco = cor_saco.lerp(Color("ff8a5c"), _impacto * 0.6)
	draw_rect(corpo.grow(6.0), Color("2a0d18"), true)
	draw_rect(corpo, cor_saco, true)
	# Costuras horizontais.
	for i in range(1, 4):
		var y := topo + saco_altura * float(i) / 4.0
		draw_line(Vector2(-saco_largura * 0.5, y), Vector2(saco_largura * 0.5, y), Color(0.25, 0.05, 0.1, 0.65), 3.0)
	# Vinil: reflexo na lateral esquerda, sombra na direita.
	draw_rect(Rect2(-saco_largura * 0.5, topo, saco_largura * 0.18, saco_altura), Color(1, 1, 1, 0.10))
	draw_rect(Rect2(saco_largura * 0.30, topo, saco_largura * 0.20, saco_altura), Color(0, 0, 0, 0.22))
	# Tiras de cima e de baixo.
	draw_rect(Rect2(-saco_largura * 0.5, topo, saco_largura, saco_altura * 0.07), Color("1c2438"))
	draw_rect(Rect2(-saco_largura * 0.5, topo + saco_altura * 0.93, saco_largura, saco_altura * 0.07), Color("1c2438"))

	# Ponto do impacto: brilho radial na altura do meio do saco.
	if _impacto > 0.01:
		var centro_golpe := Vector2(0, topo + saco_altura * 0.42)
		for i in range(3):
			var c := Color(1.0, 0.92, 0.6, _impacto * (0.5 - i * 0.14))
			draw_circle(centro_golpe, (26.0 + i * 30.0) * (1.4 - _impacto * 0.4), c)

	# Mira: anéis concêntricos pulsando enquanto o sensor espera.
	if alvo_visivel:
		var centro_mira := Vector2(0, topo + saco_altura * 0.42)
		var pulso := 0.5 + 0.5 * sin(tempo * 6.0)
		draw_arc(centro_mira, 52.0 + pulso * 10.0, 0, TAU, 64, Color(1, 0.35, 0.45, 0.9), 6.0, true)
		draw_arc(centro_mira, 30.0, 0, TAU, 48, Color(1, 1, 1, 0.7), 3.0, true)
		draw_circle(centro_mira, 8.0, Color(1, 0.3, 0.4, 0.9))

	draw_set_transform(Vector2.ZERO, 0.0)
