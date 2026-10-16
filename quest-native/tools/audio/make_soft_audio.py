"""Calm music and soft sound effects for the table game, synthesised here (no samples, no
downloads). The owner asked for quiet music and gentle effects in place of the old sounds.

  audio/music/day.ogg, audio/music/evening.ogg, audio/music/night.ogg
      slow loops (about 96 s, seamless): an oud-like plucked string over a soft drone, a
      breathy ney-like flute now and then, a muted frame drum; the night one sparser and lower
  audio/sfx/<name>.wav
      every effect the table levels play, remade soft and short (taps of wood, a felt-muted
      chime, a gentle sand shuffle for pushing, rising chimes for success)
  audio/ambience/<name>.ogg
      each scene's quiet surroundings, 40 s seamless loops: birds, wind, fire, night (crickets),
      market (a far murmur and the odd clink), water (a running channel), rain (a soft shower)

Usage: python3 tools/audio/make_soft_audio.py [ambience]      (needs numpy and ffmpeg)
       (with "ambience": only the surroundings; with "shot": only the celebration shot)
"""
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SFX = os.path.join(ROOT, "audio", "sfx")
MUSIC = os.path.join(ROOT, "audio", "music")
SR = 22050
rng = np.random.default_rng(10)


def save_wav(path, x, sr=SR):
    x = np.clip(x, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def lowpass(x, cutoff):
    """One-pole low-pass, run forwards and backwards (no phase shift)."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    for _ in range(2):
        acc = 0.0
        out = np.empty_like(x)
        for i, v in enumerate(x):
            acc = (1 - a) * v + a * acc
            out[i] = acc
        x = out[::-1]
    return x


def reverb(x, seconds=2.2, mix=0.3):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t * 6.9 / seconds)
    ir = lowpass(ir, 3500)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x) + n]
    out = np.zeros(len(x) + n)
    out[:len(x)] += x * (1 - mix)
    out += wet * mix
    return out


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-t / decay)


def pluck(freq, seconds, bright=0.5):
    """Karplus-Strong: a plucked string, its body warmed by a low-pass (oud-like)."""
    n = int(seconds * SR)
    period = int(SR / freq)
    buf = rng.uniform(-1, 1, period) * 0.6
    buf = lowpass(buf, 2000 + 3000 * bright)
    out = np.empty(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = 0.5 * (buf[i % period] + buf[(i + 1) % period]) * 0.994
    return lowpass(out, 2200) * env(n, 0.004, seconds * 0.5)


def flute(freq, seconds):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.0 * t) * np.minimum(1, t / 0.6)
    phase = 2 * np.pi * np.cumsum(freq * vib) / SR
    tone = np.sin(phase) + 0.18 * np.sin(2 * phase) + 0.05 * np.sin(3 * phase)
    breath = lowpass(rng.standard_normal(n), 1100) * 0.07
    a = np.minimum(1, t / 0.5) * np.minimum(1, (seconds - t) / 0.8)
    return (tone + breath) * np.clip(a, 0, 1)


def drum(seconds=0.6, pitch=70.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * pitch * t * (1 + 0.5 * np.exp(-t * 30)))
    skin = lowpass(rng.standard_normal(n), 900) * np.exp(-t * 40) * 0.5
    return (body + skin) * np.exp(-t * 9)


def drone(seconds, f):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.5 * t) + 0.25 * np.sin(2 * np.pi * f * 2 * t)
    return s * (0.75 + 0.25 * np.sin(2 * np.pi * t / 11.0))


# hijaz on D: D Eb F# G A Bb C D
SCALE = [146.83, 155.56, 185.0, 196.0, 220.0, 233.08, 261.63, 293.66]


def phrase_line(rng_, length):
    """A slow wandering line on the scale, stepwise mostly, resting on D and A."""
    i = 0
    line = []
    for _ in range(length):
        i = int(np.clip(i + rng_.choice([-1, -1, 0, 1, 1, 2, -2]), 0, len(SCALE) - 1))
        line.append(i)
    line[-1] = 0
    return line


def music(name, seconds=96.0, tempo=58, base=1.0, sparse=1.0, flute_on=True, drum_on=True):
    n = int(seconds * SR)
    mix = np.zeros(n + SR * 4)
    beat = 60.0 / tempo
    r = np.random.default_rng(abs(hash(name)) % 1000)
    mix[:n] += drone(seconds, SCALE[0] / 2 * base) * 0.05
    t = 0.0
    while t < seconds - 4:
        line = phrase_line(r, 6)
        for k, idx in enumerate(line):
            if r.random() < sparse:
                f = SCALE[idx] * base
                dur = beat * (2 if k == len(line) - 1 else 1)
                p = pluck(f, 2.4, bright=0.3 + 0.3 * r.random()) * 0.32
                s = int(t * SR)
                mix[s:s + len(p)] += p[:len(mix) - s]
            t += beat * (2 if k == len(line) - 1 else 1)
        t += beat * 2   # a breath between phrases
    if flute_on:
        for start in np.arange(12.0, seconds - 12, 24.0):
            idx = r.choice([4, 3, 2, 4, 0])
            f = flute(SCALE[idx] * base * 2, 5.0) * 0.07
            s = int(start * SR)
            mix[s:s + len(f)] += f
    if drum_on:
        for b in np.arange(0, seconds, beat * 4):
            d = drum(0.6, 68) * 0.12
            s = int(b * SR)
            mix[s:s + len(d)] += d[:len(mix) - s]
    wet = reverb(mix, 2.6, 0.35)
    loop = wet[:n].copy()
    loop[:len(wet) - n] += wet[n:]     # the tail wraps round: a seamless loop
    loop /= np.max(np.abs(loop)) + 1e-9
    loop *= 0.6
    tmp = os.path.join(MUSIC, name + ".wav")
    save_wav(tmp, loop)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "3",
                    os.path.join(MUSIC, name + ".ogg")], check=True)
    os.remove(tmp)
    print("music", name, "%.0f s" % seconds)


# --- effects -------------------------------------------------------------------------------------

def knock(pitch=420.0, seconds=0.18, level=0.5):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * pitch * t) * np.exp(-t * 40) + lowpass(rng.standard_normal(n), 1500) * np.exp(-t * 90) * 0.4
    return s * level


def chime(freqs, seconds=1.4, level=0.35, gap=0.0):
    n = int((seconds + gap * len(freqs)) * SR)
    out = np.zeros(n)
    for k, f in enumerate(freqs):
        m = int(seconds * SR)
        t = np.arange(m) / SR
        s = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.01 * t)) * np.exp(-t * 3.2) * np.minimum(1, t / 0.01)
        o = int(k * gap * SR)
        out[o:o + m] += s[:n - o]
    return reverb(out, 1.4, 0.3)[:n + SR // 2] * level / len(freqs) ** 0.5


def shuffle(seconds=0.5, level=0.12):
    """A soft shuffle of sand: what pushing a block or a crate sounds like now."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    s = lowpass(rng.standard_normal(n), 600) * np.sin(np.pi * t / seconds) ** 2
    return s * level


def whoosh(seconds=0.5, level=0.12):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    return lowpass(rng.standard_normal(n), 1200) * np.sin(np.pi * t / seconds) ** 3 * level


def soft_no():
    a = knock(260, 0.2, 0.35)
    b = knock(220, 0.25, 0.3)
    out = np.zeros(int(0.45 * SR))
    out[:len(a)] += a
    out[int(0.14 * SR):int(0.14 * SR) + len(b)] += b
    return lowpass(out, 1200)


def shot():
    """A celebratory shot heard from across the courtyard: a short dull crack and a little
    roll after it, kept soft like everything else."""
    r = np.random.default_rng(77)
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    crack = r.standard_normal(n) * np.exp(-t * 60)
    thump = np.sin(2 * np.pi * 90 * t * (1 + np.exp(-t * 40))) * np.exp(-t * 18) * 0.7
    roll = lowpass(r.standard_normal(n), 500) * np.exp(-t * 7) * 0.5
    x = lowpass(crack, 2600) * 0.9 + thump + roll
    return reverb(x / (np.max(np.abs(x)) + 1e-9), 1.2, 0.35)[:n] * 0.3


def effects():
    os.makedirs(SFX, exist_ok=True)
    D, A = SCALE[0], SCALE[4]
    fx = {
        "tap": knock(520, 0.12, 0.3),
        "ui_click": knock(600, 0.1, 0.25),
        "soft_reject": soft_no(),
        "success": chime([D * 2, SCALE[2] * 2, A * 2], 1.6, 0.4, 0.12),
        "level_complete": chime([D * 2, SCALE[2] * 2, A * 2, D * 4], 2.2, 0.45, 0.18),
        "unlock": chime([A * 2, D * 4], 1.4, 0.35, 0.1),
        "key_pickup": chime([A * 2, SCALE[6] * 2], 1.0, 0.3, 0.06),
        "gem_pickup": chime([SCALE[3] * 2, D * 4], 1.0, 0.3, 0.06),
        "brick_lift": whoosh(0.35, 0.08),
        "brick_place": knock(180, 0.22, 0.28),
        "brick_drop": knock(150, 0.3, 0.3),
        "crate_scrape": shuffle(0.55, 0.08),
        "crate_settle": knock(170, 0.2, 0.22),
        "bridge_move": shuffle(0.9, 0.07),
        "dial_click": knock(700, 0.08, 0.2),
        "lever": knock(300, 0.2, 0.25),
    }
    for i in range(5):
        fx["switch_%d" % i] = knock(380 + i * 40, 0.14, 0.25)
    for i in range(1, 5):
        fx["cloth_%d" % i] = whoosh(0.3 + 0.05 * i, 0.07)
    for i in range(1, 7):   # the drums (level 6) and other note sequences: soft frame drums
        d = drum(0.7, [62, 74, 88, 104, 118, 132][i - 1])
        fx["seq_%d" % i] = reverb(d, 0.8, 0.2)[:int(0.9 * SR)] * 0.45
    fx["shot"] = shot()
    for name, x in fx.items():
        save_wav(os.path.join(SFX, name + ".wav"), x)
    print("effects", len(fx))


# --- surroundings -------------------------------------------------------------------------------

AMB = os.path.join(ROOT, "audio", "ambience")


def bandnoise(n, lo, hi):
    """Noise between lo and hi Hz (two one-pole filters, done with the FFT for speed)."""
    x = rng.standard_normal(n)
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(n, 1 / SR)
    f *= np.exp(-((np.log(np.maximum(fr, 1)) - np.log(np.sqrt(lo * hi))) ** 2) / (2 * (np.log(hi / lo) / 2.5) ** 2))
    y = np.fft.irfft(f, n)
    return y / (np.max(np.abs(y)) + 1e-9)


def slow(n, period, depth=0.5, seed=0):
    """A slow wandering swell between 1 - depth and 1 (sum of a few sines, loops exactly)."""
    t = np.arange(n) / n
    r = np.random.default_rng(seed)
    v = np.zeros(n)
    for k in (1, 2, 3, 5):
        v += np.sin(2 * np.pi * k * t * max(1, round(n / SR / period)) + r.uniform(0, 6.28)) / k
    v = (v - v.min()) / (v.max() - v.min() + 1e-9)
    return 1 - depth + depth * v


def place(out, x, at):
    at = at % len(out)
    end = min(len(out), at + len(x))
    out[at:end] += x[:end - at]
    if at + len(x) > len(out):   # wrap round: a seamless loop
        out[:at + len(x) - len(out)] += x[end - at:]


def chirp(f0, f1, seconds, level):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = np.linspace(f0, f1, n)
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = np.sin(np.pi * t / seconds) ** 2
    return np.sin(ph) * e * level


def amb_birds(n, r):
    out = bandnoise(n, 300, 2500) * 0.02 * slow(n, 8, 0.6, 1)   # a breath of air
    t = 0.0
    while t < n / SR:
        f = r.uniform(2600, 4200)
        song = np.concatenate([chirp(f, f * r.uniform(0.8, 1.25), r.uniform(0.05, 0.12), 0.05) for _ in range(r.integers(2, 6))])
        place(out, song, int(t * SR))
        t += r.uniform(1.2, 4.5)
    return out


def amb_wind(n, r):
    w = bandnoise(n, 120, 900) * slow(n, 9, 0.75, 2) * 0.22
    hiss = bandnoise(n, 1500, 5000) * slow(n, 6, 0.9, 3) * 0.035   # sand on the wind
    return w + hiss


def amb_fire(n, r):
    out = bandnoise(n, 80, 400) * 0.06 * slow(n, 5, 0.4, 4)        # the soft roar
    for _ in range(int(n / SR * 7)):
        c = int(r.uniform(0.002, 0.012) * SR)
        crack = r.standard_normal(c) * np.exp(-np.arange(c) / (c / 4)) * r.uniform(0.05, 0.25)
        place(out, crack, int(r.uniform(0, n)))
    return lowpass(out, 3500)


def amb_night(n, r):
    out = bandnoise(n, 100, 600) * 0.025 * slow(n, 10, 0.5, 5)
    for voice, (f, rate) in enumerate(((4300, 0.9), (3800, 1.3))):
        t = np.arange(n) / SR
        trill = (np.sin(2 * np.pi * 28 * t) > 0.2) * (np.sin(2 * np.pi * rate * t + voice) > 0.4)
        out += np.sin(2 * np.pi * f * t) * trill * 0.018 * slow(n, 7, 0.8, 6 + voice)
    return out


def amb_market(n, r):
    # a far murmur: many voices blurred into a band of noise that rises and falls at speech pace
    out = bandnoise(n, 180, 1100) * slow(n, 4, 0.5, 7) * 0.12
    t = np.arange(n) / SR
    syll = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 2.3 * t) * np.sin(2 * np.pi * 0.37 * t))
    out *= syll
    for _ in range(int(n / SR / 3)):
        place(out, chime([r.uniform(1800, 2600)], 0.5, 0.05), int(r.uniform(0, n)))   # a cup, a coin
    return out


