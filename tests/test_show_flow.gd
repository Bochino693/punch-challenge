extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.result_score = 800
	game._entrar_em_resultado()
	assert(game.sons._players["score_loop"].playing)
	game._processar_resultado(2.0)
	assert(not game.sons._players["score_loop"].playing)
	game.verdict_time = 4.2
	game.ranking = RankingStore.migrate([990, 920, 800, 700, 600])
	game.posicao_no_ranking = 3
	game.queue_redraw()
	await process_frame
	game._entrar_em_abertura()
	assert(not game.sons._players["score_loop"].playing)
	assert(game.state == GameDef.State.IDLE)
	game.queue_free()
	await process_frame
	print("SHOW_FLOW_OK")
	quit()
