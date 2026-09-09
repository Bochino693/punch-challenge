class_name CameraService
extends Node

## Camada opcional sobre CameraServer. Toda chamada falha fechada: sem
## webcam ou sem permissão o jogo continua com um avatar desenhado.

const PHOTO_DIR := "user://ranking_photos"
const THUMB_SIZE := 320

var enabled := true
var mirrored := true
var selected_index := 0
var _feed: CameraFeed = null
var _texture: CameraTexture = null
var _bridge_texture: ImageTexture = null
var _last_image: Image = null
var _bridge_pid := -1
var _bridge_path := ""
var _bridge_modified := 0
var _bridge_digest := 0
var _last_frame_ms := 0
var _bridge_started_ms := 0
var _next_bridge_poll_ms := 0
## O CONTADOR DE QUADROS QUE A PONTE PUBLICA. Parado quer dizer imagem
## velha; a data de modificação do arquivo não serve para isso, porque
## tem resolução de um segundo em vários sistemas de arquivos.
var _bridge_contador := -1
var _bridge_contador_ms := 0
## Quantas vezes a ponte precisou ser ressuscitada. Aparece na Central:
## uma ponte que reinicia sozinha o tempo todo é cabo ruim, não software.
var _bridge_reinicios := 0
## A tarefa que lê e decodifica o JPEG fora da linha do jogo.
var _tarefa_leitura := -1
var _imagem_pronta: Image = null
var _mutex_leitura := Mutex.new()
## TETO DE RELIGAMENTOS. Sem ele, uma máquina sem Python entra num laço:
## o processo morre no mesmo instante em que nasce, o jogo o ressuscita,
## e assim a noite inteira — com o motivo verdadeiro (falta o OpenCV)
## sumindo no meio de mil reinícios.
## TETO ALTO, E DE PROPÓSITO.
##
## Seis era pouco: com a ponte e o diagnóstico disputando a webcam, a
## conta estourava em segundos e a câmera ficava desligada o resto da
## noite. A disputa foi resolvida, mas o teto continua alto — desistir é
## o pior desfecho possível para um recurso de que o jogo depende, e a
## contagem zera sozinha assim que um quadro chega.
const MAX_RELIGAMENTOS := 40
var _bridge_desistiu := false
## PULA O CAMINHO NATIVO E VAI DIRETO À PONTE.
##
## No Windows é comum o Godot ENUMERAR a webcam e nunca receber quadro: a
## máquina fica "conectada" e preta. O vigia já derruba isso em dois
## segundos e meio, mas numa instalação em que isso acontece toda vez,
## esperar dois segundos e meio a cada abertura é tempo perdido — e o
## técnico que já sabe do problema tem como dizer "vá direto".
var forcar_ponte := false
## O BACK-END QUE JÁ SE PROVOU NESTA MÁQUINA.
##
## A sondagem descobre se a webcam abre por DirectShow ou por Media
## Foundation. Guardar a resposta e passá-la para a ponte evita que cada
## religada refaça a fila inteira — e no Windows cada back-end que falha
## custa de um a três segundos, bem na hora em que o gabinete precisa da
## prévia para a foto.
var backend_preferido := ""

## Vigia do caminho nativo: quando o feed foi ativado e se ele já provou
## que entrega quadro.
var _native_started_ms := 0
var _native_ok := false
var status := "PROCURANDO CÂMERA"
## Publica um padrão sintético em vez da webcam. Serve para separar
## "a ponte está quebrada" de "a câmera está quebrada" sem webcam
## nenhuma — mesma ideia do comando TEST do firmware do sensor.
var pattern_mode := false

## O OBTURADOR ABERTO DURANTE A POSE.
##
## A foto era UM quadro, tirado no instante exato em que a contagem
## zerava. Se justo naquele sexagésimo de segundo a pessoa piscou, a
## webcam engasgou ou a ponte ainda estava subindo, a foto saía ruim ou
## não saía — e a partida seguia sem cara nenhuma no ranking, sem
## explicar por quê.
##
## Agora o jogo abre o obturador quando a contagem COMEÇA e guarda o
## melhor quadro que passar até ela zerar. "Melhor" é o de maior
## contraste: entre um quadro preto, um borrado de movimento e um nítido,
## é o nítido que tem a maior distância entre o claro e o escuro. No fim
## a máquina não tira uma foto, ela ESCOLHE uma entre umas quarenta.
## A última foto tirada, ainda em memória. Quem for desenhá-la não
## precisa relê-la do disco.
var ultima_foto: Image = null

## O ÚLTIMO QUADRO QUE A CÂMERA ENTREGOU — E ELE NÃO SE APAGA.
##
## AQUI ESTAVA O ÚLTIMO CAMINHO QUE LEVAVA DE VOLTA AO MARROM. Toda vez
## que a ponte era religada — por queda do processo, por imagem congelada,
## por troca de câmera — `_matar_ponte()` zerava a textura, e a tela
## caía no boneco desenhado pelos dois ou três segundos até o primeiro
## quadro novo chegar. Do lado de fora isso é indistinguível de a câmera
## ter desligado, e acontecia várias vezes por noite.
##
## Esta cópia sobrevive à religada. Enquanto a câmera estiver LIGADA na
## Central, a tela mostra a última imagem que existiu — parada por um
## instante, e infinitamente melhor do que um desenho. Ela só é
## descartada quando o operador desliga a câmera de propósito.
var _ultima_textura: ImageTexture = null
var _melhor_imagem: Image = null
var _melhor_nota := -1.0
var _obturador_ate_ms := 0

