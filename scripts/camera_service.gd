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
var _bridge_started_ms := 0
var _next_bridge_poll_ms := 0
var status := "PROCURANDO CÂMERA"

func _ready() -> void:
	if not CameraServer.camera_feeds_updated.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feeds_updated.connect(_on_camera_feeds_updated)
	set_process(true)
	call_deferred("refresh")

func _process(_delta: float) -> void:
	if _bridge_pid <= 0:
		return
	var now := Time.get_ticks_msec()
	if now < _next_bridge_poll_ms:
		return
	_next_bridge_poll_ms = now + 100
	var modified := FileAccess.get_modified_time(_bridge_path)
	if modified > 0 and modified != _bridge_modified:
		var image := Image.new()
		if image.load(_bridge_path) == OK and not image.is_empty():
			_bridge_modified = modified
			_last_image = image
			if _bridge_texture == null:
				_bridge_texture = ImageTexture.create_from_image(image)
			else:
				_bridge_texture.update(image)
			status = "CÂMERA CONECTADA (WINDOWS)"
	elif now - _bridge_started_ms > 5000 and _bridge_texture == null:
		status = "CÂMERA WINDOWS: INSTALE OPENCV"

func refresh() -> void:
	_stop_feed()
	if not enabled:
		status = "CÂMERA DESATIVADA"
		return
	CameraServer.set_monitoring_feeds(true)
	var feeds := CameraServer.feeds()
	if feeds.is_empty():
		if OS.get_name() == "Windows":
			_start_windows_bridge()
		else:
			status = "CÂMERA INDISPONÍVEL"
		return
	selected_index = clampi(selected_index, 0, feeds.size() - 1)
	_feed = feeds[selected_index]
	_feed.set_active(true)
	_texture = CameraTexture.new()
	_texture.camera_feed_id = _feed.get_id()
	_texture.which_feed = 0
	status = "CÂMERA CONECTADA"

func _on_camera_feeds_updated() -> void:
	if enabled and _feed == null and _bridge_pid <= 0:
		refresh()

func set_enabled(value: bool) -> void:
	enabled = value
	refresh()

func cycle_camera() -> void:
	var feeds := CameraServer.feeds()
	if feeds.is_empty():
		if OS.get_name() == "Windows":
			# DirectShow normalmente enumera câmeras como 0..3. As que não
			# existem simplesmente acionam o fallback, sem travar o jogo.
			selected_index = (selected_index + 1) % 4
		refresh()
		return
	selected_index = (selected_index + 1) % feeds.size()
	refresh()

func preview_texture() -> Texture2D:
	return _texture if _texture != null else _bridge_texture

func available() -> bool:
	var native_ok := _texture != null and _feed != null and _feed.is_active()
	return enabled and (native_ok or _bridge_texture != null)

func camera_count() -> int:
	CameraServer.set_monitoring_feeds(true)
	return CameraServer.feeds().size()

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
	CameraServer.set_monitoring_feeds(false)

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

func _start_windows_bridge() -> void:
	if _bridge_pid > 0:
		return
	var data_dir := "user://camera_bridge"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	_bridge_path = ProjectSettings.globalize_path(data_dir + "/live.jpg")
	var script := _materialize_bridge_script(data_dir)
	if script.is_empty():
		status = "PONTE DE CÂMERA NÃO ENCONTRADA"
		return
	var args := PackedStringArray([script, "--output", _bridge_path, "--camera", str(selected_index)])
	_bridge_pid = OS.create_process("python", args, false)
	if _bridge_pid <= 0:
		args.insert(0, "-3")
		_bridge_pid = OS.create_process("py", args, false)
	if _bridge_pid <= 0:
		status = "PYTHON/OPENCV NÃO ENCONTRADO"
		return
	_bridge_started_ms = Time.get_ticks_msec()
	status = "INICIANDO CÂMERA WINDOWS…"

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
