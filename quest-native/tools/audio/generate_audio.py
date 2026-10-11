"""Original procedural sound effects and ambience for Mafateeh.

    python generate_audio.py <quest-native/audio>      (needs numpy + scipy; versions in docs)

Everything is synthesised here — no recordings, samples or downloads — so this file
is the editable source of every sound in the game (MIT, Aboden Games). Output:
44.1 kHz 16-bit mono WAV in audio/sfx (one-shots, several variations where a sound
repeats) and audio/ambience (seamless loops: noise beds are shaped in the frequency
domain, which makes them exactly periodic).
"""
import os
import sys
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../../audio")
rng = np.random.default_rng(20261011)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def env(sec, attack=0.005, decay=0.2):
    t = t_axis(sec)
    return np.clip(t / max(attack, 1e-4), 0, 1) * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], "band", output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f / (SR / 2), "low", output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f / (SR / 2), "high", output="sos"), x)


def noise(sec):
    return rng.standard_normal(int(SR * sec))


def sine(f, sec, phase=0.0):
    return np.sin(2 * np.pi * f * t_axis(sec) + phase)


def bell(f, sec, decay=0.6, partials=((1, 1.0), (2.01, 0.35), (3.02, 0.12), (4.2, 0.06))):
    t = t_axis(sec)
    out = np.zeros_like(t)
    for ratio, amp in partials:
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / (decay / ratio ** 0.6))
    return out * np.clip(t / 0.004, 0, 1)


def marimba(f, sec=0.6):
    t = t_axis(sec)
    return (np.sin(2 * np.pi * f * t) * np.exp(-t / 0.22) + 0.25 * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t / 0.05)) \
        * np.clip(t / 0.002, 0, 1)


def pluck(f, sec=1.2, damp=0.996):
    """Karplus–Strong string, a gentle oud-like pluck."""
    n = int(SR * sec)
    period = int(SR / f)
    buf = rng.uniform(-1, 1, period)
    buf = lp(buf, 3000, 1)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = damp * 0.5 * (buf[i % period] + buf[(i + 1) % period])
    return out


def knock(freqs, sec=0.25, decay=0.06, click=0.4):
    t = t_axis(sec)
    out = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / (decay * (1.0 - 0.15 * k))) for k, f in enumerate(freqs))
    tr = bp(noise(sec), 800, 6000) * np.exp(-t / 0.004) * click
    return out / len(freqs) + tr


def friction(sec, rate0, rate1, res=(650, 1150), jitter=0.25):
    """Stick–slip pulses through resonances: creaks of doors and balance arms."""
    n = int(SR * sec)
    out = np.zeros(n)
    t = 0.0
    while t < sec:
        k = t / sec
        rate = rate0 + (rate1 - rate0) * k
        i = int(t * SR)
        if i < n:
            out[i] = rng.uniform(0.5, 1.0)
        t += 1.0 / rate * (1 + rng.uniform(-jitter, jitter))
    y = sum(bp(out, f * 0.85, f * 1.15) for f in res)
    return y * np.hanning(n) ** 0.5


def place(*parts):
    """Mix (offset_seconds, signal, gain) into one buffer."""
    end = max(int(o * SR) + len(s) for o, s, g in parts)
    out = np.zeros(end)
    for o, s, g in parts:
        i = int(o * SR)
        out[i:i + len(s)] += s * g
    return out


def fade(x, fin=0.002, fout=0.02):
    n = len(x)
    a = np.ones(n)
    k = int(fin * SR)
    m = int(fout * SR)
    if k:
        a[:k] = np.linspace(0, 1, k)
    if m:
        a[-m:] *= np.linspace(1, 0, m)
    return x * a


def save(path, x, peak_db=-3.0):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * (10 ** (peak_db / 20))
    assert np.max(np.abs(x)) < 1.0, "clipping in " + path
    data = (x * 32767).astype("<i2")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    return path


SFX = os.path.join(OUT, "sfx")
AMB = os.path.join(OUT, "ambience")


def sfx(name, x, peak=-3.0):
    save(os.path.join(SFX, name + ".wav"), fade(x), peak)


# --- character and movement -------------------------------------------------------------