func _ready() -> void:
	# O CameraServer avisa por DOIS sinais (feed entrou / feed saiu), e não
	# por um "feeds_updated" — este último não existe, e enquanto o código
	# tentava conectá-lo o script inteiro não compilava: a câmera não
	# falhava, ela nunca chegava a existir.
	if not CameraServer.camera_feed_added.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feed_added.connect(_on_camera_feeds_updated)
	if not CameraServer.camera_feed_removed.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feed_removed.connect(_on_camera_feeds_updated)
	set_process(true)
	pedir_abertura()

## ---------------------------------------------------------------------
## O FLUXO ÚNICO DA CÂMERA
##
## Este bloco existe porque a câmera acendia e apagava sozinha, e a causa
## nunca era uma só: era o número de portas de entrada. Havia seis
## lugares diferentes que ligavam, desligavam, matavam ou ressuscitavam a
## ponte — `refresh`, `set_enabled`, `cycle_camera`, o sinal de feed do
## Godot, o vigia do processo e o diagnóstico — e cada par deles tinha o
## seu próprio jeito de se atrapalhar. Consertar um par fazia aparecer
## outro.
##
## Agora ninguém liga nem desliga nada de fora. Quem chama de fora só
## PEDE, e o pedido fica guardado. Uma única função por quadro,
## `_supervisionar()`, olha o estado, olha o pedido e decide o que
## acontece — e ela é o ÚNICO lugar do arquivo que sobe ou derruba a
## ponte. Duas ordens contraditórias no mesmo quadro deixam de ser uma
## corrida: a última a chegar é a que vale, e ela é atendida uma vez só.
enum Estado {
	DESLIGADA,  ## por escolha do operador
	SUBINDO,    ## processo de pé, ainda sem quadro
	ACESA,      ## entregando imagem
	EXAME,      ## o diagnóstico está com a webcam
	PARADA,     ## desistiu: sem Python que sirva
}

enum Pedido { NENHUM, ABRIR, FECHAR, EXAME_ENTRAR, EXAME_SAIR }

var estado := Estado.DESLIGADA
var _pedido := Pedido.NENHUM

## As portas de entrada. Todas só anotam a intenção.
func pedir_abertura() -> void:
	_pedido = Pedido.ABRIR

func pedir_fechamento() -> void:
	_pedido = Pedido.FECHAR

func pedir_exame() -> void:
	_pedido = Pedido.EXAME_ENTRAR

func terminar_exame() -> void:
	_pedido = Pedido.EXAME_SAIR

## A câmera está entregando imagem AGORA? É o que a contagem regressiva
## espera antes de começar, e o que a foto pergunta antes de sair.
func pronta() -> bool:
	return estado == Estado.ACESA

## Uma frase curta do estado, para a tela da pose e para a Central.
func estado_curto() -> String:
	match estado:
		Estado.DESLIGADA:
			return "CÂMERA DESLIGADA NA CENTRAL"
		Estado.SUBINDO:
			return "LIGANDO A CÂMERA…"
		Estado.ACESA:
			return "CÂMERA PRONTA"
		Estado.EXAME:
			return "EXAMINANDO A CÂMERA…"
		Estado.PARADA:
			return motivo_curto()
	return ""

func _process(delta: float) -> void:
	_supervisionar(delta)

## A ÚNICA função que sobe ou derruba a câmera.
func _supervisionar(_delta: float) -> void:
	_atender_pedido()
	# Durante o exame ninguém mexe na webcam: ela é do diagnóstico.
	if estado == Estado.EXAME or estado == Estado.DESLIGADA or estado == Estado.PARADA:
		return
	# O vigia de sempre, agora com um dono só.
	if _feed != null:
		_vigiar_nativa()
		estado = Estado.ACESA if _native_ok else Estado.SUBINDO
		return
	_vigiar_ponte()
	if _bridge_desistiu:
		estado = Estado.PARADA
	# QUATRO SEGUNDOS PARA CONTINUAR ACESA, dois e meio para a foto.
	#
	# São duas perguntas diferentes e elas tinham o mesmo prazo. A foto
	# exige um quadro de agora, e dois segundos e meio é generoso para
	# isso. Mas o ESTADO com o mesmo prazo fazia a câmera "desligar" a
	# cada engasgo da webcam — e desligar o estado trava a contagem
	# regressiva, que é como o atraso de meio segundo virava uma rodada
	# inteira esperando.
	elif _bridge_texture != null and Time.get_ticks_msec() - _last_frame_ms < 4000:
		estado = Estado.ACESA
	else:
		estado = Estado.SUBINDO

## O pedido pendente, atendido uma vez só. Separado da supervisão porque
## é aqui que mora a regra que interessa — e uma regra que interessa tem
## de poder ser verificada sozinha, sem um processo de verdade no ar.
func _atender_pedido() -> void:
	var pedido := _pedido
	_pedido = Pedido.NENHUM
	match pedido:
		Pedido.FECHAR:
			enabled = false
			_derrubar()
			# Desligar de propósito é a ÚNICA coisa que apaga a memória
			# da imagem: em todo o resto ela é o que impede a tela de
			# voltar ao boneco.
			_ultima_textura = null
			estado = Estado.DESLIGADA
			status = "CÂMERA DESATIVADA"
		Pedido.EXAME_ENTRAR:
			_derrubar()
			estado = Estado.EXAME
			status = "EXAMINANDO A CÂMERA…"
		Pedido.EXAME_SAIR:
			estado = Estado.DESLIGADA if not enabled else Estado.SUBINDO
			_riscados.clear()
			_bridge_desistiu = false
			_bridge_reinicios = 0
			if enabled:
				_levantar()
		Pedido.ABRIR:
			enabled = true
			# ACESA NÃO SE MEXE. É a regra que faltava: uma câmera que
			# está entregando imagem não é reconstruída porque alguém
			# pediu "abre" — ela já está aberta.
			if estado != Estado.ACESA:
				_derrubar()
				_riscados.clear()
				_bridge_desistiu = false
				_bridge_reinicios = 0
				estado = Estado.SUBINDO
				_levantar()

