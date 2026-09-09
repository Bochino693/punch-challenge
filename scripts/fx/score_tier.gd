class_name ScoreTier
extends RefCounted

## OS OITO NÍVEIS DE SOCO, DA ESPIVADA AO 9999.
##
## POR QUE UMA TABELA, E NÃO UMA CONTA. Cada nível é uma personagem: tem
## a sua cor, o seu som e o seu jeito de explodir na tela. Se a festa
## fosse interpolada ("tanta força = tanta faísca"), o 4000 e o 6400
## seriam o mesmo espetáculo em dois tamanhos — e ninguém paga a segunda
## ficha para ver o mesmo filme outra vez. Aqui cada faixa foi escrita à
## mão, e a máquina tem oito respostas, não uma régua.
##
## Os limites são FIXOS e em pontos (0 a `GameDef.SCORE_MAX`): quem regula
## a dificuldade é a curva de velocidade (`ScoreCurve`), não esta tabela.
## Mexer aqui muda a festa, nunca o placar.
##
## Quem usa: o veredito (em `main.gd`) lê `label`, `color` e `sound` para
## a tela e o áudio; o `ImpactDirector` lê o resto para armar os efeitos.
## Sem estado — só a tabela e consultas puras.
##
## Campos de cada nível:
##
##   min, max     faixa de pontos, inclusive nos dois lados
##   label        o nome que o veredito grita
##   color        cor primária do nível
##   secondary    cor de apoio (anéis, rastros, contraste)
##   sound        cue no AudioBank: tier_leve … tier_perfeito
##   shake        força do tremor de tela
##   flash        intensidade do clarão (0 a 1)
##   hit_stop_ms  congelamento do quadro no impacto, em milissegundos
##   zoom         zoom de impacto (fração; 0 = sem zoom)
##   waves        quantas ondas de choque saem do ponto
##   sparks       faíscas no impacto
##   embers       brasas (explosão + chuva)
##   rays         raios girando

