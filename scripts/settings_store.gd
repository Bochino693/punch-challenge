class_name SettingsStore
extends RefCounted

## Persistência em user:// com gravação segura: escreve num arquivo
## temporário e só então renomeia por cima do oficial. Se a máquina
## desligar no meio da escrita, o arquivo antigo continua intacto.

const PATH := "user://punch_challenge_settings.json"
const PATH_TMP := "user://punch_challenge_settings.tmp"

static func load_data() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

static func save_data(data: Dictionary) -> bool:
	var tmp := FileAccess.open(PATH_TMP, FileAccess.WRITE)
	if tmp == null:
		return false
	tmp.store_string(JSON.stringify(data, "\t"))
	tmp.close()
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(PATH_TMP),
		ProjectSettings.globalize_path(PATH)
	)
	if err != OK:
		# Windows não renomeia por cima de arquivo existente em alguns casos.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
		err = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(PATH_TMP),
			ProjectSettings.globalize_path(PATH)
		)
	return err == OK
