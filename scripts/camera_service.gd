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
## Vigia do caminho nativo: quando o feed foi ativado e se ele já provou
## que entrega quadro.
var _native_started_ms := 0
var _native_ok := false
var status := "PROCURANDO CÂMERA"
## Publica um padrão sintético em vez da webcam. Serve para separar
## "a ponte está quebrada" de "a câmera está quebrada" sem webcam
## nenhuma — mesma ideia do comando TEST do firmware do sensor.
var pattern_mode := false

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
		return
	var imagem := _texture.get_image() if _texture != null else null
	if imagem != null and not imagem.is_empty():
		_native_ok = true
		_last_image = imagem
		_last_frame_ms = Time.get_ticks_msec()
		status = "CÂMERA CONECTADA (NATIVA)"
		return
	if Time.get_ticks_msec() - _native_started_ms > 2500:
		_stop_feed()
		status = "CÂMERA NATIVA MUDA — TENTANDO A PONTE"
		_start_bridge()

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

func capture_photo() -> String:
	if not available():
		return ""
	var image: Image = _texture.get_image() if _texture != null else (_last_image.duplicate() if _last_image != null else null)
	if image == null or image.is_empty():
		status = "CÂMERA SEM IMAGEM"
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
