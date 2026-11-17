"""Generate original sound effects (gunshots, thunder, wind, birds, water, rain, hooves, UI)."""
import sys, math, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth as S

SR = S.SR
rng = np.random.default_rng(1234)


def place(buf, x, at, gain=1.0):
    i = int(at * SR)
    n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n] * gain


def gunshot(body_freq=70, bright=0.9, tail=1.2, crack=1.0):
    n = int(tail * SR)
    t = np.arange(n) / SR
    # initial crack: very short broadband transient
    crack_n = int(0.012 * SR)
    c = S.noise(crack_n, 11) * np.exp(-np.arange(crack_n) / (0.0025 * SR))
    # body: filtered noise burst with fast decay
    nb = S.noise(n, 12)
    lp = S.lowpass(nb, 300 + 3000 * bright)
    e = np.exp(-t * 22.0)
    body = lp * e
    # low thump
    thump = np.sin(2 * np.pi * np.cumsum(body_freq * np.exp(-t * 9) + 30) / SR) * np.exp(-t * 14)
    # tail: filtered noise with slower decay + slap-back
    tail_ = S.lowpass(S.noise(n, 13), 700) * np.exp(-t * 2.6) * 0.5
    x = body * 0.85 + thump * 0.9 + tail_
    out = np.zeros(n, dtype=np.float32)
    out[:crack_n] += c * 0.9 * crack
    out += (x).astype(np.float32)
    # slap echoes off canyon walls
    for d, g in ((0.11, 0.22), (0.23, 0.12), (0.37, 0.06)):
        k = int(d * SR)
        if k < n:
            out[k:] += out[:n - k] * g
    return out


def rifle_shot():
    x = gunshot(body_freq=95, bright=1.0, tail=0.9, crack=1.2)
    return x


def shotgun_blast():
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    lp = S.lowpass(S.noise(n, 21), 900)
    hp = lp
    body = hp * np.exp(-t * 16)
    thump = np.sin(2 * np.pi * np.cumsum(55 * np.exp(-t * 10) + 25) / SR) * np.exp(-t * 12)
    return (body * 0.9 + thump * 1.1).astype(np.float32)


def revolver_shot():
    x = gunshot(body_freq=80, bright=0.85, tail=1.4, crack=0.9)
    return x


def dry_fire():
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    click = S.noise(n, 31) * np.exp(-t * 400)
    click = S.highpass(click, 2500)
    return (click * 0.8).astype(np.float32)


def reload_(dur=0.9, seed=5):
    n = int(dur * SR)
    buf = np.zeros(n, dtype=np.float32)
    r = np.random.default_rng(seed)
    for k in range(4):
        at = r.uniform(0.02, dur - 0.15)
        m = int(0.05 * SR)
        tt = np.arange(m) / SR
        c = S.noise(m, seed * 10 + k) * np.exp(-tt * 200)
        c = S.highpass(c, 1200 + 500 * k)
        place(buf, c.astype(np.float32), at, 0.5)
    # cylinder spin whirr
    m = int(0.25 * SR)
    tt = np.arange(m) / SR
    whirr = S.noise(m, 99) * (0.3 + 0.3 * np.sin(2 * np.pi * 30 * tt))
    whirr = S.lowpass(whirr, 2500) * np.exp(-tt * 8)
    place(buf, whirr.astype(np.float32), dur * 0.35, 0.25)
    return buf


def thunder(dist=0.5):
    n = int(4.5 * SR)
    t = np.arange(n) / SR
    x = S.noise(n, 77)
    rumble = S.lowpass(x, 90 + 200 * (1 - dist), 4)
    e = np.exp(-t * 0.9) * (0.4 + 0.6 * np.exp(-t * 0.3))
    # rolling modulation
    mod = 0.55 + 0.45 * np.sin(2 * np.pi * 0.45 * t + 0.4)
    out = rumble * e * mod
    if dist < 0.5:  # close strike: sharp crack
        m = int(0.25 * SR)
        tt = np.arange(m) / SR
        crack = S.lowpass(S.noise(m, 78), 4000) * np.exp(-tt * 18)
        out[:m] += crack * (0.6 - dist)
    return out.astype(np.float32)


def wind_loop(dur=12.0, seed=3):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = S.noise(n, seed)
    # slow moving filter via amplitude modulation of two bands
    lo = S.lowpass(x, 400, 2)
    hi = S.lowpass(x, 1400, 2)
    mod1 = 0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * t + 1.0)
    mod2 = 0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * t + 2.3)
    out = lo * (0.6 + 0.4 * mod1) + hi * 0.35 * mod2
    # make it loop seamlessly with a crossfade
    fade = int(0.5 * SR)
    out[:fade] *= np.linspace(0, 1, fade)
    out[-fade:] *= np.linspace(1, 0, fade)
    return (out * 0.5).astype(np.float32)


