"""Compose original Western-style tracks (public-domain-friendly, generated from scratch)."""
import sys, math, random, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth as S
SR = S.SR

def note(name):
    names = {'C':0,'C#':1,'Db':1,'D':2,'D#':3,'Eb':3,'E':4,'F':5,'F#':6,'Gb':6,'G':7,'G#':8,'Ab':8,'A':9,'A#':10,'Bb':10,'B':11}
    p = name[:-1]; o = int(name[-1])
    midi = 12 * (o + 1) + names[p]
    return 440.0 * 2 ** ((midi - 69) / 12)


def place(buf, x, at, gain=1.0):
    i = int(at * SR)
    n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n] * gain


def guitar_chord(buf, freqs, at, dur=1.6, gain=0.35, bright=0.6, spread=0.012):
    for k, f in enumerate(freqs):
        place(buf, S.pluck(f, dur + 0.6, amp=1.0, bright=bright, decay=2.2), at + k * spread, gain / (1 + 0.25 * k))


def melody_voice(buf, seq, at, gain=0.3, vib=0.004):
    """seq: list of (name, dur) — a reedy/whistle lead with vibrato."""
    t = at
    for nm, d in seq:
        f = note(nm)
        n = int(d * SR)
        tt = np.arange(n) / SR
        w = np.sin(2 * np.pi * f * tt + vib * np.sin(2 * np.pi * 5.2 * tt) * 40)
        w += 0.25 * np.sin(4 * np.pi * f * tt)
        e = S.env(n, 0.03, 0.08, 0.7, 0.12)
        place(buf, (w * e).astype(np.float32), t, gain)
        t += d


def bass_line(buf, seq, at, gain=0.25):
    t = at
    for nm, d in seq:
        f = note(nm)
        n = int(d * SR)
        w = S.tone(f, d, 'sine', 1.0, (1.0, 0.4, 0.15))
        e = S.env(n, 0.01, 0.05, 0.6, 0.08)
        place(buf, (w * e).astype(np.float32), t, gain)
        t += d


def shaker(buf, at, gain=0.05, dur=0.09, seed=1):
    n = int(dur * SR)
    x = S.noise(n, seed)
    x = S.highpass(x, 4500)
    e = S.env(n, 0.001, 0.01, 0.2, 0.05)
    place(buf, (x * e).astype(np.float32), at, gain)


def kick(buf, at, gain=0.18):
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    f = 90 * np.exp(-t * 18) + 42
    w = np.sin(2 * np.pi * np.cumsum(f) / SR)
    e = S.env(n, 0.001, 0.02, 0.4, 0.06)
    place(buf, (w * e).astype(np.float32), at, gain)


def make_explore(path, tempo=76, bars=16, seed=7):
    """Warm, sparse acoustic-guitar-led exploration theme in D major / B minor."""
    rnd = random.Random(seed)
    beat = 60 / tempo
    total = beat * 4 * bars
    buf = np.zeros(int((total + 4) * SR), dtype=np.float32)
    prog = [
        # (bass, chord tones)
        ('D2', ['D3', 'A3', 'D4', 'F#4', 'A4']),
        ('B1', ['B2', 'F#3', 'B3', 'D4', 'F#4']),
        ('G2', ['G2', 'D3', 'G3', 'B3', 'D4']),
        ('A2', ['A2', 'E3', 'A3', 'C#4', 'E4']),
    ]
    for b in range(bars):
        root, tones = prog[b % 4]
        t0 = b * 4 * beat
        guitar_chord(buf, [note(x) for x in tones], t0, dur=2.4, gain=0.28, bright=0.55 + 0.1 * (b % 3))
        bass_line(buf, [(root, 2 * beat), (root, 2 * beat)], t0, gain=0.16)
        if b % 2 == 1:
            guitar_chord(buf, [note(x) for x in tones[1:]], t0 + 2 * beat, dur=1.6, gain=0.16)
    # a wandering melody over the back half
    pent = ['D4', 'E4', 'F#4', 'A4', 'B4', 'D5', 'E5', 'F#5']
    seq = []
    t = 8 * bars * beat / 2
    while t < total - 2 * beat:
        d = rnd.choice([beat * 0.5, beat, beat * 1.5, beat * 2])
        seq.append((rnd.choice(pent), d))
        t += d
        if rnd.random() < 0.25:
            t += beat
    melody_voice(buf, seq, 8 * bars * beat / 2, gain=0.12)
    out = S.reverb(buf, 0.22)
    S.write_wav(path, out * 0.6)


