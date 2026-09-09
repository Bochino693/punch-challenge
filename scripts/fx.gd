class_name PunchFX
extends RefCounted

## Partículas e ondas da tela — brasas, raios, faíscas, estilhaços e anéis.
##
## POR QUE FICA FORA DE `main.gd`. A tela desenha tudo à mão, num `_draw`
## só, e o resultado de um soco acende três coisas ao mesmo tempo: o que
## voa, o que treme e o que escreve. Misturar as três num arquivo faz
## qualquer ajuste de festa mexer no código que conta ponto — e ponto de
## arcade é dinheiro. Aqui mora só o que voa.
##
## Tudo é desenhado por `draw()` no mesmo `CanvasItem` do jogo: sem nó,
## sem cena e sem `GPUParticles`. Numa máquina de fliperama o computador
## costuma ser modesto, e um teto duro de partículas (`LIMITE`) vale mais
## do que um sistema bonito que engasga bem na hora do soco.

## Teto de partículas vivas. Passando disso, as mais antigas saem.
const LIMITE := 900

## O VIGIA DO RITMO, ligado por quem cria o efeito.
##
## Cada função que solta partícula pergunta a ele quantas realmente
## soltar. Num PC que está dando conta, todas; num que não está, menos —
## e a queda acontece onde ninguém repara, em vez de aparecer como
## animação aos trancos, que é onde todo mundo repara.
var vigia: Desempenho = null

func _quantas(pedido: int) -> int:
	return pedido if vigia == null else vigia.quantas(pedido)

var _particulas: Array = []
var _ondas: Array = []


func limpar() -> void:
	_particulas.clear()
	_ondas.clear()


func vivo() -> bool:
	return not _particulas.is_empty() or not _ondas.is_empty()


func atualizar(delta: float) -> void:
	var restantes: Array = []
	for p in _particulas:
		p.vida -= delta
		if p.vida <= 0.0:
			continue
		p.velocidade.y += p.gravidade * delta
		p.velocidade *= 1.0 - p.arrasto * delta
		p.posicao += p.velocidade * delta
		p.giro += p.giro_velocidade * delta
		restantes.append(p)
	_particulas = restantes

	var ondas_vivas: Array = []
	for o in _ondas:
		o.tempo += delta
		if o.tempo < o.duracao:
			ondas_vivas.append(o)
	_ondas = ondas_vivas


func desenhar(tela: CanvasItem) -> void:
	for o in _ondas:
		var t: float = o.tempo / o.duracao
		var raio: float = lerpf(o.raio_inicial, o.raio_final, ease(t, 0.35))
		var cor: Color = o.cor
		cor.a *= 1.0 - t
		tela.draw_arc(o.centro, raio, 0.0, TAU, 96, cor, o.espessura * (1.0 - t * 0.7), true)

	for p in _particulas:
		var cor: Color = p.cor
		cor.a *= clampf(p.vida / p.vida_total, 0.0, 1.0)
		match p.tipo:
			"confete":
				# Retângulo girando: o confete de verdade mostra ora a
				# face, ora o canto -- é a largura oscilando que dá isso.
				#
				# A largura tem um piso: exatamente de perfil o cosseno
				# zera, os quatro cantos caem sobre a mesma reta e o
				# desenho vira um polígono sem área, que o motor recusa
				# ("triangulation failed") e ainda enche o log. De perfil
				# o confete é uma lasca fina, não um nada.
				var largura: float = maxf(p.tamanho * 0.10, p.tamanho * absf(cos(p.giro)))
				var pontos := PackedVector2Array([
					p.posicao + Vector2(-largura, -p.tamanho * 1.6).rotated(p.giro * 0.35),
					p.posicao + Vector2(largura, -p.tamanho * 1.6).rotated(p.giro * 0.35),
					p.posicao + Vector2(largura, p.tamanho * 1.6).rotated(p.giro * 0.35),
					p.posicao + Vector2(-largura, p.tamanho * 1.6).rotated(p.giro * 0.35),
				])
				Traco.poligono(tela, pontos, cor)
			"brasa":
				# BRASA: um risco na direção do voo, com a cabeça mais
				# quente. É o que substituiu o confete — um retângulo
				# girando é festa de aniversário; o que sai de uma
				# pancada é fagulha em brasa, e fagulha tem RASTRO.
				var vel: Vector2 = p.velocidade
				var comprimento: float = clampf(vel.length() * 0.045, 10.0, 90.0)
				var atras: Vector2 = p.posicao - vel.normalized() * comprimento
				var frio := cor
				frio.a *= 0.25
				tela.draw_line(atras, p.posicao, frio, p.tamanho * 0.7, true)
				tela.draw_line(p.posicao - vel.normalized() * comprimento * 0.35, p.posicao, cor, p.tamanho, true)
				# ANTISSERRILHADO SÓ NA PARTÍCULA GRANDE. Numa faísca de
				# poucos pixels a borda lisa não se vê, e ela custa o
				# dobro da geometria — pago em cada uma das centenas que
				# voam ao mesmo tempo. É aí que a festa fica pesada.
				tela.draw_circle(
					p.posicao, p.tamanho * 0.7, Color(1, 1, 1, cor.a * 0.85),
					true, -1.0, p.tamanho >= 7.0
				)
			"raio":
				# RAIO: o mesmo símbolo que está no emblema, girando. Dá
				# à festa a linguagem da máquina em vez da de carnaval.
				Traco.poligono(tela, _forma_de_raio(p.posicao, p.tamanho, p.giro), cor)
			"faisca":
				var rastro: Vector2 = p.velocidade.normalized() * p.tamanho * 3.5
				tela.draw_line(p.posicao - rastro, p.posicao, cor, maxf(1.5, p.tamanho * 0.6), true)
			"estilhaco":
				var pontos_e := PackedVector2Array([
					p.posicao + Vector2(0, -p.tamanho).rotated(p.giro),
					p.posicao + Vector2(p.tamanho, p.tamanho * 0.6).rotated(p.giro),
					p.posicao + Vector2(-p.tamanho * 0.8, p.tamanho).rotated(p.giro),
				])
				Traco.poligono(tela, pontos_e, cor)
			_:
				tela.draw_circle(p.posicao, p.tamanho, cor, true, -1.0, p.tamanho >= 7.0)


