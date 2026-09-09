class_name CameraDoctor
extends Node

## O MÉDICO DA CÂMERA: roda os comandos e MOSTRA a saída na tela.
##
## POR QUE ISTO EXISTE. A Central tinha um botão que abria o PowerShell
## com o instalador. Num gabinete que roda em tela cheia, essa janela
## nasce ATRÁS do jogo: quem aperta não vê nada acontecer e conclui, com
## razão, que o botão não faz nada. E mesmo vendo, a saída morre junto com
## a janela — nem o operador nem quem for consertar depois fica sabendo o
## que aconteceu.
##
## Aqui os comandos rodam de dentro do jogo e cada linha de resposta
## aparece na própria tela da Central. "A câmera não funciona" deixa de
## ser um sintoma e passa a ser um relatório: qual Python respondeu, se o
## OpenCV está instalado, o que o pip disse, e quais índices de câmera
## responderam.
##
## NUMA LINHA DE EXECUÇÃO À PARTE, e não no laço do jogo. `OS.execute`
## BLOQUEIA até o comando terminar, e instalar o OpenCV leva um ou dois
## minutos: no laço principal, a tela congelaria por todo esse tempo — de
## novo o "apertei e não aconteceu nada", agora com o jogo travado junto.

signal terminou

## As linhas do relatório, na ordem em que saíram.
var linhas: Array[String] = []
var rodando := false
## O interpretador que respondeu, e o que sabemos dele.
var python := ""
var python_args: PackedStringArray = PackedStringArray()
var tem_opencv := false
## Índices de câmera que responderam na sondagem.
var indices: Array[int] = []
## O back-end (DSHOW, MSMF, V4L2...) em que a câmera respondeu.
var backend := ""
## O QUE O WINDOWS RESPONDEU sobre a webcam, quando é Windows.
##
## Isto é o que faltava para o diagnóstico ser conclusivo. O OpenCV falha
## igual quando não há câmera, quando a privacidade está fechada e quando
## outro programa está com ela — e enquanto o exame só tinha a resposta
## do OpenCV, o relatório só podia dizer "não respondeu", que manda o
## operador trocar cabo por causa de um interruptor.
var cameras_do_windows := -1
var privacidade := ""
var ocupantes := ""

var _thread: Thread = null
var _mutex := Mutex.new()
var _fila: Array[String] = []
var _fim := false
var _instalar := false
var _caminho_ponte := ""
var _caminho_inspetor := ""

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	# A linha de execução do diagnóstico só empilha texto; quem publica é
	# o laço do jogo. Tocar em `linhas` de dois lugares ao mesmo tempo é
	# como um relatório sai pela metade e o jogo cai junto.
	_mutex.lock()
	var novas := _fila.duplicate()
	_fila.clear()
	var acabou := _fim
	_fim = false
	_mutex.unlock()
	if not novas.is_empty():
		linhas.append_array(novas)
		# O relatório é uma janela dos últimos avisos, não um histórico:
		# a Central tem espaço para doze linhas e mais que isso rolaria
		# para fora da tela sem ninguém ver.
		while linhas.size() > 12:
			linhas.remove_at(0)
	if acabou:
		rodando = false
		if _thread != null:
			_thread.wait_to_finish()
			_thread = null
		terminou.emit()

func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

## Começa o exame.
##
## Com `resolver`, o médico não só examina: instala o OpenCV se faltar e
## destrava a privacidade da câmera no Windows. Sem ele, apenas relata —
## que é o que se quer quando a máquina está no salão e ninguém autorizou
## mexer em nada.
func diagnosticar(resolver: bool, caminho_ponte: String, caminho_inspetor := "") -> void:
	if rodando:
		return
	rodando = true
	linhas.clear()
	indices.clear()
	backend = ""
	cameras_do_windows = -1
	privacidade = ""
	ocupantes = ""
	_instalar = resolver
	_caminho_ponte = caminho_ponte
	_caminho_inspetor = caminho_inspetor
	_thread = Thread.new()
	_thread.start(_trabalhar)

func _dizer(texto: String) -> void:
	_mutex.lock()
	_fila.append(texto)
	_mutex.unlock()

