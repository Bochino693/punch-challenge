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
## TETO DE RELIGAMENTOS. Sem ele, uma máquina sem Python entra num laço:
## o processo morre no mesmo instante em que nasce, o jogo o ressuscita,
## e assim a noite inteira — com o motivo verdadeiro (falta o OpenCV)
## sumindo no meio de mil reinícios.
const MAX_RELIGAMENTOS := 6
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
	call_deferred("refresh")

func _process(_delta: float) -> void:
	if _feed != null:
		_vigiar_nativa()
		return
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
		# O PROCESSO MORREU: ressuscita. Antes a máquina só anunciava
		# "desconectada" e ficava assim até alguém reiniciar o jogo — num
		# salão, isso é a noite inteira sem foto no ranking.
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
		if now - _bridge_contador_ms > 3000 and _bridge_texture != null:
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
	var bytes := FileAccess.get_file_as_bytes(_bridge_path) if FileAccess.file_exists(_bridge_path) else PackedByteArray()
	var digest := hash(bytes)
	if not bytes.is_empty() and digest != _bridge_digest:
		var image := Image.new()
		if image.load_jpg_from_buffer(bytes) == OK and not image.is_empty():
			_bridge_digest = digest
			_last_frame_ms = now
			_last_image = image
			_oferecer_ao_obturador(image)
			if _bridge_texture == null:
				_bridge_texture = ImageTexture.create_from_image(image)
			else:
				_bridge_texture.update(image)
			status = "CÂMERA CONECTADA (PONTE)"
	elif now - _bridge_started_ms > 5000 and _bridge_texture == null:
		# A ponte escreve o motivo ao lado do JPEG; sem ler esse arquivo,
		# todo problema virava a mesma mensagem genérica e o técnico não
		# sabia se era OpenCV, cabo ou câmera ocupada.
		status = _bridge_status_file()

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

func refresh() -> void:
	_stop_feed()
	_native_ok = false
	# Toda tentativa manual (ligar, trocar de câmera, reabrir a Central)
	# tem direito a uma bateria nova de religamentos: quem clicou está
	# dizendo que alguma coisa mudou.
	_bridge_desistiu = false
	_bridge_reinicios = 0
	if not enabled:
		status = "CÂMERA DESATIVADA"
		return
	# O GODOT 4.6 SÓ ENUMERA CÂMERAS SOB PEDIDO.
	#
	# Até a 4.5 `CameraServer.feeds()` já vinha preenchido; na 4.6 o
	# servidor começa dormindo e responde
	# "CameraServer is not actively monitoring feeds" — a lista volta
	# vazia e a máquina conclui, errado, que não há câmera nenhuma.
	# Ligar o monitoramento é barato e idempotente.
	_acordar_servidor()
	var feeds: Array = [] if forcar_ponte else CameraServer.feeds()
	if feeds.is_empty():
		# A PONTE NÃO É MAIS SÓ DO WINDOWS. Ela é a reserva para QUALQUER
		# caso em que o Godot não enxerga a webcam — e são vários: falta
		# de driver na plataforma, permissão negada, câmera ocupada por
		# outro programa. Amarrada ao Windows, todo o resto ficava sem
		# saída, e ninguém conseguia nem testar o caminho.
		_start_bridge()
		return
	selected_index = clampi(selected_index, 0, feeds.size() - 1)
	_feed = feeds[selected_index]
	# ESCOLHER O FORMATO ANTES DE ATIVAR. Nas plataformas em que o Godot
	# fala com a câmera de verdade (V4L2 no Linux, Media Foundation no
	# Windows), um feed sem formato escolhido ativa mas nunca entrega
	# quadro — fica "conectada" e preta. Pegamos o primeiro formato que a
	# câmera anuncia, que é sempre um que ela suporta.
	var formatos := _feed.get_formats()
	if not formatos.is_empty():
		_feed.set_format(0, {})
	_feed.set_active(true)
	_texture = CameraTexture.new()
	_texture.camera_feed_id = _feed.get_id()
	_texture.which_feed = CameraServer.FEED_RGBA_IMAGE
	_native_started_ms = Time.get_ticks_msec()
	status = "ABRINDO CÂMERA…"

func _on_camera_feeds_updated(_id: int = 0) -> void:
	if enabled and _feed == null and _bridge_pid <= 0:
		refresh()

func set_enabled(value: bool) -> void:
	enabled = value
	refresh()

