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
	if _bridge_pid <= 0:
		return
	var now := Time.get_ticks_msec()
	if now < _next_bridge_poll_ms:
		return
	_next_bridge_poll_ms = now + 100
	if not OS.is_process_running(_bridge_pid):
		_bridge_texture = null
		_last_image = null
		status = "CÂMERA DESCONECTADA"
		return
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

func refresh() -> void:
	_stop_feed()
	if not enabled:
		status = "CÂMERA DESATIVADA"
		return
	var feeds := CameraServer.feeds()
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
	status = "CÂMERA CONECTADA"

func _on_camera_feeds_updated(_id: int = 0) -> void:
	if enabled and _feed == null and _bridge_pid <= 0:
		refresh()

func set_enabled(value: bool) -> void:
	enabled = value
	refresh()

func cycle_camera() -> void:
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
	var native_ok := _texture != null and _feed != null and _feed.is_active()
	return enabled and (native_ok or (_bridge_texture != null and Time.get_ticks_msec() - _last_frame_ms < 2500))

func camera_count() -> int:
	return CameraServer.get_feed_count()

func capture_photo() -> String:
	if not available():
		return ""
	var image: Image = _texture.get_image() if _texture != null else _last_image.duplicate()
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
	if _bridge_pid > 0:
		OS.kill(_bridge_pid)
	_bridge_pid = -1
	_bridge_texture = null
	_last_image = null
	_bridge_digest = 0
	_last_frame_ms = 0

func _start_bridge() -> void:
	if _bridge_pid > 0:
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

## Lê a linha de estado que a ponte grava ao lado do JPEG.
func _bridge_status_file() -> String:
	var caminho := _bridge_path.get_base_dir() + "/estado.txt"
	if not FileAccess.file_exists(caminho):
		return "PONTE SEM RESPOSTA — INSTALE OPENCV"
	var texto := FileAccess.get_file_as_string(caminho).strip_edges()
	return texto if not texto.is_empty() else "PONTE SEM RESPOSTA"

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
