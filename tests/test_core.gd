extends SceneTree

## Testes de núcleo: curva, níveis, ranking e estatística. Puros — não
## abrem cena nem tocam áudio. O fluxo da máquina é testado em
## `tests/test_show_flow.gd`.

func _initialize() -> void:
	_test_escala_e_niveis()
	_test_curva_monotonica()
	_test_zona_morta_e_teto()
	_test_migracao_acontece_uma_vez()
	_test_top20_guarda_vinte_e_a_foto_certa()
	_test_statistics()
	print("CORE_TESTS_OK")
	quit(0)

# ------------------------------------------------------------ escala
func _test_escala_e_niveis() -> void:
	assert(GameDef.SCORE_MAX == 9999)
	assert(ScoreTier.PERFEITO == GameDef.SCORE_MAX)
	# As oito faixas cobrem 0..9999 sem buraco e sem sobreposição.
	var esperado := 0
	for nivel in ScoreTier.NIVEIS:
		assert(int(nivel["min"]) == esperado)
		assert(int(nivel["max"]) >= int(nivel["min"]))
		esperado = int(nivel["max"]) + 1
	assert(esperado == GameDef.SCORE_MAX + 1)
	assert(ScoreTier.NIVEIS.size() == 8)
	# Cada nível tem apresentação PRÓPRIA: nenhum par pode compartilhar a
	# mesma receita de efeito, senão dois níveis leem igual na tela.
	var assinaturas := {}
	for nivel in ScoreTier.NIVEIS:
		var chave := "%s|%.2f|%.2f|%.3f|%d|%d|%d" % [
			str(nivel["cor"]), nivel["tremor"], nivel["clarao"], nivel["hitstop"],
			int(nivel["ondas"]), int(nivel["brasas"]), int(nivel["raios"]),
		]
		assert(not assinaturas.has(chave))
		assinaturas[chave] = true
		assert(not str(nivel["som"]).is_empty())
	assert(ScoreTier.nome_de(0) == "IMPACTO LEVE")
	assert(ScoreTier.nome_de(9999) == "SOCO PERFEITO")
	assert(ScoreTier.nome_de(9998) == "LENDÁRIO")
	# As três faixas grossas continuam derivando dos níveis.
	assert(GameDef.faixa_de(0) == GameDef.Faixa.FRACA)
	assert(GameDef.faixa_de(4500) == GameDef.Faixa.MEDIA)
	assert(GameDef.faixa_de(9999) == GameDef.Faixa.FORTE)

# ------------------------------------------------------------ curva
func _test_curva_monotonica() -> void:
	var vmin := ScoreCurve.DEFAULT_MIN_SPEED
	var vmax := ScoreCurve.DEFAULT_MAX_SPEED
	var g := ScoreCurve.DEFAULT_EXPONENT
	var dz := ScoreCurve.DEFAULT_DEAD_ZONE
	var anterior := -1
	# Passo fino, e além do teto: um soco mais forte NUNCA pode valer menos.
	for i in range(0, 2001):
		var v := float(i) * 0.02
		var pts := ScoreCurve.points_from_speed(v, vmin, vmax, g, dz)
		assert(pts >= anterior)
		assert(pts >= 0 and pts <= GameDef.SCORE_MAX)
		anterior = pts
	# Monotônica também em relação ao expoente: mais dificuldade, nunca
	# mais pontos, para a mesma velocidade.
	var meio := (vmin + vmax) * 0.5
	var facil := ScoreCurve.points_from_speed(meio, vmin, vmax, 1.5, dz)
	var duro := ScoreCurve.points_from_speed(meio, vmin, vmax, 4.5, dz)
	assert(facil >= duro)
	# A amostragem que a Central desenha também é monotônica.
	var curva := ScoreCurve.amostrar(vmin, vmax, g, dz, 60)
	var ultimo := -1.0
	for ponto in curva:
		assert((ponto as Vector2).y >= ultimo)
		ultimo = (ponto as Vector2).y