func cycle_camera() -> void:
	# O GODOT 4.6 SÓ ENUMERA CÂMERAS SOB PEDIDO.
	#
	# Até a 4.5 `CameraServer.feeds()` já vinha preenchido; na 4.6 o
	# servidor começa dormindo e responde
	# "CameraServer is not actively monitoring feeds" — a lista volta
	# vazia e a máquina conclui, errado, que não há câmera nenhuma.
	# Ligar o monitoramento é barato e idempotente.
	_acordar_servidor()
	var feeds := CameraServer.feeds()
	if feeds.is_empty():
		# Sem feed nativo, quem troca de câmera é a ponte: os índices
		# 0..3 cobrem as webcams que o sistema costuma enumerar.
		selected_index = (selected_index + 1) % 4
		refresh()
		return
	selected_index = (selected_index + 1) % feeds.size()
	refresh()

func preview_texture() -> Texture2D:
	return _texture if _texture != null else _bridge_texture

func available() -> bool:
	if not enabled:
		return false
	# "Disponível" é ter QUADRO, e não ter feed aberto: era por confiar em
	# `is_active()` que a máquina anunciava câmera e fotografava preto.
	if _feed != null:
		return _native_ok
	return _bridge_texture != null and Time.get_ticks_msec() - _last_frame_ms < 2500

func camera_count() -> int:
	return CameraServer.get_feed_count()

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
	var args := PackedStringArray([script, "--output", _bridge_path, "--camera", str(selected_index)])
	if not backend_preferido.is_empty():
		args.append("--backend")
		args.append(backend_preferido)
	if pattern_mode:
		args.append("--pattern")
	# Três nomes de interpretador, porque cada instalação de Windows
	# expõe um: `python` (loja/PATH), `py` (o lançador oficial) e
	# `python3` (Linux e macOS).
	for interpretador in ["python", "python3", "py"]:
		_bridge_pid = OS.create_process(interpretador, args, false)
		if _bridge_pid > 0:
			break
	if _bridge_pid <= 0:
		status = "PYTHON NÃO ENCONTRADO — VEJA docs/CAMERA.md"
		return
	_bridge_started_ms = Time.get_ticks_msec()
	status = "INICIANDO PONTE DE CÂMERA…"

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

## O caminho real do inspetor do Windows (`camera_windows.ps1`), pela
## mesma razão da ponte: num pacote exportado ele não é um arquivo que o
## PowerShell consiga abrir.
func caminho_do_inspetor() -> String:
	if OS.get_name() != "Windows":
		return ""
	var data_dir := "user://camera_bridge"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	return _copiar_para_disco("res://tools/camera_windows.ps1", data_dir + "/camera_windows.ps1")

## RODA O INSTALADOR DA CÂMERA, do próprio jogo.
##
## Existe porque o operador do salão não é quem abre PowerShell. A
## mensagem "instale o OpenCV" é correta e inútil para quem está na
## frente do gabinete às onze da noite: o botão faz o que a mensagem
## pede.
##
## Só no Windows — no Linux e no macOS o OpenCV entra pelo gerenciador de
## pacotes do sistema, e um script de PowerShell ali não teria sentido.
func instalar_dependencias() -> String:
	if OS.get_name() != "Windows":
		return "INSTALAÇÃO AUTOMÁTICA SÓ NO WINDOWS — VEJA docs/CAMERA.md"
	var data_dir := "user://camera_bridge"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	# O .py precisa estar ao lado do .ps1: o instalador procura a ponte na
	# própria pasta para poder sondar as câmeras no fim.
	_materialize_bridge_script(data_dir)
	var script := _copiar_para_disco("res://tools/instalar_camera_windows.ps1", data_dir + "/instalar_camera_windows.ps1")
	if script.is_empty():
		return "INSTALADOR NÃO ENCONTRADO NO PACOTE"
	var pid := OS.create_process("powershell", PackedStringArray([
		"-NoExit", "-ExecutionPolicy", "Bypass", "-File", script,
	]), false)
	if pid <= 0:
		return "NÃO FOI POSSÍVEL ABRIR O POWERSHELL"
	# `-NoExit` de propósito: a janela FICA ABERTA no fim. Fechando
	# sozinha, o resultado da sondagem de câmeras — que é a informação
	# mais útil da tela toda — passaria voando.
	return "INSTALADOR ABERTO NUMA JANELA À PARTE — ACOMPANHE POR LÁ"

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
