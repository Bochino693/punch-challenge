class_name SerialLink
extends RefCounted

## Interface da camada serial. O jogo só fala com esta API; a
## implementação real (GdSerialLink, sobre a extensão GdSerial) ou a
## vazia (NullSerialLink, quando a extensão não carregou) fica por
## conta da fábrica `create_best`. Para trocar de extensão serial no
## futuro, escreva outro backend com estes mesmos métodos.

signal line_received(line: String)
signal opened(port: String)
signal closed(port: String)

## OS NOMES DOS DOIS CAMINHOS, porque agora o jogo TROCA de caminho
## sozinho enquanto está rodando. Antes a escolha era feita uma vez, no
## arranque, e valia para sempre: se o caminho escolhido não funcionasse
## naquela máquina, a máquina ficava morta a noite inteira mesmo com o
## outro caminho ali, funcionando, sem ninguém para chamá-lo.
const CAMINHO_NATIVO := "nativa"
const CAMINHO_PONTE := "ponte"
const CAMINHO_NENHUM := "nenhuma"

## A ESCOLHA DO CAMINHO ATÉ O ARDUINO, DO MELHOR PARA O QUE SEMPRE EXISTE.
##
## 1. A extensão nativa (`gdserial`), quando o Godot conseguiu carregá-la:
##    é a mais rápida e a única que fala a porta direto do processo.
## 2. A PONTE POR PROCESSO, quando não conseguiu — e é este o caso do
##    gabinete, onde a extensão não carregou e a máquina inteira ficou
##    morta: START, CRÉDITO, sensor e fitas. A ponte não depende de
##    binário nenhum que possa faltar; ela usa o que o sistema já tem
##    (PowerShell no Windows, `stty` no Linux).
## 3. O backend vazio, só para o jogo abrir e explicar o que houve.
##
## Ter o degrau 2 é a diferença entre "não funciona nada e ninguém sabe
## por quê" e uma máquina que trabalha.
##
## `evitar` É O QUE FALTAVA, e é o que conserta o "funciona no meu PC".
##
## A extensão nativa pode CARREGAR e ainda assim não servir: no Windows
## ela depende do runtime do Visual C++, e onde ele falta o .dll nem
## chega a entrar; onde ele existe pela metade, a extensão entra, diz que
## está viva e nunca enumera porta nenhuma. Nos dois casos o jogo antigo
## parava ali, porque a escolha do caminho era definitiva. Agora o jogo
## pede o PRÓXIMO caminho, e é ele quem descobre, na máquina do cliente,
## qual dos dois presta — sem ninguém precisar mexer em arquivo.
static func create_best(evitar := "") -> SerialLink:
	# Uma saída pela porta dos fundos para quem estiver com a máquina na
	# mão: `PUNCH_SERIAL=ponte` pula a extensão nativa mesmo que ela tenha
	# carregado, e `PUNCH_SERIAL=nativa` faz o contrário. Serve para
	# comparar os dois caminhos no mesmo gabinete sem trocar arquivo
	# nenhum de lugar. Quando está posto, ele MANDA — nem a troca
	# automática o contraria, senão não haveria como comparar.
	var forcado := OS.get_environment("PUNCH_SERIAL").strip_edges().to_lower()
	if forcado == CAMINHO_PONTE:
		evitar = CAMINHO_NATIVO
	elif forcado == CAMINHO_NATIVO:
		evitar = CAMINHO_PONTE
	# Primeiro a escada normal, sem o caminho que já se provou inútil.
	var escolhido := _tentar_caminho(_outro(evitar))
	if escolhido != null:
		return escolhido
	# O CAMINHO EVITADO AINDA É MELHOR DO QUE NENHUM. Se o outro não
	# existe nesta máquina, volta-se para ele: uma máquina meio boa
	# trabalha, uma máquina desligada não.
	if not evitar.is_empty() and forcado.is_empty():
		escolhido = _tentar_caminho(evitar)
		if escolhido != null:
			return escolhido
	var vazia := NullSerialLink.new()
	vazia.explicar(_motivo_de_nao_haver_caminho())
	return vazia

