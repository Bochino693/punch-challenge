extends SceneTree

## Carrega o jogo e roda 300 quadros de verdade, contando erro de script.
## Um jogo que abre e quebra no quadro 200 abre igual a um que funciona.
var jogo: Control
var quadro := 0

func _initialize() -> void:
	jogo = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(jogo)

func _process(_d: float) -> bool:
	quadro += 1
	# Passa por todos os estados no caminho, e não só pela abertura.
	match quadro:
		30: jogo.credits = 9; jogo.game_mode = "credit"
		60: jogo._pressionou_start()
		330: jogo._registrar_impacto(9999, 16.5, true)
		420: jogo.central_aberta = true
		450: jogo.central_pagina = 1
		470: jogo._abrir_calibracao()
		490: jogo.central_pagina = 2
		510: jogo.central_pagina = 3
		530: jogo.central_aberta = false; jogo._fechar_calibracao()
	if quadro >= 600:
		print("CARGA_300_OK quadros=%d" % quadro)
		quit(0)
	return false
