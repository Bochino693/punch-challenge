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
## TRANCA SEPARADA PARA ESCREVER. Antes escrever no cano e empilhar o que
## chegou disputavam a MESMA tranca -- e a thread leitora, que empilha em
## rajada quando a placa fala, fazia o jogo esperar para mandar um LEDS.
## Sao duas coisas diferentes e nao ha razao para uma segurar a outra.
var _tranca_escrita := Mutex.new()
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
var _proxima_listagem_ms := 0
var _falha := ""
var _sistema := ""
var _codificado := false
var _prazo_da_apresentacao_ms := 0
## Quando o ajudante disse alguma coisa pela ultima vez. Ver o vigia de
## silencio em `poll()`.
var _ultima_linha_ms := 0
## A GERACAO DO AJUDANTE QUE ESTA DE PE.
##
## AQUI ESTAVA O LACO QUE MATAVA A PONTE PARA SEMPRE. Ao derrubar o
## ajudante, a thread leitora empilha um `#MORREU` de despedida -- e a
## fila NAO era limpa. O `#MORREU` do ajudante VELHO sobrava na fila e
## era digerido depois, quando o ajudante NOVO ja estava de pe: o jogo
## matava o recem-nascido, subia outro, e o `#MORREU` desse matava o
## seguinte. A ponte nunca chegava a dizer a primeira palavra, e na tela
## ficava "PROCURANDO ARDUINO..." a noite inteira.
##
## Agora cada ajudante nasce com um numero, a despedida vem assinada, e
## despedida de ajudante velho nao mata ajudante novo.
var _geracao := 0
## Quantas vezes o ajudante teve de ser ressuscitado. A Central mostra:
## muitas religadas seguidas e cabo ruim ou antivirus no caminho.
var _religadas := 0
## Ja funcionou alguma vez nesta sessao? Um ajudante que JA falou merece
## paciencia infinita; um que nunca falou merece a troca de receita.
var _ja_falou := false

const ESPERA_ENTRE_ABERTURAS_MS := 700
const ESPERA_ENTRE_SUBIDAS_MS := 2500
## SEIS SEGUNDOS ERAM POUCOS, e o preco de errar era a maquina morta.
##
## O prazo existe para trocar de receita quando a politica do Windows
## recusa arquivos .ps1 sem matar o processo. Mas ele tambem estourava em
## maquina LENTA e em maquina com antivirus: a primeira execucao de um
## .ps1 recem-escrito no AppData e escaneada, e o escaneamento sozinho
## passa de seis segundos num PC modesto. O jogo trocava de receita no
## meio de um ajudante que estava para falar, e recomecava -- de novo e de
## novo, sempre a seis segundos de funcionar.
const ESPERA_DA_APRESENTACAO_MS := 12000
## De quanto em quanto a ponte pede a lista de portas de novo enquanto
## nenhuma esta aberta.
##
## PORQUE A LISTA NAO SE ATUALIZAVA SOZINHA. O ajudante do Unix so
## enumera quando alguem manda `@LISTAR`, e o jogo mandava UMA vez, na
## apresentacao. Arduino espetado depois de o jogo abrir -- que e o caso
## normal de quem liga a maquina antes de conferir o cabo -- nunca
## aparecia na lista, e a busca "nunca terminava" porque nao havia mais
## nenhuma busca acontecendo.
const ESPERA_ENTRE_LISTAGENS_MS := 2000
## Silencio de um ajudante VIVO que passa disto e ajudante travado. O
## numero e folgado de proposito: enquanto nenhuma porta esta aberta o
## jogo pede a lista a cada dois segundos, entao vinte segundos sem uma
## palavra sao dez pedidos sem resposta.
const ESPERA_ATE_DESCONFIAR_MS := 20000

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
		return [bandeiras, _candidatos_de_powershell()]
	var script_unix := _desembrulhar(CAMINHO_UNIX, "ponte_serial.sh")
	if script_unix.is_empty():
		return []
	return [[script_unix], ["/bin/sh"]]

