"""Banco de áudio do Punch Challenge, sintetizado do zero.

POR QUE SINTETIZAR EM VEZ DE BAIXAR. Uma máquina que fica num salão de
festas toca os mesmos quinze sons mil vezes por dia; qualquer amostra
licenciada vira um problema de licença multiplicado por cada gabinete
vendido. Sintetizando, o banco é do projeto, é reproduzível (a semente
é fixa) e cabe no repositório.

O QUE MUDOU EM RELAÇÃO À PRIMEIRA VERSÃO. Antes cada efeito era meia
dúzia de senóides com um decaimento exponencial por cima. Isso não é som
de fliperama, é bipe de relógio: falta o TRANSIENTE (o estalo dos
primeiros milissegundos, que é o que o ouvido usa para julgar "forte"),
falta GRAVE (o corpo que se sente no peito), falta RUÍDO (nenhuma
percussão real é periódica) e falta ESPAÇO (tudo soava colado no
alto-falante).

Agora cada som é montado em camadas, do jeito que um sound designer
monta:

    transiente  →  clique curtíssimo, ruído filtrado no agudo
    corpo       →  a parte afinada, que dá a nota
    grave       →  senóide varrendo para baixo, que dá o peso
    cauda       →  reverberação curta, que dá o tamanho da sala

e passa por saturação, que é o que faz um som parecer ALTO sem precisar
de volume — o mesmo truque de um disco masterizado.

Uso: python3 tools/gerar_audio_arcade.py
"""

from pathlib import Path
import wave
import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio" / "arcade"
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(8258)

# ======================================================================
# FERRAMENTAS DE DSP
# ======================================================================

def n_amostras(segundos: float) -> int:
    return int(round(segundos * RATE))


def tempo(segundos: float) -> np.ndarray:
    return np.arange(n_amostras(segundos)) / RATE


def ruido(segundos: float) -> np.ndarray:
    return rng.normal(0.0, 1.0, n_amostras(segundos))


def senoide(freq, segundos: float, fase: float = 0.0) -> np.ndarray:
    """`freq` pode ser um número ou uma curva de frequência por amostra."""
    t = tempo(segundos)
    if np.isscalar(freq):
        return np.sin(2 * np.pi * freq * t + fase)
    # Frequência variável: a fase é a INTEGRAL da frequência. Multiplicar
    # freq por t (o erro comum) dá um glissando com o dobro da inclinação.
    return np.sin(2 * np.pi * np.cumsum(np.asarray(freq)) / RATE + fase)


def dente(freq, segundos: float, harmonicos: int = 14) -> np.ndarray:
    """Serra por soma de harmônicos: sem alias, ao contrário da rampa."""
    saida = np.zeros(n_amostras(segundos))
    for h in range(1, harmonicos + 1):
        f = np.asarray(freq) * h if not np.isscalar(freq) else freq * h
        limite = f if np.isscalar(f) else np.max(f)
        if limite > RATE * 0.45:
            break
        saida += senoide(f, segundos) / h
    return saida * 0.6


def quadrada(freq, segundos: float, harmonicos: int = 9) -> np.ndarray:
    saida = np.zeros(n_amostras(segundos))
    for h in range(1, harmonicos * 2, 2):
        f = np.asarray(freq) * h if not np.isscalar(freq) else freq * h
        limite = f if np.isscalar(f) else np.max(f)
        if limite > RATE * 0.45:
            break
        saida += senoide(f, segundos) / h
    return saida * 0.8


def varredura(f0: float, f1: float, segundos: float, curva: float = 3.0) -> np.ndarray:
    """Curva de frequência de f0 a f1. Exponencial, porque é assim que o
    ouvido percebe altura — uma rampa linear soa lenta no fim."""
    t = np.linspace(0.0, 1.0, n_amostras(segundos))
    return f0 * (f1 / f0) ** (1.0 - np.exp(-curva * t)) ** 1.0