def rain_loop(dur=8.0):
    n = int(dur * SR)
    x = S.noise(n, 41)
    body = 0.6 * S.lowpass(x, 6000, 2) + 0.4 * S.lowpass(x, 1800, 2)
    # scattered droplets
    r = np.random.default_rng(7)
    for _ in range(400):
        at = r.uniform(0, dur - 0.05)
        m = int(0.02 * SR)
        tt = np.arange(m) / SR
        d = np.exp(-tt * 300) * r.uniform(0.05, 0.2)
        place(body, (np.sin(2 * np.pi * r.uniform(1500, 5000) * tt) * d).astype(np.float32), at)
    fade = int(0.4 * SR)
    body[:fade] *= np.linspace(0, 1, fade)
    body[-fade:] *= np.linspace(1, 0, fade)
    return (body * 0.35).astype(np.float32)


def birds_loop(dur=10.0, seed=9):
    n = int(dur * SR)
    buf = np.zeros(n, dtype=np.float32)
    r = np.random.default_rng(seed)
    t = 0.2
    while t < dur - 1.0:
        # a chirp: fast frequency-swept sine with 2-4 notes
        for _ in range(r.integers(2, 5)):
            f0 = r.uniform(1800, 4200)
            m = int(r.uniform(0.05, 0.12) * SR)
            tt = np.arange(m) / SR
            f = f0 * (1 + 0.35 * np.sin(2 * np.pi * r.uniform(20, 45) * tt))
            w = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 22)
            place(buf, (w * 0.16).astype(np.float32), t)
            t += r.uniform(0.07, 0.2)
        t += r.uniform(0.5, 1.8)
    fade = int(0.3 * SR)
    buf[:fade] *= np.linspace(0, 1, fade)
    buf[-fade:] *= np.linspace(1, 0, fade)
    return buf.astype(np.float32)


def river_loop(dur=10.0):
    n = int(dur * SR)
    x = S.noise(n, 55)
    body = 0.7 * S.lowpass(x, 2200, 2) + 0.3 * S.lowpass(x, 700, 2)
    t = np.arange(n) / SR
    body *= (0.8 + 0.2 * np.sin(2 * np.pi * 0.21 * t))
    # bubbling gurgles
    r = np.random.default_rng(21)
    for _ in range(60):
        at = r.uniform(0, dur - 0.2)
        m = int(r.uniform(0.06, 0.18) * SR)
        tt = np.arange(m) / SR
        f = r.uniform(180, 520)
        g = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 14) * 0.12
        place(body, g.astype(np.float32), at)
    fade = int(0.4 * SR)
    body[:fade] *= np.linspace(0, 1, fade)
    body[-fade:] *= np.linspace(1, 0, fade)
    return (body * 0.45).astype(np.float32)


def forest_loop(dur=12.0):
    n = int(dur * SR)
    buf = S.lowpass(S.noise(n, 66), 900, 2) * 0.18
    r = np.random.default_rng(31)
    t = 0.5
    while t < dur - 1.2:
        f0 = r.uniform(2200, 3600)
        m = int(r.uniform(0.08, 0.18) * SR)
        tt = np.arange(m) / SR
        f = f0 * (1 + 0.2 * np.sin(2 * np.pi * r.uniform(15, 30) * tt))
        w = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 16) * 0.12
        place(buf, w.astype(np.float32), t)
        t += r.uniform(1.2, 3.5)
    fade = int(0.4 * SR)
    buf[:fade] *= np.linspace(0, 1, fade)
    buf[-fade:] *= np.linspace(1, 0, fade)
    return buf.astype(np.float32)


def horse_whinny(seed=1):
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    f = 420 * np.exp(-t * 0.6) * (1 + 0.12 * np.sin(2 * np.pi * 26 * t)) + 160
    x = np.sin(2 * np.pi * np.cumsum(f) / SR)
    # rasp
    rasp = S.lowpass(S.noise(n, seed), 2200) * 0.4
    env_ = np.minimum(1, t * 12) * np.exp(-t * 1.5)
    y = (x * 0.6 + rasp * x * 2.0) * env_
    return (y * 0.5).astype(np.float32)


def horse_snort():
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    x = S.lowpass(S.noise(n, 4), 1400) * np.exp(-t * 7)
    mod = 0.5 + 0.5 * np.sin(2 * np.pi * 14 * t)
    return (x * mod * 0.5).astype(np.float32)