def amb_water(n, r):
    out = bandnoise(n, 400, 3000) * 0.07 * slow(n, 3, 0.4, 8)
    for _ in range(int(n / SR * 9)):
        f = r.uniform(500, 1400)
        place(out, chirp(f, f * 1.6, r.uniform(0.02, 0.05), r.uniform(0.02, 0.06)), int(r.uniform(0, n)))
    return out


def amb_rain(n, r):
    out = bandnoise(n, 900, 7000) * 0.1 * slow(n, 6, 0.3, 9)
    for _ in range(int(n / SR * 25)):
        c = int(0.01 * SR)
        drop = r.standard_normal(c) * np.exp(-np.arange(c) / (c / 5)) * r.uniform(0.02, 0.08)
        place(out, drop, int(r.uniform(0, n)))
    return lowpass(out, 5000)


def ambience():
    os.makedirs(AMB, exist_ok=True)
    n = 40 * SR
    for name, fn in (("birds", amb_birds), ("wind", amb_wind), ("fire", amb_fire), ("night", amb_night),
                     ("market", amb_market), ("water", amb_water), ("rain", amb_rain)):
        x = fn(n, np.random.default_rng(len(name) * 31))
        x = x / (np.max(np.abs(x)) + 1e-9) * 0.5
        tmp = os.path.join(AMB, "_tmp_" + name + ".wav")   # (the old game has its own <name>.wav here)
        save_wav(tmp, x)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "2",
                        os.path.join(AMB, name + ".ogg")], check=True)
        os.remove(tmp)
        print("ambience", name)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "ambience":
        ambience()
        sys.exit(0)
    if len(sys.argv) > 1 and sys.argv[1] == "shot":
        save_wav(os.path.join(SFX, "shot.wav"), shot())
        sys.exit(0)
    os.makedirs(MUSIC, exist_ok=True)
    effects()
    music("day", tempo=60)
    music("evening", tempo=54, sparse=0.85)
    music("night", tempo=48, base=0.75, sparse=0.6, drum_on=False)
    ambience()
