class_name RankingStore
extends RefCounted

const LIMIT := 20
const PHOTO_DIR := "user://ranking_photos"

static func migrate(raw: Variant, old_best := 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw is Array:
		for item in raw:
			if item is Dictionary:
				var entry := _sanitize_entry(item)
				if int(entry["score"]) > 0:
					result.append(entry)
			else:
				var score := clampi(int(item), 0, GameDef.SCORE_MAX)
				if score > 0:
					result.append(_new_entry(score, "", "LEGADO"))
	if result.is_empty() and old_best > 0:
		result.append(_new_entry(clampi(old_best, 0, GameDef.SCORE_MAX), "", "LEGADO"))
	result.sort_custom(_higher_score)
	if result.size() > LIMIT:
		result.resize(LIMIT)
	return result

static func insert(entries: Array[Dictionary], score: int, photo_path := "", source := "SENSOR") -> Dictionary:
	var next := entries.duplicate(true)
	var entry := _new_entry(clampi(score, 0, GameDef.SCORE_MAX), photo_path, source)
	# O id identifica a tentativa, então empates nunca roubam a posição
	# da pessoa errada como acontecia com Array.find(pontos).
	next.append(entry)
	next.sort_custom(_higher_score)
	var position := 0
	for i in range(next.size()):
		if str(next[i]["id"]) == str(entry["id"]):
			position = i + 1
			break
	var dropped: Array[String] = []
	while next.size() > LIMIT:
		var removed: Dictionary = next.pop_back()
		var path := str(removed.get("photo_path", ""))
		if not path.is_empty():
			dropped.append(path)
	if position > LIMIT:
		position = 0
	return {"entries": next, "position": position, "dropped_photos": dropped}

static func best(entries: Array[Dictionary]) -> int:
	return int(entries[0].get("score", 0)) if not entries.is_empty() else 0

static func score_at(entries: Array[Dictionary], index: int) -> int:
	if index < 0 or index >= entries.size():
		return 0
	return int(entries[index].get("score", 0))

static func delete_photo(path: String) -> void:
	if path.begins_with(PHOTO_DIR) and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

static func clear_photos(entries: Array[Dictionary]) -> void:
	for entry in entries:
		delete_photo(str(entry.get("photo_path", "")))

static func _new_entry(score: int, photo_path: String, source: String) -> Dictionary:
	return {
		"id": "%d-%d" % [Time.get_ticks_usec(), randi()],
		"score": score,
		"photo_path": photo_path,
		"created_at": Time.get_datetime_string_from_system(false, true),
		"source": source,
	}

static func _sanitize_entry(value: Dictionary) -> Dictionary:
	var entry := value.duplicate(true)
	entry["id"] = str(entry.get("id", "%d-%d" % [Time.get_ticks_usec(), randi()]))
	entry["score"] = clampi(int(entry.get("score", 0)), 0, GameDef.SCORE_MAX)
	entry["photo_path"] = str(entry.get("photo_path", ""))
	entry["created_at"] = str(entry.get("created_at", ""))
	entry["source"] = str(entry.get("source", "LEGADO"))
	return entry

static func _higher_score(a: Dictionary, b: Dictionary) -> bool:
	var score_a := int(a.get("score", 0))
	var score_b := int(b.get("score", 0))
	if score_a == score_b:
		return str(a.get("created_at", "")) < str(b.get("created_at", ""))
	return score_a > score_b
