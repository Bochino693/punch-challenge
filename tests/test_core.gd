extends SceneTree

const VMIN := 1.2
const VMAX := 16.0
const EXPO := 2.80
const DZ := 0.08

func _initialize() -> void:
	_test_score_curve()
	_test_ranking_migration_and_ties()
	_test_schema_migration()
	_test_statistics()
	_test_top20()
	_test_format()
	print("CORE_TESTS_OK")
	quit(0)

func _test_top20() -> void:
	var entries: Array[Dictionary] = []
	for score in range(1000, 3500, 100):
		entries.assign(RankingStore.insert(entries, score)["entries"])
	assert(entries.size() == 20)
	assert(RankingStore.score_at(entries, 19) == 1500)
	var inserted := RankingStore.insert(entries, 1550)
	assert(int(inserted["position"]) == 20)
	assert(int(RankingStore.insert(entries, 100)["position"]) == 0)

func _test_score_curve() -> void:
	# Zona morta: nada pontua até vmin + dz * (vmax - vmin) = 2.384 m/s.
	assert(ScoreCurve.points_from_speed(0.0, VMIN, VMAX, EXPO, DZ) == 0)
	assert(ScoreCurve.points_from_speed(VMIN, VMIN, VMAX, EXPO, DZ) == 0)
	assert(ScoreCurve.points_from_speed(2.38, VMIN, VMAX, EXPO, DZ) == 0)
	# 9999 só no teto: abaixo de vmax nunca chega lá.
	assert(ScoreCurve.points_from_speed(VMAX, VMIN, VMAX, EXPO, DZ) == 9999)
	assert(ScoreCurve.points_from_speed(VMAX + 3.0, VMIN, VMAX, EXPO, DZ) == 9999)
	assert(ScoreCurve.points_from_speed(VMAX - 0.05, VMIN, VMAX, EXPO, DZ) < 9999)
	# Monotônica do início ao fim.
	var previous := -1
	for i in range(301):
		var speed := float(i) / 10.0
		var points := ScoreCurve.points_from_speed(speed, VMIN, VMAX, EXPO, DZ)
		assert(points >= previous)
		previous = points
	# Contínua na saída da zona morta: primeiro ponto depois dela é baixo.
	assert(ScoreCurve.points_from_speed(2.45, VMIN, VMAX, EXPO, DZ) < 60)
	# Sanitização respeita os limites reguláveis da Central.
	var cfg := ScoreCurve.sanitize(99.0, 1.0, 99.0, 9.0)
	assert(float(cfg["min_speed"]) == ScoreCurve.VMIN_MAX)
	assert(float(cfg["max_speed"]) >= float(cfg["min_speed"]))
	assert(float(cfg["exponent"]) == ScoreCurve.EXPONENT_MAX)
	assert(float(cfg["dead_zone"]) == ScoreCurve.DEAD_ZONE_MAX)
	# Simulação de bancada passa pela mesma curva do sensor.
	assert(ScoreCurve.points_from_charge(0.2, VMIN, VMAX, EXPO, DZ) < 300)
	assert(ScoreCurve.points_from_charge(2.8, VMIN, VMAX, EXPO, DZ) == 9999)
	for tenths in range(29):
		var seconds := float(tenths) / 10.0
		var virtual_speed := ScoreCurve.speed_from_charge(seconds, VMIN, VMAX)
		assert(
			ScoreCurve.points_from_charge(seconds, VMIN, VMAX, EXPO, DZ)
			== ScoreCurve.points_from_speed(virtual_speed, VMIN, VMAX, EXPO, DZ)
		)

func _test_ranking_migration_and_ties() -> void:
	var legacy := RankingStore.migrate([9000, 7000, 5000], 0)
	assert(legacy.size() == 3)
	assert(RankingStore.best(legacy) == 9000)
	var first := RankingStore.insert(legacy, 7000, "", "TESTE")
	assert(int(first["position"]) == 3)
	var entries: Array[Dictionary] = first["entries"]
	var top := RankingStore.insert(entries, 9500, "", "TESTE")
	assert(int(top["position"]) == 1)
	assert((top["entries"] as Array).size() <= RankingStore.LIMIT)
	# A foto viaja junto com a entrada certa, mesmo em empate: o segundo
	# 7000 entra DEPOIS do primeiro (desempate por horário).
	var com_foto := RankingStore.insert(entries, 7000, "user://ranking_photos/p.jpg", "TESTE")
	var pos := int(com_foto["position"])
	assert(pos == 4)
	assert(str((com_foto["entries"] as Array)[pos - 1].get("photo_path", "")) == "user://ranking_photos/p.jpg")

func _test_schema_migration() -> void:
	# Dados legados 0–999 viram 0–9999 multiplicando por dez, UMA vez.
	var legado := {
		"ranking": [{"score": 900, "photo_path": "user://ranking_photos/a.jpg"}, 700, 50],
		"best_score": 900,
		"statistics": {"days": {"2025-01-01": {"plays": 2, "score_sum": 1000, "best": 700}}},
	}
	var migrado := RankingStore.migrate_settings(legado)
	assert(int(migrado["schema_version"]) == RankingStore.SCHEMA_VERSION)
	var ranking: Array = migrado["ranking"]
	assert(int((ranking[0] as Dictionary)["score"]) == 9000)
	assert(int(ranking[1]) == 7000)
	assert(int(migrado["best_score"]) == 9000)
	var stats: Dictionary = migrado["statistics"]
	var dia: Dictionary = (stats["days"] as Dictionary)["2025-01-01"]
	assert(int(dia["best"]) == 7000)
	assert(int(dia["score_sum"]) == 10000)
	# Chamar de novo NÃO multiplica outra vez.
	var de_novo := RankingStore.migrate_settings(migrado)
	assert(int((de_novo["ranking"] as Array)[1]) == 7000)
	assert(int(de_novo["best_score"]) == 9000)

func _test_statistics() -> void:
	var stats := StatisticsStore.record({}, 5000, GameDef.band_of(5000), true)
	stats = StatisticsStore.record(stats, 8000, GameDef.band_of(8000), false)
	var summary := StatisticsStore.summary(stats)
	assert(int(summary["today"]) == 2)
	assert(int(summary["average"]) == 6500)
	assert(int(summary["best"]) == 8000)
	assert(int(summary["top5_entries"]) == 1)

func _test_format() -> void:
	# Todo valor visual da máquina usa quatro dígitos.
	assert(GameDef.fmt_score(0) == "0000")
	assert(GameDef.fmt_score(950) == "0950")
	assert(GameDef.fmt_score(9999) == "9999")
	assert(GameDef.SCORE_MAX == 9999)
