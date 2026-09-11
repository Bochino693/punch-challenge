class_name ArduinoProtocol
extends RefCounted

## Protocolo serial V2 entre Godot e o firmware punch_sensor (MPU-6050).
## Linhas terminadas em \n, campos separados por vírgula. Mensagens
## incompletas ou com valores inválidos são descartadas aqui — o jogo
## nunca recebe lixo. Ver docs/PROTOCOLO_SERIAL.md.

## parse(line) -> Dictionary com ao menos a chave "type".
## type == "" significa "linha inválida, ignore".
static func parse(line: String) -> Dictionary:
	var parts := line.split(",")
	if parts.is_empty():
		return {"type": ""}
	var head := parts[0].strip_edges().to_upper()
	match head:
		"READY":
			# READY,PUNCH_MPU6050,V2
			return {
				"type": "READY",
				"device": parts[1] if parts.size() > 1 else "",
				"version": parts[2] if parts.size() > 2 else "",
			}
		"CALIBRATING":
			if parts.size() != 2 or not parts[1].is_valid_int():
				return {"type": ""}
			return {"type": "CALIBRATING", "percent": clampi(parts[1].to_int(), 0, 100)}
		"CALIBRATED":
			if parts.size() != 4:
				return {"type": ""}
			var offs := _floats(parts, 1, 3)
			if offs.is_empty():
				return {"type": ""}
			return {"type": "CALIBRATED", "offsets": offs}
		"PONG":
			return {"type": "PONG"}
		"PINS":
			# PINS,<start>,<credito> — 1 é APERTADO. O estado cru dos dois
			# pinos, para a Central mostrar ao vivo: se o número não muda
			# quando o botão é apertado, o problema é antes do firmware.
			if parts.size() != 3:
				return {"type": ""}
			return {
				"type": "PINS",
				"start": parts[1].strip_edges() == "1",
				"credit": parts[2].strip_edges() == "1",
			}
		"BUTTON":
			if parts.size() != 2:
				return {"type": ""}
			var botao := parts[1].strip_edges().to_upper()
			if botao != "START" and botao != "CREDIT":
				return {"type": ""}
			return {"type": "BUTTON", "button": botao}
		"TELEMETRY":
			# TELEMETRY,ax,ay,az,gx,gy,gz,velocidade,pico_g
			if parts.size() != 9:
				return {"type": ""}
			var vals := _floats(parts, 1, 8)
			if vals.is_empty():
				return {"type": ""}
			return {
				"type": "TELEMETRY",
				"accel": Vector3(vals[0], vals[1], vals[2]),
				"gyro": Vector3(vals[3], vals[4], vals[5]),
				"velocity": vals[6],
				"peak_g": vals[7],
			}
		"HIT":
			# HIT,velocidade_pico,aceleracao_pico,duracao_ms,eixo
			if parts.size() != 5:
				return {"type": ""}
			var vals := _floats(parts, 1, 3)
			if vals.is_empty():
				return {"type": ""}
			var eixo := parts[4].strip_edges().to_upper()
			if eixo != "X" and eixo != "Y" and eixo != "Z":
				return {"type": ""}
			# Valores impossíveis não viram golpe.
			if vals[0] < 0.0 or vals[0] > 60.0 or vals[1] < 0.0 or vals[1] > 17.0 or vals[2] <= 0.0 or vals[2] > 5000.0:
				return {"type": ""}
			return {"type": "HIT", "speed": vals[0], "accel": vals[1], "duration_ms": vals[2], "axis": eixo}
		"REJECT":
			# REJECT,<motivo>,<pico_g>,<duracao_ms>,<giro_dps>,<velocidade>
			#
			# A PLACA VIU ALGO E DESCARTOU, e diz por quê. É o que
			# transforma "nada acontece" — que é o mesmo sintoma para seis
			# causas diferentes — numa frase que aponta o limiar errado.
			if parts.size() != 6:
				return {"type": ""}
			var nums := _floats(parts, 2, 4)
			if nums.is_empty():
				return {"type": ""}
			return {
				"type": "REJECT",
				"reason": parts[1].strip_edges().to_upper(),
				"peak_g": nums[0],
				"duration_ms": nums[1],
				"gyro_dps": nums[2],
				"speed": nums[3],
			}
		"STATUS":
			# STATUS,<medindo>,<forca_agora_g>,<gatilho_g>
			#
			# `forca_agora` é a aceleração já sem a gravidade. Parada, a
			# máquina mostra perto de zero; um soco passa de 3. É o número
			# que se confere a olho, sem interpretar nada.
			if parts.size() != 4:
				return {"type": ""}
			var st := _floats(parts, 2, 2)
			if st.is_empty():
				return {"type": ""}
			return {
				"type": "STATUS",
				"measuring": parts[1].strip_edges() == "1",
				"force_g": st[0],
				"trigger_g": st[1],
			}
		"NOISE":
			# NOISE,<ruido_g>,<ruido_dps> — o piso medido nesta montagem.
			if parts.size() != 3:
				return {"type": ""}
			var nz := _floats(parts, 1, 2)
			if nz.is_empty():
				return {"type": ""}
			return {"type": "NOISE", "noise_g": nz[0], "noise_dps": nz[1]}
		"SATURATION":
			if parts.size() != 2:
				return {"type": ""}
			var fonte := parts[1].strip_edges().to_upper()
			if fonte != "ACCEL" and fonte != "GYRO":
				return {"type": ""}
			return {"type": "SATURATION", "source": fonte}
		"ERROR":
			return {"type": "ERROR", "code": parts[1].strip_edges().to_upper() if parts.size() > 1 else "DESCONHECIDO"}
		"OK":
			return {"type": "OK", "detail": parts[1].strip_edges().to_upper() if parts.size() > 1 else ""}
	return {"type": ""}