## Sobe o caminho da câmera: nativo quando o Godot enxerga, ponte quando
## não. Chamada de um lugar só.
func _levantar() -> void:
	_native_ok = false
	var feeds: Array = []
	if not forcar_ponte:
		# O Godot 4.6 só enumera câmeras sob pedido. E acordar o servidor
		# EMITE `camera_feed_added` na mesma pilha — por isso este
		# despertar mora aqui dentro, onde o sinal não tem como virar uma
		# segunda abertura: ele só marca um pedido para o próximo quadro.
		_acordar_servidor()
		feeds = CameraServer.feeds()
	if feeds.is_empty():
		_start_bridge()
		return
	selected_index = clampi(selected_index, 0, feeds.size() - 1)
	_feed = feeds[selected_index]
	var formatos := _feed.get_formats()
	if not formatos.is_empty():
		_feed.set_format(0, {})
	_feed.set_active(true)
	_texture = CameraTexture.new()
	_texture.camera_feed_id = _feed.get_id()
	_texture.which_feed = CameraServer.FEED_RGBA_IMAGE
	_native_started_ms = Time.get_ticks_msec()
	status = "ABRINDO CÂMERA…"

## Derruba tudo o que estiver de pé. Chamada de um lugar só.
func _derrubar() -> void:
	if _feed != null:
		_feed.set_active(false)
	_feed = null
	_texture = null
	_native_ok = false
	_matar_ponte()

func _vigiar_ponte() -> void:
	# EXAME EM CURSO: A PONTE FICA FORA DO AR, E O VIGIA TAMBÉM.
	#
	# AQUI ESTAVA A PISCA-PISCA. Só um programa por vez consegue abrir uma
	# webcam — é regra do sistema operacional, não do jogo. A sondagem do
	# diagnóstico abre os índices 0 a 9 em três back-ends para descobrir
	# onde a câmera está; enquanto ela faz isso, a ponte perde o
	# dispositivo, publica "CAMERA PAROU DE RESPONDER", o vigia religa a
	# ponte, a ponte rouba a câmera de volta da sondagem, e os dois ficam
	# se atropelando. Na tela isso aparece exatamente como o operador
	# descreveu: a imagem ligando e desligando.
	#
	# O conserto é combinar quem manda: durante o exame, a ponte sai do
	# ar de propósito e ninguém a religa. Ela volta no fim, já com o
	# índice, o back-end e o Python que o exame descobriu.
	if _bridge_pid <= 0:
		return
	var now := Time.get_ticks_msec()
	if now < _next_bridge_poll_ms:
		return
	# QUINZE VEZES POR SEGUNDO, que é a taxa em que a ponte publica.
	# Cem milissegundos deixavam a prévia em dez quadros e a pose parecia
	# travada justamente quando a pessoa está se ajeitando na frente da
	# câmera.
	_next_bridge_poll_ms = now + 66
	if not OS.is_process_running(_bridge_pid):
		# MORREU SEM NUNCA PUBLICAR NADA? O INTERPRETADOR É QUE ESTÁ
		# ERRADO, e insistir nele é perder a noite.
		#
		# É a assinatura exata do atalho da Microsoft Store: nasce, abre a
		# loja e morre em menos de um segundo e meio, sem escrever o
		# arquivo de estado que a ponte de verdade escreve no primeiro
		# quadro. Riscando o candidato, o próximo (`python3`, `python`)
		# entra na tentativa seguinte em vez de repetir o mesmo erro seis
		# vezes e desistir.
		var viveu := Time.get_ticks_msec() - _bridge_started_ms
		if _bridge_texture == null and viveu < 2500 and _bridge_status_line().is_empty():
			_riscar_interpretador(_interpretador_em_teste)
			status = "PYTHON \"%s\" NÃO SERVIU — TENTANDO OUTRO" % _interpretador_em_teste
			_interpretador_em_teste = ""
			_bridge_pid = -1
			_start_bridge()
			return
		_bridge_texture = null
		_last_image = null
		_bridge_pid = -1
		_bridge_reinicios += 1
		if _bridge_reinicios > MAX_RELIGAMENTOS:
			# DESISTIR É INFORMAÇÃO. Seis mortes seguidas não são cabo
			# solto: é o processo não conseguindo nem começar. O motivo
			# está no arquivo de estado que a ponte deixa para trás.
			_bridge_desistiu = true
			status = _bridge_status_file()
			return
		status = "PONTE CAIU — RELIGANDO (%d)" % _bridge_reinicios
		_start_bridge()
		return

	# O CONTADOR VEM PRIMEIRO. Ler o estado é ler dezenas de bytes; ler o
	# JPEG e calcular o resumo dele é ler dezenas de milhares. Sem
	# quadro novo, não há por que tocar na imagem.
	var contador := _bridge_frame_counter()
	if contador >= 0 and contador == _bridge_contador:
		# SEIS SEGUNDOS, E NÃO TRÊS. Uma webcam USB barata engasga por
		# dois ou três segundos quando muda a exposição — e religar a
		# ponte nesse engasgo troca uma imagem parada por uma imagem
		# AUSENTE, que é pior. Só é congelamento de verdade quando passa
		# de meia dúzia de segundos.
		if now - _bridge_contador_ms > 6000 and _bridge_texture != null:
			# IMAGEM CONGELADA COM O PROCESSO VIVO. Acontece quando a
			# webcam trava sem devolver erro ao OpenCV: a ponte fica
			# publicando o mesmo quadro para sempre, e a prévia mostra
			# uma foto antiga como se fosse ao vivo.
			status = "IMAGEM CONGELADA — RELIGANDO A PONTE"
			_bridge_reinicios += 1
			_matar_ponte()
			_start_bridge()
		return
	if contador >= 0:
		# Quadro novo: a ponte está viva de verdade, e a conta de
		# desistência recomeça. Sem zerar, seis trancos no cabo ao longo
		# de uma tarde acabariam desligando a câmera para sempre.
		_bridge_contador = contador
		_bridge_contador_ms = now
		_bridge_reinicios = 0
	# LER E DECODIFICAR O JPEG SAI DA LINHA DO JOGO.
	#
	# Isto era um engasgo de verdade, e periódico — o pior tipo. A cada
	# quadro novo da ponte (quinze por segundo) a linha principal lia o
	# arquivo inteiro do disco, calculava o resumo dele e decodificava o
	# JPEG, tudo entre um quadro desenhado e o seguinte. Num PC de
	# gabinete isso são alguns milissegundos QUINZE VEZES POR SEGUNDO: a
	# animação não fica lenta, fica ENGASGADA, que é a impressão de
	# travamento que se vê e não se consegue apontar.
	#
	# Agora quem lê e decodifica é uma tarefa do pool de linhas do Godot.
	# A linha do jogo só encosta na imagem quando ela já está pronta.
	_colher_quadro_da_ponte(now)
	if _bridge_texture == null and now - _bridge_started_ms > 5000:
		# A ponte escreve o motivo ao lado do JPEG; sem ler esse arquivo,
		# todo problema virava a mesma mensagem genérica e o técnico não
		# sabia se era OpenCV, cabo ou câmera ocupada.
		status = _bridge_status_file()