## OS LUGARES ONDE O POWERSHELL PODE ESTAR, com o SysNative na frente do
## System32 por um motivo especifico: num jogo de 32 bits rodando em
## Windows de 64 bits, `C:/Windows/System32` e redirecionado para o
## SysWOW64, e o PowerShell de 32 bits que mora la nao enxerga as mesmas
## portas COM que o de 64 enxerga em algumas imagens do Windows. O
## caminho `Sysnative` fura o redirecionamento e chega no PowerShell
## certo. Em processo de 64 bits ele simplesmente nao existe, e a lista
## segue para o seguinte -- custo zero.
static func _candidatos_de_powershell() -> Array:
	var raiz := OS.get_environment("SystemRoot")
	if raiz.is_empty():
		raiz = "C:/Windows"
	raiz = raiz.replace("\\", "/").rstrip("/")
	return [
		"powershell.exe",
		"%s/Sysnative/WindowsPowerShell/v1.0/powershell.exe" % raiz,
		"%s/System32/WindowsPowerShell/v1.0/powershell.exe" % raiz,
		"C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
		"pwsh.exe",
		"C:/Program Files/PowerShell/7/pwsh.exe",
	]

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
	# OS COMENTARIOS FICAM NO ARQUIVO, E NAO NA LINHA DE COMANDO.
	#
	# O script e mais comentario do que codigo -- de proposito, porque o
	# proximo a mexer nele estara com uma maquina quebrada na frente. Mas
	# na linha de comando do Windows cabem 32767 caracteres, e cada
	# comentario gasta desse teto. Levar comentario para dentro do
	# `-EncodedCommand` e gastar o unico recurso escasso deste caminho com
	# a unica parte que ninguem vai ler ali.
	var apertado := _sem_comentarios(texto).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	var carga := Marshalls.raw_to_base64(apertado)
	var envelope := "\n".join([
		"$b=[Convert]::FromBase64String('%s')" % carga,
		"$m=New-Object IO.MemoryStream(,$b)",
		"$g=New-Object IO.Compression.GZipStream($m,[IO.Compression.CompressionMode]::Decompress)",
		"$r=New-Object IO.StreamReader($g,[Text.Encoding]::UTF8)",
		"& ([scriptblock]::Create($r.ReadToEnd()))",
	])
	return Marshalls.raw_to_base64(envelope.to_utf16_buffer())

## Tira as linhas que sao SO comentario e as linhas vazias. Uma linha com
## codigo seguido de comentario fica inteira: cortar ali exigiria saber
## onde comeca uma string do PowerShell, e errar isso quebraria o script
## no caminho que so e usado quando o outro ja falhou -- o pior lugar do
## mundo para um defeito.
static func _sem_comentarios(texto: String) -> String:
	var linhas := PackedStringArray()
	for linha in texto.split("\n"):
		var limpa := linha.strip_edges()
		if limpa.is_empty() or limpa.begins_with("#"):
			continue
		linhas.append(linha)
	return "\n".join(linhas)

func _receita_codificada() -> Array:
	var base := comando_codificado()
	if base.is_empty():
		return []
	return [[
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden", "-EncodedCommand", base,
	], _candidatos_de_powershell()]

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
	var recusados: Array[String] = []
	for candidato in receita[1]:
		ultimo = str(candidato)
		canos = OS.execute_with_pipe(ultimo, argumentos)
		if not canos.is_empty() and canos.has("stdio"):
			break
		canos = {}
		recusados.append(ultimo.get_file())
	if canos.is_empty():
		_falha = "o sistema recusou abrir %s" % ", ".join(recusados)
		return
	_cano = canos["stdio"]
	_pid = int(canos.get("pid", -1))
	_prazo_da_apresentacao_ms = Time.get_ticks_msec() + ESPERA_DA_APRESENTACAO_MS
	_ultima_linha_ms = Time.get_ticks_msec()
	_proxima_listagem_ms = 0
	_parar = false
	_geracao += 1
	var minha := _geracao
	_thread = Thread.new()
	_thread.start(_laco_leitor.bind(minha))