func _trabalhar() -> void:
	_dizer("Procurando o Python...")
	if not _achar_python():
		_dizer("PYTHON NÃO ENCONTRADO NESTE COMPUTADOR.")
		_dizer("Instale em python.org e marque 'Add python.exe to PATH'.")
		_terminar()
		return
	_dizer("Python: %s" % python)

	_dizer("Conferindo o OpenCV...")
	tem_opencv = _rodar(python, _com_args(["-c", "import cv2"])) == 0
	if tem_opencv:
		_dizer("OpenCV: instalado.")
	elif not _instalar:
		_dizer("OPENCV AUSENTE. Use o botão INSTALAR OPENCV.")
		_terminar()
		return
	else:
		_dizer("OpenCV ausente. Instalando — isto leva 1 a 2 minutos...")
		var saida: Array = []
		var codigo := OS.execute(python, _com_args(["-m", "pip", "install", "--user", "opencv-python"]), saida, true)
		# Só as últimas linhas do pip: a saída inteira tem dezenas de
		# linhas de download e nenhuma delas ajuda quem está olhando.
		for linha in _ultimas_linhas(saida, 3):
			_dizer(str(linha))
		if codigo != 0:
			_dizer("FALHA AO INSTALAR. Confira a conexão com a internet.")
			_terminar()
			return
		tem_opencv = _rodar(python, _com_args(["-c", "import cv2"])) == 0
		_dizer("OpenCV instalado." if tem_opencv else "Instalou, mas o import ainda falha.")
		if not tem_opencv:
			_terminar()
			return

	# PERGUNTA AO WINDOWS ANTES DE PERGUNTAR AO OPENCV.
	#
	# A ordem importa: se a privacidade estiver fechada, sondar câmeras
	# primeiro só produz dez falhas idênticas e um relatório que culpa o
	# cabo. Com a resposta do Windows na mão, a sondagem que vem depois
	# já pode ser interpretada.
	_perguntar_ao_windows()

	if _caminho_ponte.is_empty():
		_dizer("Ponte de câmera não encontrada no pacote.")
		_terminar()
		return
	_dizer("Procurando câmeras...")
	var sonda: Array = []
	OS.execute(python, _com_args([_caminho_ponte, "--probe"]), sonda, true)
	var achou := false
	for bruta in _linhas_de(sonda):
		var linha := str(bruta).strip_edges()
		if linha.is_empty():
			continue
		# A ponte imprime `INDICE=n` e `BACKEND=nome` para cada câmera que
		# respondeu. São essas linhas que o jogo lê — as outras, com
		# acento e travessão, são para a pessoa, e mudam quando alguém
		# melhora o texto.
		if linha.begins_with("INDICE="):
			var n := linha.substr(7).strip_edges()
			if n.is_valid_int():
				indices.append(n.to_int())
				achou = true
			continue
		if linha.begins_with("BACKEND="):
			if backend.is_empty():
				backend = linha.substr(8).strip_edges()
			continue
		_dizer(linha)
	if achou:
		_dizer("CÂMERA %d PRONTA%s." % [indices[0], "" if backend.is_empty() else " (%s)" % backend])
	else:
		_dizer(_veredito())
	_terminar()

## O VEREDITO: uma frase que diz de quem é a culpa.
##
## Antes o relatório terminava sempre igual — "nenhuma câmera respondeu,
## feche o Teams" — desse mesmo jeito quando a webcam nem estava
## conectada. Uma resposta que serve para tudo não serve para nada: o
## operador tenta a única coisa que a tela sugere, não resolve, e conclui
## que o botão não funciona. Agora a frase muda com o que se descobriu.
func _veredito() -> String:
	if cameras_do_windows == 0:
		return "O WINDOWS TAMBÉM NÃO VÊ A CÂMERA: é cabo, porta USB ou driver."
	if privacidade == "Deny":
		return "PRIVACIDADE BLOQUEADA no Windows. Use RESOLVER TUDO."
	if cameras_do_windows > 0:
		if not ocupantes.is_empty() and ocupantes != "nenhum":
			return "A CÂMERA ESTÁ COM OUTRO PROGRAMA: feche %s." % ocupantes
		return "O WINDOWS VÊ A CÂMERA E O OPENCV NÃO ABRE: feche quem a usa e repita."
	return "NENHUMA CÂMERA RESPONDEU. Feche Teams, Meet, OBS e o app Câmera."