## Entrega à linha do jogo o quadro que a tarefa de leitura terminou, e
## põe a próxima tarefa para rodar. Nunca há mais de uma no ar: com duas,
## a mais velha poderia terminar depois da mais nova e a prévia andaria
## para trás.
func _colher_quadro_da_ponte(agora: int) -> void:
	if _tarefa_leitura != -1:
		if not WorkerThreadPool.is_task_completed(_tarefa_leitura):
			return
		WorkerThreadPool.wait_for_task_completion(_tarefa_leitura)
		_tarefa_leitura = -1
		_mutex_leitura.lock()
		var pronta := _imagem_pronta
		_imagem_pronta = null
		_mutex_leitura.unlock()
		if pronta != null and not pronta.is_empty():
			_last_frame_ms = agora
			_last_image = pronta
			_oferecer_ao_obturador(pronta)
			if _bridge_texture == null:
				_bridge_texture = ImageTexture.create_from_image(pronta)
			else:
				_bridge_texture.update(pronta)
			_ultima_textura = _bridge_texture
			status = "CÂMERA CONECTADA (PONTE)"
	if _bridge_pid > 0 and _tarefa_leitura == -1:
		_tarefa_leitura = WorkerThreadPool.add_task(_ler_quadro, false, "camera: ler quadro")

## Corpo da tarefa. Roda FORA da linha do jogo: aqui não se toca em nada
## que o desenho leia — só no par mutex/imagem que existe para isto.
func _ler_quadro() -> void:
	if _bridge_path.is_empty() or not FileAccess.file_exists(_bridge_path):
		return
	var bytes := FileAccess.get_file_as_bytes(_bridge_path)
	if bytes.is_empty():
		return
	var digest := hash(bytes)
	if digest == _bridge_digest:
		return
	var imagem := Image.new()
	if imagem.load_jpg_from_buffer(bytes) != OK or imagem.is_empty():
		return
	_bridge_digest = digest
	_mutex_leitura.lock()
	_imagem_pronta = imagem
	_mutex_leitura.unlock()

## Espera a tarefa de leitura antes de mexer no estado que ela usa.
## Sem isto, matar a ponte enquanto uma leitura está no ar deixa a tarefa
## lendo um arquivo que acabou de ser apagado.
func _esperar_leitura() -> void:
	if _tarefa_leitura == -1:
		return
	WorkerThreadPool.wait_for_task_completion(_tarefa_leitura)
	_tarefa_leitura = -1
	_mutex_leitura.lock()
	_imagem_pronta = null
	_mutex_leitura.unlock()

## O FEED NATIVO PRECISA PROVAR QUE FUNCIONA.
##
## `is_active()` só diz que o Godot MANDOU ligar a câmera, não que ela
## respondeu. No Windows é comum a câmera ser enumerada e nunca entregar
## quadro: aí o jogo mostrava "CÂMERA CONECTADA" com a tela preta e
## jamais caía para a ponte, porque a ponte só entrava quando NENHUMA
## câmera era enumerada. Dois segundos e meio sem imagem e trocamos.
func _vigiar_nativa() -> void:
	if _native_ok:
		# Já provada: daqui em diante o trabalho é só alimentar o
		# obturador, para a foto da pose ter de onde escolher.
		var atual := _texture.get_image() if _texture != null else null
		if atual != null and not atual.is_empty():
			_last_image = atual
			_last_frame_ms = Time.get_ticks_msec()
			_oferecer_ao_obturador(atual)
		return
	var imagem := _texture.get_image() if _texture != null else null
	# NÃO BASTA A IMAGEM EXISTIR: ELA PRECISA TER ALGUMA COISA DENTRO.
	#
	# Este era o defeito que fazia "a cara não pegar" numa máquina com a
	# webcam perfeita. O Godot no Windows ENUMERA a câmera, aceita ativar
	# o feed e devolve um buffer do tamanho certo — todo preto. Como o
	# teste era só `not is_empty()`, o jogo declarava CÂMERA CONECTADA,
	# nunca caía para a ponte, e fotografava um quadrado preto em cima do
	# quadrado preto anterior, a noite inteira, sem uma linha de erro.
	if imagem != null and _imagem_util(imagem):
		_native_ok = true
		_last_image = imagem
		_last_frame_ms = Time.get_ticks_msec()
		status = "CÂMERA CONECTADA (NATIVA)"
		return
	if Time.get_ticks_msec() - _native_started_ms > 2500:
		_stop_feed()
		status = "CÂMERA NATIVA MUDA — TENTANDO A PONTE"
		_start_bridge()

