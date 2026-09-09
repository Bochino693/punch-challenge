class_name ScoreCurve
extends RefCounted

## Converte a velocidade real do saco (m/s, medida pelo MPU-6050) em uma
## nota de arcade de 0 a 9999. A VELOCIDADE é a medida principal; pico
## de aceleração e duração validam a qualidade física do golpe no
## firmware, não inflam a nota.
##
##   x = clamp((velocidade - vmin) / (vmax - vmin), 0, 1)
##   x = 0 dentro da zona morta
##   s = x*x*(3 - 2*x)
##   pontos = round(9999 * pow(s, expoente))
##
## A curva é contínua e monotônica: o smoothstep tira o salto da zona
## morta e o expoente > 1 impede que um golpe mediano chegue cedo às
## notas altas. 9999 exige alcançar ou superar vmax — nunca é fixado
## artificialmente.

const EXPONENT_MIN := 1.5
const EXPONENT_MAX := 4.5
const DEFAULT_EXPONENT := 2.80
const DEAD_ZONE_MIN := 0.0
const DEAD_ZONE_MAX := 0.25
const DEFAULT_DEAD_ZONE := 0.08
const VMIN_MIN := 0.2
const VMIN_MAX := 10.0
const VMAX_MIN := 5.0
const VMAX_MAX := 30.0
const DEFAULT_VMIN := 1.2
const DEFAULT_VMAX := 16.0
const CHARGE_MAX_SECONDS := 2.80

static func sanitize(min_speed: float, max_speed: float, exponent: float, dead_zone: float) -> Dictionary:
	var low := clampf(min_speed, VMIN_MIN, VMIN_MAX)
	var high := clampf(max_speed, VMAX_MIN, VMAX_MAX)
	if high <= low:
		high = minf(low + 1.0, VMAX_MAX)
		if high <= low:
			low = high - 1.0
	return {
		"min_speed": low,
		"max_speed": high,
		"exponent": clampf(exponent, EXPONENT_MIN, EXPONENT_MAX),
		"dead_zone": clampf(dead_zone, DEAD_ZONE_MIN, DEAD_ZONE_MAX),
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
	if exponent < 2.2:
		return "FÁCIL"
	if exponent < 2.9:
		return "NORMAL"
	if exponent <= 3.4:
		return "DIFÍCIL"
	return "PERSONALIZADO"

static func next_difficulty(exponent: float) -> float:
	var name := difficulty_name(exponent)
	match name:
		"FÁCIL":
			return 2.80
		"NORMAL":
			return 3.30
		"DIFÍCIL":
			return 3.90
	return 1.90
