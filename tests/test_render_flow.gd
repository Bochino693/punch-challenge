extends SceneTree

const Stage = preload("res://scripts/presentation/arcade_stage.gd")
var jogo: Control

func _initialize() -> void:
	call_deferred("run")

func quadro() -> void:
	jogo.queue_redraw()
	await process_frame
	await process_frame

func run() -> void:
	jogo = load("res://scenes/main.tscn").instantiate()
	root.add_child(jogo)
	await process_frame
	jogo.set_process(false)
	jogo.central_aberta = false
	jogo.calib_ativo = false
	jogo.transicao = -1.0
	jogo.state = GameDef.State.IDLE
	jogo.intro_active = true
	# Exercita o desenho, não apenas a duração da animação.
	for i in range(61):
		jogo.intro_time = Stage.T_MORPH + float(i) / 60.0 * Stage.MORPH_SECONDS
		await quadro()
	jogo._processar_abertura(0.01)
	await quadro()
	assert(not jogo.letreiro_do_nome._linhas.is_empty())
	for pagina in [1, 2, 0, 2, 1, 0]:
		jogo.state_time = pagina * jogo.ABERTURA_DURACAO + 0.6
		await quadro()
		assert(jogo.letreiro_do_nome._linhas.is_empty() == (pagina != 0))
	jogo.central_aberta = true
	await quadro()
	assert(jogo.letreiro_do_nome._linhas.is_empty())
	jogo.central_aberta = false
	jogo.state = GameDef.State.MEASURING
	jogo.hitstop_left = 0.15
	var antes: float = jogo.animation_time
	jogo._process(0.016)
	assert(jogo.animation_time > antes)
	await quadro()
	assert(jogo.letreiro_do_nome._linhas.is_empty())
	jogo.state = GameDef.State.RESULT
	jogo.ranking.clear()
	for i in range(20):
		jogo.ranking.append({"score": 9999 - i * 200, "photo_path": "", "id": str(i)})
	jogo.posicao_no_ranking = 15
	for i in range(80):
		jogo.verdict_time = 2.5 + float(i) / 15.0
		await quadro()
	jogo.posicao_no_ranking = 0
	for i in range(30):
		jogo.verdict_time = 2.5 + float(i) / 15.0
		await quadro()
	jogo.queue_free()
	await process_frame
	print("RENDER_FLOW_OK")
	quit()