## AMOSTRAS EM GRADE, PARA SABER SE HÁ IMAGEM DE VERDADE.
##
## Uma cena real — uma pessoa na frente de um gabinete iluminado — nunca
## é de uma cor só. Um buffer não inicializado, uma câmera com a tampa
## na lente e um feed que ativou sem entregar nada SÃO de uma cor só. A
## conta é sobre 48 pontos espalhados: se o mais claro e o mais escuro
## estiverem a menos de 4% um do outro, não há imagem ali.
##
## Barato de propósito: roda a cada quadro enquanto a câmera não provou
## que funciona, e ler a imagem inteira nesse laço custaria mais do que
## desenhar a tela.
const CONTRASTE_MINIMO := 0.04

func _imagem_util(imagem: Image) -> bool:
	return _nota_da_imagem(imagem) >= CONTRASTE_MINIMO

## A distância entre o ponto mais claro e o mais escuro da grade. Serve
## de duas maneiras: acima do mínimo, diz que há imagem; comparada entre
## quadros, diz qual deles é o melhor.
func _nota_da_imagem(imagem: Image) -> float:
	if imagem == null or imagem.is_empty():
		return -1.0
	var largura := imagem.get_width()
	var altura := imagem.get_height()
	if largura < 8 or altura < 8:
		return -1.0
	var claro := 0.0
	var escuro := 1.0
	for gx in range(8):
		for gy in range(6):
			var x := int((float(gx) + 0.5) / 8.0 * float(largura))
			var y := int((float(gy) + 0.5) / 6.0 * float(altura))
			var v := imagem.get_pixel(x, y).get_luminance()
			claro = maxf(claro, v)
			escuro = minf(escuro, v)
	return claro - escuro

## Abre o obturador por `janela_ms`. Chamado quando a contagem começa.
func abrir_obturador(janela_ms := 3200) -> void:
	_melhor_imagem = null
	_melhor_nota = -1.0
	_obturador_ate_ms = Time.get_ticks_msec() + janela_ms

## Oferece um quadro ao obturador. Só guarda se for melhor que o guardado
## e se a janela ainda estiver aberta.
func _oferecer_ao_obturador(imagem: Image) -> void:
	if imagem == null or Time.get_ticks_msec() > _obturador_ate_ms:
		return
	var nota := _nota_da_imagem(imagem)
	if nota <= _melhor_nota:
		return
	_melhor_nota = nota
	_melhor_imagem = imagem.duplicate()

## Acorda o servidor de câmeras do Godot. Existe como função própria
## porque a 4.6 exige isso e as versões anteriores não têm o método:
## chamar direto quebraria o jogo em qualquer instalação mais antiga.
func _acordar_servidor() -> void:
	if CameraServer.has_method("set_monitoring_feeds"):
		CameraServer.call("set_monitoring_feeds", true)

## Ligar e desligar pela Central. Como tudo o mais, só anota a intenção:
## quem age é `_supervisionar()`, no próximo quadro.
func set_enabled(value: bool) -> void:
	if value:
		pedir_abertura()
	else:
		pedir_fechamento()

## TROCAR DE CÂMERA É ORDEM DO TÉCNICO: derruba a que está no ar de
## propósito, porque é justamente isso que ele pediu.
func cycle_camera() -> void:
	# Vai até o índice 9 porque é até onde a sondagem procura — parar no
	# 3 deixava de fora justamente a máquina com câmera virtual
	# instalada, que é onde a webcam boa acaba no 6 ou no 7.
	selected_index = (selected_index + 1) % 10
	# Trocou de câmera, o back-end provado não vale mais para o novo
	# índice: sem limpar, a ponte insistiria com `--fixo` num par
	# índice/back-end que nunca foi testado junto.
	backend_preferido = ""
	# Derruba de propósito: é a única ordem que quer a câmera reaberta
	# mesmo estando acesa.
	estado = Estado.SUBINDO
	_derrubar()
	pedir_abertura()

func _on_camera_feeds_updated(_id: int = 0) -> void:
	# SÓ UM PEDIDO, NUNCA UMA AÇÃO. Este aviso chega de dentro do próprio
	# `_levantar()`, quando ele acorda o servidor: se aqui houvesse
	# qualquer abertura, ela aconteceria no meio da abertura que a
	# provocou. Anotando um pedido, o pior caso vira um quadro a mais.
	if forcar_ponte or not enabled:
		return
	if estado == Estado.SUBINDO and _feed == null and _bridge_pid <= 0:
		pedir_abertura()

func preview_texture() -> Texture2D:
	if _texture != null:
		return _texture
	return _bridge_texture if _bridge_texture != null else _ultima_textura

