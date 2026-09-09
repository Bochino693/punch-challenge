class_name GameDef
extends RefCounted

## Definições compartilhadas do Punch Challenge: estados, faixas de golpe
## e constantes de jogo. Sem estado — só tipos e funções puras.

enum State { IDLE, COUNTDOWN, ARMED, MEASURING, RESULT, CONFIGURATION }

## As três faixas continuam existindo só para as ESTATÍSTICAS diárias
## (fraco/médio/forte por dia). Quem decide veredito, cor e efeitos é a
## tabela de oito níveis em scripts/fx/score_tier.gd.
enum Faixa { FRACA, MEDIA, FORTE }

## A escala da máquina: 0 a 9999, sempre exibida com quatro dígitos.
const SCORE_MAX := 9999
const SCORE_DIGITS := 4
const CREDITOS_MAX := 99
const SERIAL_BAUD := 115200
## Debounce dos botões físicos do gabinete (Zero Delay e serial).
const BOTAO_DEBOUNCE_MS := 250
## QUANTO A MÁQUINA ESPERA PELO SOCO.
##
## A espera é longa e o fim dela DEVOLVE o crédito — o limite existe só
## para a máquina não passar a tarde armada se a pessoa foi embora,
## nunca para cobrar.
const ESPERA_DO_SOCO := 90.0
## A partir daqui a tela avisa que vai voltar, com o relógio à mostra.
const AVISO_DE_VOLTA := 15.0
const CONTAGEM_DURACAO := 1.9 ## Subida do número no resultado.
const IMPACTO_DURACAO := 0.55 ## Estado MEASURING: flash + onda de choque.
const RESULTADO_TIMEOUT := 12.0
const CARGA_MAX_S := 2.8 ## Carga da simulação de bancada (barra de espaço).

## Todo número de pontos na tela passa por aqui: quatro dígitos, com
## zeros à esquerda, de 0000 a 9999. Um formato só é o que impede uma
## tela de mostrar "950" onde a outra mostra "0950".
static func fmt_score(pontos: int) -> String:
	return "%04d" % clampi(pontos, 0, SCORE_MAX)

## A barra de espaço e as teclas 1/Enter e 5/C são instrumentos de
## BANCADA. Em produção (gabinete no salão) elas não podem pontuar nem
## operar a máquina: só funcionam com a chave punch/debug_simulation
## ligada nas configurações do projeto, ou com a Central Técnica aberta.
static func debug_simulation() -> bool:
	return bool(ProjectSettings.get_setting("punch/debug_simulation", false))

## Faixa estatística de um placar, derivada da escala fixa dos oito
## níveis (0–1799 e 1800–3999 = fraca; 4000–6499 = média; daí para cima
## = forte). Fixa por construção: as faixas não são mais reguláveis,
## quem se regula é a curva de velocidade.
static func band_of(pontos: int) -> Faixa:
	if pontos >= 6500:
		return Faixa.FORTE
	if pontos >= 1800:
		return Faixa.MEDIA
	return Faixa.FRACA
