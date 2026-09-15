extends SceneTree

## A CÂMERA ESTÁ VIVA? — a pergunta que o jogo fazia errado, e que este
## arquivo passou a cobrar.
##
## O SINTOMA ERA ESTE: "no segundo 2 a câmera congela". Durante a pose, a
## imagem parava e ficava parada até a foto sair — e a foto saía daquele
## quadro velho. A causa não era um defeito só, era uma CONFUSÃO: o
## serviço media a câmera pelo PROCESSO (a ponte de pé, o feed ativado, o
## contador subindo) e nunca pela IMAGEM. Com o processo vivo e a imagem
## parada, tudo respondia "pronta", "disponível", "tem imagem" — e a
## máquina seguia em frente mostrando uma fotografia.
##
## O que se trava aqui:
##
##   1. `ao_vivo()` responde pela imagem, e não pelo estado;
##   2. dois quadros IDÊNTICOS não contam como vida (sensor de verdade
##      sempre tem ruído; buffer morto, não);
##   3. um quadro escuro CONTA como vida — um salão à noite não é uma
##      câmera quebrada, e era por confundir os dois que o caminho
##      nativo se desligava sozinho aos 2,5 s;
##   4. a foto não sai de um quadro congelado.
##
## Roda sem webcam e sem Python: tudo aqui é imagem construída à mão.

const Servico = preload("res://scripts/camera_service.gd")

var svc: CameraService

func _initialize() -> void:
	call_deferred("run")

## Um quadro diferente a cada chamada, e a diferença cai num dos 48
## pontos da grade que o serviço olha — mexer fora dela seria oferecer,
## para quem mede, dois quadros iguais.
func quadro(semente: int, claro := true) -> Image:
	var img := Image.create(64, 48, false, Image.FORMAT_RGB8)
	img.fill(Color(0.20, 0.20, 0.20))
	if claro:
		for x in range(64):
			for y in range(18):
				img.set_pixel(x, y, Color.WHITE)
	img.set_pixel(4, 36, Color(float(semente % 9) / 9.0, 0.4, 0.7))
	return img

## Uma cena real de pouca luz: nada de branco, tudo em tons baixos — mas
## com ruído, como qualquer sensor entrega.
func quadro_escuro(semente: int) -> Image:
	var img := Image.create(64, 48, false, Image.FORMAT_RGB8)
	img.fill(Color(0.06, 0.06, 0.07))
	img.set_pixel(4, 36, Color(0.05 + float(semente % 5) * 0.002, 0.05, 0.06))
	return img

func run() -> void:
	svc = Servico.new()
	svc.enabled = true
	root.add_child(svc)
	svc.set_process(false)
	await process_frame

	_vida_vem_da_imagem()
	_quadro_repetido_nao_e_vida()
	_escuro_conta_como_vida()
	_foto_nao_sai_de_quadro_congelado()
	_obturador_guarda_o_melhor_da_pose()

	print("CAMERA_VIVA_OK")
	quit()

# ---------------------------------------------------------------------
func _vida_vem_da_imagem() -> void:
	svc._registrar_quadro(quadro(1), Time.get_ticks_msec())
	assert(svc.ao_vivo())
	assert(svc.parada_ha() < 100)

	# O ESTADO SOZINHO NÃO BASTA. Este é o coração do defeito: ACESA com
	# a imagem parada dizia "pronta", e a contagem começava em cima dela.
	svc.estado = svc.Estado.ACESA
	assert(svc.pronta())
	svc._ultima_mudanca_ms = Time.get_ticks_msec() - svc.VIDA_MAXIMA_MS - 50
	assert(not svc.ao_vivo())
	assert(not svc.pronta())
	assert(not svc.available())

	# E volta a valer no primeiro quadro novo.
	svc._registrar_quadro(quadro(2), Time.get_ticks_msec())
	assert(svc.ao_vivo())
	assert(svc.pronta())