func available() -> bool:
	if not enabled:
		return false
	# "Disponível" é ter QUADRO, e não ter feed aberto: era por confiar em
	# `is_active()` que a máquina anunciava câmera e fotografava preto.
	if _feed != null:
		return _native_ok
	return _bridge_texture != null and Time.get_ticks_msec() - _last_frame_ms < 2500

## HÁ IMAGEM PARA MOSTRAR? — pergunta diferente de `available()`.
##
## `available()` responde "a imagem é de agora?", e serve para decidir se
## vale tirar foto. Para decidir o que DESENHAR ela é a pergunta errada,
## e era por isso que a prévia voltava a ser o boneco marrom no começo de
## cada rodada: bastava a ponte atrasar meio segundo além dos dois e meio
## — trocando de exposição, ou logo depois de a foto anterior ter sido
## salva — para a tela concluir que não havia câmera e devolver o
## desenho, com a webcam acesa na frente da pessoa.
##
## Enquanto o processo da ponte está de pé e já houve um quadro, há
## imagem para mostrar. Um quadro parado por um instante é infinitamente
## melhor do que um boneco: ele é a cara de quem está ali.
func tem_imagem() -> bool:
	if not enabled:
		return false
	if _feed != null:
		return _native_ok
	# `_ultima_textura` entra aqui de propósito: enquanto a câmera está
	# ligada, o que existiu uma vez continua valendo de imagem. É esta
	# linha que cumpre o "ligou, não volta mais para o boneco".
	return _bridge_texture != null or _ultima_textura != null

## A FICHA DA PONTE, numa linha: qual Python, qual índice, qual
## back-end. Sem ela, "não conecta" continua sendo um mistério — e foi
## justamente por não mostrar QUAL interpretador estava sendo usado que o
## defeito do atalho da Microsoft Store passou tanto tempo escondido.
func ficha_da_ponte() -> String:
	var quem := _interpretador_em_teste if not _interpretador_em_teste.is_empty() else _proximo_interpretador()
	if quem.is_empty():
		quem = "nenhum"
	var riscados := "" if _riscados.is_empty() else "  •  riscados: %s" % ", ".join(_riscados)
	return "python %s%s  •  índice %d  •  back-end %s" % [
		quem, riscados, selected_index,
		backend_preferido if not backend_preferido.is_empty() else "automático",
	]

## A MARCA NÃO ENTRA NA FOTO.
##
## Ela chegou a ser gravada no canto da imagem salva, e foi um erro: a
## foto é o rosto de uma pessoa, e carimbo dentro dela some quando a
## miniatura do ranking é pequena e atrapalha quando é grande. A marca
## mora na TELA, ao lado do retrato — onde ela é grande o bastante para
## ser lida e não disputa um pixel sequer com a cara de quem jogou.

## POR QUE NÃO SAIU FOTO, em poucas palavras.
##
## A tela da pose dizia "SEM CÂMERA • VAMOS JOGAR" para tudo: câmera
## desligada na Central, Python faltando, webcam ocupada, ponte subindo
## ainda. Quem está na frente da máquina merece a frase certa — e quem vai
## consertar precisa dela.
func motivo_curto() -> String:
	if not enabled:
		return "CÂMERA DESLIGADA NA CENTRAL"
	if _feed == null and _bridge_pid <= 0:
		return "PONTE NÃO SUBIU — VEJA A CENTRAL"
	if _bridge_desistiu:
		return "PONTE DESISTIU — F9 E DIAGNOSTICAR"
	if _bridge_texture == null and _feed == null:
		return "AINDA ABRINDO A CÂMERA"
	return "SEM QUADRO NOVO"

## A IDADE DO QUADRO QUE ESTÁ NA MÃO, em milissegundos.
##
## A foto da pose é tirada num instante marcado — o zero da contagem — e
## até aqui ninguém perguntava QUÃO VELHA era a imagem usada. Uma webcam
## que trava sem devolver erro continua entregando o mesmo quadro para
## sempre, e o gabinete fotografa a pessoa da partida anterior sem nunca
## dizer nada. Com a idade medida, isso vira uma linha na Central em vez
## de um mistério no ranking.
func idade_do_quadro() -> int:
	if _feed != null:
		return 0 if _native_ok else 999999
	if _last_frame_ms <= 0:
		return 999999
	return Time.get_ticks_msec() - _last_frame_ms

