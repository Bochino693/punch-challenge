#!/bin/sh
# CONFERE A PONTE SERIAL CONTRA UMA PORTA DE VERDADE.
#
# POR QUE ISTO EXISTE. A ponte e o unico caminho ate o Arduino quando a
# extensao nativa nao carrega -- e foi exatamente isso que aconteceu no
# gabinete. Um defeito aqui nao aparece como "a ponte falhou": aparece
# como START morto, CREDITO morto e sensor mudo, e quem esta na frente da
# maquina procura fio solto por horas.
#
# O teste do jogo (tests/test_show_flow.gd) exercita o lado do Godot com
# um ajudante de mentira. Este aqui faz o contrario: pega o ajudante DE
# VERDADE, o tools/ponte_serial.sh, e o poe para conversar com uma porta
# serial DE VERDADE -- um par de pseudo-terminais, que aceita `stty` e se
# comporta como a porta do Arduino. O unico pedaco que fica de fora e o
# fio de cobre.
#
# (O irmao dele, o ponte_serial.ps1, so pode ser exercitado no Windows;
# o protocolo dos dois e o mesmo, linha por linha, de proposito.)
#
# Uso:  sh tools/conferir_ponte.sh
set -e
raiz=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$raiz" <<'PY'
import os, pty, subprocess, sys, time, select

raiz = sys.argv[1]
ponte = os.path.join(raiz, "tools", "ponte_serial.sh")

mestre, escravo = pty.openpty()
porta = os.ttyname(escravo)

p = subprocess.Popen(["sh", ponte, porta, "115200"],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     bufsize=0)

def dizer(linha):
    p.stdin.write((linha + "\n").encode())
    p.stdin.flush()

def esperar(alvo, segundos=5.0):
    """Le linhas da ponte ate ver `alvo`. Nunca fica preso."""
    fim = time.time() + segundos
    vistas = []
    while time.time() < fim:
        pronto, _, _ = select.select([p.stdout], [], [], 0.2)
        if not pronto:
            continue
        linha = p.stdout.readline().decode("utf-8", "replace").strip()
        if not linha:
            continue
        vistas.append(linha)
        if alvo in linha:
            return vistas
    print("FALHA: nao veio %r; vi %r" % (alvo, vistas))
    sys.exit(1)

def do_arduino(texto):
    os.write(mestre, (texto + "\r\n").encode())

falhas = []

# 1. A ponte se apresenta e abre a porta que foi mandada abrir.
esperar("#PONTE,V1")
esperar("#ABERTA," + porta)

# 2. O QUE A PLACA FALA CHEGA NO JOGO, E CHEGA NA HORA.
#    Aqui mora o defeito mais traicoeiro desta ponte: um `tr` no meio do
#    caminho acumularia 4 KB antes de soltar a primeira linha, e a placa
#    ficaria falando com o jogo surdo. Como `esperar` desiste em cinco
#    segundos, uma ponte que so entrega em bloco reprova neste ponto.
#    (O \r do Arduino sobrevive a travessia de proposito; quem le no
#    Godot passa cada linha por `strip_edges()`.)
do_arduino("READY,PUNCH_MPU6050,V3")
esperar("READY,PUNCH_MPU6050,V3")

# 3. Linhas seguidas nao se embaralham nem se perdem.
for i in range(20):
    do_arduino("PINS,%d,%d" % (i % 2, (i + 1) % 2))
esperar("PINS,1,0")
esperar("PINS,0,1")

# 4. O CAMINHO DE VOLTA. Sem ele nao ha CONFIG, nao ha LEDS e nao ha
#    PING: nem calibracao, nem fitas acompanhando o soco.
dizer("LEDS,640")
fim = time.time() + 5.0
eco = b""
while time.time() < fim and b"LEDS,640" not in eco:
    pronto, _, _ = select.select([mestre], [], [], 0.2)
    if pronto:
        eco += os.read(mestre, 4096)
if b"LEDS,640" not in eco:
    falhas.append("o comando do jogo nao chegou na porta (recebi %r)" % eco)

