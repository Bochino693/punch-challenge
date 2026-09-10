class_name PonteProcessoLink
extends SerialLink

## PORTA COM SEM EXTENSAO NATIVA -- o plano B que funciona em PC cru.
##
## O Godot nao abre uma porta COM sozinho. Ate aqui quem fazia isso era a
## extensao nativa `gdserial` (um .dll ao lado do executavel). Quando ela
## nao carrega -- e no gabinete do operador ela NAO CARREGOU -- a maquina
## inteira morre junto: START morto, CREDITO morto, sensor mudo, fitas
## apagadas, e na tela so "SIMULACAO".
##
## Este backend nao depende de binario nenhum que possa faltar. Ele sobe
## um ajudante feito do que o sistema JA TEM -- PowerShell no Windows,
## `stty` + `cat` no Linux e no Mac -- e conversa com ele por linhas de
## texto pelos canos padrao (OS.execute_with_pipe). Nao ha .dll para o
## antivirus apagar, nao ha Python para instalar, nao ha arquitetura
## errada. Se o PC liga, isto funciona.
##
## O protocolo esta descrito em tools/ponte_serial.ps1. Em resumo:
##   jogo -> ponte : @LISTAR / @ABRIR,COM5,115200 / @FECHAR / @SAIR
##                   e qualquer outra linha vai crua para o Arduino
##   ponte -> jogo : #PONTE,V1 / #PORTAS,... / #ABERTA,... / #FECHADA,...
##                   #FALHA,... / #ERRO,... e o resto veio cru da placa

const CAMINHO_WINDOWS := "res://tools/ponte_serial.ps1"
const CAMINHO_UNIX := "res://tools/ponte_serial.sh"

## LER DE UM CANO BLOQUEIA -- POR ISSO A LEITURA MORA NUMA THREAD.
##
## `FileAccess.get_line()` num cano fica parado ate a linha chegar. Feito
## no laco do jogo, isso e a maquina congelada esperando um Arduino que
## talvez nem esteja ligado. A thread abaixo e a unica que le; ela empilha
## as linhas, e `poll()` -- chamado no laco normal do jogo -- so recolhe o
## que ja chegou. O jogo nunca espera.
var _thread: Thread = null
var _tranca := Mutex.new()
var _recebidas: Array[String] = []
var _parar := false

var _cano: FileAccess = null
var _pid := -1
var _apresentou := false
var _portas: PackedStringArray = PackedStringArray()
var _porta := ""
var _abrindo := ""
var _ultima_abertura_ms := -100000
var _proxima_subida_ms := 0
var _falha := ""
var _sistema := ""
var _codificado := false
var _prazo_da_apresentacao_ms := 0

const ESPERA_ENTRE_ABERTURAS_MS := 700
const ESPERA_ENTRE_SUBIDAS_MS := 4000
const ESPERA_DA_APRESENTACAO_MS := 6000

func _init() -> void:
	_sistema = OS.get_name()
	_subir()

# ----------------------------------------------------------------------
#  SUBIR E DERRUBAR O AJUDANTE
# ----------------------------------------------------------------------

## O script viaja DENTRO do executavel (res://), e de la nenhum programa
## do sistema consegue le-lo: `res://` nao e uma pasta de verdade depois
## de exportado, e um indice dentro do .pck. Por isso ele e copiado para
## `user://` a cada partida -- barato (poucos KB) e garante que uma
## correcao no script chegue junto com a atualizacao do jogo.
static func _desembrulhar(origem: String, nome: String) -> String:
	# NO EDITOR, `res://` E UMA PASTA DE VERDADE -- e vale usar o arquivo
	# de la, sem copia. Nao e economia: e que um `powershell.exe -File`
	# apontando para dentro do AppData e um dos desenhos que antivirus
	# olham com desconfianca, e quanto menos vezes a maquina precisar
	# fazer isso, melhor.
	var no_disco := ProjectSettings.globalize_path(origem)
	if not no_disco.begins_with("res://") and FileAccess.file_exists(no_disco):
		return no_disco
	var entrada := FileAccess.open(origem, FileAccess.READ)
	if entrada == null:
		return ""
	var dados := entrada.get_buffer(entrada.get_length())
	entrada.close()
	if dados.is_empty():
		return ""
	var destino := "user://%s" % nome
	var saida := FileAccess.open(destino, FileAccess.WRITE)
	if saida == null:
		return ""
	saida.store_buffer(dados)
	saida.close()
	return ProjectSettings.globalize_path(destino)

