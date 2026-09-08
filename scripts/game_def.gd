class_name GameDef
extends RefCounted

## Definições compartilhadas do Punch Challenge: estados, faixas de golpe
## e constantes de jogo. Sem estado — só tipos e funções puras.

enum State { IDLE, COUNTDOWN, ARMED, MEASURING, RESULT, CONFIGURATION }

## AS TRÊS FAIXAS. É por elas que a máquina decide entre festa, aceno e
## derrota, e é isso que faz (ou não faz) o cliente jogar de novo. Os
## dois limites que as separam são regulados na Central Técnica, porque
## a mecânica de cada máquina responde diferente: uma faixa errada faz
## todo mundo tirar nocaute, que é o jeito mais rápido de esvaziar a fila.
enum Faixa { FRACA, MEDIA, FORTE }

const SCORE_MAX := 999
const CREDITOS_MAX := 99
const SERIAL_BAUD := 115200
const JANELA_DO_SOCO := 8.0 ## Segundos para golpear depois do ARM.
const CONTAGEM_DURACAO := 1.9 ## Subida do número no resultado.
const IMPACTO_DURACAO := 0.55 ## Estado MEASURING: flash + onda de choque.
const RESULTADO_TIMEOUT := 12.0
const CARGA_MAX_S := 1.5 ## Carga máxima da simulação pela barra de espaço.

## Limites de fábrica das faixas, na escala de 0 a 999.
const LIMIAR_FRACO_PADRAO := 330
const LIMIAR_FORTE_PADRAO := 700
## Espaço mínimo entre os dois limites, para nunca existir faixa média
## de largura zero (que deixaria a regulagem sem efeito visível).
const LIMIAR_FOLGA := 60

## Cor de cada faixa, usada pela moldura de LEDs, pelo medidor e pelo
## veredito ao mesmo tempo — a tela inteira fala a mesma cor.
const COR_FRACA := Color("7c88a8")
const COR_MEDIA := Color("ffd23f")
const COR_FORTE := Color("ff2d55")

## Dentro de cada faixa o rótulo ainda sobe de degrau: dois socos fortes
## diferentes não podem ler igual, senão o placar perde a graça. `ate` é
## a posição relativa DENTRO da faixa (0 no piso, 1 no teto).
const DEGRAUS := {
	Faixa.FRACA: [
		{"ate": 0.5, "label": "FRACO!", "color": Color("7c88a8")},
		{"ate": 1.1, "label": "GOLPE LEVE", "color": Color("8fa8c8")},
	],
	Faixa.MEDIA: [
		{"ate": 0.5, "label": "BOM GOLPE", "color": Color("4beaff")},
		{"ate": 1.1, "label": "GOLPE FORTE", "color": Color("ffd23f")},
	],
	Faixa.FORTE: [
		{"ate": 0.40, "label": "NOCAUTE!", "color": Color("ff7a1a")},
		{"ate": 0.80, "label": "PESO-PESADO", "color": Color("ff2d55")},
		{"ate": 1.1, "label": "LENDÁRIO", "color": Color("b45cff")},
	],
}

## Devolve os dois limites já saneados: dentro da escala, na ordem certa
## e com folga entre eles. Quem chama nunca precisa validar de novo.
static func limiares(fraco: int, forte: int) -> Vector2i:
	var a := clampi(fraco, 20, SCORE_MAX - LIMIAR_FOLGA - 20)
	var b := clampi(forte, a + LIMIAR_FOLGA, SCORE_MAX - 20)
	return Vector2i(a, b)

static func faixa_de(pontos: int, fraco: int, forte: int) -> Faixa:
	var lim := limiares(fraco, forte)
	if pontos >= lim.y:
		return Faixa.FORTE
	if pontos >= lim.x:
		return Faixa.MEDIA
	return Faixa.FRACA

## Cor da faixa — a mesma que tinge moldura, medidor e fundo.
static func cor_da_faixa(faixa: Faixa) -> Color:
	match faixa:
		Faixa.FORTE:
			return COR_FORTE
		Faixa.MEDIA:
			return COR_MEDIA
	return COR_FRACA

## O veredito completo de um golpe: faixa, rótulo e cor do rótulo.
static func classificar(pontos: int, fraco: int, forte: int) -> Dictionary:
	var lim := limiares(fraco, forte)
	var faixa := faixa_de(pontos, lim.x, lim.y)
	var piso := 0
	var teto := lim.x
	match faixa:
		Faixa.MEDIA:
			piso = lim.x
			teto = lim.y
		Faixa.FORTE:
			piso = lim.y
			teto = SCORE_MAX + 1
	var t := clampf(float(pontos - piso) / maxf(1.0, float(teto - piso)), 0.0, 1.0)
	var degraus: Array = DEGRAUS[faixa]
	var escolhido: Dictionary = degraus[degraus.size() - 1]
	for d in degraus:
		if t < float(d["ate"]):
			escolhido = d
			break
	return {
		"faixa": faixa,
		"label": str(escolhido["label"]),
		"color": escolhido["color"] as Color,
		"cor_faixa": cor_da_faixa(faixa),
	}

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
