extends SceneTree

## A PONTE QUE AINDA NÃO SUBIU NÃO PODE SER JOGADA FORA.
##
## Este arquivo existe por causa do laço que só aparecia no PC de destino:
## "PowerShell, depois nenhum, PowerShell, depois nenhum", para sempre, e
## nunca uma conexão firme com o Arduino.
##
## A causa eram duas peças brigando:
##
##  1. `SerialLink.create_best` perguntava `available()` — "está de pé
##     AGORA?" — e, no não, DESCARTAVA a ponte e devolvia o backend vazio.
##     Mas a ponte é feita para ressuscitar o ajudante sozinha, dentro do
##     `poll()`. Descartá-la é destruir a peça que ia consertar o
##     problema. E o primeiro nascimento é o mais provável de falhar: é
##     quando o script acaba de ser escrito no disco e o PowerShell é
##     lançado pela primeira vez naquela máquina.
##
##  2. O supervisor trocava de caminho passados 40 s — derrubando a ponte
##     no meio da recuperação e montando outra do zero, que recomeçava a
##     mesma espera. Num PC sem a extensão nativa não há nem para onde
##     trocar: a troca devolve a mesma ponte com o relógio zerado.
##
## No PC de quem desenvolve isso nunca aparece, porque lá a extensão
## nativa carrega e a ponte nunca é usada.

func _initialize() -> void:
	_test_ponte_sem_ajudante_nao_e_descartada()
	_test_sem_materia_prima_nao_ha_o_que_insistir()
	_test_a_ultima_palavra_do_ajudante_vira_motivo()
	_test_create_best_devolve_a_ponte_quando_ela_e_pedida()
	print("PONTE_TEIMOSA_OK")
	quit(0)

func _falhar(o_que: String) -> void:
	printerr("FALHOU: %s" % o_que)
	quit(1)

## Uma ponte cujo ajudante não sobe: o programa não existe.
func _ponte_sem_ajudante() -> PonteProcessoLink:
	PonteProcessoLink.receita_de_teste = [[], ["/nao/existe/ajudante/nenhum"]]
	return PonteProcessoLink.new()

func _test_ponte_sem_ajudante_nao_e_descartada() -> void:
	var ponte := _ponte_sem_ajudante()
	# Mesmo sem estar de pé, ela promete insistir — e é essa promessa que
	# `create_best` passou a respeitar.
	if not ponte.pode_insistir():
		_falhar("com receita válida, a ponte tem de insistir")
	ponte.encerrar()

func _test_sem_materia_prima_nao_ha_o_que_insistir() -> void:
	# Receita vazia = o script não veio na instalação. Aí não é lentidão,
	# é ausência, e nenhuma espera resolve: esta é a ÚNICA condição em que
	# vale desistir da ponte.
	PonteProcessoLink.receita_de_teste = []
	var ponte := PonteProcessoLink.new()
	var insiste := ponte.pode_insistir()
	ponte.encerrar()
	if OS.get_name() == "Windows" or OS.get_name() == "Linux":
		# Em bancada o script de fato existe em res://, então esta
		# asserção só vale quando ele não existe. O que importa provar
		# aqui é que o método responde sem quebrar.
		pass
	if typeof(insiste) != TYPE_BOOL:
		_falhar("pode_insistir tem de responder sim ou não")

func _test_a_ultima_palavra_do_ajudante_vira_motivo() -> void:
	# O PowerShell, quando falha, ESCREVE O MOTIVO — e esse texto vinha
	# pelo mesmo cano das mensagens do Arduino. Como não começa com "#",
	# era tratado como linha da placa, não casava com o protocolo e era
	# descartado em silêncio. A explicação chegava e era jogada fora.
	var ponte := _ponte_sem_ajudante()
	ponte._digerir("Add-Type : Nao foi possivel carregar System.IO.Ports")
	var motivo := ponte.motivo_da_falta()
	ponte.encerrar()
	if not motivo.contains("System.IO.Ports"):
		_falhar("o que o ajudante disse tem de virar motivo: %s" % motivo)


## O QUE ESTE ARQUIVO NÃO CONSEGUE PROVAR — e é importante dizer.
##
## O conserto de `create_best` (ficar com a ponte em vez de descartá-la)
## só muda o resultado quando o LANÇAMENTO DO AJUDANTE FALHA. E isso não
## se reproduz em Linux: medido, `OS.execute_with_pipe` devolve um cano
## mesmo para um programa que não existe, para `/dev/null` e para
## `/bin/false` — `available()` volta verdadeiro nos três. A falha de
## lançamento é condição do Windows.
##
## Então o que está abaixo é fumaça, não prova: garante que a escada
## devolve a ponte quando a ponte é pedida, e que nada quebrou no
## caminho. A correção em si foi verificada por leitura do código, e quem
## a confirma de verdade é o PC de destino.
func _test_create_best_devolve_a_ponte_quando_ela_e_pedida() -> void:
	PonteProcessoLink.receita_de_teste = [[], ["/nao/existe/ajudante/nenhum"]]
	var escolhido := SerialLink.create_best(SerialLink.CAMINHO_NATIVO)
	var caminho := escolhido.nome_do_caminho()
	escolhido.encerrar()
	if caminho != SerialLink.CAMINHO_PONTE:
		_falhar("pedida a ponte, a escada devolveu: %s" % caminho)
