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

O FRESCOR É UM CONTADOR, NÃO O RELÓGIO DO ARQUIVO. O mtime do Windows
tem resolução de até 1–2 s em algumas combinações de sistema de
arquivos/antivírus, e o jogo precisa saber em 2,5 s se a imagem
congelou. Por isso cada quadro gravado atualiza também um irmão
`<output>.count` com "contador epoch_ms" — o jogo compara o contador e
não depende de data de modificação nem de hash do JPEG.

MORRE QUANDO A CÂMERA MORRE. Se a webcam para de entregar quadro e as
reaberturas não resolvem, a ponte escreve o motivo no estado.txt e sai
com código != 0. Quem decide tentar de novo (com limite de tentativas)
é o camera_service.gd — assim um cabo solto não vira dois processos
disputando a mesma webcam.

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

# Quantas leituras falhas seguidas derrubam a captura para reabrir, e
# quantas reaberturas sem sucesso encerram a ponte de vez. Um tranco no
# cabo USB costuma se resolver na primeira reabertura; persistindo, o
# problema é físico e insistir só esconde o estado.txt útil.
LEITURAS_FALHAS_LIMITE = 25
REABERTURAS_LIMITE = 3


def argumentos() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Ponte de webcam do Punch Challenge")
    parser.add_argument("--output", help="arquivo JPEG que o jogo lê")
    parser.add_argument("--camera", type=int, default=-1,
                        help="índice pedido; -1 (ou falha ao abrir) varre 0..5")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--fps", type=float, default=15.0)
    parser.add_argument("--quality", type=int, default=80)
    parser.add_argument("--probe", action="store_true", help="lista as câmeras e sai")
    parser.add_argument("--pattern", action="store_true", help="imagem sintética")
    return parser.parse_args()


def importar_opencv(estado: Path | None):
    """O OpenCV é a única dependência e a falha mais comum no gabinete,
    então a ausência dele vira linha de estado em pt-BR — sem isso o
    técnico via só um processo que morre em silêncio."""
    try:
        import cv2
        import numpy as np
        return cv2, np
    except ImportError:
        texto = "OPENCV AUSENTE — rode tools/instalar_camera_windows.ps1"
        if estado is not None:
            anotar_estado(estado, texto)
        print(texto, file=sys.stderr)
        raise SystemExit(2)


def backends(cv2) -> list[tuple[str, int]]:
    """Ordem de tentativa. No Windows, DirectShow abre webcams baratas
    que o Media Foundation recusa; em algumas outras é o contrário,
    então vale tentar os dois antes de desistir."""
    if sys.platform == "win32":
        return [("DSHOW", cv2.CAP_DSHOW), ("MSMF", cv2.CAP_MSMF)]
    return [("V4L2", cv2.CAP_V4L2), ("ANY", cv2.CAP_ANY)]


def abrir(cv2, indice: int, largura: int, silencioso: bool = False):
    """Abre a câmera testando cada back-end. Devolve (captura, nome) ou
    (None, "") — abrir sem conseguir LER um quadro não conta como aberta:
    várias webcams respondem `isOpened()` e só então falham."""
    for nome, backend in backends(cv2):
        captura = cv2.VideoCapture(indice, backend)
        if captura.isOpened():
            captura.set(cv2.CAP_PROP_FRAME_WIDTH, largura)
            captura.set(cv2.CAP_PROP_FRAME_HEIGHT, int(largura * 3 / 4))
            captura.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            ok, quadro = captura.read()
            if ok and quadro is not None and quadro.size > 0:
                return captura, nome
        captura.release()
        if not silencioso:
            print(f"  índice {indice} não respondeu em {nome}", file=sys.stderr)
    return None, ""


def escolher_camera(cv2, pedido: int, largura: int):
    """Devolve (captura, índice, back-end) ou (None, -1, ""). Tenta o
    índice pedido; falhando (ou se o pedido for -1), varre 0..5 e fica
    com o PRIMEIRO que entrega quadro válido. No gabinete a webcam certa
    é a que responde — o índice anotado um dia muda quando o Windows
    reenumera os dispositivos USB."""
    candidatos = ([pedido] if pedido >= 0 else []) + [i for i in range(6) if i != pedido]
    for indice in candidatos:
        captura, backend = abrir(cv2, indice, largura, silencioso=True)
        if captura is not None:
            return captura, indice, backend
    return None, -1, ""


