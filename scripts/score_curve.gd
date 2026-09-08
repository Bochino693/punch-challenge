class_name ScoreCurve
extends RefCounted

## Converte a velocidade real do saco em uma nota de arcade. O smoothstep
## tira o salto da zona morta e o expoente > 1 impede que um golpe mediano
## chegue cedo demais às notas altas.

const EXPONENT_MIN := 1.10
const EXPONENT_MAX := 3.00
const DEFAULT_EXPONENT := 2.00
const DEFAULT_DEAD_ZONE := 0.06
const CHARGE_MAX_SECONDS := 2.80

static func sanitize(min_speed: float, max_speed: float, exponent: float, dead_zone: float) -> Dictionary:
	var low := clampf(min_speed, 0.0, 59.0)
	var high := clampf(max_speed, low + 0.1, 60.0)
	return {
		"min_speed": low,
		"max_speed": high,
		"exponent": clampf(exponent, EXPONENT_MIN, EXPONENT_MAX),
		"dead_zone": clampf(dead_zone, 0.0, 0.35),
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
	if exponent < 1.52:
		return "FÁCIL"
	if exponent < 1.86:
		return "NORMAL"
	if exponent <= 2.06:
		return "DIFÍCIL"
	return "PERSONALIZADO"

static func next_difficulty(exponent: float) -> float:
	var name := difficulty_name(exponent)
	match name:
		"FÁCIL":
			return 1.70
		"NORMAL":
			return 2.00
		"DIFÍCIL":
			return 2.35
	return 1.35