# 5. Fechar avisa, e a ponte continua viva para abrir de novo.
dizer("@FECHAR")
esperar("#FECHADA")
dizer("@LISTAR")
esperar("#PORTAS")

dizer("@SAIR")
try:
    p.wait(timeout=5)
except subprocess.TimeoutExpired:
    falhas.append("a ponte nao saiu quando mandaram sair")
    p.kill()

if falhas:
    for f in falhas:
        print("FALHA:", f)
    sys.exit(1)
print("PONTE_OK")

# ----------------------------------------------------------------------
#  SEGUNDA ETAPA: O JOGO INTEIRO ATE A PORTA.
# ----------------------------------------------------------------------
#
#  Ate aqui o que foi provado e que o ajudante conversa com uma porta
#  serial. Falta a metade que importa mais: que o GODOT conversa com o
#  ajudante. Os testes do jogo trocam o ajudante por um de mentira -- e um
#  defeito no ajudante de verdade passaria por eles sem ser notado, para
#  aparecer no gabinete como "o Arduino nao funciona".
#
#  Aqui os dois lados sao os de verdade e no meio ha uma porta que o
#  sistema trata como porta serial. Nesta ponta do fio, um Arduino de
#  mentira.
import shutil
godot = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
if not godot:
    print("PONTA_A_PONTA_PULADO (sem godot no caminho)")
    sys.exit(0)

mestre2, escravo2 = pty.openpty()
porta2 = os.ttyname(escravo2)
ambiente = dict(os.environ, PUNCH_PORTA_FALSA=porta2)
jogo = subprocess.Popen(
    [godot, "--headless", "--path", raiz, "--script", "tools/ponte_ponta_a_ponta.gd"],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=ambiente, bufsize=0)

def responder(texto):
    os.write(mestre2, (texto + "\r\n").encode())

sobras = b""
falou = False
proximo_ready = 0.0
fim = time.time() + 60.0
while time.time() < fim and jogo.poll() is None:
    # A placa se apresenta ate alguem falar com ela: nao ha como saber
    # daqui o instante exato em que a ponte abriu a porta, e o READY
    # perdido faria o teste inteiro parecer um defeito de protocolo.
    if not falou and time.time() >= proximo_ready:
        responder("READY,PUNCH_MPU6050,V3")
        proximo_ready = time.time() + 0.15
    pronto, _, _ = select.select([mestre2], [], [], 0.05)
    if not pronto:
        continue
    try:
        sobras += os.read(mestre2, 4096)
    except OSError:
        break
    while b"\n" in sobras:
        crua, sobras = sobras.split(b"\n", 1)
        pedido = crua.decode("utf-8", "replace").strip()
        if not pedido:
            continue
        falou = True
        if pedido == "PING":
            responder("PONG")
        elif pedido == "RAJADA":
            # Trinta linhas coladas, como um botao apertado depressa.
            for i in range(30):
                responder("RAJADA,%d" % i)

saida = jogo.stdout.read().decode("utf-8", "replace") if jogo.stdout else ""
if jogo.poll() is None:
    jogo.kill()
    print("FALHA: o jogo nao terminou a conversa com a ponte")
    print(saida)
    sys.exit(1)
if "PONTA_A_PONTA_OK" not in saida:
    print("FALHA: ponta a ponta reprovou")
    print(saida.strip())
    sys.exit(1)
print("PONTA_A_PONTA_OK")

# ----------------------------------------------------------------------
#  TERCEIRA ETAPA: A PONTE DO WINDOWS, DE VERDADE.
# ----------------------------------------------------------------------
#
#  tools/ponte_serial.ps1 e o arquivo que vai rodar no gabinete -- e era
#  tambem o unico que nunca tinha rodado em lugar nenhum antes de chegar
#  la. Escrever codigo que so estreia na maquina do cliente foi
#  exatamente como a maquina ficou quebrada das outras vezes.
#
#  O PowerShell 7 roda em Linux e traz a mesma System.IO.Ports que o
#  Windows usa, entao o script pode ser cobrado aqui, contra a mesma
#  porta de mentira. O que sobra de diferente e a consulta ao gerenciador
#  de dispositivos, que so existe no Windows e ja esta dentro de um
#  try/catch -- e este teste, rodando fora do Windows, prova de quebra que
#  o catch segura.
pwsh = os.environ.get("PWSH") or shutil.which("pwsh") or shutil.which("powershell")
if not pwsh:
    print("PS1_PULADO (sem powershell no caminho)")
    sys.exit(0)