## Extrai `count` floats a partir do índice `from`. Se qualquer campo
## não for float válido, devolve array vazio (mensagem rejeitada).
static func _floats(parts: PackedStringArray, from: int, count: int) -> Array:
	var out: Array = []
	for i in range(from, from + count):
		if i >= parts.size() or not parts[i].strip_edges().is_valid_float():
			return []
		out.append(parts[i].strip_edges().to_float())
	return out

static func build_config(
	axis: String, radius_m: float, min_speed: float, min_accel_g: float, max_speed := 0.0
) -> String:
	# Validação idêntica à do firmware — o Arduino revalida tudo.
	var eixo := axis.to_upper()
	if eixo != "X" and eixo != "Y" and eixo != "Z":
		eixo = "X"
	var raio := clampf(radius_m, 0.05, 1.50)
	var vmin := clampf(min_speed, 0.2, 20.0)
	var amin := clampf(min_accel_g, 0.5, 15.0)
	if max_speed <= 0.0:
		return "CONFIG,%s,%.3f,%.2f,%.2f" % [eixo, raio, vmin, amin]
	# O QUINTO CAMPO É O TETO DAS FITAS DE LED.
	#
	# A placa precisa dele para saber que velocidade enche a coluna
	# inteira quando estiver se virando sozinha — com o PC desligado, ou
	# nos décimos de segundo entre o golpe e o primeiro `LEDS` do jogo.
	# É opcional nos dois lados: firmware novo aceita CONFIG de quatro
	# campos, e este método só manda o quinto quando ele existe.
	var vmax := clampf(max_speed, vmin + 0.5, 40.0)
	return "CONFIG,%s,%.3f,%.2f,%.2f,%.2f" % [eixo, raio, vmin, amin, vmax]

## A ALTURA DA COLUNA DE LED, em por mil.
##
## Mandada enquanto o placar sobe na tela: assim a fita acompanha o NÚMERO
## subindo, e não o golpe cru. As duas coisas no mesmo compasso é o que
## faz a máquina parecer uma peça só, em vez de um monitor com uma fita
## pendurada do lado.
static func build_leds(fracao: float) -> String:
	return "LEDS,%d" % clampi(int(round(clampf(fracao, 0.0, 1.0) * 1000.0)), 0, 1000)