def env_ad(segundos: float, ataque: float, queda: float, curva: float = 2.5) -> np.ndarray:
    """Envelope ataque-queda. O ataque curtíssimo é o que dá o estalo."""
    n = n_amostras(segundos)
    na = max(1, n_amostras(ataque))
    env = np.ones(n)
    env[:na] = np.linspace(0.0, 1.0, na) ** 0.6
    resto = n - na
    if resto > 0 and queda > 0:
        env[na:] = np.exp(-curva * np.linspace(0.0, segundos / queda, resto))
    return env


def biquad(x: np.ndarray, freq: float, q: float, modo: str) -> np.ndarray:
    """Filtro RBJ de segunda ordem. Um pólo só (média móvel) não tem
    inclinação suficiente para separar um chimbal de um estalo."""
    freq = float(np.clip(freq, 20.0, RATE * 0.45))
    w = 2.0 * np.pi * freq / RATE
    alpha = np.sin(w) / (2.0 * q)
    cw = np.cos(w)
    if modo == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
    elif modo == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
    else:  # bp
        b = [alpha, 0.0, -alpha]
    a = [1 + alpha, -2 * cw, 1 - alpha]
    b = [c / a[0] for c in b]
    a = [c / a[0] for c in a]
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, amostra in enumerate(x):
        saida = b[0] * amostra + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1 = x1, amostra
        y2, y1 = y1, saida
        y[i] = saida
    return y


def satura(x: np.ndarray, forca: float = 2.5) -> np.ndarray:
    """Saturação suave. É o que faz um som parecer ALTO sem subir o
    volume: os picos achatam e a energia média sobe."""
    return np.tanh(x * forca) / np.tanh(forca)


def reverb(x: np.ndarray, tamanho: float = 0.5, mistura: float = 0.25) -> np.ndarray:
    """Reverberação de Schroeder: quatro pentes em paralelo e dois
    passa-tudo em série. Barata e suficiente para dar tamanho de sala."""
    combs = [0.0297, 0.0371, 0.0411, 0.0437]
    saida = np.zeros(len(x) + n_amostras(0.6))
    entrada = np.concatenate([x, np.zeros(n_amostras(0.6))])
    for atraso_s in combs:
        d = n_amostras(atraso_s)
        buf = np.zeros(len(entrada))
        realim = 0.78 * tamanho + 0.14
        for i in range(len(entrada)):
            anterior = buf[i - d] if i >= d else 0.0
            buf[i] = entrada[i] + anterior * realim
        saida += buf / len(combs)
    for atraso_s in (0.005, 0.0017):
        d = n_amostras(atraso_s)
        buf = np.zeros(len(saida))
        for i in range(len(saida)):
            anterior = buf[i - d] if i >= d else 0.0
            buf[i] = -0.7 * saida[i] + anterior + 0.7 * (saida[i - d] if i >= d else 0.0)
        saida = buf
    seco = np.concatenate([x, np.zeros(len(saida) - len(x))])
    return seco * (1.0 - mistura) + saida * mistura


def somar(destino: np.ndarray, trecho: np.ndarray, posicao: int, ganho: float = 1.0,
          circular: bool = False) -> None:
    """Mistura `trecho` em `destino` na posição dada.

    Com `circular`, o que passa do fim volta para o começo — é isso que
    faz a cauda de um prato atravessar a emenda de um loop sem o clique
    que denuncia repetição.
    """
    n = len(destino)
    if posicao >= n:
        return
    fim = posicao + len(trecho)
    if fim <= n:
        destino[posicao:fim] += trecho * ganho
        return
    corte = n - posicao
    destino[posicao:] += trecho[:corte] * ganho
    if circular:
        sobra = trecho[corte:]
        destino[: min(len(sobra), n)] += sobra[: min(len(sobra), n)] * ganho


