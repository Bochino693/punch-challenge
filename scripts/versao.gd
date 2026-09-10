class_name Versao
extends RefCounted

## O CARIMBO DA BUILD.
##
## Este é o número que responde à pergunta "atualizei a máquina e não
## mudou nada?". Ele aparece no rodapé da abertura e na Central Técnica,
## então basta olhar a tela do fliperama para saber qual versão está
## rodando — sem abrir terminal, sem conferir git.
##
## REGRA: sempre que uma mudança visível for para o repositório, suba o
## NUMERO em um e escreva em NOTA o que mudou. Um carimbo que não sobe
## mente, e um carimbo que mente é pior do que carimbo nenhum.

const NUMERO := 42
const DATA := "10/09/2026"
const NOTA := "sem Python obrigatorio e a serial que grita quando falta"

## Rodapé da abertura: cabe em uma linha discreta.
static func curta() -> String:
	return "BUILD %02d  •  %s" % [NUMERO, DATA]

## Central Técnica: aqui há espaço para a nota, que diz ao operador o que
## esperar de diferente nesta versão.
static func longa() -> String:
	return "BUILD %02d  •  %s  •  %s" % [NUMERO, DATA, NOTA]