def sondar(largura: int) -> int:
    """Varre os primeiros índices e diz quais funcionam."""
    cv2, _np = importar_opencv(estado=None)
    achou = []
    for indice in range(6):
        captura, nome = abrir(cv2, indice, largura, silencioso=True)
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


def imagem_padrao(cv2, np, largura: int, quadro_n: int):
    """Padrão sintético: quadriculado com um contador desenhado. O
    contador é o que prova que a imagem está VIVA e não é um arquivo
    parado — no jogo, o .count confirma a mesma coisa."""
    altura = int(largura * 3 / 4)
    img = np.zeros((altura, largura, 3), dtype=np.uint8)
    casa = max(largura // 10, 16)
    for y in range(0, altura, casa):
        for x in range(0, largura, casa):
            tom = 210 if (x // casa + y // casa) % 2 == 0 else 45
            img[y:y + casa, x:x + casa] = (tom, tom, tom)
    cv2.putText(img, "PADRAO DE TESTE", (int(largura * 0.06), int(altura * 0.14)),
                cv2.FONT_HERSHEY_SIMPLEX, largura / 900.0, (40, 200, 240), 2)
    cv2.putText(img, f"{quadro_n:05d}", (int(largura * 0.06), int(altura * 0.94)),
                cv2.FONT_HERSHEY_SIMPLEX, largura / 500.0, (60, 25, 200), 3)
    return img


def publicar(destino: Path, temporario: Path, contador_path: Path,
             contador_tmp: Path, cv2, quadro, qualidade: int, quadros: int) -> None:
    """Grava o JPEG e o contador de frescor, os dois de forma atômica.
    Levanta OSError em falha de escrita — quem chama traduz para o
    estado.txt (antivírus segurando a pasta é o caso clássico)."""
    ok, buffer = cv2.imencode(".jpg", quadro, [cv2.IMWRITE_JPEG_QUALITY, qualidade])
    if not ok:
        return
    temporario.write_bytes(buffer.tobytes())
    os.replace(temporario, destino)
    agora_ms = int(time.time() * 1000)
    contador_tmp.write_text(f"{quadros} {agora_ms}", encoding="ascii")
    os.replace(contador_tmp, contador_path)


def anotar_estado(estado: Path, texto: str) -> None:
    """O estado.txt é a linha que a Central Técnica mostra. Também vai
    por temporário + rename: o jogo lê esse arquivo enquanto a ponte
    escreve, e uma linha cortada pela metade confundiria o parser."""
    try:
        temporario = estado.with_name(estado.stem + ".tmp")
        temporario.write_text(texto, encoding="utf-8")
        os.replace(temporario, estado)
    except OSError:
        pass


def rodar_padrao(args, destino: Path, estado: Path) -> int:
    cv2, np = importar_opencv(estado)
    temporario = destino.with_name(destino.stem + ".tmp.jpg")
    contador_path = Path(str(destino) + ".count")
    contador_tmp = Path(str(destino) + ".count.tmp")
    intervalo = 1.0 / max(args.fps, 1.0)
    quadros = 0
    janela_inicio = time.monotonic()
    janela_quadros = 0
    anotar_estado(estado, "PADRÃO DE TESTE — iniciando…")
    try:
        while True:
            inicio = time.monotonic()
            publicar(destino, temporario, contador_path, contador_tmp,
                     cv2, imagem_padrao(cv2, np, args.width, quadros), args.quality, quadros)
            quadros += 1
            janela_quadros += 1
            decorrido = time.monotonic() - janela_inicio
            if decorrido >= 2.0:
                fps = janela_quadros / decorrido
                anotar_estado(estado, f"PADRÃO DE TESTE — {fps:.1f} FPS")
                janela_inicio = time.monotonic()
                janela_quadros = 0
            time.sleep(max(0.0, intervalo - (time.monotonic() - inicio)))
    except KeyboardInterrupt:
        return 0
    except OSError as erro:
        anotar_estado(estado, f"SEM PERMISSÃO DE ESCRITA — {erro.strerror or erro}")
        return 1
    finally:
        temporario.unlink(missing_ok=True)
        contador_tmp.unlink(missing_ok=True)


def rodar_camera(args, destino: Path, estado: Path) -> int:
    cv2, _np = importar_opencv(estado)
    temporario = destino.with_name(destino.stem + ".tmp.jpg")
    contador_path = Path(str(destino) + ".count")
    contador_tmp = Path(str(destino) + ".count.tmp")
    intervalo = 1.0 / max(args.fps, 1.0)
    quadros = 0
    reaberturas = 0
    captura = None
    try:
        while True:
            if captura is None:
                captura, indice, backend = escolher_camera(cv2, args.camera, args.width)
                if captura is None:
                    reaberturas += 1
                    if reaberturas > REABERTURAS_LIMITE:
                        anotar_estado(estado, "SEM CÂMERA — nenhum índice respondeu (0 a 5)")
                        return 1
                    anotar_estado(estado, f"PROCURANDO CÂMERA — tentativa {reaberturas}/{REABERTURAS_LIMITE}")
                    time.sleep(1.0)
                    continue
                falhas = 0
                janela_inicio = time.monotonic()
                janela_quadros = 0
                anotar_estado(estado, f"CONECTADA — câmera {indice} via {backend}")

            inicio = time.monotonic()
            ok, quadro = captura.read()
            if not ok or quadro is None or quadro.size == 0:
                falhas += 1
                if falhas >= LEITURAS_FALHAS_LIMITE:
                    # Tranco no cabo USB tira a webcam por um segundo.
                    # Solta e reabre; persistindo, sai com erro e o jogo
                    # decide se tenta de novo.
                    captura.release()
                    captura = None
                    reaberturas += 1
                    if reaberturas > REABERTURAS_LIMITE:
                        anotar_estado(estado, "CÂMERA PAROU DE RESPONDER — verifique o cabo USB e feche outros programas")
                        return 1
                    anotar_estado(estado, f"RECONECTANDO — tentativa {reaberturas}/{REABERTURAS_LIMITE}")
                    time.sleep(1.0)
                continue

            if quadro.shape[1] > args.width:
                escala = args.width / quadro.shape[1]
                quadro = cv2.resize(quadro, (args.width, int(quadro.shape[0] * escala)))
            publicar(destino, temporario, contador_path, contador_tmp,
                     cv2, quadro, args.quality, quadros)
            quadros += 1
            falhas = 0
            reaberturas = 0  # entregou quadro: a câmera está saudável
            janela_quadros += 1
            decorrido = time.monotonic() - janela_inicio
            if decorrido >= 2.0:
                fps = janela_quadros / decorrido
                anotar_estado(estado, f"CONECTADA — câmera {indice} via {backend} — {fps:.1f} FPS")
                janela_inicio = time.monotonic()
                janela_quadros = 0
            time.sleep(max(0.0, intervalo - (time.monotonic() - inicio)))
    except KeyboardInterrupt:
        return 0
    except OSError as erro:
        anotar_estado(estado, f"SEM PERMISSÃO DE ESCRITA — {erro.strerror or erro}")
        return 1
    finally:
        if captura is not None:
            captura.release()
        temporario.unlink(missing_ok=True)
        contador_tmp.unlink(missing_ok=True)


def main() -> int:
    args = argumentos()
    if args.probe:
        return sondar(args.width)
    if not args.output:
        print("--output é obrigatório fora do modo --probe", file=sys.stderr)
        return 2
    destino = Path(args.output)
    destino.parent.mkdir(parents=True, exist_ok=True)
    estado = destino.with_name("estado.txt")
    if args.pattern:
        return rodar_padrao(args, destino, estado)
    return rodar_camera(args, destino, estado)


if __name__ == "__main__":
    raise SystemExit(main())