def masterizar(x: np.ndarray, alvo_rms: float = 0.15) -> np.ndarray:
    """Iguala o volume PERCEBIDO e depois segura os picos.

    Normalizar pelo pico — que era o que a versão anterior fazia — deixa
    o volume à mercê do transiente: um som com estalo curto e forte fica
    com o corpo inaudível, e no jogo a fanfarra de recorde saía mais
    baixa que o tique da contagem. Casando o RMS, todos os efeitos
    chegam com a mesma presença; o limitador suave impede que a conta
    estoure os picos."""
    rms = float(np.sqrt(np.mean(x ** 2)))
    if rms > 1e-9:
        x = x * (alvo_rms / rms)
    joelho = 0.70
    acima = np.abs(x) > joelho
    if np.any(acima):
        excesso = (np.abs(x[acima]) - joelho) / (1.0 - joelho)
        x[acima] = np.sign(x[acima]) * (joelho + (1.0 - joelho) * np.tanh(excesso))
    return np.clip(x, -0.985, 0.985)


def salvar(nome: str, esquerda: np.ndarray, direita: np.ndarray = None,
           loop: bool = False, alvo_rms: float = 0.15) -> None:
    """Grava estéreo 16 bits. Estéreo porque é o que separa um efeito de
    2026 de um bipe de 1985: a largura é metade da sensação de moderno."""
    if direita is None:
        direita = esquerda.copy()
    tamanho = min(len(esquerda), len(direita))
    esquerda, direita = esquerda[:tamanho], direita[:tamanho]
    if not loop:
        # Rampa de saída: sem ela o corte no fim vira estalo.
        n = min(n_amostras(0.006), tamanho // 4)
        if n > 0:
            janela = np.linspace(1.0, 0.0, n)
            esquerda[-n:] *= janela
            direita[-n:] *= janela
    junto = np.stack([esquerda, direita], axis=1)
    junto = masterizar(junto, alvo_rms)
    with wave.open(str(OUT / (nome + ".wav")), "wb") as arquivo:
        arquivo.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        arquivo.writeframes((junto * 32767).astype("<i2").tobytes())


def nota(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


# ======================================================================
# INSTRUMENTOS
# ======================================================================

def bumbo(segundos: float = 0.42, f0: float = 165.0, f1: float = 44.0) -> np.ndarray:
    corpo = senoide(varredura(f0, f1, segundos, 6.0), segundos) * env_ad(segundos, 0.001, 0.11, 4.0)
    clique = biquad(ruido(0.012), 2600, 0.9, "hp") * env_ad(0.012, 0.0002, 0.004, 6.0)
    saida = corpo * 1.0
    somar(saida, clique, 0, 0.35)
    return satura(saida, 1.9)


def caixa(segundos: float = 0.26) -> np.ndarray:
    corpo = ruido(segundos) * env_ad(segundos, 0.001, 0.055, 4.0)
    corpo = biquad(corpo, 1900, 0.8, "bp") * 1.4 + biquad(corpo, 320, 1.2, "bp") * 0.7
    afinado = senoide(varredura(330, 180, segundos, 8.0), segundos) * env_ad(segundos, 0.001, 0.035, 5.0)
    return satura(corpo * 0.8 + afinado * 0.45, 1.6)


def chimbal(segundos: float = 0.055, aberto: bool = False) -> np.ndarray:
    dur = 0.24 if aberto else segundos
    x = biquad(ruido(dur), 8200, 0.7, "hp")
    return x * env_ad(dur, 0.0005, 0.05 if aberto else 0.012, 5.0) * 0.6


def prato(segundos: float = 1.4) -> np.ndarray:
    x = biquad(ruido(segundos), 6000, 0.5, "hp")
    return x * env_ad(segundos, 0.002, 0.45, 3.0) * 0.5


def blip(midi: float, segundos: float, forma=quadrada, queda: float = 0.05) -> np.ndarray:
    return forma(nota(midi), segundos) * env_ad(segundos, 0.002, queda, 3.5)


def impacto(segundos: float = 0.75, peso: float = 1.0) -> np.ndarray:
    """O soco. Quatro camadas, e é a soma delas que soa caro."""
    grave = senoide(varredura(150 * peso, 38, segundos, 7.0), segundos) * env_ad(segundos, 0.001, 0.13, 3.5)
    estalo = biquad(ruido(0.03), 3200, 0.8, "hp") * env_ad(0.03, 0.0002, 0.008, 6.0)
    couro = biquad(ruido(segundos), 900, 1.1, "bp") * env_ad(segundos, 0.001, 0.06, 4.0)
    metal = senoide(varredura(520, 210, 0.25, 9.0), 0.25) * env_ad(0.25, 0.001, 0.05, 4.0)
    saida = grave * 1.0
    somar(saida, estalo, 0, 0.75)
    saida += couro * 0.6
    somar(saida, metal, 0, 0.30)
    return satura(saida, 2.4)


def subida(segundos: float, f0: float = 180.0, f1: float = 2400.0) -> np.ndarray:
    """Riser: ruído filtrado subindo. É o som que promete que algo vem."""
    x = ruido(segundos)
    passo = max(1, n_amostras(segundos) // 40)
    saida = np.zeros(n_amostras(segundos))
    curva = np.geomspace(f0, f1, 40)
    for i, corte in enumerate(curva):
        fatia = slice(i * passo, min((i + 1) * passo, len(saida)))
        if fatia.start >= len(saida):
            break
        saida[fatia] = biquad(x[fatia], corte, 2.2, "bp")
    return saida * np.linspace(0.15, 1.0, len(saida)) ** 1.6


def arpejo(midis, segundos_por_nota: float, forma=quadrada, cauda: float = 0.28) -> np.ndarray:
    total = len(midis) * segundos_por_nota + cauda
    saida = np.zeros(n_amostras(total))
    for i, m in enumerate(midis):
        voz = blip(m, segundos_por_nota + cauda, forma, cauda * 0.55)
        somar(saida, voz, n_amostras(i * segundos_por_nota), 0.5)
    return saida


def largura(x: np.ndarray, atraso_ms: float = 12.0, ganho: float = 0.55):
    """Espalha um som mono no estéreo com um atraso curto de um lado (o
    efeito Haas). Duas linhas, e o som deixa de sair de um ponto só."""
    d = n_amostras(atraso_ms / 1000.0)
    direita = np.zeros(len(x) + d)
    direita[d:] = x * ganho
    esquerda = np.concatenate([x, np.zeros(d)])
    return esquerda, direita


# ======================================================================
# EFEITOS
# ======================================================================

def gerar_efeitos() -> None:
    # --- o soco: o som mais importante do jogo
    seco = impacto(0.85, 1.0)
    molhado = reverb(seco, 0.55, 0.30)
    e, d = largura(molhado, 9.0, 0.8)
    salvar("hit", e, d)

    # --- contagem: blip curto e seco, com peso
    conta = blip(88, 0.16, quadrada, 0.035) * 0.9
    somar(conta, senoide(varredura(700, 480, 0.1, 8.0), 0.1) * env_ad(0.1, 0.001, 0.03, 4.0), 0, 0.5)
    salvar("count", satura(conta, 1.5))

    # --- GO: riser curto terminando num impacto
    vai = np.zeros(n_amostras(0.9))
    somar(vai, subida(0.42, 220, 3000), 0, 0.8)
    somar(vai, impacto(0.6, 0.8), n_amostras(0.40), 1.0)
    somar(vai, prato(0.8), n_amostras(0.40), 0.5)
    e, d = largura(reverb(vai, 0.5, 0.25), 11.0)
    salvar("go", e, d)

    # --- start: fanfarra curta ascendente + bumbo
    ini = arpejo([57, 64, 69, 76], 0.085, quadrada, 0.34)
    somar(ini, bumbo(0.4), 0, 0.9)
    somar(ini, prato(1.0), n_amostras(0.255), 0.45)
    e, d = largura(reverb(ini, 0.45, 0.22), 13.0)
    salvar("start", e, d)

    # --- crédito: duas moedas metálicas (FM curta)
    moeda = np.zeros(n_amostras(0.5))
    for i, m in enumerate((93, 100)):
        f = nota(m)
        t = tempo(0.24)
        voz = np.sin(2 * np.pi * f * t + 3.4 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-24 * t))
        somar(moeda, voz * env_ad(0.24, 0.0008, 0.06, 4.0), n_amostras(i * 0.085), 0.55)
    e, d = largura(reverb(moeda, 0.35, 0.2), 8.0)
    salvar("credit", e, d)

    # --- menu: tique curtíssimo
    salvar("menu", satura(blip(84, 0.06, quadrada, 0.014), 1.3))

    # --- erro: zumbido descendente e sujo
    erro = dente(varredura(240, 90, 0.45, 5.0), 0.45) * env_ad(0.45, 0.002, 0.13, 3.0)
    salvar("error", satura(erro, 3.2))

    # --- médio / vitória / lendário: a mesma família, subindo de porte
    medio = arpejo([64, 71, 76], 0.10, quadrada, 0.36)
    somar(medio, bumbo(0.35), 0, 0.6)
    e, d = largura(reverb(medio, 0.45, 0.24), 12.0)
    salvar("medium", e, d)

    venceu = arpejo([69, 73, 76, 81], 0.095, quadrada, 0.5)
    somar(venceu, bumbo(0.45), 0, 0.8)
    somar(venceu, prato(1.2), n_amostras(0.285), 0.5)
    e, d = largura(reverb(venceu, 0.6, 0.3), 14.0)
    salvar("win", e, d)

    lenda = np.zeros(n_amostras(2.6))
    somar(lenda, subida(0.5, 300, 3600), 0, 0.5)
    for i, m in enumerate((57, 64, 69, 73, 76, 81, 88)):
        voz = blip(m, 0.9, dente, 0.35) + blip(m + 12, 0.9, quadrada, 0.3) * 0.4
        somar(lenda, voz, n_amostras(0.5 + i * 0.075), 0.42)
    somar(lenda, impacto(1.0, 1.1), n_amostras(0.5), 0.9)
    somar(lenda, prato(1.6), n_amostras(0.5), 0.6)
    e, d = largura(reverb(lenda, 0.75, 0.34), 16.0)
    salvar("legendary", e, d)

    # --- derrota: descida curta e abafada
    perdeu = arpejo([64, 59, 52], 0.14, dente, 0.4)
    perdeu = biquad(perdeu, 1400, 0.7, "lp")
    e, d = largura(reverb(perdeu, 0.4, 0.2), 10.0)
    salvar("lose", e, d)

    # --- recorde: brilho subindo, sem peso grave (o peso já veio do hit)
    rec = np.zeros(n_amostras(2.0))
    for i, m in enumerate((81, 85, 88, 93, 96, 100)):
        somar(rec, blip(m, 0.7, quadrada, 0.26), n_amostras(i * 0.085), 0.4)
    somar(rec, prato(1.4), 0, 0.45)
    e, d = largura(reverb(rec, 0.7, 0.34), 15.0)
    salvar("record", e, d)

    # --- ranking: varredura entrando na lista
    rank = np.zeros(n_amostras(1.5))
    somar(rank, subida(0.45, 400, 5200), 0, 0.55)
    for i, m in enumerate((76, 81, 85, 88)):
        somar(rank, blip(m, 0.55, quadrada, 0.2), n_amostras(0.42 + i * 0.075), 0.42)
    e, d = largura(reverb(rank, 0.55, 0.28), 13.0)
    salvar("ranking", e, d)

    # --- obturador: mecânico, dois estalos e uma mola
    obt = np.zeros(n_amostras(0.3))
    for pos, ganho in ((0.0, 1.0), (0.055, 0.7)):
        somar(obt, biquad(ruido(0.018), 3600, 1.1, "hp") * env_ad(0.018, 0.0002, 0.004, 7.0),
              n_amostras(pos), ganho)
    somar(obt, biquad(ruido(0.12), 5200, 3.0, "bp") * env_ad(0.12, 0.001, 0.03, 5.0),
          n_amostras(0.012), 0.35)
    salvar("shutter", satura(obt, 1.4))


# ======================================================================
# LOOPS
# ======================================================================

def gerar_loops() -> None:
    # --- carga: serra grave subindo, com tremolo. Emenda exata em 1 s.
    dur = 1.0
    n = n_amostras(dur)
    t = np.arange(n) / RATE
    # AS DUAS FREQUÊNCIAS PRECISAM FECHAR CICLO INTEIRO EM UM SEGUNDO.
    # A versão anterior desafinava a segunda serra em 110,5 Hz: meio
    # ciclo sobrando na emenda, e o loop estalava a cada volta.
    #
    # E O FILTRO PRECISA ENTRAR AQUECIDO. Um biquad começa com estado
    # zerado, então os primeiros milissegundos saem abafados enquanto o
    # fim do loop já está em regime — o degrau entre os dois é outro
    # clique. Filtrando DOIS períodos e ficando com o segundo, o trecho
    # gravado é todo regime permanente.
    base2 = dente(110.0, dur * 2) + dente(111.0, dur * 2) * 0.6
    fechado = biquad(base2, 480.0, 2.6, "lp")[n:]
    aberto = biquad(base2, 2300.0, 2.6, "lp")[n:]
    mistura = 0.5 + 0.5 * np.sin(2 * np.pi * 1.0 * t - np.pi / 2)
    filtrado = fechado * (1.0 - mistura) + aberto * mistura
    tremolo = 0.72 + 0.28 * np.sin(2 * np.pi * 8.0 * t)
    e, d = filtrado * tremolo, np.roll(filtrado * tremolo, n_amostras(0.004))
    salvar("charge", satura(e, 1.8), satura(d, 1.8), loop=True, alvo_rms=0.12)

    # --- contagem do placar: tique rápido. O jogo ainda muda o pitch.
    dur = 0.5
    n = n_amostras(dur)
    tick = np.zeros(n)
    for i in range(8):
        somar(tick, blip(96, 0.06, quadrada, 0.012), n_amostras(i * dur / 8.0), 0.7, circular=True)
    salvar("score_loop", tick, np.roll(tick, n_amostras(0.003)), loop=True, alvo_rms=0.11)

    # --- música da abertura
    salvar_musica()


def salvar_musica() -> None:
    """Tema da abertura: 8 compassos em 150 BPM, lá menor.

    Loop de verdade, e não uma sequência que reinicia: as caudas que
    passam do fim voltam para o começo (`circular=True`), então a emenda
    não estala. É o que separa uma trilha que a pessoa ouve o dia inteiro
    de uma que irrita depois da terceira volta.
    """
    bpm = 150.0
    batida = 60.0 / bpm
    compassos = 8
    dur = compassos * 4 * batida
    n = n_amostras(dur)
    esq = np.zeros(n)
    dir_ = np.zeros(n)

    def pos(compasso: float) -> int:
        return n_amostras(compasso * 4 * batida)

    # Progressão i - VI - III - VII, dois compassos cada: a mais direta
    # que existe para soar grande sem exigir atenção.
    acordes = [
        (45, [57, 60, 64]),   # Am
        (41, [57, 60, 65]),   # F
        (48, [55, 60, 64]),   # C
        (43, [55, 59, 62]),   # G
    ]

    for c in range(compassos):
        raiz, notas = acordes[(c // 2) % 4]
        base_c = float(c)

        # Bateria: bumbo em todos os tempos, caixa em 2 e 4, chimbal nas
        # colcheias. É a fórmula que faz qualquer coisa andar.
        for b in range(4):
            somar(esq, bumbo(0.40), pos(base_c + b / 4.0), 0.95, True)
            somar(dir_, bumbo(0.40), pos(base_c + b / 4.0), 0.95, True)
            if b in (1, 3):
                cx = caixa(0.28)
                somar(esq, cx, pos(base_c + b / 4.0), 0.55, True)
                somar(dir_, cx, pos(base_c + b / 4.0), 0.55, True)
            for meia in (0.0, 0.5):
                ch = chimbal(0.05, aberto=(b == 3 and meia == 0.5))
                # Chimbal alternando de lado: é o que dá largura sem
                # mexer no que precisa ficar no centro (bumbo e baixo).
                forte = 0.38 if meia == 0.0 else 0.22
                fraco = 0.22 if meia == 0.0 else 0.38
                somar(esq, ch, pos(base_c + (b + meia) / 4.0), forte, True)
                somar(dir_, ch, pos(base_c + (b + meia) / 4.0), fraco, True)

        # Baixo: colcheias na tônica, com salto de oitava no fim do compasso.
        for oitavo in range(8):
            m = raiz + (12 if oitavo in (6, 7) else 0)
            voz = dente(nota(m), 0.24) * env_ad(0.24, 0.002, 0.055, 3.5)
            voz = biquad(voz, 320.0, 1.1, "lp")
            somar(esq, voz, pos(base_c + oitavo / 8.0), 0.55, True)
            somar(dir_, voz, pos(base_c + oitavo / 8.0), 0.55, True)

        # Arpejo em semicolcheias, alternando os lados: é ele que dá a
        # sensação de velocidade sem acelerar a batida.
        for s in range(16):
            m = notas[s % len(notas)] + (12 if (s // len(notas)) % 2 else 0)
            voz = quadrada(nota(m), 0.16) * env_ad(0.16, 0.001, 0.035, 4.0)
            voz = biquad(voz, 2600.0, 1.4, "lp")
            ganho = 0.24 if s % 2 == 0 else 0.16
            somar(esq if s % 2 == 0 else dir_, voz, pos(base_c + s / 16.0), ganho, True)
            somar(dir_ if s % 2 == 0 else esq, voz, pos(base_c + s / 16.0), ganho * 0.18, True)

        # Prato no começo de cada bloco de dois compassos.
        if c % 2 == 0:
            pr = prato(1.3)
            somar(esq, pr, pos(base_c), 0.32, True)
            somar(dir_, pr, pos(base_c), 0.32, True)

    # Melodia sobre a segunda metade: o "gancho" que faz lembrar do jogo.
    gancho = [(0.0, 76), (0.5, 74), (1.0, 72), (1.75, 74), (2.0, 76), (3.0, 79), (3.5, 76)]
    for compasso_base in (4.0, 6.0):
        for atraso, m in gancho:
            voz = quadrada(nota(m), 0.5) * env_ad(0.5, 0.004, 0.16, 3.0)
            voz = biquad(voz, 3200.0, 1.0, "lp")
            # Gancho com atraso curto de um lado (efeito Haas): a melodia
            # deixa de sair de um ponto só e passa a envolver.
            somar(esq, voz, pos(compasso_base + atraso / 4.0), 0.26, True)
            somar(dir_, voz, pos(compasso_base + atraso / 4.0) + n_amostras(0.011), 0.24, True)

    # Riser no último compasso, empurrando para a volta do loop.
    somar(esq, subida(batida * 4, 300, 4200), pos(compassos - 1.0), 0.28, True)
    somar(dir_, subida(batida * 4, 300, 4200), pos(compassos - 1.0), 0.28, True)

    salvar("music", satura(esq, 1.35), satura(dir_, 1.35), loop=True, alvo_rms=0.17)


if __name__ == "__main__":
    gerar_efeitos()
    gerar_loops()
    print("ARCADE_AUDIO_OK")