def footsteps():
    for i in range(1, 6):
        sec = 0.16
        t = t_axis(sec)
        grit = bp(noise(sec), rng.uniform(900, 1300), rng.uniform(3500, 5000)) * np.exp(-t / rng.uniform(0.018, 0.03))
        thump = np.sin(2 * np.pi * rng.uniform(80, 110) * t) * np.exp(-t / 0.03) * 0.6
        sfx("foot_stone_%d" % i, lp(grit + thump, 7000), -9)
    for i in range(1, 6):
        k = knock([rng.uniform(170, 210), rng.uniform(380, 450), rng.uniform(720, 820)], 0.22, rng.uniform(0.04, 0.06), 0.5)
        sfx("foot_wood_%d" % i, lp(k, 6000), -8)
    for i in range(1, 5):
        sec = rng.uniform(0.18, 0.28)
        t = t_axis(sec)
        e = np.sin(np.pi * t / sec) ** 2
        sfx("cloth_%d" % i, bp(noise(sec), 1200, 5200) * e, -14)


# --- objects and puzzles ------------------------------------------------------------------

def objects():
    sec = 1.45
    t = t_axis(sec)
    slip = np.abs(signal.sosfilt(signal.butter(1, 18 / (SR / 2), output="sos"), noise(sec))) * 3
    scrape = bp(noise(sec), 250, 1800) * (0.6 + slip)
    rumble = lp(noise(sec), 160) * 2.0
    sfx("crate_scrape", (scrape + rumble) * np.clip(t / 0.08, 0, 1) * np.clip((sec - t) / 0.15, 0, 1), -6)
    sfx("crate_settle", place((0, knock([75, 160, 330], 0.35, 0.08, 0.3), 1.0), (0.02, knock([220, 480], 0.2, 0.04), 0.4)), -5)
    sfx("plate_click", place((0, knock([900, 1750], 0.12, 0.015, 0.6), 1.0), (0.05, knock([140], 0.2, 0.05, 0.1), 0.6)), -8)
    sfx("brick_lift", place((0, bp(noise(0.3), 300, 2500) * env(0.3, 0.03, 0.08), 0.8), (0.0, knock([95], 0.15, 0.04, 0.1), 0.5)), -9)
    sfx("brick_place", place((0, lp(noise(0.25), 500) * env(0.25, 0.003, 0.05) * 4, 1.0), (0, knock([110, 240], 0.25, 0.05, 0.2), 0.7)), -6)
    sfx("brick_drop", place((0, lp(noise(0.35), 600) * env(0.35, 0.002, 0.07) * 4, 1.0), (0, knock([85, 190], 0.3, 0.07, 0.3), 1.0)), -5)
    clink = lambda f: bell(f, 0.5, 0.15, ((1, 1), (2.76, 0.5), (5.4, 0.25)))
    sfx("weight_lift", place((0, clink(1250), 0.6), (0.0, bp(noise(0.12), 2000, 6000) * env(0.12, 0.002, 0.02), 0.3)), -10)
    sfx("weight_place", place((0, knock([160, 340], 0.25, 0.05, 0.2), 1.0), (0.01, clink(1150), 0.6)), -7)
    sfx("balance_creak", friction(0.6, 35, 55, (520, 980)) * 0.8, -12)
    sfx("balance_ok", place((0, bell(587.33, 1.4, 0.7), 1.0), (0.14, bell(739.99, 1.4, 0.7), 0.8)), -8)
    sfx("door_creak", place((0, friction(0.95, 18, 55, (610, 1080, 1720)), 1.0), (0.0, lp(noise(0.95), 300) * 0.3, 1.0)), -8)
    sfx("door_close", place((0, knock([90, 210], 0.35, 0.08, 0.3), 1.0), (0.08, knock([1400, 2600], 0.08, 0.01, 0.5), 0.5)), -6)
    sfx("latch_click", place((0, knock([2100, 3400], 0.06, 0.008, 0.8), 1.0), (0.07, knock([1800, 3000], 0.06, 0.008, 0.8), 0.8)), -9)
    sfx("unlock", place((0, knock([1500, 2900], 0.05, 0.007), 0.7), (0.08, knock([1500, 2900], 0.05, 0.007), 0.7),
                       (0.16, knock([1400, 2700], 0.05, 0.007), 0.7), (0.26, knock([180, 420], 0.2, 0.05, 0.2), 1.0)), -8)
    sfx("lever", place((0, knock([150, 320], 0.3, 0.06, 0.3), 1.0), (0.05, friction(0.18, 60, 90, (900, 1600)), 0.4)), -7)
    sec = 1.0
    t = t_axis(sec)
    wood = bp(noise(sec), 120, 600) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 7 * t)))
    splash = bp(noise(sec), 1500, 6000) * np.exp(-((t - 0.75) / 0.1) ** 2) * 0.4
    sfx("bridge_move", (wood + splash) * np.sin(np.pi * t / sec) ** 0.7, -9)
    sfx("gate_lift", friction(0.7, 25, 40, (300, 700)) + bp(noise(0.7), 150, 500) * 0.3, -10)
    sfx("mirror_click", place((0, knock([2400, 3800], 0.07, 0.01, 0.7), 1.0), (0.01, bell(2600, 0.3, 0.08), 0.2)), -10)
    sfx("dial_click", place((0, knock([1700, 2900], 0.05, 0.008), 1.0), (0.06, knock([1600, 2800], 0.05, 0.008), 0.7),
                           (0.0, knock([200], 0.12, 0.03, 0.0), 0.5)), -10)
    # Lamps: one harmonious pentatonic voice per lamp count, never the same beep.
    penta = [293.66, 349.23, 392.0, 440.0, 523.25]
    for k, f in enumerate(penta):
        sfx("switch_%d" % k, place((0, knock([220, 460], 0.15, 0.03, 0.3), 0.6), (0.02, bell(f, 1.0, 0.45), 0.8)), -10)
    # Carved tiles: marimba-like tones climbing as the sequence advances.
    for k, f in enumerate([220.0, 261.63, 293.66, 329.63, 392.0, 440.0], start=1):
        sfx("seq_%d" % k, place((0, marimba(f, 0.7), 1.0), (0, lp(noise(0.03), 2000) * 0.2, 1.0)), -9)
    t = t_axis(1.4)
    shimmer = sum(np.sin(2 * np.pi * f * t) * (1 - np.exp(-t / 0.25)) * np.exp(-t / 0.7) for f in (1318.5, 1975.5, 2637.0))
    sfx("receiver_on", shimmer, -12)
    t = t_axis(0.9)
    sweep = bp(noise(0.9), 400, 4000) * np.sin(np.pi * t / 0.9) ** 2
    sfx("portal", sweep * 0.6 + sine(196, 0.9) * np.sin(np.pi * t / 0.9) ** 2 * 0.4, -11)
    sfx("key_pickup", place((0, bell(659.25, 0.9, 0.35), 1.0), (0.09, bell(987.77, 1.0, 0.4), 0.8)), -9)
    sfx("gem_pickup", place((0, bell(880.0, 0.8, 0.3), 0.9), (0.07, bell(1108.73, 0.8, 0.3), 0.8), (0.14, bell(1318.5, 1.0, 0.45), 0.8)), -9)
    sfx("success", place((0, bell(587.33, 1.6, 0.7), 0.8), (0.12, bell(739.99, 1.6, 0.7), 0.7), (0.24, bell(880.0, 1.8, 0.8), 0.7)), -9)
    # Exit flourish: a short hijaz-flavoured pluck arpeggio (D Eb F# A D).
    notes = [293.66, 311.13, 369.99, 440.0, 587.33]
    sfx("level_complete", place(*[(i * 0.11, pluck(f, 1.3), 0.8) for i, f in enumerate(notes)]), -8)
    sfx("soft_reject", place((0, marimba(196.0, 0.4), 0.8), (0.11, marimba(164.81, 0.45), 0.7)), -14)
    sfx("tap", knock([1800], 0.04, 0.006, 0.3), -22)