roteiro = os.path.join(raiz, "tools", "ponte_serial.ps1")
erros = subprocess.run(
    [pwsh, "-NoProfile", "-Command",
     "$e=$null;$f=$null;"
     "[System.Management.Automation.Language.Parser]::ParseFile('%s',[ref]$f,[ref]$e)|Out-Null;"
     "if($e -and $e.Count -gt 0){$e|ForEach-Object{$_.Extent.StartLineNumber.ToString()+': '+$_.Message};exit 1}"
     % roteiro],
    capture_output=True, text=True)
if erros.returncode != 0:
    print("FALHA: erro de sintaxe no ponte_serial.ps1")
    print(erros.stdout.strip() or erros.stderr.strip())
    sys.exit(1)

mestre3, escravo3 = pty.openpty()
porta3 = os.ttyname(escravo3)
ps = subprocess.Popen([pwsh, "-NoProfile", "-NonInteractive", "-File", roteiro, porta3, "115200"],
                      stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                      stderr=subprocess.STDOUT, bufsize=0)

def dizer3(linha):
    ps.stdin.write((linha + "\n").encode())
    ps.stdin.flush()

def esperar3(alvo, segundos=25.0):
    fim = time.time() + segundos
    vistas = []
    while time.time() < fim:
        if ps.poll() is not None:
            print("FALHA: o ponte_serial.ps1 morreu esperando %r; vi %r" % (alvo, vistas))
            print(ps.stdout.read().decode("utf-8", "replace"))
            sys.exit(1)
        pronto, _, _ = select.select([ps.stdout], [], [], 0.2)
        if not pronto:
            continue
        linha = ps.stdout.readline().decode("utf-8", "replace").strip()
        if not linha:
            continue
        vistas.append(linha)
        if alvo in linha:
            return vistas
    print("FALHA: o ponte_serial.ps1 nao disse %r; disse %r" % (alvo, vistas))
    ps.kill()
    sys.exit(1)

# A APRESENTACAO PRECISA VIR LIMPA, E ESTA E A LINHA MAIS FRAGIL DE TODAS.
# O console do Windows poe tres bytes invisiveis (o BOM) no comeco da
# primeira coisa que se escreve. Caindo dentro do "#PONTE,V1", o jogo nao
# reconhece a ponte e conclui que nao ha caminho ate a placa.
vistas = esperar3("#PONTE,V1")
if not vistas[0].startswith("#PONTE,V1"):
    print("FALHA: sujeira antes da apresentacao: %r" % vistas[0])
    sys.exit(1)
esperar3("#ABERTA," + porta3)

os.write(mestre3, b"READY,PUNCH_MPU6050,V3\r\n")
esperar3("READY,PUNCH_MPU6050,V3")

# Rajada: nada pode se perder nem sair fora de ordem.
for i in range(30):
    os.write(mestre3, ("RAJADA,%d\r\n" % i).encode())
vistas = esperar3("RAJADA,29")
so_rajada = [v for v in vistas if v.startswith("RAJADA,")]
if so_rajada != ["RAJADA,%d" % i for i in range(30)]:
    print("FALHA: a rajada chegou torta pela ponte do Windows: %r" % so_rajada)
    sys.exit(1)

# O caminho de volta: sem ele nao ha CONFIG, nem LEDS, nem PING.
dizer3("LEDS,640")
fim = time.time() + 15.0
eco = b""
while time.time() < fim and b"LEDS,640" not in eco:
    pronto, _, _ = select.select([mestre3], [], [], 0.2)
    if pronto:
        eco += os.read(mestre3, 4096)
