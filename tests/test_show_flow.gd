extends SceneTree

class FakeCamera extends CameraService:
	var shots := 0
	func _ready() -> void:
		pass
	func capture_photo() -> String:
		shots += 1
		return ""

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	assert(game.intro_active)
	game._processar_abertura(0.9)
	assert(game.intro_hit_played)
	game._processar_abertura(3.5)
	assert(not game.intro_active)
	assert(game.state == GameDef.State.IDLE)
	for sound in ["music", "charge", "score_loop"]:
		assert(game.sons._players[sound].stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	assert(game.sons._players["hit"].stream.mix_rate == 48000)
	game.sons.music(-19.0)
	assert(game.sons._players["music"].playing)
	game.camera_service.queue_free()
	var camera := FakeCamera.new()
	game.add_child(camera)
	game.camera_service = camera
	game.state = GameDef.State.COUNTDOWN
	game.countdown_left = 3.0
	game.pose_finished = false
	game._processar_contagem(2.0)
	assert(camera.shots == 0)
	game._processar_contagem(1.0)
	assert(camera.shots == 1)
	assert(game.state == GameDef.State.COUNTDOWN)
	game._processar_contagem(1.3)
	assert(game.state == GameDef.State.ARMED)
	assert(camera.shots == 1)
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
	for player in game.sons._players.values():
		assert(not player.playing)
	game.queue_free()
	await process_frame
	print("SHOW_FLOW_OK")
	quit()