## O contorno de um raio de seis pontas, na escala e no giro pedidos.
static func _forma_de_raio(centro: Vector2, tamanho: float, giro: float) -> PackedVector2Array:
	const MOLDE := [
		Vector2(0.10, -1.00), Vector2(-0.55, 0.10), Vector2(-0.10, 0.10),
		Vector2(-0.20, 1.00), Vector2(0.55, -0.15), Vector2(0.08, -0.15),
	]
	var pontos := PackedVector2Array()
	for ponto in MOLDE:
		pontos.append(centro + (ponto as Vector2).rotated(giro) * tamanho)
	return pontos


func _nascer(dados: Dictionary) -> void:
	if _particulas.size() >= LIMITE:
		_particulas.remove_at(0)
	dados["vida_total"] = dados.vida
	_particulas.append(dados)


func onda(centro: Vector2, raio_inicial: float, raio_final: float, cor: Color, espessura: float = 8.0, duracao: float = 0.7) -> void:
	_ondas.append({
		"centro": centro,
		"raio_inicial": raio_inicial,
		"raio_final": raio_final,
		"cor": cor,
		"espessura": espessura,
		"duracao": maxf(0.05, duracao),
		"tempo": 0.0,
	})


func confete(centro: Vector2, quantidade: int, cores: Array, forca: float = 900.0) -> void:
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(-PI, 0.0)
		var velocidade := Vector2(cos(angulo), sin(angulo)) * randf_range(forca * 0.35, forca)
		_nascer({
			"tipo": "confete",
			"posicao": centro + Vector2(randf_range(-40.0, 40.0), randf_range(-20.0, 20.0)),
			"velocidade": velocidade,
			"gravidade": randf_range(760.0, 1150.0),
			"arrasto": 0.9,
			"tamanho": randf_range(5.0, 11.0),
			"giro": randf_range(0.0, TAU),
			"giro_velocidade": randf_range(-9.0, 9.0),
			"cor": cores[randi() % cores.size()],
			"vida": randf_range(1.6, 3.1),
		})


## A CHUVA DE BRASAS, no lugar da chuva de confete.
##
## Cai mais rápido e mais reta do que o confete caía: confete plana no ar,
## e planar é o gesto de uma festa de aniversário. Brasa despenca.
func chuva_de_brasas(largura: float, quantidade: int, cores: Array) -> void:
	for i in range(_quantas(quantidade)):
		_nascer({
			"tipo": "brasa",
			"posicao": Vector2(randf_range(0.0, largura), randf_range(-300.0, -20.0)),
			"velocidade": Vector2(randf_range(-40.0, 40.0), randf_range(520.0, 980.0)),
			"gravidade": randf_range(420.0, 720.0),
			"arrasto": 0.25,
			"tamanho": randf_range(3.0, 6.5),
			"giro": 0.0,
			"giro_velocidade": 0.0,
			"cor": cores[randi() % cores.size()],
			"vida": randf_range(1.6, 2.8),
		})