def hoof(dur=0.16, tone=90, seed=8):
    n = int(dur * SR)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * np.cumsum(tone * np.exp(-t * 20) + 40) / SR) * np.exp(-t * 26)
    click = S.highpass(S.noise(n, seed) * np.exp(-t * 90), 900) * 0.4
    return ((thump + click) * 0.6).astype(np.float32)


def gallop_loop():
    """4 hoofbeats in a looping 0.5 s pattern."""
    dur = 0.52
    n = int(dur * SR)
    buf = np.zeros(n, dtype=np.float32)
    for i, at in enumerate([0.0, 0.11, 0.2, 0.33]):
        place(buf, hoof(tone=95 - i * 6, seed=40 + i), at, 0.9 if i % 2 == 0 else 0.6)
    fade = int(0.02 * SR)
    return buf.astype(np.float32)


def footstep(surface='grass', seed=1):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    if surface == 'grass':
        x = S.lowpass(S.noise(n, seed), 2600) * np.exp(-t * 40)
        x += np.sin(2 * np.pi * 70 * t) * np.exp(-t * 40) * 0.3
    elif surface == 'dirt':
        x = S.lowpass(S.noise(n, seed), 1600) * np.exp(-t * 45)
        x += np.sin(2 * np.pi * 85 * t) * np.exp(-t * 50) * 0.4
    else:  # wood
        x = S.lowpass(S.noise(n, seed), 900) * np.exp(-t * 60)
        x += np.sin(2 * np.pi * 160 * t) * np.exp(-t * 35) * 0.5
    return (x * 0.55).astype(np.float32)


def bullet_impact(seed=3):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    x = S.lowpass(S.noise(n, seed), 3000) * np.exp(-t * 40)
    ric = np.sin(2 * np.pi * np.cumsum(3800 * np.exp(-t * 6) + 900) / SR) * np.exp(-t * 22) * 0.25
    return ((x + ric) * 0.6).astype(np.float32)


def ui_click(seed=2):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * 1400 * t) * np.exp(-t * 90) + np.sin(2 * np.pi * 720 * t) * np.exp(-t * 60) * 0.5
    return (x * 0.4).astype(np.float32)


def heartbeat_loop():
    n = int(1.2 * SR)
    buf = np.zeros(n, dtype=np.float32)
    for at, g in ((0.0, 0.7), (0.28, 0.45)):
        m = int(0.22 * SR)
        t = np.arange(m) / SR
        f = 55 * np.exp(-t * 8) + 28
        w = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 12)
        place(buf, w.astype(np.float32), at, g)
    return buf


def wolf_howl():
    n = int(2.6 * SR)
    t = np.arange(n) / SR
    f = 300 + 260 * np.minimum(1, t / 0.5) - 120 * np.minimum(1, np.maximum(0, (t - 1.4) / 1.2))
    f *= (1 + 0.02 * np.sin(2 * np.pi * 5 * t))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.6 + np.sin(4 * np.pi * np.cumsum(f) / SR) * 0.2
    env_ = np.minimum(1, t * 3) * np.exp(-np.maximum(0, t - 1.5) * 2.2)
    x = x * env_
    y = S.lowpass(x, 2500)
    # echo
    out = np.zeros(n, dtype=np.float32)
    out += y
    for d, g in ((0.28, 0.3), (0.6, 0.15)):
        k = int(d * SR)
        out[k:] += y[:n - k] * g
    return (out * 0.4).astype(np.float32)


def deer_call():
    n = int(1.1 * SR)
    t = np.arange(n) / SR
    f = 620 - 120 * (t / 1.1)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 3.2)
    x += S.lowpass(S.noise(n, 5), 2200) * np.exp(-t * 12) * 0.2
    return (x * 0.28).astype(np.float32)


