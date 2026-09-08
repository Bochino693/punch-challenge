"""Ponte de webcam para a exportação Windows do Punch Challenge.

Godot CameraServer não expõe feeds no Windows. Este processo local usa
OpenCV/DirectShow e publica somente o quadro mais recente no diretório
user:// do jogo. Nenhuma imagem é enviada à rede.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

try:
    import cv2
except ImportError:
    print("OpenCV ausente. Instale com: py -m pip install opencv-python", file=sys.stderr)
    raise SystemExit(2)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--camera", type=int, default=0)
    args = parser.parse_args()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name("live.tmp.jpg")
    backend = cv2.CAP_DSHOW if sys.platform == "win32" else cv2.CAP_ANY
    camera = cv2.VideoCapture(args.camera, backend)
    camera.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    camera.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not camera.isOpened():
        print(f"Não foi possível abrir a câmera {args.camera}", file=sys.stderr)
        return 3

    try:
        while True:
            ok, frame = camera.read()
            if not ok:
                time.sleep(0.05)
                continue
            if frame.shape[1] > 640:
                scale = 640.0 / frame.shape[1]
                frame = cv2.resize(frame, (640, int(frame.shape[0] * scale)))
            if cv2.imwrite(str(temporary), frame, [cv2.IMWRITE_JPEG_QUALITY, 78]):
                os.replace(temporary, output)
            time.sleep(1.0 / 12.0)
    except KeyboardInterrupt:
        return 0
    finally:
        camera.release()
        if temporary.exists():
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