def birds():
    for i in range(1, 5):
        parts = []
        o = 0.0
        for s in range(rng.integers(2, 5)):
            d = rng.uniform(0.05, 0.11)
            t = t_axis(d)
            f0, f1 = rng.uniform(2600, 3600), rng.uniform(3800, 5200)
            f = np.linspace(f0, f1, len(t)) if s % 2 == 0 else np.linspace(f1, f0, len(t))
            ph = 2 * np.pi * np.cumsum(f) / SR
            parts.append((o, np.sin(ph + 2 * np.sin(2 * np.pi * 45 * t)) * np.sin(np.pi * t / d), 1.0))
            o += d + rng.uniform(0.03, 0.09)
        sfx("bird_%d" % i, place(*parts), -10)


def ui():
    sfx("ui_click", knock([1500, 2400], 0.05, 0.01, 0.2), -14)
    sfx("ui_open", place((0, marimba(523.25, 0.3), 1.0), (0.06, marimba(659.25, 0.3), 0.8)), -14)
    sfx("ui_close", place((0, marimba(659.25, 0.3), 1.0), (0.06, marimba(523.25, 0.3), 0.8)), -14)
    sfx("ui_recenter", bp(noise(0.35), 500, 3000) * np.sin(np.pi * t_axis(0.35) / 0.35) ** 2, -16)