if b"LEDS,640" not in eco:
    print("FALHA: o comando do jogo nao chegou na porta pela ponte do Windows (%r)" % eco)
    ps.kill()
    sys.exit(1)

dizer3("@FECHAR")
esperar3("#FECHADA")
dizer3("@LISTAR")
esperar3("#PORTAS")
dizer3("@SAIR")
try:
    ps.wait(timeout=15)
except subprocess.TimeoutExpired:
    print("FALHA: o ponte_serial.ps1 nao saiu quando mandaram sair")
    ps.kill()
    sys.exit(1)
print("PS1_OK")

# ----------------------------------------------------------------------
#  QUARTA ETAPA: O PLANO B DO PLANO B.
# ----------------------------------------------------------------------
#
#  Quando a politica da maquina proibe rodar arquivos .ps1 -- regra de
#  grupo, rede de empresa -- o `-ExecutionPolicy Bypass` nao vence, e a
#  ponte morreria antes de dizer a primeira palavra. O jogo entao tenta de
#  novo mandando o script como COMANDO CODIFICADO, que a politica nao
#  alcanca. Este caminho tambem tem de funcionar, e o unico jeito de saber
#  e rodando.
#
#  O base64 e montado aqui exatamente como o Godot monta: UTF-16
#  little-endian, sem marca de ordem de bytes.
#  O comando e montado PELO PROPRIO GODOT, e nao por uma imitacao feita
#  aqui: uma imitacao passaria no teste mesmo com o de verdade quebrado.
montagem = subprocess.run(
    [godot, "--headless", "--path", raiz, "--script", "tools/ponte_codificada.gd"],
    capture_output=True, text=True)
codificado = ""
for linha in montagem.stdout.splitlines():
    linha = linha.strip()
    if len(linha) > 200 and linha.replace("+", "").replace("/", "").replace("=", "").isalnum():
        codificado = linha
if not codificado:
    print("FALHA: o Godot nao montou o comando codificado")
    print(montagem.stdout.strip(), montagem.stderr.strip())
    sys.exit(1)
if len(codificado) > 30000:
    print("FALHA: o comando codificado (%d) nao cabe na linha de comando do Windows" % len(codificado))
    sys.exit(1)

ps2 = subprocess.Popen(
    [pwsh, "-NoProfile", "-NonInteractive", "-EncodedCommand", codificado],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
fim = time.time() + 30.0
vistas = []
ok = False
while time.time() < fim and not ok:
    if ps2.poll() is not None:
        break
    pronto, _, _ = select.select([ps2.stdout], [], [], 0.2)
    if not pronto:
        continue
    linha = ps2.stdout.readline().decode("utf-8", "replace").strip()
    if linha:
        vistas.append(linha)
    if linha.startswith("#PONTE,V1"):
        ok = True
if not ok:
    print("FALHA: o script codificado nao se apresentou; disse %r" % vistas)
    ps2.kill()
    sys.exit(1)
# Ele tem de continuar sendo uma ponte de verdade, e nao so imprimir a
# apresentacao: aceitar comando e sair quando mandarem.
ps2.stdin.write(b"@LISTAR\n")
ps2.stdin.flush()
fim = time.time() + 15.0
achou = False
while time.time() < fim and not achou and ps2.poll() is None:
    pronto, _, _ = select.select([ps2.stdout], [], [], 0.2)
    if pronto and ps2.stdout.readline().decode("utf-8", "replace").startswith("#PORTAS"):
        achou = True
if not achou:
    print("FALHA: o script codificado nao respondeu a @LISTAR")
    ps2.kill()
    sys.exit(1)
ps2.stdin.write(b"@SAIR\n")
ps2.stdin.flush()
try:
    ps2.wait(timeout=15)
except subprocess.TimeoutExpired:
    print("FALHA: o script codificado nao saiu quando mandaram sair")
    ps2.kill()
    sys.exit(1)
print("PS1_CODIFICADO_OK (%d caracteres na linha de comando)" % len(codificado))
PY