## O CANO NAO AVISA QUANDO O AJUDANTE MORRE -- e este e o defeito mais
## fundo de todos, porque ele fazia a ponte ficar de pe MENTINDO.
##
## O laco confiava em `eof_reached()`. Medido: depois de o processo filho
## morrer, o cano do Godot devolve `eof_reached() == false` PARA SEMPRE, e
## `get_line()` passa a voltar vazio NA HORA, com `get_error()` em
## ERR_FILE_CANT_READ. Duas consequencias, as duas graves:
##
##  1. A condicao de parada nunca acontecia. A thread nunca terminava, o
##     `#MORREU` nunca era empilhado, e a ponte seguia jurando estar viva
##     -- `available()` verdadeiro, `_cano` no lugar -- com o ajudante ha
##     muito enterrado. O jogo esperava por uma placa que nao tinha mais
##     ninguem do outro lado para ouvir, e a tela ficava
##     "PROCURANDO ARDUINO..." ate alguem reiniciar a maquina. Nenhuma
##     ressurreicao acontecia porque a morte nunca era percebida.
##
##  2. `get_line()` voltando vazio na hora vira um laco fechado sem
##     espera nenhuma: a thread passa a girar em vazio queimando um
##     nucleo inteiro. Numa maquina de gabinete isso e o jogo perdendo
##     quadros "sem motivo" pelo resto da noite.
##
## Agora a parada olha o ERRO, e nao so o fim-de-arquivo. E `poll()`
## confere o processo por fora, com `OS.is_process_running`, que e a
## unica autoridade que nao depende de o cano se comportar.
func _laco_leitor(geracao: int) -> void:
	while not _parar:
		var cano := _cano
		if cano == null:
			break
		var linha := cano.get_line()
		if not linha.is_empty():
			linha = linha.strip_edges()
			if not linha.is_empty():
				_tranca.lock()
				_recebidas.append(linha)
				_tranca.unlock()
			continue
		if cano.eof_reached() or cano.get_error() != OK:
			break
		# Linha em branco de um cano saudavel: raro, mas nao e morte.
		# A espera existe so para nunca girar em vazio.
		OS.delay_msec(5)
	_tranca.lock()
	# A despedida vem ASSINADA: um `#MORREU` de ajudante velho chegando
	# depois que o novo subiu nao pode derrubar o novo.
	_recebidas.append("#MORREU,%d" % geracao)
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
	# A FILA MORRE COM O AJUDANTE. O que ele deixou pela metade nao vale
	# nada para o proximo, e o `#MORREU` da despedida dele mataria o
	# proximo antes de o proximo falar. Ver o comentario de `_geracao`.
	_tranca.lock()
	_recebidas.clear()
	_tranca.unlock()

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

func nome_do_caminho() -> String:
	return SerialLink.CAMINHO_PONTE

func available() -> bool:
	return _cano != null

## Quantas vezes o ajudante precisou ser ressuscitado nesta sessao.
func religadas() -> int:
	return _religadas

## Frase curta para a Central Tecnica dizer POR QUE nao ha Arduino.
func motivo_da_falta() -> String:
	return _falha

func descricao() -> String:
	if _sistema == "Windows":
		return "ponte PowerShell codificada" if _codificado else "ponte PowerShell"
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
	# e o jogo, que ja tem paciencia contada para isso. Se a abertura
	# falhar de verdade, `#FALHA` chega e derruba.
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
	var cano := _cano
	if cano == null:
		return false
	_tranca_escrita.lock()
	cano.store_line(linha)
	cano.flush()
	_tranca_escrita.unlock()
	return true

