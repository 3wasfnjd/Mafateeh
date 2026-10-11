"""Automated audio checks (not a substitute for listening on a headset).
python check_audio.py <quest-native/audio>  -> exit 1 on failure.
Checks: every sound the game references exists; no clipping (peak < -0.5 dBFS);
loops are seamless (end-to-start jump small relative to RMS); distinct materials
differ (stone vs wood footsteps by spectral centroid)."""
import os, re, sys, wave
import numpy as np

root = sys.argv[1]
fail = []


def read(path):
    with wave.open(path) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768.0
        return x, w.getframerate()


def centroid(x, sr):
    s = np.abs(np.fft.rfft(x))
    f = np.fft.rfftfreq(len(x), 1 / sr)
    return float((s * f).sum() / (s.sum() + 1e-9))


rows = []
for sub in ("sfx", "ambience"):
    for name in sorted(os.listdir(os.path.join(root, sub))):
        if not name.endswith(".wav"):
            continue
        x, sr = read(os.path.join(root, sub, name))
        peak = 20 * np.log10(np.max(np.abs(x)) + 1e-9)
        rms = 20 * np.log10(np.sqrt(np.mean(x * x)) + 1e-9)
        line = "%-9s %-22s %5.2fs peak %6.1f dBFS rms %6.1f dB" % (sub, name, len(x) / sr, peak, rms)
        if peak > -0.5:
            fail.append("clipping risk: " + name)
        if sub == "ambience":
            jump = abs(x[-1] - x[0]) / (np.sqrt(np.mean(x * x)) + 1e-9)
            line += "  seam %.2f" % jump
            if jump > 1.5:
                fail.append("loop seam: " + name)
        rows.append(line)
print("\n".join(rows))

# Every stream name used by the game code must exist.
code = open(os.path.join(root, "../scripts/audio/game_audio.gd"), encoding="utf8").read()
names = set(re.findall(r'play(?:_later)?\(\s*(?:[\d.]+,\s*)?"([a-z_]+)"', code))
names |= set(re.findall(r'_stream\("([a-z_]+)"\)', code))
for n in sorted(x for x in names if not x.endswith("_")):
    if not (os.path.exists(os.path.join(root, "sfx", n + ".wav")) or os.path.exists(os.path.join(root, "sfx", n + "_1.wav"))
            or os.path.exists(os.path.join(root, "ambience", n + ".wav"))):
        fail.append("missing sound referenced by code: " + n)

stone = np.mean([centroid(read(os.path.join(root, "sfx", "foot_stone_%d.wav" % i))[0], 44100) for i in range(1, 6)])
wood = np.mean([centroid(read(os.path.join(root, "sfx", "foot_wood_%d.wav" % i))[0], 44100) for i in range(1, 6)])
print("footstep spectral centroid: stone %.0f Hz, wood %.0f Hz" % (stone, wood))
if abs(stone - wood) < 400:
    fail.append("stone and wood footsteps are not distinct")
print("RESULT:", "PASS" if not fail else "FAIL")
for f in fail:
    print("  FAIL:", f)
sys.exit(1 if fail else 0)
