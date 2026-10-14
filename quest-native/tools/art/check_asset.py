"""Quick report on an incoming GLB before it goes into the game (no Blender needed).
Usage: python3 tools/art/check_asset.py model.glb [--slot falcon|cat|sparrow]

Prints triangles, meshes, materials, embedded textures (size), skins/bones, animation
clips with durations, the bounding box (glTF: Y up, +Z forward) and a verdict against
the Quest budget. With --slot it also checks the clip names a creature slot needs
(see scripts/art/creature_slot.gd).
"""
import json
import struct
import sys

BUDGET_TRIS = 8000      # per creature / prop on Quest (a soft limit, warn above)
HARD_TRIS = 20000
MAX_TEX = 2048
SLOT_ROLES = {
    "falcon": {"perch": ["perch", "idle", "sit", "stand"], "fly": ["fly", "flap", "flying", "fly_loop"]},
    "cat": {"sit": ["sit", "idle_sit", "sitting", "idle"], "walk": ["walk", "walking", "walk_loop"],
            "sleep": ["sleep", "lie", "lying", "rest", "sleeping"]},
    "sparrow": {"peck": ["peck", "eat", "idle"], "fly": ["fly", "flap", "flying"]},
}


def read_glb(path):
    data = open(path, "rb").read()
    if data[:4] != b"glTF":
        sys.exit("not a GLB (binary glTF) file: " + path)
    off, js, binc = 12, None, b""
    while off < len(data):
        n, kind = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8:off + 8 + n]
        if kind == 0x4E4F534A:
            js = json.loads(chunk)
        elif kind == 0x004E4942:
            binc = chunk
        off += 8 + n
    return js, binc


def image_size(blob):
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", blob[16:24])
    if blob[:2] == b"\xff\xd8":  # JPEG: scan for SOF
        i = 2
        while i < len(blob) - 9:
            if blob[i] != 0xFF:
                i += 1
                continue
            marker = blob[i + 1]
            ln = struct.unpack(">H", blob[i + 2:i + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", blob[i + 5:i + 9])
                return w, h
            i += 2 + ln
    return None


def short(name):
    return name.split("|")[-1].lower()


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    slot = sys.argv[sys.argv.index("--slot") + 1] if "--slot" in sys.argv else None
    j, binc = read_glb(path)
    acc = j.get("accessors", [])
    tris, lo, hi = 0, [1e9] * 3, [-1e9] * 3
    for m in j.get("meshes", []):
        for p in m["primitives"]:
            if "indices" in p:
                tris += acc[p["indices"]]["count"] // 3
            else:
                tris += acc[p["attributes"]["POSITION"]]["count"] // 3
            a = acc[p["attributes"]["POSITION"]]
            if "min" in a:
                lo = [min(x, y) for x, y in zip(lo, a["min"])]
                hi = [max(x, y) for x, y in zip(hi, a["max"])]
    warn = []
    print("file:", path)
    print("meshes: %d   triangles: %d   materials: %d" % (len(j.get("meshes", [])), tris, len(j.get("materials", []))))
    if tris > HARD_TRIS:
        warn.append("too heavy for Quest (%d tris > %d): decimate it" % (tris, HARD_TRIS))
    elif tris > BUDGET_TRIS:
        warn.append("above the %d-triangle budget: fine for the hero, heavy for a creature" % BUDGET_TRIS)
    views = j.get("bufferViews", [])
    for i, im in enumerate(j.get("images", [])):
        if "bufferView" in im:
            v = views[im["bufferView"]]
            blob = binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
            sz = image_size(blob)
            print("texture %d: %s %s (%d KB)" % (i, im.get("name", ""), "%dx%d" % sz if sz else "?", len(blob) // 1024))
            if sz and max(sz) > MAX_TEX:
                warn.append("texture %d is %dx%d: resize to %d or less" % (i, sz[0], sz[1], MAX_TEX))
        else:
            warn.append("texture %d is an external file (%s): export as GLB with embedded textures" % (i, im.get("uri")))
    for s in j.get("skins", []):
        print("skin: %d bones" % len(s["joints"]))
    clips = []
    for a in j.get("animations", []):
        t = 0.0
        for smp in a["samplers"]:
            t = max(t, acc[smp["input"]].get("max", [0])[0])
        clips.append(a.get("name", "?"))
        print("clip: %-24s %.2fs" % (a.get("name", "?"), t))
    if lo[0] < 1e8:
        size = [h - l for h, l in zip(hi, lo)]
        print("bounds (m): width %.3f  height %.3f  depth %.3f   (lowest point y=%.3f)" % (size[0], size[1], size[2], lo[1]))
        print("  forward is +Z in glTF (-Y in Blender); front-most z=%.3f, back-most z=%.3f" % (hi[2], lo[2]))
    if slot:
        roles = SLOT_ROLES.get(slot)
        if roles is None:
            sys.exit("unknown slot " + slot)
        for role, aliases in roles.items():
            hit = next((c for a in aliases for c in clips if short(c) == a), None)
            hit = hit or next((c for a in aliases for c in clips if a in c.lower()), None)
            print("slot %s role %-6s -> %s" % (slot, role, hit or "MISSING (model holds still)"))
            if not hit:
                warn.append("no clip for %s (rename one of: %s)" % (role, ", ".join(aliases)))
    print()
    print("OK for Quest" if not warn else "\n".join("! " + w for w in warn))


if __name__ == "__main__":
    main()