func capture_photo() -> String:
	# O MELHOR QUADRO DA POSE VEM ANTES DE TUDO — inclusive antes de
	# `available()`. Se a câmera parou de responder no último segundo mas
	# entregou trinta quadros bons durante a contagem, a foto existe: sair
	# sem foto aí seria jogar fora uma imagem boa por causa de um estado
	# que mudou depois que ela foi feita.
	var image: Image = null
	if _melhor_imagem != null and _melhor_nota >= CONTRASTE_MINIMO:
		image = _melhor_imagem
		# CONSOME. O melhor quadro pertence À POSE QUE O ESCOLHEU: deixá-lo
		# guardado fazia o TESTAR FOTO da Central devolver a cara de quem
		# jogou a partida anterior, e o técnico concluir que a câmera
		# estava congelada quando ela estava perfeita.
		_melhor_imagem = null
		_melhor_nota = -1.0
	elif available():
		image = _texture.get_image() if _texture != null else (_last_image.duplicate() if _last_image != null else null)
	if image == null or image.is_empty():
		status = "CÂMERA SEM IMAGEM — %s" % motivo_curto()
		return ""
	if not _imagem_util(image):
		# UMA FOTO PRETA É PIOR DO QUE FOTO NENHUMA: o ranking mostra um
		# retângulo escuro no lugar da pessoa e ninguém entende. Sem foto,
		# ao menos a silhueta desenhada diz "não deu".
		status = "IMAGEM SEM CONTRASTE — TAMPA DA LENTE OU SALA ESCURA"
		return ""
	var side := mini(image.get_width(), image.get_height())
	if side <= 0:
		return ""
	var origin := Vector2i((image.get_width() - side) / 2, (image.get_height() - side) / 2)
	image = image.get_region(Rect2i(origin, Vector2i(side, side)))
	if mirrored:
		image.flip_x()
	image.resize(THUMB_SIZE, THUMB_SIZE, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PHOTO_DIR))
	var path := "%s/player_%d.jpg" % [PHOTO_DIR, Time.get_ticks_usec()]
	# A FOTO FICA NA MÃO, e não só no disco.
	#
	# Aqui estava o "ela desliga por um instante para tirar a foto". No
	# quadro do obturador o jogo gravava o JPEG, e logo em seguida a tela
	# PEDIA ESSE MESMO ARQUIVO DE VOLTA para desenhar: abrir, ler,
	# decodificar. São dezenas de milissegundos de ida e volta ao disco no
	# meio da linha do desenho — um quadro perdido bem no instante em que
	# a prévia troca pela foto, e o que se vê é a imagem sumir e voltar.
	# Guardando a imagem que JÁ ESTÁ na memória, a troca é instantânea e o
	# disco vira só o arquivo do ranking.
	ultima_foto = image
	var error := image.save_jpg(path, 0.86)
	if error != OK:
		status = "ERRO AO SALVAR FOTO"
		return ""
	# A FOTO SAIU, MAS DE QUANDO? Guardar a foto é melhor do que não
	# guardar nenhuma — quem joga quer a cara dele no ranking, mesmo com
	# um terço de segundo de atraso. O que não pode é a máquina esconder
	# que fotografou uma imagem parada.
	var idade := idade_do_quadro()
	status = "FOTO OK" if idade < 400 else "FOTO COM IMAGEM DE %d ms ATRÁS" % idade
	return path

func _exit_tree() -> void:
	_stop_feed()
	_esperar_leitura()

func _stop_feed() -> void:
	if _feed != null:
		_feed.set_active(false)
	_feed = null
	_texture = null
	_matar_ponte()
	_native_ok = false

## Derruba o processo da ponte e esquece tudo o que veio dele.
##
## SEMPRE por aqui, e nunca com um `OS.kill` solto: um Python órfão
## segurando a webcam faz a próxima ponte não conseguir abrir a câmera, e
## o sintoma aparece como "câmera não funciona" numa máquina em que a
## câmera está perfeita.
func _matar_ponte() -> void:
	_esperar_leitura()
	if _bridge_pid > 0:
		OS.kill(_bridge_pid)
	_bridge_pid = -1
	_bridge_texture = null
	_last_image = null
	_bridge_digest = 0
	_bridge_contador = -1
	_bridge_contador_ms = 0
	_last_frame_ms = 0

func _start_bridge() -> void:
	if _bridge_pid > 0 or _bridge_desistiu:
		return
	var data_dir := "user://camera_bridge"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	_bridge_path = ProjectSettings.globalize_path(data_dir + "/live.jpg")
	if FileAccess.file_exists(_bridge_path):
		DirAccess.remove_absolute(_bridge_path)
	var script := _materialize_bridge_script(data_dir)
	if script.is_empty():
		status = "PONTE DE CÂMERA NÃO ENCONTRADA"
		return
	var args := PackedStringArray()
	var candidato := _proximo_interpretador()
	if candidato.is_empty():
		status = "NENHUM PYTHON SERVIU — F9 E DIAGNOSTICAR"
		_bridge_desistiu = true
		return
	for a in _args_do_interpretador(candidato):
		args.append(a)
	args.append(script)
	args.append("--output")
	args.append(_bridge_path)
	args.append("--camera")
	args.append(str(selected_index))
	if not backend_preferido.is_empty():
		args.append("--backend")
		args.append(backend_preferido)
		# BACK-END CONHECIDO QUER DIZER ÍNDICE PROVADO: a sondagem
		# descobriu os dois juntos. Daí em diante a ponte insiste nesse
		# número em vez de passear pelos dez — passear leva mais de um
		# minuto por volta, e a pose dura três segundos.
		args.append("--fixo")
	if pattern_mode:
		args.append("--pattern")
	_bridge_pid = OS.create_process(candidato, args, false)
	if _bridge_pid <= 0:
		# Nem criou processo: este nome não existe nesta máquina. Risca e
		# tenta o próximo já no mesmo instante.
		_riscar_interpretador(candidato)
		_start_bridge()
		return
	_interpretador_em_teste = candidato
	_bridge_started_ms = Time.get_ticks_msec()
	status = "INICIANDO PONTE DE CÂMERA…"

## O INTERPRETADOR QUE O JOGO VAI USAR — e por que isto virou uma lista
## com eliminação, em vez de três tentativas em sequência.
##
## AQUI ESTAVA O DEFEITO que fazia a sonda achar a câmera e o jogo não
## mostrar imagem nenhuma.
##
## O diagnóstico procura o Python DIREITO: roda cada candidato com
## `--version` e só aceita quem responder "Python 3". O jogo não fazia
## nada disso — pedia `python` primeiro e dava por bom qualquer PID
## maior que zero. No Windows, `python` quase sempre é o ATALHO DA
## MICROSOFT STORE: ele existe, abre, devolve um PID perfeitamente
## válido, mostra a loja e morre. Para o jogo isso era "a ponte subiu".
## Ela morria, o jogo religava, morria de novo, seis vezes, e desistia —
## enquanto o `py -3` ao lado tinha OpenCV, câmera e tudo funcionando.
##
## E o `py` precisa do `-3`, que também nunca era passado.
##
## Agora um candidato que morre sem publicar quadro é RISCADO, e o
## próximo entra. `py` vem primeiro porque é o lançador oficial; o atalho
## da loja fica por último, onde ele não atrapalha mais ninguém.
## A lista muda com o sistema. `py` é o lançador do Windows e não existe
## em mais lugar nenhum: tentá-lo no Linux só produz um erro no registro
## a cada abertura, e erro no registro que é normal treina quem lê a
## ignorar os que não são.
static func _lista_de_interpretadores() -> Array:
	if OS.get_name() == "Windows":
		return ["py", "python", "python3"]
	return ["python3", "python"]
