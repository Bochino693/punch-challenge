extends SceneTree

func _initialize() -> void:
	_test_score_curve()
	_test_ranking_migration_and_ties()
	_test_statistics()
	_test_top20()
	print("CORE_TESTS_OK")
	quit(0)

func _test_top20() -> void:
	var entries: Array[Dictionary] = []
	for score in range(100, 350, 10):
		entries.assign(RankingStore.insert(entries, score)["entries"])
	assert(entries.size() == 20)
	assert(RankingStore.score_at(entries, 19) == 150)
	var inserted := RankingStore.insert(entries, 155)
	assert(int(inserted["position"]) == 20)
	assert(int(RankingStore.insert(entries, 10)["position"]) == 0)

func _test_score_curve() -> void:
	assert(ScoreCurve.points_from_speed(0.2, 0.8, 12.0, 2.0, 0.06) == 0)
	assert(ScoreCurve.points_from_speed(0.8, 0.8, 12.0, 2.0, 0.06) == 0)
	assert(ScoreCurve.points_from_speed(12.0, 0.8, 12.0, 2.0, 0.06) == 999)
	var previous := -1
	for i in range(121):
		var speed := float(i) / 10.0
		var points := ScoreCurve.points_from_speed(speed, 0.8, 12.0, 2.0, 0.06)
		assert(points >= previous)
		previous = points
	assert(ScoreCurve.points_from_charge(0.2, 0.8, 12.0, 2.0, 0.06) < 30)
	assert(ScoreCurve.points_from_charge(1.3, 0.8, 12.0, 2.0, 0.06) < 500)
	assert(ScoreCurve.points_from_charge(2.0, 0.8, 12.0, 2.0, 0.06) >= 700)
	assert(ScoreCurve.points_from_charge(2.8, 0.8, 12.0, 2.0, 0.06) == 999)
	for tenths in range(29):
		var seconds := float(tenths) / 10.0
		var virtual_speed := ScoreCurve.speed_from_charge(seconds, 0.8, 12.0)
		assert(
			ScoreCurve.points_from_charge(seconds, 0.8, 12.0, 2.0, 0.06)
			== ScoreCurve.points_from_speed(virtual_speed, 0.8, 12.0, 2.0, 0.06)
		)

func _test_ranking_migration_and_ties() -> void:
	var legacy := RankingStore.migrate([900, 700, 500], 0)
	assert(legacy.size() == 3)
	assert(RankingStore.best(legacy) == 900)
	var first := RankingStore.insert(legacy, 700, "", "TESTE")
	assert(int(first["position"]) == 3)
	var entries: Array[Dictionary] = first["entries"]
	var top := RankingStore.insert(entries, 950, "", "TESTE")
	assert(int(top["position"]) == 1)
	assert((top["entries"] as Array).size() <= RankingStore.LIMIT)

func _test_statistics() -> void:
	var stats := StatisticsStore.record({}, 500, GameDef.Faixa.MEDIA, true)
	stats = StatisticsStore.record(stats, 800, GameDef.Faixa.FORTE, false)
	var summary := StatisticsStore.summary(stats)
	assert(int(summary["today"]) == 2)
	assert(int(summary["average"]) == 650)
	assert(int(summary["best"]) == 800)
	assert(int(summary["top5_entries"]) == 1)