func poll() -> void:
	if _cano == null:
		# O ajudante caiu. Sobe de novo, com pausa, para o caso de o
		# defeito ser permanente (PowerShell bloqueado por politica, por
		# exemplo): insistir sem pausa vira um processo novo por quadro.
		#
		# ESTA E A LINHA QUE O JOGO ANTIGO NUNCA ALCANCAVA, porque so
		# chamava `poll()` enquanto `available()` fosse verdadeiro -- e
		# `available()` e falso exatamente aqui. Ver o comentario de
		# `SerialLink.poll`.
		var agora := Time.get_ticks_msec()
		if agora >= _proxima_subida_ms:
			_proxima_subida_ms = agora + ESPERA_ENTRE_SUBIDAS_MS
			_religadas += 1
			_subir()
		return

	# O QUE O AJUDANTE JA DISSE SE OUVE ANTES DE ELE SER DADO POR MORTO.
	#
	# A ordem aqui e uma regra, e nao um detalhe. Um ajudante que fala e
	# morre no mesmo instante -- que e o caso do PowerShell derrubado por
	# antivirus logo depois de se apresentar -- deixa palavras na fila. Se
	# a constatacao da morte viesse primeiro, ela limparia a fila e essas
	# palavras se perderiam: a lista de portas que ele alcancou a mandar,
	# a linha da placa que estava a caminho. Digerir primeiro nao atrasa
	# nada (a morte e constatada no mesmo quadro, logo abaixo) e nao
	# perde nada.
	_tranca.lock()
	var lote := _recebidas.duplicate()
	_recebidas.clear()
	_tranca.unlock()
	if not lote.is_empty():
		_ultima_linha_ms = Time.get_ticks_msec()
	for linha in lote:
		_digerir(linha)
	if _cano == null:
		# A propria fila trazia a despedida: `_digerir` ja derrubou.
		return

	# O AJUDANTE ESTA VIVO? A PERGUNTA E FEITA AO SISTEMA, NAO AO CANO.
	#
	# Ver o comentario de `_laco_leitor`: o cano nao avisa a morte. Quem
	# avisa e o sistema operacional, e a pergunta custa quase nada. Sem
	# ela, um ajudante morto -- derrubado por antivirus, por politica, ou
	# porque o PowerShell engasgou -- deixava a ponte "de pe" e muda para
	# sempre, e a tela ficava "PROCURANDO ARDUINO..." a noite inteira.
	if _pid > 0 and not OS.is_process_running(_pid):
		var estava_em := _porta if not _porta.is_empty() else _abrindo
		_falha = "o ajudante da ponte morreu"
		_derrubar()
		_proxima_subida_ms = Time.get_ticks_msec() + ESPERA_ENTRE_SUBIDAS_MS
		if not estava_em.is_empty():
			closed.emit(estava_em)
		return

	# UM AJUDANTE VIVO E MUDO TAMBEM PRECISA SER TROCADO.
	#
	# Vivo, o processo passa na pergunta acima -- e pode estar travado do
	# mesmo jeito: um PowerShell preso numa consulta ao gerenciador de
	# dispositivos que nao volta, uma porta que prendeu a thread do .NET.
	# Enquanto nenhuma porta esta aberta o jogo pede a lista de dois em
	# dois segundos, entao silencio longo aqui nao tem explicacao inocente.
	if _apresentou and not is_open() and _ultima_linha_ms > 0:
		if Time.get_ticks_msec() - _ultima_linha_ms > ESPERA_ATE_DESCONFIAR_MS:
			_falha = "o ajudante da ponte parou de responder"
			_derrubar()
			_proxima_subida_ms = Time.get_ticks_msec() + ESPERA_ENTRE_SUBIDAS_MS
			return

	# UM AJUDANTE QUE SOBE E NAO FALA E PIOR DO QUE UM QUE NAO SOBE.
	#
	# O processo existe, o cano existe, `available()` diz que sim -- e a
	# maquina fica muda para sempre, porque a politica da rede recusou o
	# arquivo .ps1 sem matar o processo. Passado o prazo sem uma palavra,
	# o jogo troca para o caminho codificado, que a politica nao alcanca.
	#
	# E DEPOIS VOLTA. A troca era de mao unica: uma vez no codificado,
	# nunca mais no arquivo. Se o problema fosse do codificado (linha de
	# comando gigante recusada por politica de auditoria, por exemplo), a
	# ponte ficava presa no caminho ruim. Agora as duas receitas se
	# alternam, e a maquina acaba caindo na que funciona nela.
	if not _apresentou and Time.get_ticks_msec() > _prazo_da_apresentacao_ms:
		_falha = "a ponte subiu mas nao respondeu em %d s" % (ESPERA_DA_APRESENTACAO_MS / 1000)
		_derrubar()
		# RECEITA QUE JA FUNCIONOU NAO SE TROCA. Se a ponte ja falou uma
		# vez nesta sessao, a receita esta provada nesta maquina e o
		# silencio de agora e outra coisa (o PC engasgado, o antivirus no
		# meio de uma varredura). Trocar de receita ali seria abandonar o
		# que funciona por causa de um tropeco.
		if _sistema == "Windows" and not _ja_falou:
			_codificado = not _codificado
		_proxima_subida_ms = Time.get_ticks_msec() + ESPERA_ENTRE_SUBIDAS_MS
		return

	# A LISTA DE PORTAS TEM DE CONTINUAR ACONTECENDO.
	#
	# Enquanto nenhuma porta esta aberta, o jogo esta procurando -- e
	# procurar e pedir a lista de novo, nao esperar que a lista de um
	# minuto atras mude sozinha. Sem isto, um Arduino espetado depois de
	# o jogo abrir nunca entrava na fila (o ajudante do Unix so enumera
	# quando mandam, e o jogo mandava UMA vez, na apresentacao). Ver
	# `ESPERA_ENTRE_LISTAGENS_MS`.
	if _apresentou and not is_open():
		var agora2 := Time.get_ticks_msec()
		if agora2 >= _proxima_listagem_ms:
			_proxima_listagem_ms = agora2 + ESPERA_ENTRE_LISTAGENS_MS
			_escrever("@LISTAR")

