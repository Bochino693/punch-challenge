class_name Letreiro
extends Control

## O NOME DO JOGO, NUM NÓ SÓ PARA ELE.
##
## Ele fica separado do desenho geral para poder manter o próprio cache
## de CanvasItem. Fundo e efeitos mudam todo quadro; o nome não precisa
## ser rasterizado novamente enquanto texto, posição e alfa não mudarem.
##
## O material com shader que existia aqui era compilado somente no
## primeiro quadro em que o nome da abertura aparecia. Em TV Box esse
## trabalho acontece na linha de renderização e congela exatamente a
## emenda entre a vinheta e a tela principal. O letreiro usa agora apenas
## as passadas tipográficas abaixo: o visual continua iluminado e não há
## compilação tardia de shader.

var fonte: Font
var _linhas: Array = []
var _inicio_x := 0.0
var _extensao_x := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

## Recebe o que desenhar neste quadro. Cada entrada é
## {texto, y, tamanho, cor}. Chamado pelo desenho da tela: assim o nome
## continua obedecendo à mesma animação de entrada de antes, e este nó
## não precisa saber nada sobre estados do jogo.
func mostrar(linhas: Array, inicio_x: float, extensao_x: float) -> void:
	# A raiz redesenha por causa dos efeitos, mas o nome quase sempre fica
	# idêntico por vários segundos. Não invalide este CanvasItem se nada
	# mudou: numa TV Box isso evita rasterizar quatro passadas de duas
	# linhas grandes em todo quadro da tela de atração.
	if _linhas == linhas and is_equal_approx(_inicio_x, inicio_x) \
			and is_equal_approx(_extensao_x, extensao_x):
		return
	_linhas = linhas
	_inicio_x = inicio_x
	_extensao_x = extensao_x
	queue_redraw()

func esconder() -> void:
	if not _linhas.is_empty():
		_linhas = []
		queue_redraw()

func _draw() -> void:
	if fonte == null or _linhas.is_empty():
		return
	for linha in _linhas:
		var texto: String = linha["texto"]
		var tamanho: int = int(linha["tamanho"])
		var cor: Color = linha["cor"]
		var medida := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
		var pos := Vector2(float(linha["x"]) - medida.x * 0.5, float(linha["y"]))
		# As mesmas três passadas do letreiro de sempre: halo, contorno
		# grosso e a letra. O shader trata as três — e é por isso que ele
		# exige luminância além do alfa, para não acender o contorno.
		draw_string_outline(
			fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho,
			int(tamanho * 0.34), Color(cor, cor.a * 0.28)
		)
		draw_string_outline(
			fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho,
			maxi(6, int(tamanho * 0.17)), Color(Paleta.CONTORNO, cor.a)
		)
		draw_string(
			fonte, pos - Vector2(0.0, tamanho * 0.055), texto,
			HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, Color(cor.lightened(0.42), cor.a)
		)
		draw_string(fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, cor)