## A EXPLOSÃO DO GOLPE: brasas para todo lado e alguns raios girando.
##
## Sai do ponto do impacto, e não do alto da tela, porque quem manda na
## comemoração é o soco — a origem tem de ser o lugar onde ele aterrissou.
func explosao(centro: Vector2, quantidade: int, cores: Array, forca: float = 1100.0) -> void:
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(0.0, TAU)
		var direcao := Vector2(cos(angulo), sin(angulo))
		# Achatada na vertical: uma explosão redonda em tela alta some
		# pelas laterais antes de a pessoa ver.
		direcao.y *= 0.75
		_nascer({
			"tipo": "brasa",
			"posicao": centro + direcao * randf_range(0.0, 70.0),
			"velocidade": direcao * randf_range(forca * 0.30, forca),
			"gravidade": randf_range(520.0, 900.0),
			"arrasto": 1.1,
			"tamanho": randf_range(3.0, 7.0),
			"giro": 0.0,
			"giro_velocidade": 0.0,
			"cor": cores[randi() % cores.size()],
			"vida": randf_range(0.9, 1.9),
		})


## Raios saindo do ponto do soco, girando enquanto voam.
func raios(centro: Vector2, quantidade: int, cor: Color, forca: float = 780.0) -> void:
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(0.0, TAU)
		_nascer({
			"tipo": "raio",
			"posicao": centro,
			"velocidade": Vector2(cos(angulo), sin(angulo) * 0.8) * randf_range(forca * 0.4, forca),
			"gravidade": randf_range(420.0, 760.0),
			"arrasto": 1.3,
			"tamanho": randf_range(16.0, 34.0),
			"giro": randf_range(0.0, TAU),
			"giro_velocidade": randf_range(-7.0, 7.0),
			"cor": cor,
			"vida": randf_range(0.8, 1.6),
		})


func faiscas(centro: Vector2, quantidade: int, cor: Color, forca: float = 1000.0) -> void:
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(0.0, TAU)
		var tom := cor
		tom.a = randf_range(0.65, 1.0)
		_nascer({
			"tipo": "faisca",
			"posicao": centro,
			"velocidade": Vector2(cos(angulo), sin(angulo)) * randf_range(forca * 0.25, forca),
			"gravidade": randf_range(240.0, 620.0),
			"arrasto": 2.2,
			"tamanho": randf_range(2.0, 4.5),
			"giro": 0.0,
			"giro_velocidade": 0.0,
			"cor": tom,
			"vida": randf_range(0.45, 1.05),
		})


func estilhacos(centro: Vector2, quantidade: int, cor: Color) -> void:
	## O que cai quando o soco foi fraco: pedaço escuro, pesado, sem brilho.
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(-PI * 0.85, -PI * 0.15)
		_nascer({
			"tipo": "estilhaco",
			"posicao": centro + Vector2(randf_range(-120.0, 120.0), randf_range(-40.0, 40.0)),
			"velocidade": Vector2(cos(angulo), sin(angulo)) * randf_range(140.0, 420.0),
			"gravidade": randf_range(900.0, 1400.0),
			"arrasto": 0.4,
			"tamanho": randf_range(6.0, 15.0),
			"giro": randf_range(0.0, TAU),
			"giro_velocidade": randf_range(-5.0, 5.0),
			"cor": cor,
			"vida": randf_range(1.1, 2.0),
		})


func poeira(centro: Vector2, quantidade: int, cor: Color, alcance: float = 420.0) -> void:
	for i in range(_quantas(quantidade)):
		var angulo := randf_range(0.0, TAU)
		_nascer({
			"tipo": "poeira",
			"posicao": centro + Vector2(cos(angulo), sin(angulo)) * randf_range(0.0, 60.0),
			"velocidade": Vector2(cos(angulo), sin(angulo)) * randf_range(alcance * 0.2, alcance),
			"gravidade": -randf_range(20.0, 90.0),
			"arrasto": 1.6,
			"tamanho": randf_range(2.0, 6.0),
			"giro": 0.0,
			"giro_velocidade": 0.0,
			"cor": cor,
			"vida": randf_range(0.8, 1.8),
		})


func fogos(centro: Vector2, cores: Array) -> void:
	var cor: Color = cores[randi() % cores.size()]
	onda(centro, 6.0, randf_range(120.0, 210.0), Color(cor.r, cor.g, cor.b, 0.55), 5.0, 0.55)
	faiscas(centro, 46, cor, 780.0)
