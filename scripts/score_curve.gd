class_name ScoreCurve
extends RefCounted

## A nota usa a velocidade integrada enviada pelo firmware em m/s.
## Pico em g e duração continuam informativos: não são massa ou força.
##
## x = fração da faixa calibrada, após a zona morta
## pontos = round(9999 * pow(x, expoente))
##
## Uma única potência evita achatar os golpes baixos duas vezes.
## Com expoente 2,20, superar 8000 exige x > 0,9036.
## Estes padrões são uma referência; o assistente mede a faixa da montagem.
const EXPONENT_MIN := 1.50
const EXPONENT_MAX := 4.50
const DEFAULT_EXPONENT := 2.20
const DEFAULT_DEAD_ZONE := 0.0
const DEFAULT_MIN_SPEED := 0.30
const DEFAULT_MAX_SPEED := 5.20
## Limites de regulagem oferecidos pela Central Técnica.
const MIN_SPEED_MIN := 0.20
const MIN_SPEED_MAX := 10.00
const MAX_SPEED_MIN := 0.75
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
	var pontos := clampi(int(round(pow(x, cfg["exponent"]) * GameDef.SCORE_MAX)), 0, GameDef.SCORE_MAX)
	# Um golpe aprovado e acima da zona morta precisa aparecer. A curva
	# difícil pode arredondar o começo para zero, que parece falha do saco.
	if x > 0.000001 and pontos == 0:
		return 1
	# Não deixe o arredondamento entregar 9999 antes de o golpe alcançar
	# de fato o teto calibrado da máquina.
	if pontos >= GameDef.SCORE_MAX and speed < float(cfg["max_speed"]):
		return GameDef.SCORE_MAX - 1
	return pontos

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
