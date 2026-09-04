#!/usr/bin/env python3
"""Ponte local Arduino USB -> UDP para o Punch Challenge."""

from __future__ import annotations

import argparse
import socket
import sys
import time

try:
    import serial
except ImportError:
    serial = None


def send(sock: socket.socket, udp_port: int, message: str) -> None:
    sock.sendto(message.encode("utf-8"), ("127.0.0.1", udp_port))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="COM3")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--udp-port", type=int, default=4242)
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if serial is None:
        send(sock, args.udp_port, "STATUS,PYTHON SEM PYSERIAL")
        return 2

    while True:
        try:
            send(sock, args.udp_port, f"STATUS,CONECTANDO {args.port}")
            with serial.Serial(args.port, args.baud, timeout=0.08) as board:
                time.sleep(1.6)
                board.reset_input_buffer()
                board.write(b"PING\n")
                send(sock, args.udp_port, f"STATUS,CONECTADO {args.port}")
                last_ping = time.monotonic()

                while True:
                    raw = board.readline()
                    if raw:
                        message = raw.decode("utf-8", errors="ignore").strip()
                        if message:
                            send(sock, args.udp_port, message)
                    if time.monotonic() - last_ping > 4.0:
                        board.write(b"PING\n")
                        last_ping = time.monotonic()
        except KeyboardInterrupt:
            return 0
        except Exception as exc:
            send(sock, args.udp_port, f"STATUS,OFFLINE {args.port}")
            print(f"Falha serial: {exc}", file=sys.stderr)
            time.sleep(2.0)


if __name__ == "__main__":
    raise SystemExit(main())

