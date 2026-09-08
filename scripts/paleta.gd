class_name Paleta
extends RefCounted

## A PALETA DA MÁQUINA, NUM LUGAR SÓ.
##
## Tema de arena: fundo escuro e peças azul-marinho fazem os números,
## fotografias e LEDs neon saltarem mesmo em um salão iluminado.
##
## POR QUE TUDO PASSA POR AQUI. Antes, cada arquivo carregava as suas
## próprias cores em hexadecimal — trocar o tema significava caçar
## `Color("...")` em seis arquivos e esquecer metade. Agora fundo, saco,
## medidor, moldura e textos leem daqui, então o tema é uma coisa só e
## muda de uma vez.

# ---------------------------------------------------------------- fundo
## Céu do salão: claro em cima, quente perto do chão.
const CEU_TOPO := Color("050816")
const CEU_BASE := Color("111c3f")
## Piso do palco e as linhas de perspectiva.
const PISO := Color("080e22")
const PISO_LINHA := Color("174a70")
## A luz do refletor, quente, caindo sobre o saco.
const LUZ := Color("65eaff")
## Creme do miolo do letreiro: o fundo sobre o qual a marca é montada.
const CREME := Color("f6fbff")

# ---------------------------------------------------------------- peças
const CARTAO := Color("101a36")
const CARTAO_BORDA := Color("285784")
## Sombra padrão das peças. Azulada, não cinza: sombra cinza sobre fundo
## azul-claro parece sujeira.
const SOMBRA := Color(0.0, 0.0, 0.0, 0.52)
## Fundo de campos e trilhos vazios.
const VAZIO := Color("0a1128")

# ---------------------------------------------------------------- tinta
const TINTA := Color("f4f8ff")        ## títulos e números
const TINTA_FRACA := Color("adc1e3")  ## rótulos e apoio
const TINTA_LEVE := Color("7489ad")   ## legendas discretas

# ---------------------------------------------------------------- marca
## Tiradas da logo da casa: o vermelho do alvo e o azul do dardo.
const VERMELHO := Color("ef3b54")
const CIANO := Color("35e6ff")
const AMBAR := Color("ffbc32")
const VERDE := Color("32f2a0")
const ROXO := Color("9965ff")
const ROSA := Color("ff3ca6")
## Azul profundo do bezel do letreiro e das bordas fortes.
const MARINHO := Color("09142f")
## Contorno das letras de fliperama. Quase preto, e não o marinho: o
## contorno grosso só funciona se for MUITO mais escuro que o
## preenchimento — é ele que segura a letra sobre qualquer fundo.
const CONTORNO := Color("11172b")
## O vidro escuro do visor de LED, e o brilho do reflexo em cima dele.
const VISOR_FUNDO := Color("111b30")
const VISOR_VIDRO := Color("3f5480")

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
	if luminancia < 0.55:
		return cor.lightened((0.55 - luminancia) * 0.72)
	return cor
