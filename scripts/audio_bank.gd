class_name AudioBank
extends Node

## Central de sons. Cada som vira um AudioStreamPlayer filho deste nó;
## se o arquivo não existir (projeto recém-clonado antes da importação),
## o player fica mudo em vez de derrubar o jogo.

const SONS := {
	"credit": "res://assets/audio/credit.wav",
	"start": "res://assets/audio/start.wav",
	"count": "res://assets/audio/count.wav",
	"go": "res://assets/audio/go.wav",
	"hit": "res://assets/audio/hit.wav",
	"tick": "res://assets/audio/tick.wav",
	"charge": "res://assets/audio/charge.wav",
	"win": "res://assets/audio/win.wav",
	"medium": "res://assets/audio/medium.wav",
	"lose": "res://assets/audio/lose.wav",
	"error": "res://assets/audio/error.wav",
	"menu": "res://assets/audio/menu.wav",
	"record": "res://assets/audio/record.wav",
	"legendary": "res://assets/audio/legendary.wav",
}

var _players: Dictionary = {}

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

func play(nome: String, volume_db: float = 0.0) -> void:
	var player: AudioStreamPlayer = _players.get(nome)
	if player != null and player.stream != null:
		player.volume_db = volume_db
		player.play()

func stop(nome: String) -> void:
	var player: AudioStreamPlayer = _players.get(nome)
	if player != null:
		player.stop()