func _digerir(linha: String) -> void:
	if not linha.begins_with("#"):
		line_received.emit(linha)
		return
	var campos := linha.substr(1).split(",")
	var cabeca := campos[0].strip_edges().to_upper()
	match cabeca:
		"PONTE":
			_apresentou = true
			_ja_falou = true
			_falha = ""
			_escrever("@LISTAR")
		"PORTAS":
			var achadas := PackedStringArray()
			for i in range(1, campos.size()):
				var nome := campos[i].strip_edges()
				if not nome.is_empty():
					achadas.append(nome)
			# LISTA VAZIA NAO APAGA A LISTA BOA.
			#
			# Uma enumeracao que falhou no meio (o gerenciador de
			# dispositivos ocupado, o registro momentaneamente sem
			# resposta) devolve vazio -- e apagar a lista por causa dela
			# joga o jogo de volta para "PROCURANDO ARDUINO..." depois de
			# ele JA ter encontrado a porta. So uma lista vazia com a
			# porta tambem fechada quer dizer "nao ha nada espetado".
			if achadas.is_empty() and is_open():
				return
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
			# So a despedida da geracao QUE ESTA DE PE conta -- ver o
			# comentario de `_geracao`.
			var quem := int(campos[1]) if campos.size() > 1 else _geracao
			if quem != _geracao:
				return
			var estava := _porta if not _porta.is_empty() else _abrindo
			_derrubar()
			_proxima_subida_ms = Time.get_ticks_msec() + ESPERA_ENTRE_SUBIDAS_MS
			if not estava.is_empty():
				closed.emit(estava)