## O caminho oposto ao pedido. Vazio quer dizer "a escada inteira".
static func _outro(evitar: String) -> String:
	match evitar:
		CAMINHO_NATIVO:
			return CAMINHO_PONTE
		CAMINHO_PONTE:
			return CAMINHO_NATIVO
	return ""

## Sobe UM caminho, ou a escada inteira quando `qual` está vazio.
## Devolve `null` quando o caminho pedido não existe nesta máquina.
static func _tentar_caminho(qual: String) -> SerialLink:
	if qual.is_empty() or qual == CAMINHO_NATIVO:
		if ClassDB.class_exists(&"GdSerialManager"):
			var nativa := GdSerialLink.new()
			if nativa.available():
				return nativa
		if qual == CAMINHO_NATIVO:
			return null
	var ponte := PonteProcessoLink.new()
	if ponte.available():
		return ponte
	_ultimo_motivo = ponte.motivo_da_falta()
	return null

static var _ultimo_motivo := ""

static func _motivo_de_nao_haver_caminho() -> String:
	if not _ultimo_motivo.is_empty():
		return _ultimo_motivo
	if OS.get_name() == "Windows":
		# AS DUAS CAUSAS DE VERDADE, num PC que não é o de desenvolvimento.
		#
		# 1. A extensão nativa (`gdserial.dll`) importa VCRUNTIME140.dll,
		#    que NÃO faz parte do Windows: ela vem do "Visual C++
		#    2015-2022 Redistributable". O PC de quem desenvolve tem
		#    sempre, porque o Godot e outras ferramentas o instalam; um PC
		#    limpo pode não ter, e aí o Windows nem carrega o .dll.
		# 2. A ponte usa o PowerShell, que existe em todo Windows 10/11 —
		#    mas uma política de rede ou de grupo pode barrar o que ela
		#    precisa fazer.
		#
		# Confirmado por inspeção do próprio .dll deste repositório, e não
		# por suposição: as importações dele são VCRUNTIME140.dll,
		# api-ms-win-crt-*, SETUPAPI, CFGMGR32, ADVAPI32, KERNEL32.
		return ("nem a extensão nativa nem a ponte subiram — instale o "
			+ "Visual C++ 2015-2022 Redistributable (x64) e confira o PowerShell")
	return "nem a extensão nativa nem a ponte subiram neste sistema"

## Qual degrau da escada é este backend. O jogo usa para pedir o OUTRO
## quando este não deu em nada.
func nome_do_caminho() -> String:
	return CAMINHO_NENHUM

## A extensão serial está presente e carregada?
func available() -> bool:
	return false

## Como o jogo está falando com a placa, em duas palavras, para a Central.
func descricao() -> String:
	return "nenhuma"

## Quando não há caminho nenhum: a frase que diz por quê.
func motivo_da_falta() -> String:
	return ""

## Nomes das portas disponíveis (ex.: ["COM3", "COM5"]).
func list_ports() -> PackedStringArray:
	return PackedStringArray()

func open_port(_port: String, _baud: int = GameDef.SERIAL_BAUD) -> bool:
	return false

func close_port() -> void:
	pass

func is_open() -> bool:
	return false

func send_line(_line: String) -> bool:
	return false

## Chamado a cada frame pelo jogo.
##
## E CHAMADO SEMPRE, inclusive quando `available()` diz que não. Este
## método é o BATIMENTO do backend: é dentro dele que a ponte por
## processo ressuscita o ajudante que morreu. O jogo antigo só chamava
## `poll()` enquanto `available()` fosse verdadeiro — e como a ponte
## responde `false` justamente no intervalo em que está caída, o
## batimento parava exatamente quando era necessário. A ponte ficava
## caída para sempre, e na tela ficava "PROCURANDO ARDUINO…" até alguém
## reiniciar a máquina. Nenhum backend pode presumir que só é chamado
## quando está de pé.
func poll() -> void:
	pass

## Solta tudo o que o backend segurar fora do processo do jogo.
func encerrar() -> void:
	pass
