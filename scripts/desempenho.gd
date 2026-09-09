class_name Desempenho
extends RefCounted

## O VIGIA DO RITMO — e o que ele faz quando o ritmo cai.
##
## POR QUE ISTO EXISTE. "A animação está travada" é a queixa mais difícil
## de consertar de todas, porque quem programa não vê: aqui a tela roda
## lisa, e o gabinete do cliente tem outro vídeo, outra resolução, outra
## TV. Sem número, o conserto vira palpite — e palpite em desempenho
## costuma otimizar a parte que não custava nada.
##
## Este módulo faz duas coisas, e a segunda depende da primeira:
##
##   1. MEDE. Guarda o tempo dos últimos quadros e responde quantos
##      quadros por segundo a máquina está de fato entregando. É esse
##      número que aparece na Central e é ele que se manda para quem for
##      consertar, em vez de "está travado".
##
##   2. AJUSTA. Se a máquina não está dando conta, o jogo GASTA MENOS —
##      sozinho, sem ninguém configurar nada. Confete, brasa e estilhaço
##      são a parte cara e a parte que ninguém conta: cortar metade das
##      partículas num PC fraco é invisível, e a animação lisa que se
##      ganha com isso é o contrário de invisível.
##
## O ajuste é LENTO de propósito, nos dois sentidos. Um vigia que reage a
## cada quadro faz a quantidade de confete piscar, e piscar chama mais
## atenção do que a queda que ele estava tentando esconder.

## Quantos quadros entram na média. Um terço de segundo a 60 fps: curto
## o bastante para perceber uma queda, longo o bastante para não reagir
## a um soluço isolado do sistema operacional.
const JANELA := 20

## Abaixo disto a máquina está sofrendo; acima, sobra folga.
const ALVO_BAIXO := 50.0
const ALVO_ALTO := 58.0

## Quanto a qualidade anda por segundo, para baixo e para cima. Descer
## mais rápido do que subir é de propósito: alívio tem de chegar logo,
## e a volta pode esperar até ter certeza de que a folga é real.
const QUEDA := 0.9
const SUBIDA := 0.25

## O piso: nem no pior PC o jogo fica sem efeito nenhum. Um fliperama
## sem confete não é um fliperama lento, é um fliperama quebrado.
const PISO := 0.35

var _tempos: Array[float] = []
var _soma := 0.0
## 1.0 = tudo; 0.35 = o mínimo que ainda parece festa.
var qualidade := 1.0

func medir(delta: float) -> void:
	# Quadros absurdos não entram na conta: o primeiro quadro depois de
	# carregar uma cena, ou depois de a janela voltar do minimizado, mede
	# meio segundo e derrubaria a qualidade por um evento que não é o
	# desempenho do jogo.
	if delta <= 0.0 or delta > 0.5:
		return
	_tempos.append(delta)
	_soma += delta
	if _tempos.size() > JANELA:
		_soma -= _tempos[0]
		_tempos.remove_at(0)
	if _tempos.size() < JANELA:
		return
	var fps := float(_tempos.size()) / _soma
	if fps < ALVO_BAIXO:
		qualidade = maxf(PISO, qualidade - QUEDA * delta)
	elif fps > ALVO_ALTO:
		qualidade = minf(1.0, qualidade + SUBIDA * delta)

## Quadros por segundo medidos, ou 0 enquanto não há amostra suficiente.
func fps() -> float:
	if _tempos.is_empty() or _soma <= 0.0:
		return 0.0
	return float(_tempos.size()) / _soma

## Milissegundos do quadro mais lento da janela. É este número que
## denuncia engasgo: a média pode estar em 60 e o pior quadro em 40 ms,
## e é o pior quadro que o olho vê.
func pior_ms() -> float:
	var pior := 0.0
	for t in _tempos:
		pior = maxf(pior, t)
	return pior * 1000.0

## Quantas partículas pedir, dado quantas o efeito gostaria de soltar.
func quantas(cheio: int) -> int:
	return maxi(1, int(round(float(cheio) * qualidade)))