## COMO OS TESTES ENTRAM AQUI.
##
## O caminho de verdade precisa de uma porta COM e de uma placa espetada
## — coisas que nenhuma máquina de teste tem. Sem um jeito de trocar o
## ajudante por um de mentira, esta classe inteira só seria exercitada na
## bancada do operador, que é exatamente onde não se pode descobrir um
## defeito. Com isto, o teste sobe um ajudante que fala o mesmo protocolo
## e o percurso completo — processo, thread, cano, protocolo — roda de
## verdade.
## A forma e [argumentos, candidatos_a_programa] -- a mesma que
## `_programa_e_argumentos` devolve.
static var receita_de_teste: Array = []

func _programa_e_argumentos() -> Array:
	if not receita_de_teste.is_empty():
		return receita_de_teste
	if _sistema == "Windows":
		if _codificado:
			return _receita_codificada()
		var script := _desembrulhar(CAMINHO_WINDOWS, "ponte_serial.ps1")
		if script.is_empty():
			return []
		# `-NoProfile` porque o perfil do usuario pode imprimir coisas na
		# saida e sujar a primeira linha. `-ExecutionPolicy Bypass` porque
		# a politica padrao do Windows recusa rodar arquivos .ps1 -- e
		# recusaria justamente no PC cru onde esta ponte mais importa.
		var bandeiras := [
			"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
			"-WindowStyle", "Hidden", "-File", script,
		]
		# O NOME SOZINHO NEM SEMPRE ACHA O POWERSHELL.
		#
		# Numa instalacao arrumada `powershell.exe` esta no PATH e acaba
		# aqui. Mas PC de gabinete e PC remendado: PATH mexido por
		# instalador, perfil de usuario limitado, imagem enxugada. Como o
		# preco de errar e a maquina inteira muda, a lista tem o caminho
		# absoluto do Windows e ainda o PowerShell 7, que algumas maquinas
		# tem no lugar do antigo.
		return [bandeiras, [
			"powershell.exe",
			"C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
			"pwsh.exe",
		]]
	var script_unix := _desembrulhar(CAMINHO_UNIX, "ponte_serial.sh")
	if script_unix.is_empty():
		return []
	return [[script_unix], ["/bin/sh"]]

## QUANDO A POLITICA DA MAQUINA PROIBE ARQUIVOS .ps1.
##
## `-ExecutionPolicy Bypass` resolve o padrao do Windows, que ja recusa
## rodar arquivos .ps1. O que ele NAO vence e uma politica imposta pela
## rede da empresa ou por regra de grupo: ali, arquivo .ps1 nao roda de
## jeito nenhum, e a ponte morreria antes de dizer a primeira palavra.
##
## `-EncodedCommand` nao passa por arquivo -- e um comando, e comando nao
## e alcancado pela politica. Vira o plano B automatico: se a ponte nao se
## apresentar em poucos segundos, o jogo tenta de novo por este caminho.
##
## O texto vai em UTF-16 (que e o que o PowerShell espera) e depois em
## base64. O script e ASCII puro, entao o resultado cabe folgado no limite
## de tamanho da linha de comando do Windows.
## O ENVELOPE QUE CARREGA O SCRIPT DENTRO DE UM COMANDO.
##
## O script inteiro nao cabe: o Windows para a linha de comando em 32767
## caracteres, e o texto vira UTF-16 (dobra) e depois base64 (mais um
## terco) -- passaria de 33 mil so com o que ja esta escrito. Comprimido
## antes, ele cai para menos da metade disso com folga de sobra.
##
## O Godot comprime em gzip e o PowerShell descomprime com a GZipStream
## que existe nele desde sempre. Nada para instalar dos dois lados.
##
## `[scriptblock]::Create` e nao `Invoke-Expression` porque o script comeca
## com um bloco `param(...)`, que so e valido no inicio de um bloco de
## codigo de verdade.
static func comando_codificado() -> String:
	var entrada := FileAccess.open(CAMINHO_WINDOWS, FileAccess.READ)
	if entrada == null:
		return ""
	var texto := entrada.get_as_text()
	entrada.close()
	if texto.is_empty():
		return ""
	var apertado := texto.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	var carga := Marshalls.raw_to_base64(apertado)
	var envelope := "\n".join([
		"$b=[Convert]::FromBase64String('%s')" % carga,
		"$m=New-Object IO.MemoryStream(,$b)",
		"$g=New-Object IO.Compression.GZipStream($m,[IO.Compression.CompressionMode]::Decompress)",
		"$r=New-Object IO.StreamReader($g,[Text.Encoding]::UTF8)",
		"& ([scriptblock]::Create($r.ReadToEnd()))",
	])
	return Marshalls.raw_to_base64(envelope.to_utf16_buffer())

