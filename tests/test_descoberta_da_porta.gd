extends SceneTree

## POR QUE A MÁQUINA DEMORAVA A ACHAR A COM.
##
## A ponte sempre soube quais portas o Windows chama de Arduino/CH340/FTDI
## — ela já as ordenava na frente. Mas mandava ao jogo apenas a ORDEM, e
## ordem se perde: o jogo gastava a MESMA paciência longa numa porta de
## Bluetooth e na porta da placa.
##
## A conta, com quatro portas anônimas antes da certa:
##   antes:  4 × 8,0 s  = 32 s   (mais 6 s de confirmação cada)
##   agora:  4 × 1,5 s  =  6 s   (mais 3,5 s de confirmação cada)
## E no caso normal — a placa se anunciando — ela vai na frente da fila e
## responde em pouco mais de dois segundos.
##
## Este arquivo prova as duas metades: que a marca CHEGA ao jogo, e que
## "não sei" nunca vira pressa.

func _initialize() -> void:
	_test_a_marca_chega_e_sai_do_nome()
	_test_sem_marca_nenhuma_ninguem_tem_pressa()
	print("DESCOBERTA_OK")
	quit(0)

func _falhar(o_que: String) -> void:
	printerr("FALHOU: %s" % o_que)
	quit(1)

## Uma ponte SEM ajudante nenhum: a receita aponta para um programa que
## não existe, então nenhum processo sobe, nenhuma thread nasce e nenhum
## cano é aberto. É de propósito.
##
## O que se prova aqui é a LEITURA DA MENSAGEM — a parte que eu mudei.
## Subir um processo de verdade só para entregar duas linhas de texto
## acrescentaria um subprocesso, uma thread e um cano ao teste, e foi
## exatamente essa camada a mais que fez `tests/test_serial_teimoso.gd`
## terminar em SIGPIPE (141) desde antes desta versão. Teste que precisa
## de meia máquina de pé para provar meia linha de texto é teste que
## quebra por motivos que não são o que ele mede.
func _ponte_muda() -> PonteProcessoLink:
	PonteProcessoLink.receita_de_teste = [[], ["/nao/existe/ajudante"]]
	return PonteProcessoLink.new()

func _test_a_marca_chega_e_sai_do_nome() -> void:
	var ponte := _ponte_muda()
	ponte._digerir("#PORTAS,COM3*,COM5,COM7")
	var portas := ponte.list_ports()
	var promissoras := ponte.portas_promissoras()
	# SOLTAR UMA PONTE VIVA SEM ENCERRAR DEIXA A THREAD LEITORA ORFA, e o
	# Godot acusa. `encerrar()` e a unica forma correta -- em teste e em
	# producao (onde quem faz isso e `_soltar_link`).
	ponte.encerrar()

	# O asterisco é do protocolo, não do nome da porta: ninguém abaixo da
	# ponte pode vê-lo, ou o jogo tentaria abrir uma porta chamada "COM3*".
	if not portas.has("COM3") or portas.has("COM3*"):
		_falhar("o asterisco tem de sair do nome: %s" % str(portas))
	if portas.size() != 3:
		_falhar("as tres portas continuam na lista: %s" % str(portas))
	if promissoras != PackedStringArray(["COM3"]):
		_falhar("so a COM3 e promissora: %s" % str(promissoras))

func _test_sem_marca_nenhuma_ninguem_tem_pressa() -> void:
	# Um PC onde o gerenciador de dispositivos não sabe nomear nada: a
	# ponte manda a lista sem asterisco. "Não sei" NÃO pode virar pressa —
	# com a lista de promissoras vazia o jogo trata todas com a paciência
	# inteira, que é o comportamento de antes. É a diferença entre
	# acelerar e passar a descartar a porta certa.
	var ponte := _ponte_muda()
	ponte._digerir("#PORTAS,COM1,COM2")
	var portas := ponte.list_ports()
	var promissoras := ponte.portas_promissoras()
	# SOLTAR UMA PONTE VIVA SEM ENCERRAR DEIXA A THREAD LEITORA ORFA, e o
	# Godot acusa. `encerrar()` e a unica forma correta -- em teste e em
	# producao (onde quem faz isso e `_soltar_link`).
	ponte.encerrar()

	if portas.size() != 2:
		_falhar("as portas continuam vindo: %s" % str(portas))
	if not promissoras.is_empty():
		_falhar("sem asterisco nao ha promissora: %s" % str(promissoras))
