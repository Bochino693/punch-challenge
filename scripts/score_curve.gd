class_name ScoreCurve
extends RefCounted

## A VELOCIDADE DO SOCO VIRA NOTA AQUI, E SÓ AQUI.
##
##     x = clamp((v - vmin) / (vmax - vmin), 0, 1)
##     x = 0, dentro da zona morta
##     s = x*x*(3 - 2*x)                  (smoothstep)
##     pontos = round(9999 * pow(s, expoente))
##
## O smoothstep tira o degrau na saída da zona morta — sem ele, o
## primeiro ponto acima do piso já valeria dezenas. O expoente maior que
## 1 é o que segura a escala: com expoente 1 um golpe de metade da
## velocidade máxima já valeria metade da nota, e 5000 pontos deixaria de
## significar alguma coisa.
##
## A CURVA É MONOTÔNICA POR CONSTRUÇÃO: x cresce com v, s cresce com x, e
## pow com expoente positivo preserva a ordem. Um soco mais forte nunca
## pode valer menos, e isso é testado.
##
## Só a VELOCIDADE entra na nota. O pico de aceleração e a duração do
## evento servem para o firmware e para o jogo decidirem se aquilo foi um
## soco de verdade — validam, não inflam.

const EXPONENT_MIN := 1.50
const EXPONENT_MAX := 4.50
## Parâmetros de fábrica, medidos para um saco de arcade comum.
const DEFAULT_EXPONENT := 2.80
const DEFAULT_DEAD_ZONE := 0.08
const DEFAULT_MIN_SPEED := 1.20
const DEFAULT_MAX_SPEED := 16.00
## Limites de regulagem oferecidos pela Central Técnica.
const MIN_SPEED_MIN := 0.20
const MIN_SPEED_MAX := 10.00
const MAX_SPEED_MIN := 5.00
const MAX_SPEED_MAX := 30.00
const DEAD_ZONE_MAX := 0.25
const CHARGE_MAX_SECONDS := 2.80

static func sanitize(min_speed: float, max_speed: float, exponent: float, dead_zone: float) -> Dictionary:
	var low := clampf(min_speed, MIN_SPEED_MIN, MIN_SPEED_MAX)
	var high := clampf(max_speed, maxf(MAX_SPEED_MIN, low + 0.5), MAX_SPEED_MAX)
	return {
		"min_speed": low,
		"max_speed": high,
		"exponent": clampf(exponent, EXPONENT_MIN, EXPONENT_MAX),
		"dead_zone": clampf(dead_zone, 0.0, DEAD_ZONE_MAX),
	}

static func normalized(speed: float, min_speed: float, max_speed: float, dead_zone := DEFAULT_DEAD_ZONE) -> float:
	var cfg := sanitize(min_speed, max_speed, DEFAULT_EXPONENT, dead_zone)
	var span: float = cfg["max_speed"] - cfg["min_speed"]
	var x := clampf((maxf(speed, 0.0) - cfg["min_speed"]) / span, 0.0, 1.0)
	var dz: float = cfg["dead_zone"]
	if x <= dz:
		return 0.0
	x = (x - dz) / maxf(1.0 - dz, 0.01)
	return clampf(x, 0.0, 1.0)

static func points_from_speed(
	speed: float,
	min_speed: float,
	max_speed: float,
	exponent := DEFAULT_EXPONENT,
	dead_zone := DEFAULT_DEAD_ZONE
) -> int:
	var cfg := sanitize(min_speed, max_speed, exponent, dead_zone)
	var x := normalized(speed, cfg["min_speed"], cfg["max_speed"], cfg["dead_zone"])
	var smooth := x * x * (3.0 - 2.0 * x)
	return clampi(int(round(pow(smooth, cfg["exponent"]) * GameDef.SCORE_MAX)), 0, GameDef.SCORE_MAX)

static func speed_from_charge(seconds: float, min_speed: float, max_speed: float) -> float:
	var t := clampf(seconds / CHARGE_MAX_SECONDS, 0.0, 1.0)
	# A carga virtual cresce devagar no começo e acelera perto do fim.
	var virtual_strength := pow(t, 0.65)
	return lerpf(min_speed, max_speed, virtual_strength)

static func points_from_charge(
	seconds: float,
	min_speed: float,
	max_speed: float,
	exponent := DEFAULT_EXPONENT,
	dead_zone := DEFAULT_DEAD_ZONE
) -> int:
	return points_from_speed(
		speed_from_charge(seconds, min_speed, max_speed),
		min_speed, max_speed, exponent, dead_zone
	)

static func difficulty_name(exponent: float) -> String:
	if exponent <= 1.85:
		return "FÁCIL"
	if exponent <= 2.45:
		return "NORMAL"
	if exponent <= 3.10:
		return "DIFÍCIL"
	return "IMPLACÁVEL"

static func next_difficulty(exponent: float) -> float:
	match difficulty_name(exponent):
		"FÁCIL":
			return 2.20
		"NORMAL":
			return 2.80
		"DIFÍCIL":
			return 3.60
	return 1.70

## A CURVA INTEIRA EM `amostras` PONTOS, para a Central desenhar antes de
## salvar. Quem regula precisa VER o que a mudança faz: um expoente é um
## número abstrato, e a diferença entre 2,80 e 3,20 só existe no desenho.
static func amostrar(
	min_speed: float, max_speed: float, exponent: float, dead_zone: float, amostras := 48
) -> Array:
	var cfg := sanitize(min_speed, max_speed, exponent, dead_zone)
	var pontos: Array = []
	for i in range(amostras + 1):
		var t := float(i) / float(amostras)
		var v: float = lerpf(0.0, cfg["max_speed"] * 1.05, t)
		pontos.append(Vector2(v, float(points_from_speed(
			v, cfg["min_speed"], cfg["max_speed"], cfg["exponent"], cfg["dead_zone"]
		))))
	return pontos
