"""Gera assets/icon.png no tema claro: luva vermelha sobre placa creme."""
import zlib, struct, math

N = 512
SS = 3                      # supersample: 3x3 amostras por pixel
W = N * SS
buf = [[(0, 0, 0, 0)] * W for _ in range(W)]

CREME   = (255, 248, 236)
MARINHO = (28, 53, 102)
VERMELHO= (230, 57, 80)
AMBAR   = (242, 160, 7)
BRANCO  = (255, 255, 255)

def blend(dst, src, a):
    return tuple(int(dst[i] * (1 - a) + src[i] * a) for i in range(3))

def put(x, y, cor, a=1.0):
    if 0 <= x < W and 0 <= y < W:
        d = buf[y][x]
        base = d[:3] if d[3] else cor
        buf[y][x] = blend(base, cor, a) + (max(d[3], int(255 * a)),)

def disco(cx, cy, r, cor):
    for y in range(max(0, int(cy - r) - 1), min(W, int(cy + r) + 2)):
        dy = y - cy
        dx = math.sqrt(max(0.0, r * r - dy * dy))
        for x in range(max(0, int(cx - dx)), min(W, int(cx + dx) + 1)):
            put(x, y, cor)

def retangulo_redondo(x0, y0, x1, y1, r, cor):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            cx = min(max(x, x0 + r), x1 - r)
            cy = min(max(y, y0 + r), y1 - r)
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                put(x, y, cor)

def poligono(pts, cor):
    ys = [p[1] for p in pts]
    for y in range(max(0, int(min(ys))), min(W, int(max(ys)) + 1)):
        xs = []
        for i in range(len(pts)):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
            if (y0 <= y < y1) or (y1 <= y < y0):
                xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(max(0, int(xs[i])), min(W, int(xs[i + 1]) + 1)):
                put(x, y, cor)

def linha(p0, p1, largura, cor):
    n = int(math.dist(p0, p1)) + 1
    for i in range(n + 1):
        t = i / n
        disco(p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, largura / 2, cor)

S = SS
# Placa: moldura marinho e miolo creme.
retangulo_redondo(14 * S, 14 * S, 498 * S, 498 * S, 112 * S, MARINHO)
retangulo_redondo(34 * S, 34 * S, 478 * S, 478 * S, 94 * S, CREME)

# Raios de impacto atrás da luva.
c = (256 * S, 262 * S)
for k in range(8):
    a = math.pi * 2 * k / 8 + 0.35
    linha((c[0] + math.cos(a) * 150 * S, c[1] + math.sin(a) * 150 * S),
          (c[0] + math.cos(a) * 205 * S, c[1] + math.sin(a) * 205 * S), 18 * S, AMBAR)

# Luva de boxe. A silhueta é a UNIÃO de quatro formas redondas, e o
# contorno sai de desenhar as mesmas quatro dilatadas por baixo: assim a
# borda continua redonda em vez de ganhar bicos, que é o que acontece ao
# escalar um polígono de poucos vértices.
R = 150 * S

def luva(escala, cor):
    d = escala
    disco(c[0] + 0.10 * R, c[1] - 0.26 * R, 0.64 * R + d, cor)
    retangulo_redondo(c[0] - 0.54 * R - d, c[1] - 0.30 * R - d,
                      c[0] + 0.58 * R + d, c[1] + 0.26 * R + d, 0.16 * R, cor)
    disco(c[0] - 0.58 * R, c[1] + 0.02 * R, 0.30 * R + d, cor)
    retangulo_redondo(c[0] - 0.30 * R - d, c[1] + 0.24 * R - d,
                      c[0] + 0.50 * R + d, c[1] + 0.84 * R + d, 0.16 * R, cor)

luva(0.09 * R, MARINHO)
luva(0.0, VERMELHO)
# Vinco dos dedos e faixa do punho: os dois riscos que fazem o olho ler
# "luva" e não "mancha vermelha".
linha((c[0] - 0.24 * R, c[1] - 0.22 * R), (c[0] + 0.60 * R, c[1] - 0.26 * R), 0.10 * R, BRANCO)
linha((c[0] - 0.20 * R, c[1] + 0.42 * R), (c[0] + 0.40 * R, c[1] + 0.42 * R), 0.11 * R, BRANCO)

# Reduz o supersample e escreve o PNG.
linhas = []
for y in range(N):
    row = bytearray([0])
    for x in range(N):
        r = g = b = a = 0
        for dy in range(SS):
            for dx in range(SS):
                px = buf[y * SS + dy][x * SS + dx]
                r += px[0]; g += px[1]; b += px[2]; a += px[3]
        n = SS * SS
        row += bytes([r // n, g // n, b // n, a // n])
    linhas.append(bytes(row))

def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)

png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 6, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(b''.join(linhas), 9))
       + chunk(b'IEND', b''))
open('assets/icon.png', 'wb').write(png)
print('assets/icon.png', len(png), 'bytes')