func _test_zona_morta_e_teto() -> void:
	var vmin := ScoreCurve.DEFAULT_MIN_SPEED
	var vmax := ScoreCurve.DEFAULT_MAX_SPEED
	var g := ScoreCurve.DEFAULT_EXPONENT
	var dz := ScoreCurve.DEFAULT_DEAD_ZONE
	# Abaixo e no piso: zero. Dentro da zona morta: ainda zero.
	assert(ScoreCurve.points_from_speed(0.0, vmin, vmax, g, dz) == 0)
	assert(ScoreCurve.points_from_speed(vmin, vmin, vmax, g, dz) == 0)
	var span := vmax - vmin
	assert(ScoreCurve.points_from_speed(vmin + span * dz * 0.5, vmin, vmax, g, dz) == 0)
	assert(ScoreCurve.points_from_speed(vmin + span * dz, vmin, vmax, g, dz) == 0)
	# Logo acima da zona morta a nota ainda é desprezível — é o expoente
	# fazendo o seu trabalho — mas na metade da escala já existe placar.
	assert(ScoreCurve.points_from_speed(vmin + span * 0.5, vmin, vmax, g, dz) > 0)
	# 9999 SÓ no teto. Uma pancada comum, mesmo forte, não chega lá.
	assert(ScoreCurve.points_from_speed(vmax, vmin, vmax, g, dz) == GameDef.SCORE_MAX)
	assert(ScoreCurve.points_from_speed(vmax * 2.0, vmin, vmax, g, dz) == GameDef.SCORE_MAX)
	assert(ScoreCurve.points_from_speed(vmax * 0.90, vmin, vmax, g, dz) < GameDef.SCORE_MAX)
	assert(ScoreCurve.points_from_speed(vmax * 0.75, vmin, vmax, g, dz) < 9000)

# ------------------------------------------------------------ ranking
func _test_migracao_acontece_uma_vez() -> void:
	# Arquivo antigo, escala 0 a 999, sem versão gravada.
	var antigo := [{"score": 900}, {"score": 500}, 250]
	var convertido := RankingStore.migrate(antigo, 0, RankingStore.ESQUEMA_LEGADO)
	assert(RankingStore.best(convertido) == 9000)
	assert(RankingStore.score_at(convertido, 1) == 5000)
	assert(RankingStore.score_at(convertido, 2) == 2500)
	# Reabrir JÁ CONVERTIDO não pode multiplicar de novo.
	var reaberto := RankingStore.migrate(convertido, 0, RankingStore.ESQUEMA)
	assert(RankingStore.best(reaberto) == 9000)
	var terceira := RankingStore.migrate(reaberto, 0, RankingStore.ESQUEMA)
	assert(RankingStore.best(terceira) == 9000)
	# O recorde solto de instalações muito antigas também converte uma vez.
	var so_recorde := RankingStore.migrate([], 870, RankingStore.ESQUEMA_LEGADO)
	assert(RankingStore.best(so_recorde) == 8700)
	# E a conversão respeita o teto.
	var estourado := RankingStore.migrate([{"score": 999}], 0, RankingStore.ESQUEMA_LEGADO)
	assert(RankingStore.best(estourado) == 9990)

func _test_top20_guarda_vinte_e_a_foto_certa() -> void:
	var entries: Array[Dictionary] = []
	for score in range(1000, 3500, 100):
		entries.assign(RankingStore.insert(entries, score, "foto_%d.png" % score)["entries"])
	assert(entries.size() == RankingStore.LIMIT)
	# A foto acompanha a marca, e não o índice.
	for entrada in entries:
		assert(str(entrada["photo_path"]) == "foto_%d.png" % int(entrada["score"]))
	assert(RankingStore.score_at(entries, 0) == 3400)
	assert(RankingStore.score_at(entries, 19) == 1500)
	# Entrar no fim empurra a última para fora e devolve a foto descartada.
	var entrou := RankingStore.insert(entries, 1550, "foto_nova.png")
	assert(int(entrou["position"]) == 20)
	assert((entrou["entries"] as Array).size() == RankingStore.LIMIT)
	assert((entrou["dropped_photos"] as Array).size() == 1)
	assert(str((entrou["dropped_photos"] as Array)[0]) == "foto_1500.png")
	# Marca fraca demais não entra e não guarda foto.
	var fora := RankingStore.insert(entries, 100, "descartar.png")
	assert(int(fora["position"]) == 0)
	assert(str((fora["dropped_photos"] as Array)[0]) == "descartar.png")

func _test_statistics() -> void:
	var stats := StatisticsStore.record({}, 5000, GameDef.Faixa.MEDIA, true)
	stats = StatisticsStore.record(stats, 8000, GameDef.Faixa.FORTE, false)
	var summary := StatisticsStore.summary(stats)
	assert(int(summary["today"]) == 2)
	assert(int(summary["average"]) == 6500)
	assert(int(summary["best"]) == 8000)
	assert(int(summary["top5_entries"]) == 1)
