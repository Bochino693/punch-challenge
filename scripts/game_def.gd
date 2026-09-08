class_name GameDef
extends RefCounted

## Definições compartilhadas do Punch Challenge: estados, classes de golpe
## e constantes de jogo. Sem estado — só tipos e funções puras.

enum State { IDLE, COUNTDOWN, ARMED, MEASURING, RESULT, CONFIGURATION }

## Faixas da classificação, na escala de 0 a 999 PONTOS DE POTÊNCIA.
## O limite inferior é inclusivo. A ordem é crescente.
const CLASSES := [
	{"min": 930, "label": "LENDÁRIO", "color": Color("b45cff")},
	{"min": 800, "label": "PESO-PESADO", "color": Color("ff2d55")},
	{"min": 600, "label": "IMPACTO BRUTAL", "color": Color("ff7a1a")},
	{"min": 400, "label": "GOLPE FORTE", "color": Color("ffd23f")},
	{"min": 200, "label": "BOM GOLPE", "color": Color("4beaff")},
	{"min": 0, "label": "GOLPE LEVE", "color": Color("7f8fb3")},
]

const SCORE_MAX := 999
const CREDITOS_MAX := 99
const SERIAL_BAUD := 115200
const JANELA_DO_SOCO := 8.0 ## Segundos para golpear depois do ARM.
const CONTAGEM_DURACAO := 1.9 ## Subida do número no resultado.
const IMPACTO_DURACAO := 0.55 ## Estado MEASURING: flash + onda de choque.
const RESULTADO_TIMEOUT := 12.0
const CARGA_MAX_S := 1.5 ## Carga máxima da simulação pela barra de espaço.

static func classificar(pontos: int) -> Dictionary:
	for c in CLASSES:
		if pontos >= int(c["min"]):
			return c
	return CLASSES[CLASSES.size() - 1]

## Simulação: tempo de carga (s) -> pontos, por interpolação linear entre
## as faixas acordadas. Contínua por construção — não há saltos.
const CARGA_PONTOS := [
	Vector2(0.00, 80.0),
	Vector2(0.08, 200.0),
	Vector2(0.35, 480.0),
	Vector2(0.80, 760.0),
	Vector2(1.20, 920.0),
	Vector2(1.50, 999.0),
]

static func pontos_da_carga(tempo_s: float) -> int:
	var t := clampf(tempo_s, 0.0, CARGA_MAX_S)
	var pts: Array = CARGA_PONTOS
	if t <= (pts[0] as Vector2).x:
		return int(round((pts[0] as Vector2).y))
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		if t <= b.x:
			var f := (t - a.x) / (b.x - a.x)
			return clampi(int(round(lerpf(a.y, b.y, f))), 0, SCORE_MAX)
	return SCORE_MAX
