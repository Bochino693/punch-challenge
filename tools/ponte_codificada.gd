extends SceneTree

## Imprime a linha de comando codificada que o jogo usa quando a politica
## da maquina proibe rodar arquivos .ps1. Existe para o
## tools/conferir_ponte.sh cobrar exatamente os bytes que o Godot produz
## -- e nao uma imitacao feita noutra linguagem, que passaria mesmo se o
## de verdade estivesse errado.
func _initialize() -> void:
	var base := PonteProcessoLink.comando_codificado()
	if base.is_empty():
		printerr("FALHA: nao consegui montar o comando codificado")
		quit(1)
		return
	print(base)
	quit(0)
