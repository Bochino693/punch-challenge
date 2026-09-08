class_name AudioBank
extends Node

## Central de sons. Cada som vira um AudioStreamPlayer filho deste nó;
## se o arquivo não existir (projeto recém-clonado antes da importação),
## o player fica mudo em vez de derrubar o jogo.

const Catalog = preload("res://scripts/audio/audio_catalog.gd")
const SONS = Catalog.FALLBACK

var _players: Dictionary = {}
var music_target := -80.0

func _process(delta: float) -> void:
	var player: AudioStreamPlayer = _players.get("music")
	if player != null:
		player.volume_db = move_toward(player.volume_db, music_target, delta * 45.0)
		if music_target <= -79.0 and player.volume_db <= -79.0:
			player.stop()

func music(level: float) -> void:
	music_target = level
	var player: AudioStreamPlayer = _players.get("music")
	if player != null and level > -79.0 and not player.playing:
		player.volume_db = -45.0
		player.play()

func silence() -> void:
	music_target = -80.0
	for player in _players.values():
		player.stop()

func start_score_loop() -> void:
	if not _players.has("score_loop"):
		var player := AudioStreamPlayer.new()
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = 22050
		var pcm := PackedByteArray()
		pcm.resize(44100)
		for i in range(22050):
			var t := float(i) / 22050.0
			var envelope := 0.65 + 0.35 * cos(TAU * 8.0 * t)
			var sample := (sin(TAU * 220.0 * t) + 0.25 * sin(TAU * 440.0 * t)) * envelope * 0.22
			pcm.encode_s16(i * 2, int(sample * 32767.0))
		stream.data = pcm
		player.stream = stream
		add_child(player)
		_players["score_loop"] = player
	play("score_loop", -12.0)

func score_progress(progress: float) -> void:
	var player: AudioStreamPlayer = _players.get("score_loop")
	if player != null:
		player.pitch_scale = lerpf(0.85, 1.8, clampf(progress, 0.0, 1.0))

func _ready() -> void:
	for nome in SONS:
		var player := AudioStreamPlayer.new()
		player.name = "Som_%s" % nome
		var caminho: String = SONS[nome]
		if ResourceLoader.exists(caminho):
			player.stream = load(caminho)
		add_child(player)
		_players[nome] = player
	# WAVs originais; leitura direta também funciona na primeira importação.
	for nome in SONS.keys() + Catalog.EXTRA:
		var path := Catalog.path_for(nome)
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			continue
		var stream: AudioStreamWAV = load(path).duplicate() if ResourceLoader.exists(path) else AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(path))
		if stream == null:
			continue
		if nome in Catalog.LOOPS:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = stream.data.size() / 2
		var player: AudioStreamPlayer = _players.get(nome)
		if player == null:
			player = AudioStreamPlayer.new()
			add_child(player)
			_players[nome] = player
		player.stream = stream

func play(nome: String, volume_db: float = 0.0) -> void:
	var player: AudioStreamPlayer = _players.get(nome)
	if player != null and player.stream != null:
		player.volume_db = volume_db
		player.play()

func stop(nome: String) -> void:
	var player: AudioStreamPlayer = _players.get(nome)
	if player != null:
		player.stop()
