class_name Paleta
extends RefCounted

## A PALETA DA MÁQUINA, NUM LUGAR SÓ.
##
## O jogo é CLARO. Uma máquina de soco fica num salão de festas iluminado,
## no meio de infláveis e mesas de aniversário, e não numa sala escura de
## fliperama: uma tela preta ali parece um monitor desligado, e o preto
## come justamente a cor da marca. O fundo é céu claro, as peças são
## cartões brancos com sombra, e a tinta é escura sobre elas.
##
## POR QUE TUDO PASSA POR AQUI. Antes, cada arquivo carregava as suas
## próprias cores em hexadecimal — trocar o tema significava caçar
## `Color("...")` em seis arquivos e esquecer metade. Agora fundo, saco,
## medidor, moldura e textos leem daqui, então o tema é uma coisa só e
## muda de uma vez.

# ---------------------------------------------------------------- fundo
## Céu do salão: claro em cima, quente perto do chão.
const CEU_TOPO := Color("dbe9fd")
const CEU_BASE := Color("fff1de")
## Piso do palco e as linhas de perspectiva.
const PISO := Color("c9dbf2")
const PISO_LINHA := Color("9ab7dd")
## A luz do refletor, quente, caindo sobre o saco.
const LUZ := Color("fff0cc")
## Creme do miolo do letreiro: o fundo sobre o qual a marca é montada.
const CREME := Color("fff8ec")

# ---------------------------------------------------------------- peças
const CARTAO := Color("ffffff")
const CARTAO_BORDA := Color("bccfea")
## Sombra padrão das peças. Azulada, não cinza: sombra cinza sobre fundo
## azul-claro parece sujeira.
const SOMBRA := Color(0.12, 0.22, 0.42, 0.16)
## Fundo de campos e trilhos vazios.
const VAZIO := Color("e4ecf9")

# ---------------------------------------------------------------- tinta
const TINTA := Color("16233d")        ## títulos e números
const TINTA_FRACA := Color("55688a")  ## rótulos e apoio
const TINTA_LEVE := Color("8a9bb8")   ## legendas discretas

# ---------------------------------------------------------------- marca
## Tiradas da logo da casa: o vermelho do alvo e o azul do dardo.
const VERMELHO := Color("ef3b54")
const CIANO := Color("0f9ed6")
const AMBAR := Color("f2a007")
const VERDE := Color("13a877")
const ROXO := Color("7040e8")
const ROSA := Color("e0338a")
## Azul profundo do bezel do letreiro e das bordas fortes.
const MARINHO := Color("1c3566")

## Cores de festa — confete e fogos. Escurecidas o suficiente para
## aparecerem sobre um fundo claro; branco puro sumiria.
const FESTA := [
	Color("ef3b54"), Color("f2a007"), Color("0f9ed6"),
	Color("7040e8"), Color("13a877"), Color("e0338a"),
]

# ---------------------------------------------------------------- saco
## O saco é VERMELHO VIVO, na cor do alvo da marca. Num salão claro um
## saco escuro vira uma mancha marrom no meio da tela — e é justamente
## ele que o cliente tem de ver do outro lado do corredor.
const SACO_VINIL := Color("e63950")
const SACO_COURO := Color("6b3a48")
const SACO_CONTORNO := Color("53202f")

## Fundo de um cartão colorido: a cor da vez, bem diluída no branco.
static func tinta_clara(cor: Color, forca := 0.12) -> Color:
	return CARTAO.lerp(cor, forca)

## Versão da cor com contraste suficiente para virar TEXTO sobre branco.
## Amarelos e cianos puros somem no branco; este escurecimento resolve
## sem obrigar cada tela a escolher um segundo tom à mão.
static func para_texto(cor: Color) -> Color:
	var luminancia := cor.r * 0.299 + cor.g * 0.587 + cor.b * 0.114
	if luminancia > 0.62:
		return cor.darkened((luminancia - 0.62) * 1.35)
	return cor