func _receita_codificada() -> Array:
	var base := comando_codificado()
	if base.is_empty():
		return []
	return [[
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden", "-EncodedCommand", base,
	], [
		"powershell.exe",
		"C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
		"pwsh.exe",
	]]

func _subir() -> void:
	_falha = ""
	var receita := _programa_e_argumentos()
	if receita.is_empty():
		_falha = "script da ponte nao veio na instalacao"
		return
	var argumentos := PackedStringArray()
	for pedaco in receita[0]:
		argumentos.append(str(pedaco))
	var canos := {}
	var ultimo := ""
	for candidato in receita[1]:
		ultimo = str(candidato)
		canos = OS.execute_with_pipe(ultimo, argumentos)
		if not canos.is_empty() and canos.has("stdio"):
			break
		canos = {}
	if canos.is_empty():
		_falha = "o sistema recusou abrir %s" % ultimo
		return
	_cano = canos["stdio"]
	_pid = int(canos.get("pid", -1))
	_prazo_da_apresentacao_ms = Time.get_ticks_msec() + ESPERA_DA_APRESENTACAO_MS
	_parar = false
	_thread = Thread.new()
	_thread.start(_laco_leitor)

func _laco_leitor() -> void:
	while not _parar:
		var cano := _cano
		if cano == null:
			break
		var linha := cano.get_line()
		if linha.is_empty() and cano.eof_reached():
			break
		linha = linha.strip_edges()
		if linha.is_empty():
			continue
		_tranca.lock()
		_recebidas.append(linha)
		_tranca.unlock()
	_tranca.lock()
	_recebidas.append("#MORREU")
	_tranca.unlock()

func _derrubar() -> void:
	_parar = true
	if _pid > 0:
		# Mata ANTES de esperar a thread. A ordem importa: a thread esta
		# parada dentro de `get_line()`, e o que a acorda e o cano fechando
		# quando o processo morre. Esperar primeiro e travar para sempre.
		OS.kill(_pid)
		_pid = -1
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_cano = null
	_apresentou = false
	_porta = ""
	_abrindo = ""

## FECHAR NA MAO, E NAO NO DESTRUIDOR.
##
## A tentacao era derrubar o ajudante em `_notification(PREDELETE)`. Nao
## funciona: quando o aviso chega, o objeto ja esta meio desmontado e a
## chamada morre em "null instance" -- justamente na saida do jogo, que e
## quando ela precisaria funcionar.
##
## E nao faz falta. O ajudante le a entrada padrao num laco; quando o jogo
## termina, o cano fecha, a leitura devolve fim-de-arquivo e ele sai
## sozinho. `_exit_tree()` do jogo chama isto para a saida ser limpa e
## imediata; se algo escapar, o sistema operacional resolve.
func encerrar() -> void:
	_derrubar()

# ----------------------------------------------------------------------
#  A API QUE O JOGO USA
# ----------------------------------------------------------------------

func available() -> bool:
	return _cano != null

## Frase curta para a Central Tecnica dizer POR QUE nao ha Arduino.
func motivo_da_falta() -> String:
	return _falha

func descricao() -> String:
	if _sistema == "Windows":
		return "ponte PowerShell"
	return "ponte de sistema"

func list_ports() -> PackedStringArray:
	return _portas