var _riscados: Array[String] = []
var _interpretador_em_teste := ""
## Preenchido pelo diagnóstico quando ele confirma um Python com OpenCV.
## Tem precedência sobre a lista: já foi provado nesta máquina.
var python_exe := ""
var python_args: PackedStringArray = PackedStringArray()

func _proximo_interpretador() -> String:
	if not python_exe.is_empty() and python_exe not in _riscados:
		return python_exe
	for nome in _lista_de_interpretadores():
		if nome not in _riscados:
			return nome
	return ""

func _args_do_interpretador(nome: String) -> PackedStringArray:
	if nome == python_exe:
		return python_args
	# O lançador oficial do Windows escolhe a versão pelo argumento. Sem
	# `-3` ele pode abrir um Python 2 esquecido na máquina.
	return PackedStringArray(["-3"]) if nome == "py" else PackedStringArray()

func _riscar_interpretador(nome: String) -> void:
	if nome.is_empty() or nome in _riscados:
		return
	_riscados.append(nome)
	if nome == python_exe:
		python_exe = ""

## A linha de estado que a ponte grava ao lado do JPEG, no formato
## `TEXTO|contador|epoch_ms`.
func _bridge_status_line() -> String:
	var caminho := _bridge_path.get_base_dir() + "/estado.txt"
	if not FileAccess.file_exists(caminho):
		return ""
	return FileAccess.get_file_as_string(caminho).strip_edges()

func _bridge_status_file() -> String:
	var linha := _bridge_status_line()
	if linha.is_empty():
		return "PONTE SEM RESPOSTA — INSTALE OPENCV"
	return linha.split("|")[0]

## O contador de quadros publicado pela ponte, ou -1 se ainda não há.
func _bridge_frame_counter() -> int:
	var partes := _bridge_status_line().split("|")
	if partes.size() < 2 or not partes[1].is_valid_int():
		return -1
	return partes[1].to_int()

## Quantas vezes a ponte precisou ser religada nesta sessão. A Central
## mostra: uma ponte que reinicia sozinha o tempo todo é cabo ou porta
## USB com defeito, e não software.
func reinicios_da_ponte() -> int:
	return _bridge_reinicios

## O caminho real do `camera_bridge.py` em disco, materializando-o se
## preciso. O diagnóstico precisa dele para sondar as câmeras, e numa
## exportação com PCK embutido o .py não é um arquivo que o Python
## consiga abrir.
func caminho_da_ponte() -> String:
	var data_dir := "user://camera_bridge"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	return _materialize_bridge_script(data_dir)

## O DIAGNÓSTICO ENTREGA O QUE PROVOU. Índice, back-end e — o que
## faltava — o interpretador. Sem esta última peça o exame dizia
## "câmera 0 pronta via DSHOW" e o jogo continuava tentando abrir a ponte
## com um Python que não tinha OpenCV, ou que nem era Python.
func adotar_python(exe: String, args: PackedStringArray) -> void:
	if exe.is_empty():
		return
	python_exe = exe
	python_args = args.duplicate()
	_riscados.clear()
	_bridge_desistiu = false
	_bridge_reinicios = 0

## O caminho real do inspetor do Windows (`camera_windows.ps1`), pela
## mesma razão da ponte: num pacote exportado ele não é um arquivo que o
## PowerShell consiga abrir.
func caminho_do_inspetor() -> String:
	if OS.get_name() != "Windows":
		return ""
	var data_dir := "user://camera_bridge"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	return _copiar_para_disco("res://tools/camera_windows.ps1", data_dir + "/camera_windows.ps1")

## O INSTALADOR EM JANELA À PARTE FOI REMOVIDO.
##
## Ele abria o PowerShell com `-NoExit` para o operador acompanhar. Num
## gabinete em tela cheia essa janela nasce ATRÁS do jogo: quem apertava
## não via nada acontecer e concluía, com razão, que o botão não fazia
## nada. Quem faz esse serviço agora é o RESOLVER TUDO da Central, que
## roda em linha própria e escreve cada passo na própria tela.
##
func _copiar_para_disco(origem: String, destino: String) -> String:
	var fonte := FileAccess.open(origem, FileAccess.READ)
	if fonte == null:
		return ""
	var alvo := FileAccess.open(destino, FileAccess.WRITE)
	if alvo == null:
		return ""
	alvo.store_string(fonte.get_as_text())
	alvo.close()
	return ProjectSettings.globalize_path(destino)

func _materialize_bridge_script(data_dir: String) -> String:
	# Em exportação com PCK embutido o .py não é um arquivo físico. Copiá-lo
	# para user:// dá ao processo Python um caminho real e gravável.
	var source := FileAccess.open("res://tools/camera_bridge.py", FileAccess.READ)
	if source == null:
		return ""
	var target_path := data_dir + "/camera_bridge.py"
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return ""
	target.store_string(source.get_as_text())
	target.close()
	return ProjectSettings.globalize_path(target_path)
