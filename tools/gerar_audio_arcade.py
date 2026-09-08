"""Banco original sintetizado a 48 kHz. Execute para reproduzir os WAVs."""
from pathlib import Path
import wave
import numpy as np

RATE = 48000
OUT = Path(__file__).resolve().parents[1] / 'assets' / 'audio' / 'arcade'
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(8258)

def save(name, samples, loop=False):
    samples = np.asarray(samples, dtype=float)
    if not loop:
        n = min(480, len(samples)//4)
        samples[:n] *= np.linspace(0, 1, n)
        samples[-n:] *= np.linspace(1, 0, n)
    samples *= .72 / max(1., np.max(np.abs(samples)))
    with wave.open(str(OUT / (name + '.wav')), 'wb') as f:
        f.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        f.writeframes((samples * 32767).astype('<i2').tobytes())

def tone(freq, duration, decay=4):
    t = np.arange(int(duration*RATE))/RATE
    return (np.sin(2*np.pi*freq*t) + .22*np.sin(4*np.pi*freq*t))*np.exp(-decay*t)

def phrase(name, notes, beat=.14):
    y = np.zeros(int((len(notes)*beat+.65)*RATE))
    for i, note in enumerate(notes):
        x = tone(440*2**((note-69)/12), .55, 7)
        pos = int(i*beat*RATE)
        y[pos:pos+len(x)] += x*.42
    save(name, y)

phrase('credit', [76, 83], .1)
phrase('start', [57, 64, 69, 76], .10)
phrase('go', [57, 69, 81], .065)
phrase('count', [81], .07)
phrase('win', [69, 73, 76, 81], .13)
phrase('medium', [64, 69, 76], .12)
phrase('lose', [64, 60], .15)
phrase('error', [48, 47], .08)
phrase('menu', [76], .04)
phrase('record', [69, 73, 76, 81, 85, 88], .15)
phrase('legendary', [57, 64, 69, 73, 76, 81], .12)
phrase('ranking', [76, 81, 85, 88], .11)
t = np.arange(int(.7*RATE))/RATE
# Corpo grave descendente + ataque de couro + cauda curta de arena.
body = np.sin(2*np.pi*(48*t+95*.045*(1-np.exp(-t/.045))))*np.exp(-10*t)
noise = rng.normal(0, 1, len(t))
leather = np.convolve(noise, np.ones(9)/9, mode='same')*np.exp(-35*t)
hit = .85*body + .55*leather
echo = int(.065*RATE)
hit[echo:] += .12*hit[:-echo]
save('hit', hit)
t = np.arange(int(.18*RATE))/RATE
save('shutter', rng.normal(0,.22,len(t))*np.exp(-65*t) + .3*np.sin(2*np.pi*1800*t)*np.exp(-55*t))
# Loops periódicos; os osciladores completam ciclos inteiros na emenda.
t = np.arange(RATE)/RATE
save('score_loop', (np.sin(2*np.pi*240*t)+.2*np.sin(2*np.pi*480*t))*(.22+.08*np.cos(2*np.pi*12*t)), True)
save('charge', (np.sin(2*np.pi*120*t)+.18*np.sin(2*np.pi*360*t))*(.20+.06*np.cos(2*np.pi*8*t)), True)
# Oito segundos, 120 BPM: bateria, baixo e arpejo com espaço para os efeitos.
music = np.zeros(8*RATE)
for step in range(32):
    pos = int(step*.25*RATE)
    note = [45, 52, 57, 64, 41, 48, 53, 60][(step//4)%8]
    x = tone(440*2**((note-69)/12), .24, 14)*.25
    music[pos:pos+len(x)] += x
    if step % 2 == 0:
        t = np.arange(int(.23*RATE))/RATE
        kick = np.sin(2*np.pi*(48*t+60*.03*(1-np.exp(-t/.03))))*np.exp(-22*t)*.45
        music[pos:pos+len(kick)] += kick
    t = np.arange(int(.08*RATE))/RATE
    hat = rng.normal(0,.035,len(t))*np.exp(-65*t)
    music[pos:pos+len(hat)] += hat
save('music', music, True)
print('ARCADE_AUDIO_OK')
