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
