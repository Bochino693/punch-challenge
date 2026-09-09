extends RefCounted
## Catálogo único dos arquivos sonoros. AudioBank cuida da reprodução.
const FALLBACK := {
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
## Sons que existem só como arquivo em `assets/audio/arcade/` e não têm
## um par no FALLBACK. Os oito níveis entram aqui: eles nasceram já na
## mesa nova e nunca tiveram versão antiga.
const EXTRA := [
	"music", "shutter", "ranking", "score_loop",
	"nivel_leve", "nivel_bom", "nivel_forte", "nivel_explosivo",
	"nivel_nocaute", "nivel_peso", "nivel_lendario", "nivel_perfeito",
	"start_negado", "armado", "couro", "subgrave",
]
const LOOPS := ["music", "charge", "score_loop"]
const ROOT := "res://assets/audio/arcade/"

static func path_for(cue: String) -> String:
	return ROOT + cue + ".wav"