def ambient_saloon_loop(dur=14.0):
    """Murmur of a crowded saloon: low chatter + occasional glass/piano notes."""
    n = int(dur * SR)
    buf = np.zeros(n, dtype=np.float32)
    r = np.random.default_rng(88)
    # chatter bed
    t = np.arange(n) / SR
    chat = S.lowpass(S.noise(n, 91), 700, 2) * (0.35 + 0.2 * np.sin(2 * np.pi * 0.13 * t))
    buf += chat * 0.5
    # piano notes in a ragtime-ish figure
    scale = [220.0, 261.63, 293.66, 329.63, 392.0, 440.0]
    at = 0.7
    while at < dur - 1.0:
        f = r.choice(scale) * (2 if r.random() < 0.35 else 1)
        m = int(0.9 * SR)
        tt = np.arange(m) / SR
        w = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 3.2)
        w += np.sin(4 * np.pi * f * tt) * np.exp(-tt * 6) * 0.3
        place(buf, (w * 0.12).astype(np.float32), at)
        at += r.choice([0.5, 0.66, 0.75, 1.0])
    # glass clinks
    for _ in range(9):
        at = r.uniform(0.4, dur - 0.4)
        m = int(0.3 * SR)
        tt = np.arange(m) / SR
        w = (np.sin(2 * np.pi * r.uniform(2200, 4200) * tt) * np.exp(-tt * 30) * 0.1)
        place(buf, w.astype(np.float32), at)
    fade = int(0.5 * SR)
    buf[:fade] *= np.linspace(0, 1, fade)
    buf[-fade:] *= np.linspace(1, 0, fade)
    return buf.astype(np.float32)


def campfire_loop(dur=9.0):
    n = int(dur * SR)
    buf = 0.35 * S.lowpass(S.noise(n, 17), 500, 2)
    r = np.random.default_rng(19)
    for _ in range(160):
        at = r.uniform(0, dur - 0.1)
        m = int(r.uniform(0.01, 0.05) * SR)
        tt = np.arange(m) / SR
        p = S.noise(m, int(r.integers(0, 9999))) * np.exp(-tt * r.uniform(60, 400))
        place(buf, (p * r.uniform(0.1, 0.4)).astype(np.float32), at)
    fade = int(0.3 * SR)
    buf[:fade] *= np.linspace(0, 1, fade)
    buf[-fade:] *= np.linspace(1, 0, fade)
    return buf.astype(np.float32)


def whistle_loop(dur=6.0):
    """Lonely cowboy whistle melody (breathy sine + vibrato)."""
    n = int(dur * SR)
    buf = np.zeros(n, dtype=np.float32)
    seq = [(587.33, 0.5), (659.25, 0.5), (783.99, 0.75), (659.25, 0.5),
           (587.33, 0.5), (523.25, 1.0), (0, 0.5), (587.33, 0.5), (659.25, 0.5),
           (587.33, 1.5)]
    t = 0.15
    for f, d in seq:
        if f > 0:
            m = int(d * SR)
            tt = np.arange(m) / SR
            w = np.sin(2 * np.pi * f * tt + 0.008 * np.sin(2 * np.pi * 5.5 * tt) * f)
            w += S.lowpass(S.noise(m, int(f) % 1000), 3000) * 0.06
            e = S.env(m, 0.06, 0.05, 0.85, 0.12)
            place(buf, (w * e).astype(np.float32), t, 0.18)
        t += d
    S.write_wav_buf = None
    fade = int(0.3 * SR)
    buf[-fade:] *= np.linspace(1, 0, fade)
    return buf


JOBS = {
    'shot_revolver': lambda: revolver_shot(),
    'shot_rifle': lambda: rifle_shot(),
    'shot_shotgun': lambda: shotgun_blast(),
    'dry_fire': dry_fire,
    'reload_revolver': lambda: reload_(0.75, 5),
    'reload_rifle': lambda: reload_(1.1, 8),
    'reload_shotgun': lambda: reload_(1.0, 12),
    'thunder_far': lambda: thunder(0.8),
    'thunder_close': lambda: thunder(0.15),
    'amb_wind': lambda: wind_loop(12.0),
    'amb_rain': lambda: rain_loop(8.0),
    'amb_birds': lambda: birds_loop(10.0),
    'amb_river': lambda: river_loop(10.0),
    'amb_forest': lambda: forest_loop(12.0),
    'amb_saloon': lambda: ambient_saloon_loop(14.0),
    'amb_campfire': lambda: campfire_loop(9.0),
    'horse_whinny': lambda: horse_whinny(1),
    'horse_snort': horse_snort,
    'horse_gallop': gallop_loop,
    'horse_hoof': lambda: hoof(),
    'step_grass': lambda: footstep('grass', 1),
    'step_dirt': lambda: footstep('dirt', 2),
    'step_wood': lambda: footstep('wood', 3),
    'impact_bullet': lambda: bullet_impact(3),
    'ui_click': lambda: ui_click(2),
    'heartbeat': heartbeat_loop,
    'wolf_howl': wolf_howl,
    'deer_call': deer_call,
    'whistle': lambda: whistle_loop(6.0),
}

if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, fn in JOBS.items():
        x = fn()
        S.write_wav(os.path.join(out, name + '.wav'),
                    np.asarray(x, dtype=np.float32) * 0.9)
