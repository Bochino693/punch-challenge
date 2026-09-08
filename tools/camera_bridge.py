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
    print(
        "OpenCV ausente. Instale com:  py -m pip install opencv-python",
        file=sys.stderr,
    )
    raise SystemExit(2)


# Ordem de tentativa dos back-ends. No Windows, DirectShow abre webcams
# baratas que o Media Foundation recusa; em algumas outras é o contrário,
# então vale tentar os dois antes de desistir.
def backends() -> list[tuple[str, int]]:
    if sys.platform == "win32":
        return [("DSHOW", cv2.CAP_DSHOW), ("MSMF", cv2.CAP_MSMF), ("ANY", cv2.CAP_ANY)]
    return [("V4L2", cv2.CAP_V4L2), ("ANY", cv2.CAP_ANY)]


def abrir(indice: int, largura: int, silencioso: bool = False):
    """Abre a câmera testando cada back-end. Devolve (captura, nome) ou
    (None, "") — abrir sem conseguir LER um quadro não conta como aberta:
    várias webcams respondem `isOpened()` e só então falham."""
    for nome, backend in backends():
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


def sondar(largura: int) -> int:
    """Varre os primeiros índices e diz quais funcionam."""
    achou = []
    for indice in range(6):
        captura, nome = abrir(indice, largura, silencioso=True)
        if captura is not None:
            w = int(captura.get(cv2.CAP_PROP_FRAME_WIDTH))
            h = int(captura.get(cv2.CAP_PROP_FRAME_HEIGHT))
            print(f"câmera {indice}: OK via {nome} — {w}x{h}")
            achou.append(indice)
            captura.release()
    if not achou:
        print("nenhuma câmera respondeu (índices 0 a 5)")
        print("verifique cabo USB, driver, e se outro programa está usando a webcam")
        return 1
    print(f"\nuse --camera {achou[0]} (ou ajuste na Central Técnica do jogo)")
    return 0


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

    def anotar(texto: str) -> None:
        try:
            estado.write_text(texto, encoding="utf-8")
        except OSError:
            pass

    if args.pattern:
        anotar("PADRAO DE TESTE")
        quadro_n = 0
        try:
            while True:
                escrever(destino, temporario, imagem_de_teste(args.width, quadro_n), args.quality)
                quadro_n += 1
                time.sleep(intervalo)
        except KeyboardInterrupt:
            return 0
        finally:
            temporario.unlink(missing_ok=True)

    captura = None
    nome_backend = ""
    quadros = 0
    try:
        while True:
            if captura is None:
                # RECONECTA SOZINHA. Uma webcam USB que dá tranco no cabo
                # some por um segundo; se a ponte morresse nisso, o
                # gabinete ficaria sem câmera até alguém reiniciar o jogo.
                captura, nome_backend = abrir(args.camera, args.width, silencioso=True)
                if captura is None:
                    anotar(f"PROCURANDO CAMERA {args.camera}")
                    time.sleep(1.5)
                    continue
                anotar(f"CONECTADA ({nome_backend})")

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
                if quadros % 60 == 0:
                    anotar(f"CONECTADA ({nome_backend}) — {quadros} quadros")
            time.sleep(intervalo)
    except KeyboardInterrupt:
        return 0
    finally:
        if captura is not None:
            captura.release()
        temporario.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
