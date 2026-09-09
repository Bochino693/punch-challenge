"""Ponte de webcam para o Punch Challenge.

POR QUE UMA PONTE. O `CameraServer` do Godot não entrega feed no
Windows, que é onde o gabinete roda. Este processo local abre a webcam
com OpenCV e publica SÓ O QUADRO MAIS RECENTE num arquivo dentro do
`user://` do jogo. Nada vai para a rede, nada é acumulado em disco: o
mesmo arquivo é sobrescrito quinze vezes por segundo.

GRAVA EM TEMPORÁRIO E RENOMEIA. Sem isso, uma hora o jogo abre o arquivo
no meio da escrita e lê um JPEG cortado — defeito que só aparece na
máquina do cliente, uma vez a cada mil quadros. O `os.replace` é atômico
no Windows e no Linux.

MODOS DE USO

    python camera_bridge.py --probe
        Lista quais índices de câmera respondem. É por onde se começa
        quando a webcam "não funciona": se nenhum índice responde, o
        problema é driver ou cabo, e não o jogo.

    python camera_bridge.py --output C:\\...\\live.jpg
        Modo normal. É assim que o jogo chama.

    python camera_bridge.py --output ... --pattern
        Publica uma imagem sintética em vez da câmera. Serve para
        separar "a ponte está quebrada" de "a câmera está quebrada"
        sem precisar de webcam nenhuma — a mesma ideia do comando TEST
        do firmware do sensor.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

try:
    import cv2
    import numpy as np
except ImportError:
    # O JOGO PRECISA SABER O MOTIVO, e ele não lê a saída de erro.
    #
    # Sem isto, a falta do OpenCV aparecia como "o processo morreu na
    # hora" — indistinguível de câmera ocupada, cabo solto ou Python
    # errado. Escrever o motivo ao lado do JPEG é o que faz a Central
    # dizer o que instalar em vez de dizer que algo deu errado.
    for i, arg in enumerate(sys.argv):
        if arg == "--output" and i + 1 < len(sys.argv):
            try:
                destino = Path(sys.argv[i + 1])
                destino.parent.mkdir(parents=True, exist_ok=True)
                (destino.parent / "estado.txt").write_text(
                    "OPENCV AUSENTE - RODE tools/instalar_camera_windows.ps1|0|0",
                    encoding="utf-8",
                )
            except OSError:
                pass
    print(
        "OpenCV ausente. Instale com:  py -m pip install opencv-python",
        file=sys.stderr,
    )
    raise SystemExit(2)


# O OPENCV FALA DEMAIS QUANDO NÃO ACHA CÂMERA.
#
# Cada índice que não abre gera três ou quatro linhas de aviso interno
# ("VIDEOIO(V4L2): backend is generally available..."). Elas não dizem
# nada a quem está na frente do gabinete e, na tela de diagnóstico do
# jogo, empurram para fora as linhas que importam. Calamos o registro:
# quem precisa desse detalhe roda a ponte no terminal.
try:
    cv2.utils.logging.setLogLevel(cv2.utils.logging.LOG_LEVEL_SILENT)
except AttributeError:
    pass


# Ordem de tentativa dos back-ends. No Windows, DirectShow abre webcams
# baratas que o Media Foundation recusa; em algumas outras é o contrário,
# então vale tentar os dois antes de desistir.
def backends() -> list[tuple[str, int]]:
    if sys.platform == "win32":
        return [("DSHOW", cv2.CAP_DSHOW), ("MSMF", cv2.CAP_MSMF), ("ANY", cv2.CAP_ANY)]
    return [("V4L2", cv2.CAP_V4L2), ("ANY", cv2.CAP_ANY)]


def abrir(indice: int, largura: int, silencioso: bool = False, preferido: str = ""):
    """Abre a câmera testando cada back-end. Devolve (captura, nome) ou
    (None, "") — abrir sem conseguir LER um quadro não conta como aberta:
    várias webcams respondem `isOpened()` e só então falham.

    `preferido` põe na frente da fila o back-end que a sondagem já provou
    que funciona nesta máquina. Sem isso, toda religada da ponte repete a
    fila inteira, e cada tentativa frustrada de um back-end custa entre
    um e três segundos no Windows — tempo em que o gabinete fica sem
    prévia bem na hora da foto."""
    ordem = backends()
    if preferido:
        ordem = [b for b in ordem if b[0] == preferido] + [b for b in ordem if b[0] != preferido]
    for nome, backend in ordem:
        captura = cv2.VideoCapture(indice, backend)
        if captura.isOpened():
            captura.set(cv2.CAP_PROP_FRAME_WIDTH, largura)
            captura.set(cv2.CAP_PROP_FRAME_HEIGHT, int(largura * 3 / 4))
            captura.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            ok, quadro = captura.read()
            if ok and quadro is not None:
                return captura, nome
        captura.release()
        if not silencioso:
            print(f"  índice {indice} não respondeu em {nome}", file=sys.stderr)
    return None, ""


## ATÉ ONDE A VARREDURA VAI.
##
## Seis era pouco. No Windows a numeração da câmera anda quando se
## instala um driver de câmera virtual (OBS, Teams, DroidCam), quando a
## webcam do notebook está presente, e quando a webcam USB é ligada numa
## porta diferente. Uma máquina com OBS instalado pode pôr a SIGMA-W420
## no índice 7 sem nenhum aviso.
INDICE_MAXIMO = 10


def _resultado_do_indice(indice: int, largura: int) -> dict:
    """Tenta UM índice em TODOS os back-ends e conta o que aconteceu.

    A distinção que interessa não é "abriu ou não abriu": é

      * nem abriu           -> não existe câmera nesse número;
      * abriu e não leu     -> existe, mas alguém está com ela, ou o
                               driver aceita a conexão e não entrega
                               quadro (o caso clássico de privacidade
                               bloqueada no Windows);
      * abriu e leu         -> funciona.

    O segundo caso é o que fazia o diagnóstico antigo mentir: ele dizia
    "nenhuma câmera respondeu", que manda o operador conferir cabo e
    driver, quando o cabo e o driver estão certos e o problema é outro
    programa segurando a webcam.
    """
    tentativas = []
    for nome, backend in backends():
        try:
            captura = cv2.VideoCapture(indice, backend)
        except cv2.error:
            tentativas.append((nome, "erro", 0, 0))
            continue
        if not captura.isOpened():
            captura.release()
            tentativas.append((nome, "fechada", 0, 0))
            continue
        captura.set(cv2.CAP_PROP_FRAME_WIDTH, largura)
        captura.set(cv2.CAP_PROP_FRAME_HEIGHT, int(largura * 3 / 4))
        ok, quadro = captura.read()
        w = int(captura.get(cv2.CAP_PROP_FRAME_WIDTH))
        h = int(captura.get(cv2.CAP_PROP_FRAME_HEIGHT))
        captura.release()
        if ok and quadro is not None:
            tentativas.append((nome, "ok", w, h))
        else:
            tentativas.append((nome, "sem quadro", w, h))
    return {"indice": indice, "tentativas": tentativas}


def sondar(largura: int) -> int:
    """Varre os índices e diz, back-end por back-end, o que respondeu."""
    print(f"python: {sys.executable}")
    print(f"opencv: {cv2.__version__}")
    achou = []
    ocupadas = []
    for indice in range(INDICE_MAXIMO):
        resultado = _resultado_do_indice(indice, largura)
        bons = [t for t in resultado["tentativas"] if t[1] == "ok"]
        mudos = [t for t in resultado["tentativas"] if t[1] == "sem quadro"]
        if bons:
            nome, _, w, h = bons[0]
            # DUAS LINHAS: uma para gente, outra para o jogo.
            #
            # A da gente tem acento e travessão e muda quando alguém
            # melhora o texto; a do jogo é `INDICE=n` e não muda nunca.
            # Fazer o jogo ler a linha bonita é como uma correção de
            # português quebra a leitura da câmera.
            print(f"camera {indice}: OK via {nome} - {w}x{h}")
            print(f"INDICE={indice}")
            print(f"BACKEND={nome}")
            achou.append(indice)
        elif mudos:
            nomes = ", ".join(t[0] for t in mudos)
            print(f"camera {indice}: ABRE mas nao entrega quadro ({nomes})")
            ocupadas.append(indice)
    if achou:
        print(f"use --camera {achou[0]} (ou ajuste na Central Tecnica do jogo)")
        return 0
    if ocupadas:
        # ESTE É O DIAGNÓSTICO QUE FALTAVA. A câmera existe e o Windows a
        # entrega; o que não vem é o quadro. São só duas causas, e as
        # duas se resolvem sem mexer em cabo nenhum.
        print(f"CAMERA PRESENTE MAS MUDA nos indices {ocupadas}")
        print("1) feche Camera do Windows, Teams, Meet, OBS e o navegador")
        print("2) Windows: Privacidade > Camera > permitir que APLICATIVOS DE")
        print("   AREA DE TRABALHO acessem a camera")
        return 2
    print(f"nenhuma camera respondeu (indices 0 a {INDICE_MAXIMO - 1})")
    print("verifique cabo USB, driver, e se outro programa esta usando a webcam")
    return 1


def imagem_de_teste(largura: int, quadro_n: int):
    """Padrão sintético: barras de cor, um alvo e um relógio. O relógio
    é o que prova que a imagem está VIVA e não é um arquivo parado."""
    altura = int(largura * 3 / 4)
    img = np.zeros((altura, largura, 3), dtype=np.uint8)
    cores = [(60, 25, 200), (40, 200, 240), (80, 200, 90), (200, 120, 60)]
    for i, cor in enumerate(cores):
        x0 = largura * i // len(cores)
        x1 = largura * (i + 1) // len(cores)
        img[:, x0:x1] = cor
    centro = (largura // 2, altura // 2)
    for raio in range(int(altura * 0.42), 0, -int(altura * 0.10)):
        cv2.circle(img, centro, raio, (255, 255, 255), 3)
    cv2.putText(img, "PADRAO DE TESTE", (int(largura * 0.06), int(altura * 0.14)),
                cv2.FONT_HERSHEY_SIMPLEX, largura / 900.0, (255, 255, 255), 2)
    cv2.putText(img, f"{quadro_n:05d}", (int(largura * 0.06), int(altura * 0.94)),
                cv2.FONT_HERSHEY_SIMPLEX, largura / 700.0, (20, 20, 20), 3)
    return img


def escrever(destino: Path, temporario: Path, quadro, qualidade: int) -> bool:
    ok, buffer = cv2.imencode(".jpg", quadro, [cv2.IMWRITE_JPEG_QUALITY, qualidade])
    if not ok:
        return False
    temporario.write_bytes(buffer.tobytes())
    os.replace(temporario, destino)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", help="arquivo JPEG que o jogo lê")
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--fps", type=float, default=15.0)
    parser.add_argument("--quality", type=int, default=80)
    parser.add_argument("--probe", action="store_true", help="lista as câmeras e sai")
    parser.add_argument("--backend", default="", help="back-end preferido (DSHOW, MSMF, ANY, V4L2)")
    parser.add_argument("--pattern", action="store_true", help="imagem sintética")
    args = parser.parse_args()

    if args.probe:
        return sondar(args.width)
    if not args.output:
        parser.error("--output é obrigatório fora do modo --probe")

    destino = Path(args.output)
    destino.parent.mkdir(parents=True, exist_ok=True)
    temporario = destino.with_name(destino.stem + ".tmp.jpg")
    # Ao lado do JPEG fica uma linha de estado, para a Central Técnica e
    # para quem estiver depurando saberem o que a ponte está fazendo.
    estado = destino.with_name("estado.txt")
    intervalo = 1.0 / max(args.fps, 1.0)

    estado_tmp = estado.with_name("estado.tmp.txt")
    contador = 0

    def anotar(texto: str) -> None:
        """Publica o estado E O CONTADOR DE QUADROS.

        O contador existe porque a data de modificação do arquivo tem
        resolução de UM SEGUNDO em vários sistemas de arquivos: com ela,
        o jogo não consegue distinguir "quinze quadros novos" de "a
        ponte travou há novecentos milissegundos". Com um contador que
        só sobe, travamento é contador parado, e isso se detecta em
        décimos de segundo.

        Escrito em temporário e renomeado, como o JPEG: uma leitura no
        meio da escrita devolveria uma linha cortada, e uma linha
        cortada vira um contador errado.
        """
        try:
            estado_tmp.write_text(
                "%s|%d|%d" % (texto, contador, int(time.time() * 1000)),
                encoding="utf-8",
            )
            os.replace(estado_tmp, estado)
        except OSError:
            pass

    if args.pattern:
        anotar("PADRAO DE TESTE")
        quadro_n = 0
        try:
            while True:
                escrever(destino, temporario, imagem_de_teste(args.width, quadro_n), args.quality)
                quadro_n += 1
                contador = quadro_n
                anotar("PADRAO DE TESTE")
                time.sleep(intervalo)
        except KeyboardInterrupt:
            return 0
        finally:
            temporario.unlink(missing_ok=True)
            estado_tmp.unlink(missing_ok=True)

    captura = None
    nome_backend = ""
    quadros = 0
    indice = args.camera
    tentativas_no_indice = 0
    try:
        while True:
            if captura is None:
                # RECONECTA SOZINHA. Uma webcam USB que dá tranco no cabo
                # some por um segundo; se a ponte morresse nisso, o
                # gabinete ficaria sem câmera até alguém reiniciar o jogo.
                captura, nome_backend = abrir(indice, args.width, silencioso=True, preferido=args.backend)
                if captura is None:
                    tentativas_no_indice += 1
                    # O ÍNDICE CONFIGURADO NÃO É SAGRADO.
                    #
                    # No Windows a numeracao das cameras muda com a porta
                    # USB, com um driver de camera virtual instalado, com
                    # a webcam do notebook. Insistir eternamente no
                    # indice 0 e o motivo mais comum de "a camera esta
                    # ligada e o jogo nao ve": ela esta ali, no indice 1.
                    #
                    # Duas tentativas por indice e passa para o proximo,
                    # dando a volta em 0..INDICE_MAXIMO-1.
                    if tentativas_no_indice >= 2:
                        tentativas_no_indice = 0
                        indice = (indice + 1) % INDICE_MAXIMO
                        anotar(f"PROCURANDO CAMERA - TESTANDO INDICE {indice}")
                    else:
                        anotar(f"PROCURANDO CAMERA {indice}")
                    time.sleep(1.0)
                    continue
                tentativas_no_indice = 0
                anotar(f"CONECTADA ({nome_backend}) INDICE {indice}")

            ok, quadro = captura.read()
            if not ok or quadro is None:
                captura.release()
                captura = None
                anotar("CAMERA PAROU DE RESPONDER")
                continue

            if quadro.shape[1] > args.width:
                escala = args.width / quadro.shape[1]
                quadro = cv2.resize(quadro, (args.width, int(quadro.shape[0] * escala)))
            if escrever(destino, temporario, quadro, args.quality):
                quadros += 1
                contador = quadros
                # O ESTADO É ESCRITO A CADA QUADRO, e não a cada sessenta.
                # É ele que carrega o contador; publicado de quatro em
                # quatro segundos, o contador não serviria para detectar
                # travamento nenhum.
                anotar(f"CONECTADA ({nome_backend}) INDICE {indice}")
            time.sleep(intervalo)
    except KeyboardInterrupt:
        return 0
    finally:
        if captura is not None:
            captura.release()
        temporario.unlink(missing_ok=True)
        estado_tmp.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