def make_town(path, tempo=104, bars=8, seed=3):
    """Brighter, plucky town theme with a walking bass and brushed shaker."""
    rnd = random.Random(seed)
    beat = 60 / tempo
    total = beat * 4 * bars
    buf = np.zeros(int((total + 3) * SR), dtype=np.float32)
    prog = [
        ('G2', ['G3', 'B3', 'D4', 'G4']),
        ('C3', ['C3', 'E3', 'G3', 'C4']),
        ('D3', ['D3', 'F#3', 'A3', 'D4']),
        ('G2', ['G2', 'D3', 'G3', 'B3']),
    ]
    for b in range(bars):
        root, tones = prog[b % 4]
        t0 = b * 4 * beat
        for k in range(4):
            guitar_chord(buf, [note(x) for x in tones], t0 + k * beat, dur=0.5, gain=0.22 if k % 2 == 0 else 0.14, bright=0.75)
        bass_line(buf, [(root, beat), (root, beat), (root, beat), (root, beat)], t0, gain=0.14)
        for k in range(8):
            shaker(buf, t0 + k * beat * 0.5, gain=0.03, seed=b * 8 + k)
        if b % 4 == 0:
            kick(buf, t0, 0.12)
            kick(buf, t0 + 2 * beat, 0.1)
    mel = ['D4', 'E4', 'G4', 'B4', 'A4', 'G4', 'E4', 'D4']
    mel2 = ['B4', 'A4', 'G4', 'E4', 'G4', 'A4', 'B4', 'D5']
    seq = [(mel[i % len(mel)], beat) for i in range(4 * bars // 2)]
    seq2 = [(mel2[i % len(mel2)], beat) for i in range(4 * bars // 2)]
    melody_voice(buf, seq, 0, gain=0.1)
    melody_voice(buf, seq2, 4 * bars * beat / 2 * 2, gain=0.09)
    S.write_wav(path, S.reverb(buf, 0.18) * 0.62)


def make_combat(path, tempo=132, bars=8, seed=11):
    """Tense, driving action cue: low ostinato strings + snare and toms."""
    rnd = random.Random(seed)
    beat = 60 / tempo
    total = beat * 4 * bars
    buf = np.zeros(int((total + 3) * SR), dtype=np.float32)

    def snare(at, g=0.2):
        n = int(0.12 * SR)
        x = S.noise(n, rnd.randint(0, 9999))
        x = S.highpass(x, 1800)
        e = S.env(n, 0.001, 0.03, 0.15, 0.05)
        place(buf, (x * e).astype(np.float32), at, g)

    def tom(at, f=70, g=0.2):
        n = int(0.25 * SR)
        t = np.arange(n) / SR
        w = np.sin(2 * np.pi * (f * np.exp(-t * 6) + f * 0.6) * t)
        e = S.env(n, 0.001, 0.05, 0.3, 0.1)
        place(buf, (w * e).astype(np.float32), at, g)

    roots = ['D2', 'D2', 'Bb1', 'C2']
    for b in range(bars):
        r = roots[b % 4]
        t0 = b * 4 * beat
        # driving eighth-note ostinato
        for k in range(8):
            f = note(r) * (1 if k % 2 == 0 else 1.5)
            n = int(beat * 0.5 * SR)
            w = S.tone(f, beat * 0.5, 'saw', 1.0, (1.0, 0.6, 0.35, 0.2))
            e = S.env(n, 0.004, 0.03, 0.4, 0.05)
            place(buf, (w * e).astype(np.float32), t0 + k * beat * 0.5, 0.11)
        for k, pat in enumerate([1, 0, 1, 0]):
            if pat:
                snare(t0 + k * beat, 0.12)
        tom(t0, 80, 0.16)
        tom(t0 + 2 * beat, 65, 0.14)
        if b % 2 == 1:
            tom(t0 + 3.5 * beat, 90, 0.12)
    # brass-ish stabs
    for b in range(0, bars, 2):
        t0 = b * 4 * beat
        for nm, off, d in [('D4', 0, 0.5), ('F4', 0.5, 0.5), ('A4', 1.0, 1.2)]:
            w = S.tone(note(nm), d * beat, 'saw', 1.0, (1.0, 0.5, 0.3))
            e = S.env(len(w), 0.01, 0.06, 0.5, 0.1)
            place(buf, (w * e).astype(np.float32), t0 + off * beat, 0.12)
    S.write_wav(path, S.reverb(buf, 0.15) * 0.7)


def make_night(path, tempo=64, bars=8, seed=5):
    """Slow, lonely night theme: sparse guitar harmonics + pad."""
    beat = 60 / tempo
    total = beat * 4 * bars
    buf = np.zeros(int((total + 4) * SR), dtype=np.float32)
    prog = [('A2', ['A2', 'E3', 'A3', 'C4']), ('F2', ['F2', 'C3', 'F3', 'A3']),
            ('C3', ['C3', 'G3', 'C4', 'E4']), ('G2', ['G2', 'D3', 'G3', 'B3'])]
    for b in range(bars):
        root, tones = prog[b % 4]
        t0 = b * 4 * beat
        guitar_chord(buf, [note(x) for x in tones], t0, dur=3.0, gain=0.22, bright=0.35, spread=0.03)
        # pad
        n = int(4 * beat * SR)
        tt = np.arange(n) / SR
        pad = np.zeros(n, dtype=np.float32)
        for x in tones:
            f = note(x)
            pad += np.sin(2 * np.pi * f * tt) * 0.3 + np.sin(2 * np.pi * f * 2.001 * tt) * 0.08
        e = S.env(n, 0.6, 0.4, 0.8, 1.2)
        place(buf, (pad * e).astype(np.float32), t0, 0.06)
    seq = [('A4', beat * 2), ('C5', beat), ('B4', beat * 2), ('A4', beat * 2),
           ('F4', beat * 2), ('G4', beat * 2)]
    melody_voice(buf, seq, 2 * 4 * beat, gain=0.09, vib=0.006)
    S.write_wav(path, S.reverb(buf, 0.35) * 0.6)


if __name__ == '__main__':
    import os as _os
    out = sys.argv[1]
    _os.makedirs(out, exist_ok=True)
    make_explore(out + '/music_explore.wav')
    make_town(out + '/music_town.wav')
    make_combat(out + '/music_combat.wav')
    make_night(out + '/music_night.wav')