func open_port(port: String, baud: int = GameDef.SERIAL_BAUD) -> bool:
	if _cano == null or port.is_empty():
		return false
	# TENTAR SEM PARAR E PIOR DO QUE NAO TENTAR.
	#
	# Quando a porta recusa na hora (nao existe, ou outro programa esta
	# com ela), o jogo pede a proxima no mesmo quadro -- e sem esta pausa
	# ele varreria a lista inteira sessenta vezes por segundo, enchendo o
	# cano de comandos e sem dar tempo de placa nenhuma responder.
	var agora := Time.get_ticks_msec()
	if agora - _ultima_abertura_ms < ESPERA_ENTRE_ABERTURAS_MS:
		return false
	_ultima_abertura_ms = agora
	_abrindo = port
	_porta = ""
	_escrever("@ABRIR,%s,%d" % [port, baud])
	# Diz que sim ANTES da confirmacao: quem espera a placa se apresentar
	# e o jogo, que ja tem tres segundos de paciencia para isso. Se a
	# abertura falhar de verdade, `#FALHA` chega e derruba.
	return true

func close_port() -> void:
	if _cano == null:
		return
	var fechada := _porta if not _porta.is_empty() else _abrindo
	_escrever("@FECHAR")
	_porta = ""
	_abrindo = ""
	if not fechada.is_empty():
		closed.emit(fechada)

func is_open() -> bool:
	return not _porta.is_empty() or not _abrindo.is_empty()

func send_line(line: String) -> bool:
	if not is_open():
		return false
	return _escrever(line)

func _escrever(linha: String) -> bool:
	if _cano == null:
		return false
	_tranca.lock()
	_cano.store_line(linha)
	_cano.flush()
	_tranca.unlock()
	return true

func poll() -> void:
	if _cano == null:
		# O ajudante caiu. Sobe de novo, com pausa, para o caso de o
		# defeito ser permanente (PowerShell bloqueado por politica, por
		# exemplo): insistir sem pausa vira um processo novo por quadro.
		var agora := Time.get_ticks_msec()
		if agora >= _proxima_subida_ms:
			_proxima_subida_ms = agora + ESPERA_ENTRE_SUBIDAS_MS
			_subir()
		return
	# UM AJUDANTE QUE SOBE E NAO FALA E PIOR DO QUE UM QUE NAO SOBE.
	#
	# O processo existe, o cano existe, `available()` diz que sim -- e a
	# maquina fica muda para sempre, porque a politica da rede recusou o
	# arquivo .ps1 sem matar o processo. Passado o prazo sem uma palavra,
	# o jogo troca para o caminho codificado, que a politica nao alcanca.
	if not _apresentou and Time.get_ticks_msec() > _prazo_da_apresentacao_ms:
		if _sistema == "Windows" and not _codificado:
			_codificado = true
			_derrubar()
			_subir()
		else:
			_falha = "a ponte subiu mas nao respondeu"
			_derrubar()
			_proxima_subida_ms = Time.get_ticks_msec() + ESPERA_ENTRE_SUBIDAS_MS
		return
	_tranca.lock()
	var lote := _recebidas.duplicate()
	_recebidas.clear()
	_tranca.unlock()
	for linha in lote:
		_digerir(linha)

func _digerir(linha: String) -> void:
	if not linha.begins_with("#"):
		line_received.emit(linha)
		return
	var campos := linha.substr(1).split(",")
	var cabeca := campos[0].strip_edges().to_upper()
	match cabeca:
		"PONTE":
			_apresentou = true
			_escrever("@LISTAR")
		"PORTAS":
			var achadas := PackedStringArray()
			for i in range(1, campos.size()):
				var nome := campos[i].strip_edges()
				if not nome.is_empty():
					achadas.append(nome)
			_portas = achadas
		"ABERTA":
			_porta = campos[1].strip_edges() if campos.size() > 1 else _abrindo
			_abrindo = ""
			opened.emit(_porta)
		"FECHADA", "FALHA":
			var qual := campos[1].strip_edges() if campos.size() > 1 else _porta
			if qual.is_empty():
				qual = _abrindo
			_porta = ""
			_abrindo = ""
			if cabeca == "FALHA" and campos.size() > 2:
				_falha = campos[2].strip_edges()
			closed.emit(qual)
		"ERRO":
			_falha = campos[1].strip_edges() if campos.size() > 1 else "erro na ponte"
		"MORREU":
			# EOF do cano: o ajudante saiu. `poll()` sobe outro na sequencia.
			var estava := _porta if not _porta.is_empty() else _abrindo
			_derrubar()
			_proxima_subida_ms = Time.get_ticks_msec() + ESPERA_ENTRE_SUBIDAS_MS
			if not estava.is_empty():
				closed.emit(estava)