func _quadro_repetido_nao_e_vida() -> void:
	var igual := quadro(7)
	svc._registrar_quadro(igual, Time.get_ticks_msec())
	var marca: int = svc._ultima_mudanca_ms
	# O MESMO QUADRO, DE NOVO: é a assinatura de um buffer que ninguém
	# preencheu. Uma webcam de verdade nunca devolve dois quadros
	# idênticos — há ruído térmico até com a tampa na lente.
	svc._registrar_quadro(igual.duplicate(), Time.get_ticks_msec() + 500)
	assert(svc._ultima_mudanca_ms == marca)
	# Um quadro DIFERENTE, sim.
	svc._registrar_quadro(quadro(8), Time.get_ticks_msec() + 600)
	assert(svc._ultima_mudanca_ms > marca)

func _escuro_conta_como_vida() -> void:
	# ERA AQUI QUE A CÂMERA SE DESLIGAVA NO SEGUNDO 2,5.
	#
	# A prova de que o feed funcionava era o CONTRASTE: menos de 4% entre
	# o ponto mais claro e o mais escuro da grade e o quadro era tratado
	# como buffer morto. Só que uma pessoa de camiseta escura, num salão à
	# noite, na frente de uma parede escura, é uma cena real de baixo
	# contraste — e a webcam perfeita era derrubada no meio da pose,
	# deixando na tela o último quadro que existiu.
	var escuro := quadro_escuro(1)
	assert(not svc._imagem_util(escuro))  # continua sendo de baixo contraste
	svc._registrar_quadro(escuro, Time.get_ticks_msec())
	svc._registrar_quadro(quadro_escuro(2), Time.get_ticks_msec() + 70)
	assert(svc.ao_vivo())  # e continua sendo uma câmera VIVA

func _foto_nao_sai_de_quadro_congelado() -> void:
	svc.estado = svc.Estado.ACESA
	svc._melhor_imagem = null
	svc._melhor_nota = -1.0
	svc._obturador_teve_vida = false

	# A CÂMERA JÁ ESTAVA MOSTRANDO ESTE QUADRO QUANDO CONGELOU — é essa a
	# ordem que reproduz o defeito. A contagem começa (o obturador abre) e
	# daí em diante a webcam repete o MESMO quadro até a foto sair.
	var parado := quadro(3)
	svc._registrar_quadro(parado, Time.get_ticks_msec())
	svc.abrir_obturador(4000)
	for i in range(5):
		svc._registrar_quadro(parado.duplicate(), Time.get_ticks_msec())
	assert(not svc._obturador_teve_vida)
	# A imagem está parada há mais tempo do que o serviço tolera: é
	# congelamento de verdade, e não o meio segundo de engasgo que uma
	# webcam barata dá ao trocar a exposição.
	svc._ultima_mudanca_ms = Time.get_ticks_msec() - svc.VIDA_MAXIMA_MS - 100
	assert(not svc.ao_vivo())
	assert(svc.capture_photo().is_empty())

	# Com quadro novo chegando, a pose tem foto.
	svc.abrir_obturador(4000)
	svc._registrar_quadro(quadro(4), Time.get_ticks_msec())
	svc._registrar_quadro(quadro(5), Time.get_ticks_msec() + 60)
	assert(svc._obturador_teve_vida)
	assert(svc._melhor_imagem != null)

func _obturador_guarda_o_melhor_da_pose() -> void:
	svc.abrir_obturador(4000)
	svc._registrar_quadro(quadro(6, false), Time.get_ticks_msec())
	var fraca: float = svc._melhor_nota
	svc._registrar_quadro(quadro(7, true), Time.get_ticks_msec() + 60)
	assert(svc._melhor_nota > fraca)
	# E um pior depois não derruba o melhor já guardado.
	var boa: float = svc._melhor_nota
	svc._registrar_quadro(quadro(8, false), Time.get_ticks_msec() + 120)
	assert(is_equal_approx(svc._melhor_nota, boa))
	# Fechado o obturador, nada mais entra.
	svc._obturador_ate_ms = 0
	svc._registrar_quadro(quadro(9, true), Time.get_ticks_msec() + 180)
	assert(is_equal_approx(svc._melhor_nota, boa))
	svc._melhor_imagem = null
	svc._melhor_nota = -1.0
