extends SceneTree

## RETRATOS DAS TELAS — a ferramenta que faltava.
##
## Nenhuma das versões anteriores deste jogo pôde ser OLHADA por quem a
## escreveu: sem uma máquina com tela à mão, toda mudança de interface era
## feita no escuro, e um rótulo centrado na tela em vez de no cartão só
## aparecia quando o gabinete já estava no salão. Foi assim que um defeito
## grosseiro (os dizeres dos dois socos caindo no meio do visor, por cima
## um do outro) sobreviveu a uma entrega inteira.
##
## COMO USAR, num PC com Godot:
##     godot --rendering-driver opengl3 --resolution 1080x1920 \
##           --script tools/retratos.gd
##
## Em Linux sem tela, ponha `xvfb-run -a -s "-screen 0 1080x1920x24"` na
## frente: o renderizador por software do Mesa dá conta, porque o jogo usa
## o renderizador "GL Compatibility".
##
## Os arquivos saem em `user://` — no Windows,
## %APPDATA%\Godot\app_userdata\Punch Challenge.
##
## Isto NÃO é um teste: não afirma que está certo, só mostra o que está
## desenhado. Quem julga é quem olha.
var jogo: Control
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	jogo = load("res://scenes/main.tscn").instantiate()
	root.add_child(jogo)
	await process_frame
	jogo.set_process(false)
	jogo.central_aberta = false
	root.get_viewport().size = Vector2i(1080, 1920)

	# 1) a espera do PRIMEIRO soco
	jogo.socos.clear()
	jogo.state = GameDef.State.ARMED
	jogo.espera_left = GameDef.ESPERA_DO_SOCO
	jogo.animation_time = 3.0
	await _clicar("01_espera_primeiro")

	# 2) O RESULTADO DO PRIMEIRO SOCO, que agora aparece sozinho
	jogo.socos = [{"pontos": 2480, "velocidade": 2.1, "simulado": false}]
	jogo.ultimo_soco_em = 2.7
	jogo.state = GameDef.State.RESULT
	jogo.result_score = 2480
	jogo.result_speed = 2.1
	jogo.displayed_score = 2480.0
	jogo.verdict_time = 1.0
	jogo.posicao_no_ranking = 0
	await _clicar("02_resultado_do_primeiro")

	# 3) e so entao a espera do segundo
	jogo.state = GameDef.State.ARMED
	jogo.verdict_time = -1.0
	jogo.espera_left = GameDef.ESPERA_DO_SOCO
	await _clicar("03_espera_segundo")

	# 3) o resultado com os dois socos
	jogo.socos = [
		{"pontos": 2480, "velocidade": 2.1, "simulado": false},
		{"pontos": 6310, "velocidade": 3.6, "simulado": false},
	]
	jogo.state = GameDef.State.RESULT
	jogo.result_score = 6310
	jogo.result_speed = 3.6
	jogo.displayed_score = 6310.0
	jogo.verdict_time = 1.0
	jogo.posicao_no_ranking = 3
	await _clicar("04_resultado_final")

	quit(0)

func _clicar(nome: String) -> void:
	jogo.queue_redraw()
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % nome)