const TIERS := [
	{
		# 1) IMPACTO LEVE — o soco de sondagem. A máquina não finge que um
		# golpe fraco foi grande: um pulso pequeno, algumas faíscas brancas
		# e um som seco. É essa honestidade embaixo da escala que faz o
		# 9000 valer alguma coisa.
		"min": 0, "max": 1799,
		"label": "IMPACTO LEVE",
		"color": Color("f6fbff"), "secondary": Color("8a93a6"),
		"sound": "tier_leve",
		"shake": 6.0, "flash": 0.15, "hit_stop_ms": 0, "zoom": 0.0,
		"waves": 1, "sparks": 12, "embers": 0, "rays": 0,
	},
	{
		# 2) BOM GOLPE — a primeira resposta com cor: dois anéis vermelhos
		# e riscos rápidos de faísca, com grave de couro. Diz "foi um
		# soco de verdade", sem prometer o que ainda não veio.
		"min": 1800, "max": 3999,
		"label": "BOM GOLPE",
		"color": Color("ff1934"), "secondary": Color("f6fbff"),
		"sound": "tier_bom",
		"shake": 12.0, "flash": 0.28, "hit_stop_ms": 0, "zoom": 0.0,
		"waves": 2, "sparks": 26, "embers": 10, "rays": 0,
	},
	{
		# 3) GOLPE FORTE — a primeira explosão do jogo: radial, amarela,
		# com brasas caindo depois e tremor médio. Daqui para cima o
		# cliente já vira para trás procurando quem viu.
		"min": 4000, "max": 6499,
		"label": "GOLPE FORTE",
		"color": Color("ffdc27"), "secondary": Color("ff1934"),
		"sound": "tier_forte",
		"shake": 20.0, "flash": 0.42, "hit_stop_ms": 25, "zoom": 0.0,
		"waves": 2, "sparks": 44, "embers": 34, "rays": 4,
	},
	{
		# 4) EXPLOSIVO — clarão branco curto e o ponto do impacto RACHA:
		# estilhaços escuros saltam para fora. A onda é dupla, uma fina e
		# rápida colada numa larga e lenta, e o som desce para o subgrave.
		"min": 6500, "max": 7999,
		"label": "EXPLOSIVO",
		"color": Color("fff9ef"), "secondary": Color("ffdc27"),
		"sound": "tier_explosivo",
		"shake": 27.0, "flash": 0.78, "hit_stop_ms": 40, "zoom": 0.03,
		"waves": 2, "sparks": 60, "embers": 46, "rays": 6,
	},
	{
		# 5) NOCAUTE — o soco que derruba pede hit-stop de verdade
		# (80–110 ms: o quadro congela bem na hora da pancada), zoom de
		# impacto e três frentes de choque em escala, com sirene curta.
		"min": 8000, "max": 8999,
		"label": "NOCAUTE",
		"color": Color("ff1934"), "secondary": Color("ffdc27"),
		"sound": "tier_nocaute",
		"shake": 34.0, "flash": 0.85, "hit_stop_ms": 95, "zoom": 0.06,
		"waves": 3, "sparks": 72, "embers": 52, "rays": 8,
	},
	{
		# 6) PESO-PESADO — o TÚNEL: anéis concêntricos vermelho/ouro nascem
		# grandes e convergem para o ponto do impacto, como se a arena
		# inteira fosse sugada pelo soco. Brasas densas, câmera sacudindo
		# e fanfarra.
		"min": 9000, "max": 9699,
		"label": "PESO-PESADO",
		"color": Color("ffdc27"), "secondary": Color("ff1934"),
		"sound": "tier_pesado",
		"shake": 40.0, "flash": 0.90, "hit_stop_ms": 60, "zoom": 0.08,
		"waves": 4, "sparks": 84, "embers": 90, "rays": 10,
	},
	{
		# 7) LENDÁRIO — o palco inteiro reage: ondas largas cruzam a tela,
		# raios dourados ficam girando em órbita do alvo enquanto o
		# veredito está no ar e a música de vitória assume. É o nível que
		# junta gente na frente do gabinete.
		"min": 9700, "max": 9998,
		"label": "LENDÁRIO",
		"color": Color("ffda27"), "secondary": Color("fff9ef"),
		"sound": "tier_lendario",
		"shake": 44.0, "flash": 1.0, "hit_stop_ms": 70, "zoom": 0.10,
		"waves": 5, "sparks": 100, "embers": 110, "rays": 18,
	},
	{
		# 8) SOCO PERFEITO — só o 9999 exato, a cena mais rara da máquina.
		# Congelamento dramático longo, explosão branca/dourada com tudo
		# que os outros níveis têm, ao mesmo tempo e no máximo, e coro de
		# celebração. Acontece poucas vezes na vida do gabinete; quando
		# acontece, a máquina se desmancha.
		"min": 9999, "max": 9999,
		"label": "SOCO PERFEITO",
		"color": Color("ffffff"), "secondary": Color("ffdc27"),
		"sound": "tier_perfeito",
		"shake": 50.0, "flash": 1.0, "hit_stop_ms": 160, "zoom": 0.12,
		"waves": 6, "sparks": 140, "embers": 140, "rays": 24,
	},
]


## O nível completo de um placar. Pontos fora da escala são presos nos
## extremos: a tabela não conhece número negativo nem acima de 9999.
static func of(score: int) -> Dictionary:
	return TIERS[index_of(score)]


## O ÍNDICE do nível (0 a 7) de um placar. Busca linear de propósito: são
## oito faixas consultadas uma vez por soco — uma estrutura mais esperta
## aqui só esconderia a tabela.
static func index_of(score: int) -> int:
	var pontos := clampi(score, 0, GameDef.SCORE_MAX)
	for i in range(TIERS.size()):
		var nivel: Dictionary = TIERS[i]
		if pontos >= int(nivel["min"]) and pontos <= int(nivel["max"]):
			return i
	# Só se alcança aqui com a tabela furada; cair no último nível é o
	# estrago mais visível, e portanto o mais fácil de flagrar no salão.
	return TIERS.size() - 1


## O nome do nível de um placar ("BOM GOLPE", "NOCAUTE"…).
static func label_of(score: int) -> String:
	return str(of(score)["label"])


## A cor primária do nível de um placar.
static func color_of(score: int) -> Color:
	return of(score)["color"]
