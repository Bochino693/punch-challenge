"""Gera efeitos sonoros sintetizados (mono 44100 Hz, 16-bit) para o Punch Challenge.

Uso: py tools/gerar_sons.py
Gera: charge.wav, error.wav, menu.wav, record.wav, legendary.wav em assets/audio/.
Apenas stdlib (math, struct, wave).
"""

import math
import os
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")


def clamp(x):
    return max(-1.0, min(1.0, x))


def write_wav(name, samples):
    """samples: lista de floats -1..1."""
    path = os.path.join(OUT_DIR, name)
    frames = b"".join(struct.pack("<h", int(clamp(s) * 32767)) for s in samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    return path


def env_adsr(t, dur, a, d, s, r):
    """Envelope simples ADSR. t em segundos."""
    if t < a:
        return t / a if a > 0 else 1.0
    t2 = t - a
    if t2 < d:
        return 1.0 - (1.0 - s) * (t2 / d) if d > 0 else s
    t3 = t2 - d
    rel_start = dur - r
    if t < rel_start:
        return s
    return s * max(0.0, (dur - t) / r) if r > 0 else 0.0


def gen_charge(dur=1.6):
    """Subida de energia: varredura 120->700 Hz, vibrato leve, volume crescente, corte abrupto."""
    n = int(dur * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        p = t / dur
        freq = 120.0 + (700.0 - 120.0) * (p ** 1.6)
        vibrato = 1.0 + 0.012 * math.sin(2 * math.pi * (5.0 + 4.0 * p) * t)
        phase += 2 * math.pi * freq * vibrato / SR
        # sinal: seno + 2a harmonica suave para corpo
        sig = 0.75 * math.sin(phase) + 0.25 * math.sin(2 * phase)
        vol = 0.10 + 0.70 * (p ** 1.8)  # crescente ate ~0.8
        out.append(sig * vol)
    # corte abrupto: sem release nos ultimos samples (apenas 1ms de fade p/ nao estalar o DAC)
    fade = int(0.001 * SR)
    for i in range(1, fade + 1):
        out[-i] *= 1.0 - i / fade
    return out


def gen_error(dur=0.35):
    """Buzz de erro: quadrada 110 Hz, 2 pulsos."""
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        # dois pulsos: [0, 0.14] e [0.19, 0.35]
        if t < 0.14:
            g = 1.0
            pt = t
            plen = 0.14
        elif t >= 0.19:
            g = 1.0
            pt = t - 0.19
            plen = dur - 0.19
        else:
            g = 0.0
            pt = 0.0
            plen = 1.0
        if g > 0.0:
            sq = 1.0 if math.sin(2 * math.pi * 110.0 * t) >= 0 else -1.0
            sub = 0.4 * math.sin(2 * math.pi * 55.0 * t)
            # envelope de 5ms nas bordas do pulso para evitar clique
            e = min(1.0, pt / 0.005, max(0.0, (plen - pt) / 0.005))
            out.append((0.55 * sq + sub) * 0.8 * e)
        else:
            out.append(0.0)
    return out


def gen_menu(dur=0.06):
    """Clique suave de UI: blip 1800->900 Hz com decay rapido."""
    n = int(dur * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        p = t / dur
        freq = 1800.0 - 900.0 * p
        phase += 2 * math.pi * freq / SR
        env = (1.0 - p) ** 2.5
        out.append(0.6 * math.sin(phase) * env)
    return out


def tone_note(freq, start, dur, vol, harmonics=(1.0, 0.3, 0.12), a=0.008, d=0.05, s=0.7, r=None):
    """Gera amostras de uma nota com envelope; retorna (start_idx, lista)."""
    if r is None:
        r = dur * 0.4
    n = int(dur * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        phase += 2 * math.pi * freq / SR
        sig = sum(h * math.sin(phase * (k + 1)) for k, h in enumerate(harmonics))
        env = env_adsr(t, dur, a, d, s, r)
        out.append(sig * env * vol)
    return int(start * SR), out


def mix(base, start_idx, samples):
    if len(base) < start_idx + len(samples):
        base.extend([0.0] * (start_idx + len(samples) - len(base)))
    for j, s in enumerate(samples):
        base[start_idx + j] += s


def gen_record(dur=1.2):
    """Fanfarra de novo recorde: arpejo ascendente (C5 E5 G5 C6 E6) + brilho."""
    out = []
    notes = [523.25, 659.25, 783.99, 1046.50, 1318.51]
    for k, f in enumerate(notes):
        st, smp = tone_note(f, k * 0.11, 0.34, 0.30)
        mix(out, st, smp)
    # brilho: oitava acima da ultima nota, suave, com shimmer
    st, smp = tone_note(2093.0, 4 * 0.11, 0.5, 0.10, harmonics=(1.0, 0.15), a=0.02, s=0.5)
    mix(out, st, smp)
    # normaliza para pico 0.8
    peak = max(abs(s) for s in out) or 1.0
    gain = 0.8 / peak
    out = [s * gain for s in out]
    # corta/pad para dur
    n = int(dur * SR)
    if len(out) > n:
        out = out[:n]
    else:
        out += [0.0] * (n - len(out))
    # fade-out final 60ms
    fade = int(0.06 * SR)
    for i in range(fade):
        out[-fade + i] *= i / fade
    return out


def gen_legendary(dur=2.2):
    """Fanfarra lendaria: arpejo maior + acorde final, com eco decaindo (reverb simples)."""
    dry = []
    # arpejo maior ascendente: C4 E4 G4 C5 E5 G5
    arp = [261.63, 329.63, 392.00, 523.25, 659.25, 783.99]
    for k, f in enumerate(arp):
        st, smp = tone_note(f, k * 0.13, 0.42, 0.26)
        mix(dry, st, smp)
    # acorde final: C5 E5 G5 C6, longo
    chord_start = len(arp) * 0.13 + 0.05
    for f in (523.25, 659.25, 783.99, 1046.50):
        st, smp = tone_note(f, chord_start, dur - chord_start - 0.05, 0.16,
                            harmonics=(1.0, 0.25, 0.08), a=0.015, s=0.85, r=0.8)
        mix(dry, st, smp)
    # reverb simples: 3 ecos decaindo
    out = list(dry)
    for delay_s, g in ((0.09, 0.35), (0.18, 0.20), (0.30, 0.10)):
        d = int(delay_s * SR)
        echo = [0.0] * d + [s * g for s in dry]
        if len(out) < len(echo):
            out.extend([0.0] * (len(echo) - len(out)))
        for i in range(len(echo)):
            out[i] += echo[i]
    # normaliza para pico 0.8
    n = int(dur * SR)
    out = out[:n] + [0.0] * max(0, n - len(out))
    peak = max(abs(s) for s in out) or 1.0
    out = [s * (0.8 / peak) for s in out]
    # fade-out final 150ms
    fade = int(0.15 * SR)
    for i in range(fade):
        out[-fade + i] *= i / fade
    return out


def main():
    gens = [
        ("charge.wav", gen_charge),
        ("error.wav", gen_error),
        ("menu.wav", gen_menu),
        ("record.wav", gen_record),
        ("legendary.wav", gen_legendary),
    ]
    for name, fn in gens:
        samples = fn()
        path = write_wav(name, samples)
        peak = max(abs(s) for s in samples) if samples else 0.0
        # valida lendo de volta
        with wave.open(path) as w:
            d = w.getnframes() / w.getframerate()
            print(f"{name}: {d:.2f}s  pico={peak:.2f}  {w.getnchannels()}ch {w.getframerate()}Hz {w.getsampwidth()*8}bit OK")


if __name__ == "__main__":
    main()
