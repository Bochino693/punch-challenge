extends SceneTree

## DOIS SOCOS POR RODADA, e a rodada fecha uma vez só.
##
## O que este teste protege, e que é fácil de quebrar sem perceber:
##
##  1. Depois do primeiro soco a máquina REARMA, e não vai ao resultado.
##  2. Os dois socos ficam guardados individualmente, cada um com a sua
##     pontuação e a sua velocidade — é isso que a tela desenha.
##  3. A nota da rodada é o MELHOR dos dois, e a ordem não importa.
##  4. Ranking e estatística acontecem UMA VEZ por rodada. Enquanto isso
##     ficava no registro de cada impacto, dois socos da mesma pessoa
##     disputavam duas linhas do Top 20 e contavam duas partidas.
##  5. Quem já socou não recebe a ficha de volta quando a espera acaba;
##     quem não socou nenhuma vez, recebe.

var jogo: Control

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	jogo = load("res://scenes/main.tscn").instantiate()
	root.add_child(jogo)
	await process_frame
	jogo.set_process(false)
	# `simulacao_bancada` e `simulacao_por_ambiente` NAO EXISTEM neste
	# projeto -- o tests/test_show_flow.gd ainda as atribui, e e por isso
	# que ele nao roda ate o fim. Aqui basta a Central fechada.
	jogo.central_aberta = false
	# A SERIAL FICA COMO ESTA. Nao se troca nem se anula o `link` aqui: a
	# unica forma correta de solta-lo e `_soltar_link()`, e mesmo essa
	# espera a thread leitora. O que se prova neste arquivo e a maquina de
	# estados da rodada, e ela nao depende de porta nenhuma.

	_test_primeiro_soco_rearma()
	_test_melhor_dos_dois_vale()
	_test_ordem_nao_importa()
	_test_rodada_entra_uma_vez_no_ranking()
	_test_espera_esgotada_no_meio_nao_devolve()
	_test_espera_esgotada_sem_soco_devolve()

	jogo.queue_free()
	await process_frame
	print("DOIS_SOCOS_OK")
	quit(0)

func _falhar(o_que: String) -> void:
	printerr("FALHOU: %s" % o_que)
	quit(1)

## Uma rodada nova, do jeito que a contagem regressiva a entrega.
func _rodada_nova() -> void:
	jogo.socos.clear()
	jogo.state = GameDef.State.ARMED
	jogo.golpe_registrado = false
	jogo.ultimo_golpe_ms = jogo.NUNCA_MS
	jogo.result_score = 0
	jogo.espera_left = GameDef.ESPERA_DO_SOCO
	# MODO FICHA DECLARADO AQUI, e não herdado do disco: `user://` sobrevive
	# entre execuções, e um teste que depende do que a execução anterior
	# gravou passa ou falha conforme a ORDEM em que a suíte roda.
	jogo.game_mode = "credit"
	jogo.credito_gasto = true

## Um golpe válido com a velocidade pedida.
func _golpe(v: float) -> Dictionary:
	return {"speed": v, "accel": 9.0, "duration_ms": 45.0, "axis": "X"}

## Entrega um soco e deixa a máquina andar até ela decidir o que fazer.
func _socar(v: float) -> void:
	jogo.golpe_registrado = false
	jogo.ultimo_golpe_ms = jogo.NUNCA_MS
	jogo.state = GameDef.State.ARMED
	jogo._receber_hit(_golpe(v))
	# passa o tempo do impacto, que é quando a máquina rearma ou conclui
	jogo.state_time = GameDef.IMPACTO_DURACAO + 0.01
	jogo._process(0.02)

func _test_primeiro_soco_rearma() -> void:
	_rodada_nova()
	jogo._receber_hit(_golpe(2.0))
	if jogo.state != GameDef.State.MEASURING:
		_falhar("o primeiro soco tem de ir para MEASURING")
	if jogo.socos.size() != 1:
		_falhar("o primeiro soco tem de ficar guardado: %d" % jogo.socos.size())
	jogo.state_time = GameDef.IMPACTO_DURACAO + 0.01
	jogo._process(0.02)
	if jogo.state != GameDef.State.ARMED:
		_falhar("depois do primeiro soco a maquina REARMA, nao conclui (estado %d)" % jogo.state)

func _test_melhor_dos_dois_vale() -> void:
	_rodada_nova()
	_socar(1.0)
	_socar(4.0)
	if jogo.socos.size() != 2:
		_falhar("dois socos tem de ficar guardados: %d" % jogo.socos.size())
	if jogo.state != GameDef.State.RESULT:
		_falhar("o segundo soco fecha a rodada (estado %d)" % jogo.state)
	var p1: int = jogo.socos[0]["pontos"]
	var p2: int = jogo.socos[1]["pontos"]
	if p2 <= p1:
		_falhar("4,0 m/s tem de valer mais que 1,0 m/s (%d vs %d)" % [p1, p2])
	if jogo.result_score != maxi(p1, p2):
		_falhar("a nota da rodada e o melhor dos dois: %d" % jogo.result_score)

func _test_ordem_nao_importa() -> void:
	# O forte primeiro: o segundo soco, mais fraco, NAO pode rebaixar a nota.
	_rodada_nova()
	_socar(4.0)
	_socar(1.0)
	var p1: int = jogo.socos[0]["pontos"]
	var p2: int = jogo.socos[1]["pontos"]
	if jogo.result_score != maxi(p1, p2):
		_falhar("o soco fraco depois do forte nao pode rebaixar a nota: %d" % jogo.result_score)

func _test_rodada_entra_uma_vez_no_ranking() -> void:
	var antes: int = jogo.plays
	_rodada_nova()
	_socar(3.0)
	_socar(3.5)
	if jogo.plays != antes + 1:
		_falhar("dois socos sao UMA partida, nao duas (%d -> %d)" % [antes, jogo.plays])

func _test_espera_esgotada_no_meio_nao_devolve() -> void:
	_rodada_nova()
	jogo._receber_hit(_golpe(2.5))
	jogo.state_time = GameDef.IMPACTO_DURACAO + 0.01
	jogo._process(0.02)          # rearma para o segundo
	var creditos_antes: int = jogo.credits
	jogo.espera_left = 0.0
	jogo._process(0.02)          # a espera acaba com um soco dado
	if jogo.credits != creditos_antes:
		_falhar("quem ja socou nao recebe a ficha de volta")
	if jogo.state != GameDef.State.RESULT:
		_falhar("com um soco dado, a espera esgotada vai ao resultado")

func _test_espera_esgotada_sem_soco_devolve() -> void:
	_rodada_nova()
	var creditos_antes: int = jogo.credits
	jogo.espera_left = 0.0
	jogo._process(0.02)
	if jogo.credits != creditos_antes + 1:
		_falhar("sem nenhum soco, a ficha volta (%d -> %d)" % [creditos_antes, jogo.credits])
