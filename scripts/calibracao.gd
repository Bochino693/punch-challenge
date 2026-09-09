class_name Calibracao
extends RefCounted

## A CONTA DO ASSISTENTE DE CALIBRAÇÃO.
##
## Só matemática: recebe as amostras colhidas na Central e devolve os
## parâmetros sugeridos. Fica separada da tela porque é a única parte que
## dá para provar com teste — uma sugestão errada aqui desregula a
## máquina inteira, e descobrir isso com o salão cheio é caro.
##
## POR QUE PERCENTIS E NÃO MÍNIMO E MÁXIMO. Em cinco socos, um escorrega
## no saco e outro pega de raspão: usar o extremo faz a calibração inteira
## depender do pior e do melhor golpe do dia. O percentil descarta o
## acidente sem precisar que alguém decida, na hora, qual amostra jogar
## fora.

## Quantos golpes de cada tipo o assistente pede.
const AMOSTRAS := 5

## Percentis usados. O piso vem da parte de baixo dos golpes fracos; o
## teto, da parte de cima dos fortes.
const PERCENTIL_PISO := 0.20
const PERCENTIL_TETO := 0.80

## Folga aplicada depois dos percentis.
##
## O piso desce um pouco mais: quem bate fraco tem de ver ALGUM ponto,
## senão acha que a máquina não registrou e vai embora achando que
## quebrou. O teto sobe, para 9999 continuar sendo raro — se o teto
## fosse o golpe mais forte já medido, o primeiro cliente forte da noite
## zeraria o desafio.
const FOLGA_PISO := 0.85
const FOLGA_TETO := 1.08

## O valor num percentil de uma lista, por interpolação linear.
static func percentil(valores: Array, p: float) -> float:
	if valores.is_empty():
		return 0.0
	var ordenados := valores.duplicate()
	ordenados.sort()
	if ordenados.size() == 1:
		return float(ordenados[0])
	var pos := clampf(p, 0.0, 1.0) * float(ordenados.size() - 1)
	var i := int(floor(pos))
	var j := mini(i + 1, ordenados.size() - 1)
	return lerpf(float(ordenados[i]), float(ordenados[j]), pos - float(i))

## A SUGESTÃO COMPLETA.
##
## `fracos` e `fortes` são velocidades em m/s; `picos` são as acelerações
## de pico (g) dos golpes aceitos; `ruido` é o maior pico visto com o saco
## PARADO. Devolve os quatro parâmetros e o motivo de cada um, porque
## quem calibra precisa poder discordar com fundamento.
static func sugerir(fracos: Array, fortes: Array, picos: Array, ruido: float) -> Dictionary:
	var piso := percentil(fracos, PERCENTIL_PISO) * FOLGA_PISO
	var teto := percentil(fortes, PERCENTIL_TETO) * FOLGA_TETO

	# O teto tem de ficar acima do piso com folga de verdade. Se os dois
	# grupos saíram parecidos — porque quem calibrou bateu igual nas duas
	# rodadas — a escala inteira colapsaria numa faixa de nada.
	if teto < piso + 3.0:
		teto = piso + 3.0

	# A SENSIBILIDADE FICA ACIMA DO RUÍDO DE REPOUSO, e abaixo do golpe
	# mais fraco que se quer aceitar. Nessa ordem: primeiro não disparar
	# sozinha, depois não perder soco.
	var pico_minimo := percentil(picos, 0.10) * 0.6
	var amin := maxf(ruido * 1.8, 1.0)
	if pico_minimo > amin:
		amin = (amin + pico_minimo) * 0.5

	var cfg := ScoreCurve.sanitize(piso, teto, ScoreCurve.DEFAULT_EXPONENT, ScoreCurve.DEFAULT_DEAD_ZONE)
	return {
		"vmin": cfg["min_speed"],
		"vmax": cfg["max_speed"],
		"amin": clampf(amin, 0.5, 15.0),
		"ruido": ruido,
		"fracos": fracos.size(),
		"fortes": fortes.size(),
		"porque_vmin": "percentil %d dos golpes fracos, com folga de %d%%" % [
			int(PERCENTIL_PISO * 100.0), int((1.0 - FOLGA_PISO) * 100.0)
		],
		"porque_vmax": "percentil %d dos golpes fortes, com folga de %d%%" % [
			int(PERCENTIL_TETO * 100.0), int((FOLGA_TETO - 1.0) * 100.0)
		],
		"porque_amin": "acima do ruído de repouso (%.1f g) e abaixo do golpe mais fraco" % ruido,
	}

## Se há amostras suficientes para uma sugestão honesta.
static func pronta(fracos: Array, fortes: Array) -> bool:
	return fracos.size() >= AMOSTRAS and fortes.size() >= AMOSTRAS