## Roda o inspetor de PowerShell e guarda o que ele contou.
##
## No Linux e no macOS não há inspetor, e não há nada a perder: o resto
## do exame continua igual, só sem a metade que só o Windows sabe
## responder.
func _perguntar_ao_windows() -> void:
	if _caminho_inspetor.is_empty():
		return
	_dizer("Perguntando ao Windows...")
	var acao := "liberar" if _instalar else "listar"
	var saida: Array = []
	var codigo := OS.execute("powershell", PackedStringArray([
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", _caminho_inspetor, "-Acao", acao,
	]), saida, true)
	if codigo != 0:
		_dizer("O PowerShell não respondeu (código %d)." % codigo)
		return
	var nomes: Array[String] = []
	for bruta in _linhas_de(saida):
		var linha := str(bruta).strip_edges()
		if linha.begins_with("DISPOSITIVO="):
			nomes.append(linha.substr(12))
		elif linha.begins_with("WINDOWS_CAMERAS="):
			var n := linha.substr(16).strip_edges()
			if n.is_valid_int():
				cameras_do_windows = n.to_int()
		elif linha.begins_with("PRIVACIDADE_PROGRAMAS="):
			privacidade = linha.substr(22).strip_edges()
		elif linha.begins_with("OCUPANTES="):
			ocupantes = linha.substr(10).strip_edges()
		elif linha.begins_with("LIBEROU="):
			_dizer("Privacidade liberada: %s" % linha.substr(8))
		elif linha.begins_with("FALHOU="):
			_dizer("Não consegui liberar: %s" % linha.substr(7))
	# Dos nomes, só os dois primeiros: numa máquina com câmera virtual
	# instalada a lista tem seis entradas e come o relatório inteiro.
	for nome in nomes.slice(0, 2):
		_dizer("Windows vê: %s" % nome)
	if cameras_do_windows >= 0:
		_dizer("Câmeras no Windows: %d  •  privacidade: %s" % [
			cameras_do_windows, privacidade if not privacidade.is_empty() else "?"
		])
	if not ocupantes.is_empty() and ocupantes != "nenhum":
		_dizer("Programas que podem estar com ela: %s" % ocupantes)

func _terminar() -> void:
	_mutex.lock()
	_fim = true
	_mutex.unlock()

## Testa os três nomes de interpretador. A versão é conferida RODANDO o
## programa, e não pelo caminho: o Windows tem um atalho `python` da
## Microsoft Store que existe, responde e não é Python nenhum.
func _achar_python() -> bool:
	for tentativa in [["py", ["-3"]], ["python", []], ["python3", []]]:
		var exe: String = tentativa[0]
		var base: Array = tentativa[1]
		var saida: Array = []
		var args := PackedStringArray()
		for a in base:
			args.append(str(a))
		args.append("--version")
		if OS.execute(exe, args, saida, true) != 0:
			continue
		var texto := "\n".join(PackedStringArray(_linhas_de(saida)))
		if "Python 3" not in texto:
			continue
		python = exe
		python_args = PackedStringArray()
		for a in base:
			python_args.append(str(a))
		return true
	return false

func _com_args(extras: Array) -> PackedStringArray:
	var args := python_args.duplicate()
	for e in extras:
		args.append(str(e))
	return args

func _rodar(exe: String, args: PackedStringArray) -> int:
	var saida: Array = []
	return OS.execute(exe, args, saida, true)

## Prefixos de linha que são conversa interna de biblioteca, e não
## resposta para quem está lendo. O OpenCV cospe três ou quatro delas por
## índice que não abre; na tela de doze linhas da Central, elas empurram
## para fora justamente o que interessa.
const RUIDO := ["[ WARN", "[ERROR", "[INFO", "global cap", "VIDEOIO", "WARNING:"]

func _linhas_de(saida: Array) -> Array:
	var fora: Array = []
	for bloco in saida:
		for linha in str(bloco).split("\n"):
			var limpa := str(linha).strip_edges()
			if limpa.is_empty():
				continue
			var ruidosa := false
			for prefixo in RUIDO:
				if limpa.begins_with(prefixo) or prefixo in limpa:
					ruidosa = true
					break
			if not ruidosa:
				fora.append(limpa)
	return fora

func _ultimas_linhas(saida: Array, quantas: int) -> Array:
	var todas := _linhas_de(saida)
	if todas.size() <= quantas:
		return todas
	return todas.slice(todas.size() - quantas)