# --- ambience (seamless loops) -------------------------------------------------------------

def shaped_loop(sec, shape):
    """Periodic noise: spectrum shaped by shape(freqs) -> exact loop."""
    n = int(SR * sec)
    spec = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    return np.fft.irfft(spec * shape(np.maximum(freqs, 1.0)), n)


def periodic_lfo(sec, cycles, depth, phase=0.0):
    t = t_axis(sec)
    return 1 - depth + depth * (0.5 + 0.5 * np.sin(2 * np.pi * cycles * t / sec + phase))


def scatter(sec, rate, make, gain=1.0):
    """Sprinkle short events across a loop, wrapping at the end so it stays seamless."""
    n = int(SR * sec)
    out = np.zeros(n)
    for _ in range(int(rate * sec)):
        ev = make()
        i = rng.integers(0, n)
        idx = (i + np.arange(len(ev))) % n
        out[idx] += ev * gain
    return out


def save_loop(name, x, peak=-6.0):
    save(os.path.join(AMB, name + ".wav"), x, peak)


def ambience():
    sec = 12.0
    wind = shaped_loop(sec, lambda f: 1 / f ** 1.0 * (f < 900) * np.exp(-f / 500))
    wind *= periodic_lfo(sec, 2, 0.6) * periodic_lfo(sec, 5, 0.25, 1.0)
    leaves = shaped_loop(sec, lambda f: ((f > 1500) & (f < 7000)) * 1.0) * periodic_lfo(sec, 3, 0.8, 2.0) * 0.08
    save_loop("wind", wind / np.max(np.abs(wind)) + leaves, -8)

    sec = 10.0
    t = t_axis(sec)
    gate = (np.sin(2 * np.pi * 28 * t) > 0.3) * (np.sin(2 * np.pi * 1.0 * t) > 0.0)
    crickets = np.sin(2 * np.pi * 4300 * t) * lp(gate.astype(float), 400) * 0.15
    crickets2 = np.sin(2 * np.pi * 4700 * t) * lp(((np.sin(2 * np.pi * 31 * t + 1) > 0.4) * (np.sin(2 * np.pi * 0.7 * t + 2) > 0.2)).astype(float), 400) * 0.08
    night_air = shaped_loop(sec, lambda f: 1 / f * (f < 600)) * 0.5
    night_air /= np.max(np.abs(night_air))
    save_loop("night", crickets + crickets2 + night_air * 0.25, -12)

    sec = 8.0
    def blip():
        d = rng.uniform(0.03, 0.08)
        tt = t_axis(d)
        f = np.linspace(rng.uniform(500, 900), rng.uniform(250, 450), len(tt))
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / d) ** 2
    lap = shaped_loop(sec, lambda f: ((f > 150) & (f < 1200)) * 1.0) * periodic_lfo(sec, 6, 0.7)
    lap /= np.max(np.abs(lap))
    save_loop("water", lap * 0.35 + scatter(sec, 9, blip, 0.5), -12)

    sec = 10.0
    def drop(lo=2500, hi=7000):
        d = 0.012
        return bp(rng.standard_normal(int(SR * d)), lo, hi) * np.exp(-t_axis(d) / 0.003)
    bed = shaped_loop(sec, lambda f: ((f > 700) & (f < 10000)) / f ** 0.3)
    bed /= np.max(np.abs(bed))
    save_loop("rain_stone", bed * 0.6 + scatter(sec, 220, drop, 0.6), -8)

    def plink():
        d = rng.uniform(0.04, 0.09)
        tt = t_axis(d)
        f = np.linspace(rng.uniform(900, 1600), rng.uniform(1600, 2600), len(tt))
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.02)
    bed2 = shaped_loop(sec, lambda f: ((f > 300) & (f < 6000)) / f ** 0.5)
    bed2 /= np.max(np.abs(bed2))
    save_loop("rain_water", bed2 * 0.5 + scatter(sec, 60, plink, 0.35), -10)

    bed3 = shaped_loop(sec, lambda f: ((f > 200) & (f < 2500)) / f ** 0.4)
    bed3 /= np.max(np.abs(bed3))
    save_loop("rain_roof", bed3 * 0.6 + scatter(sec, 160, lambda: drop(400, 2200), 0.8), -10)


if __name__ == "__main__":
    footsteps()
    objects()
    birds()
    ui()
    ambience()
    files = sorted(os.listdir(SFX)) + sorted(os.listdir(AMB))
    print("%d sounds written to %s" % (len(files), OUT))
