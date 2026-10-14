"""Animation clips for the v2 hero «الشايب» (baked keyframes, root in place).

Clips are pose functions of time. Each pose sets local rotations (about the parent's
rest axes, degrees) like build_shaib.set_pose, plus solver goals:
  _feet  {"L"/"R": (ankle_xy_target Vector(x, y), lift, pitch_deg, pivot)}  2-bone leg IK,
         the foot pitched about its heel/ball so it rolls instead of sliding
  _hands {"L"/"R": (grip target Vector, pole Vector)}                       2-bone arm IK
  _cane  ("ground", Vector tip) | None   cane aimed so its tip stands on the tip point
  _hide  bones scaled to zero (the cane swaps between the fist and the forearm)

Cycle distances (board units travelled per loop) are exported for HeroView so the
playback rate matches the ground speed and planted feet do not slide.
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

V = Vector
FPS = 30
WALK_D = 0.66      # walk / carry: units per cycle
STAIRS_D = 0.56
PUSH_D = 0.50
TURN_D = 0.10
CYCLES = {"walk": WALK_D, "carry": WALK_D, "stairs_up": STAIRS_D, "stairs_down": STAIRS_D, "push": PUSH_D}

ANKLE = {"L": V((0.068, 0.012, 0.062)), "R": V((-0.068, 0.012, 0.062))}
HEEL = {"L": V((0.069, 0.035, 0.004)), "R": V((-0.069, 0.035, 0.004))}
BALL = {"L": V((0.070, -0.052, 0.006)), "R": V((-0.070, -0.052, 0.006))}
CANE_L = 0.394


def clamp(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def smooth(a, b, x):
    if a == b:
        return 0.0 if x < a else 1.0
    t = clamp((x - a) / (b - a))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def wrap(x):
    return x - math.floor(x)


def cosw(phase):
    return math.cos(2 * math.pi * phase)


def sinw(phase):
    return math.sin(2 * math.pi * phase)


def mix(*poses):
    """Sum several partial poses (rotations add; locations add; specials: last wins)."""
    out = {}
    for p in poses:
        for k, v in p.items():
            if k.startswith("_"):
                if k == "_hide":
                    out[k] = list(set(out.get(k, [])) | set(v))
                else:
                    out[k] = v
                continue
            rot, loc = (v[0], v[1]) if isinstance(v[0], (tuple, list)) else (v, None)
            if k in out:
                r0, l0 = out[k]
                rot = tuple(a + b for a, b in zip(r0, rot))
                if l0 is not None:
                    loc = tuple(a + b for a, b in zip(l0, loc)) if loc else l0
            out[k] = (tuple(rot), tuple(loc) if loc else None)
    return out


def blend(a, b, t):
    """Linear blend of two full poses (rotation tuples), specials from the nearer one."""
    keys = set(a) | set(b)
    out = {}
    for k in keys:
        if k.startswith("_"):
            out[k] = (b if t >= 0.5 else a).get(k, (a if t >= 0.5 else b).get(k))
            if out[k] is None:
                out.pop(k)
            continue
        ra, la = norm(a.get(k))
        rb, lb = norm(b.get(k))
        out[k] = (tuple(lerp(x, y, t) for x, y in zip(ra, rb)), tuple(lerp(x, y, t) for x, y in zip(la, lb)))
    if "_feet" in a and "_feet" in b:
        out["_feet"] = {s: blend_foot(a["_feet"][s], b["_feet"][s], t) for s in ("L", "R")}
    return out


def norm(v):
    if v is None:
        return (0, 0, 0), (0, 0, 0)
    if isinstance(v[0], (tuple, list)):
        return tuple(v[0]), tuple(v[1]) if v[1] else (0, 0, 0)
    return tuple(v), (0, 0, 0)


def blend_foot(fa, fb, t):
    return (fa[0].lerp(fb[0], t), lerp(fa[1], fb[1], t), lerp(fa[2], fb[2], t), fb[3] if t > 0.5 else fa[3])


def planted(dx=0.0, dy=0.0, side_pitch=None):
    """Both feet flat at the rest stance (offsets in x/y per foot optional)."""
    return {s: (V((ANKLE[s].x + (dx if s == "L" else -dx), ANKLE[s].y + (dy if s == "L" else -dy))), 0.0, 0.0, None) for s in ("L", "R")}


# --------------------------------------------------------------------------------------
# Solvers (operate on the posed armature; modifiers are off while baking)
# --------------------------------------------------------------------------------------
def update():
    bpy.context.view_layer.update()


def aim(arm, name, d):
    """Rotate a bone (minimal rotation) so its length axis points along d (pose space)."""
    pb = arm.pose.bones[name]
    m = pb.matrix.copy()
    y = m.col[1].xyz.normalized()
    q = y.rotation_difference(d.normalized())
    r = (q.to_matrix() @ m.to_3x3()).to_4x4()
    r.translation = m.translation
    pb.matrix = r
    update()


def two_bone(arm, upper, lower, target, pole):
    pa = arm.pose.bones[upper]
    pbn = arm.pose.bones[lower]
    a = arm.data.bones[upper].length
    b = arm.data.bones[lower].length
    s = pa.matrix.translation.copy()
    d = target - s
    dist = clamp(d.length, abs(a - b) + 1e-4, a + b - 1e-4)
    dn = d.normalized()
    # elbow/knee on the pole side of the reach line
    pn = (pole - dn * pole.dot(dn))
    if pn.length < 1e-6:
        pn = V((0, -1, 0))
    pn.normalize()
    ca = clamp((a * a + dist * dist - b * b) / (2 * a * dist), -1, 1)
    elbow = s + dn * (a * ca) + pn * (a * math.sqrt(max(0.0, 1 - ca * ca)))
    aim(arm, upper, elbow - s)
    aim(arm, lower, (s + dn * dist) - pbn.matrix.translation)


def foot_ankle(side, xy, lift, pitch, pivot):
    """Ankle position for a foot whose flat position is xy (ankle x/y), lifted, pitched
    (deg, + = heel up) about its heel / ball / ankle."""
    a0 = ANKLE[side]
    base = V((xy.x, xy.y, a0.z + lift))
    if not pitch or pivot is None:
        return base
    piv0 = HEEL[side] if pivot == "heel" else BALL[side]
    off = piv0 - a0
    piv = base + off
    q = Quaternion(V((1, 0, 0)), math.radians(pitch))
    return piv + q @ (a0 - piv0)


def solve_feet(arm, feet):
    for side in ("L", "R"):
        xy, lift, pitch, pivot = feet[side]
        target = foot_ankle(side, xy, lift, pitch, pivot)
        two_bone(arm, "Thigh." + side, "Shin." + side, target, V((0, -1, 0.0)))
        # Foot pitch is relative to the ground (world), not to the shin.
        rest = (BALL[side] - ANKLE[side]).normalized()
        heel_up = pitch if pivot == "ball" else pitch * 1.0
        d = Quaternion(V((1, 0, 0)), math.radians(heel_up)) @ (V((0.002, -0.064, -0.042)).normalized())
        aim(arm, "Foot." + side, d)
        # Toes stay flat on the ground while the heel is up.
        tq = Quaternion(V((1, 0, 0)), math.radians(min(heel_up, 0.0) * 0.6))
        aim(arm, "Toe." + side, tq @ V((0.001, -0.04, -0.004)).normalized())


def grip_world(arm):
    pb = arm.pose.bones["Cane"]
    return pb.matrix.translation.copy()


def solve_hand(arm, side, target, pole, grip=False):
    """Move the arm so the hand's grip (or palm) reaches target."""
    for _ in range(2):
        hb = arm.pose.bones["Hand." + side]
        wrist = hb.matrix.translation.copy()
        if grip and side == "R":
            g = grip_world(arm)
        else:
            g = hb.matrix @ V((0, arm.data.bones["Hand." + side].length * 0.6, 0))
        w_target = target - (g - wrist)
        two_bone(arm, "UpperArm." + side, "LowerArm." + side, w_target, pole)


def solve_cane(arm, tip, natural_dir=None):
    """Keep the right fist on the crook and stand the cane's tip on `tip`."""
    g = grip_world(arm)
    d = (g - tip)
    if natural_dir is not None:
        d = natural_dir
    d.normalize()
    target = tip + d * CANE_L
    solve_hand(arm, "R", target, V((-0.6, 0.6, -0.2)), grip=True)
    g = grip_world(arm)
    aim(arm, "Cane", tip - g)


# --------------------------------------------------------------------------------------
# Pose application + baking
# --------------------------------------------------------------------------------------
def apply_pose(arm, pose, set_pose):
    set_pose(arm, {k: v for k, v in pose.items() if k in ("_hide",) or not k.startswith("_")})
    update()
    if "_feet" in pose:
        solve_feet(arm, pose["_feet"])
    for side, goal in pose.get("_hands", {}).items():
        solve_hand(arm, side, goal[0], goal[1])
    # The forearm-hung cane always hangs plumb (a touch of swing comes from the clip).
    swing = pose.get("_cane_swing", V((0, 0.0, 0)))
    aim(arm, "CaneArm", V((0, 0.04, -1)) + swing)
    if pose.get("_cane"):
        kind, tip = pose["_cane"][0], pose["_cane"][1]
        nat = pose["_cane"][2] if len(pose["_cane"]) > 2 else None
        if kind == "ground":
            solve_cane(arm, tip, nat)


def bake(arm, name, seconds, fn, loop, set_pose):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    frames = int(round(seconds * FPS))
    prev = {}
    for f in range(frames + 1):
        t = (f % frames) / FPS if loop else f / FPS
        apply_pose(arm, fn(t, seconds), set_pose)
        for pb in arm.pose.bones:
            q = pb.rotation_quaternion.copy()
            if pb.name in prev and prev[pb.name].dot(q) < 0:
                q.negate()
                pb.rotation_quaternion = q
            prev[pb.name] = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("scale", frame=f)
    act.frame_range = (0, frames)
    act.use_frame_range = True
    act.use_cyclic = loop
    return act


# --------------------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------------------
CANE_HAND = {
    "Fingers1.R": (0, -62, 0), "Fingers2.R": (0, -80, 0), "Thumb.R": (0, -35, 10),
}
RELAXED_L = {"Fingers1.L": (0, 20, 0), "Fingers2.L": (0, 24, 0), "Thumb.L": (0, 8, 0)}
FIST_L = {"Fingers1.L": (0, 70, 0), "Fingers2.L": (0, 85, 0), "Thumb.L": (0, 30, -8)}
OPEN_R = {"Fingers1.R": (0, -14, 0), "Fingers2.R": (0, -16, 0), "Thumb.R": (0, -6, 0)}
GRAB_L = {"Fingers1.L": (0, 40, 0), "Fingers2.L": (0, 50, 0), "Thumb.L": (0, 20, 0)}
GRAB_R = {"Fingers1.R": (0, -40, 0), "Fingers2.R": (0, -50, 0), "Thumb.R": (0, -20, 0)}
CANE_TIP_REST = V((-0.232, -0.10, 0.0))   # where the cane stands while waiting


def stoop(k=1.0):
    return {"Spine": (4 * k, 0, 0), "Chest": (3 * k, 0, 0), "Neck": (-4 * k, 0, 0), "Head": (-3 * k, 0, 0)}


def breathe(t, period=3.2, k=1.0):
    b = math.sin(2 * math.pi * t / period)
    return {"Chest": (-1.2 * b * k, 0, 0), "Neck": (0.6 * b * k, 0, 0),
            "Clavicle.L": (0, 0, 1.2 * b * k), "Clavicle.R": (0, 0, -1.2 * b * k), "Hips": ((0, 0, 0), (0, 0, -0.0012 * b * k))}


def stand(t, cane=True):
    p = mix(stoop(), breathe(t), RELAXED_L, CANE_HAND if cane else OPEN_R,
            {"UpperArm.L": (-4, 0, 6), "LowerArm.L": (-20, 0, 0), "Hand.L": (-6, 0, 4),
             "Hips": ((0, 0, 0), (0, 0, -0.006))})
    p["_feet"] = planted()
    if cane:
        p["_cane"] = ("ground", CANE_TIP_REST.copy())
        p["_hide"] = ["CaneArm"]
    else:
        p["_hide"] = ["Cane"]
    return p


def gait(phi, D, beta=0.6, lift=0.03, heel=12.0, toe=20.0, width=0.0):
    """Feet for a walk cycle at phase phi (left heel strike at 0.25, right at 0.75)."""
    feet = {}
    S = D * beta
    for side, c in (("L", 0.25), ("R", 0.75)):
        u = wrap(phi - c)
        x = ANKLE[side].x + (width if side == "L" else -width)
        if u < beta:
            s = u / beta
            y = -S / 2 + S * s
            h = 0.0
            if s < 0.14:
                pitch, piv = -heel * (1 - smooth(0.0, 0.14, s)), "heel"
            elif s > 0.70:
                pitch, piv = toe * smooth(0.70, 1.0, s), "ball"
            else:
                pitch, piv = 0.0, None
        else:
            s = (u - beta) / (1 - beta)
            e = 0.5 - 0.5 * math.cos(math.pi * s)
            y = S / 2 - S * e
            h = lift * math.sin(math.pi * min(1.0, s * 1.15)) ** 1.2
            pitch, piv = lerp(toe, -heel, smooth(0.0, 1.0, s)), None
            # keep the toe clear while it swings through
            h += 0.008 * math.sin(math.pi * s)
        feet[side] = (V((x, ANKLE[side].y + y)), h, pitch, piv)
    return feet


def walk_body(phi, k=1.0, lean=6.0, bob=0.009):
    """Pelvis bob/sway/yaw, counter-rotating chest, head steady, cloth lag."""
    hz = -0.014 + bob * k * math.cos(4 * math.pi * (phi - 0.25 - 0.30))
    hx = 0.008 * k * math.cos(2 * math.pi * (phi - 0.25 - 0.30))
    yaw = -5.0 * k * cosw(phi - 0.25)
    roll = 2.2 * k * cosw(phi - 0.55)
    p = {
        "Hips": ((0, roll, yaw), (hx, 0, hz)),
        "Spine": (lean * 0.6, -roll * 0.5, -yaw * 0.5),
        "Chest": (lean * 0.4, -roll * 0.4, -yaw * 0.6),
        "Neck": (-lean * 0.5, 0, -yaw * 0.25),
        "Head": (-lean * 0.4 + 1.2 * math.cos(4 * math.pi * (phi - 0.6)), roll * 0.3, -yaw * 0.15),
        # Thobe hem lags the legs; shemagh tails swing with the bob.
        "Skirt.F": (-3 - 3 * k * abs(cosw(phi - 0.33)), 0, 0),
        "Skirt.B": (4 + 2 * k * abs(cosw(phi - 0.33)), 0, 0),
        "Skirt.L": (0, -2.5 * k * sinw(phi - 0.3), 0),
        "Skirt.R": (0, -2.5 * k * sinw(phi - 0.3), 0),
        "Shemagh.L": (4 * k + 2 * math.cos(4 * math.pi * (phi - 0.4)), 0, 0),
        "Shemagh.R": (4 * k + 2 * math.cos(4 * math.pi * (phi - 0.4)), 0, 0),
        "Shemagh.B": (5 * k, 0, 0), "Shemagh.B2": (3 * k + 2 * math.cos(4 * math.pi * (phi - 0.45)), 0, 0),
        "Shemagh.L2": (3 * k, 0, 0), "Shemagh.R2": (3 * k, 0, 0),
    }
    return p


def cane_walk(phi, D):
    """Cane tip: planted with the left heel (phase 0.25), lifted and swung forward."""
    beta = 0.55
    S = D * beta
    u = wrap(phi - 0.22)
    if u < beta:
        s = u / beta
        y = -0.17 - S / 2 + S * s
        h = 0.0
    else:
        s = (u - beta) / (1 - beta)
        e = 0.5 - 0.5 * math.cos(math.pi * s)
        y = -0.17 + S / 2 - S * e
        h = 0.035 * math.sin(math.pi * s)
    return V((-0.235, y, h))


# --------------------------------------------------------------------------------------
# Clips
# --------------------------------------------------------------------------------------
def clip_idle(t, T):
    p = stand(t)
    # weight shift and slow look around, all periods dividing the loop length (T = 4.8)
    w = math.sin(2 * math.pi * t / T)
    p = mix(p, {"Hips": ((0, 1.5 * w, 0), (0.006 * w, 0, 0)), "Spine": (0, -0.8 * w, 0),
                "Head": (0, 0, 9 * math.sin(2 * math.pi * t / T + 0.6) * smooth(0.0, 1.0, abs(math.sin(2 * math.pi * t / T)))),
                "Neck": (0, 0, 3 * math.sin(2 * math.pi * t / T + 0.6)),
                "Fingers1.L": (0, 4 * math.sin(4 * math.pi * t / T), 0)})
    p["_feet"] = planted()
    return p


def clip_idle_look(t, T):
    """One-shot: looks over the shoulder, then to the other side, back to front."""
    p = stand(t)
    a = smooth(0.1, 0.35, t / T) - smooth(0.45, 0.6, t / T)
    b = smooth(0.55, 0.72, t / T) - smooth(0.85, 1.0, t / T)
    yaw = 32 * a - 26 * b
    p = mix(p, {"Head": (-4 * (a + b), 0, yaw * 0.6), "Neck": (0, 0, yaw * 0.3), "Chest": (0, 0, yaw * 0.12),
                "Hips": ((0, 0, yaw * 0.05), None)})
    return p


def clip_walk(t, T, D=WALK_D):
    phi = t / T
    p = mix(walk_body(phi), CANE_HAND, RELAXED_L, {
        "UpperArm.L": (-14 * cosw(phi - 0.75 - 0.04), 0, 5), "LowerArm.L": (-18 - 10 * max(0.0, cosw(phi - 0.8)), 0, 0),
        "Hand.L": (-6, 0, 4),
    })
    p["_feet"] = gait(phi, D)
    tip = cane_walk(phi, D)
    p["_cane"] = ("ground", tip)
    p["_hide"] = ["CaneArm"]
    return p


def clip_turn(t, T):
    phi = t / T
    p = mix(walk_body(phi, k=0.5, lean=5, bob=0.004), CANE_HAND, RELAXED_L,
            {"UpperArm.L": (-6, 0, 6), "LowerArm.L": (-22, 0, 0)})
    p["_feet"] = gait(phi, TURN_D, beta=0.55, lift=0.025)
    p["_cane"] = ("ground", CANE_TIP_REST.copy())
    p["_hide"] = ["CaneArm"]
    return p


def clip_push(t, T):
    """Leaning into a crate, both palms on its face, short driving steps. The cane hangs
    from the right forearm."""
    phi = t / T
    feet = gait(phi, PUSH_D, beta=0.68, lift=0.02, heel=6, toe=26)
    for s in feet:
        xy, h, pitch, piv = feet[s]
        feet[s] = (xy + V((0, 0.10)), h, pitch, piv)  # feet behind: body inclined
    push = 1.5 * math.cos(4 * math.pi * (phi - 0.3))
    p = mix(walk_body(phi, k=0.6, lean=0, bob=0.006), {
        "Hips": ((0, 0, 0), (0, 0.05, -0.03)), "Spine": (16, 0, 0), "Chest": (8 + push, 0, 0),
        "Neck": (-12, 0, 0), "Head": (-12, 0, 0),
        "Hand.L": (-30, 0, -10), "Hand.R": (-30, 0, 10),
    }, OPEN_R, {"Fingers1.L": (0, 12, 0), "Fingers2.L": (0, 12, 0)})
    p["_feet"] = feet
    z = 0.66 + 0.004 * push
    p["_hands"] = {"L": (V((0.105, -0.40, z)), V((0.8, 0.2, -0.6))), "R": (V((-0.105, -0.40, z)), V((-0.8, 0.2, -0.6)))}
    p["_cane_swing"] = V((0.03 * sinw(phi), 0.08 * cosw(2 * phi), 0))
    p["_hide"] = ["Cane"]
    return p


def crouch_pose(a, reach):
    """Bend at hips and knees (feet planted), torso down, hands towards the floor."""
    return {
        "Hips": ((-6 * a, 0, 0), (0, 0.05 * a, -0.15 * a)),
        "Spine": (28 * a, 0, 0), "Chest": (14 * a, 0, 0), "Neck": (-16 * a, 0, 0), "Head": (-14 * a, 0, 0),
        "Skirt.F": (-12 * a, 0, 0), "Skirt.B": (10 * a, 0, 0),
    }


def clip_pickup(t, T):
    """Two hands lift an object from the floor; the cane goes onto the forearm."""
    u = t / T
    a = smooth(0.0, 0.45, u) - smooth(0.55, 1.0, u)
    p = mix(stoop(), crouch_pose(a, 1.0), {"Hand.L": (-25 * a, 0, -8 * a), "Hand.R": (-25 * a, 0, 8 * a)})
    p = mix(p, blend_hands(GRAB_L, RELAXED_L, smooth(0.42, 0.5, u), "L"), blend_hands(GRAB_R, OPEN_R, smooth(0.42, 0.5, u), "R"))
    p["_feet"] = planted(dy=0.0)
    lo = V((0.0, -0.24, 0.12))
    hold = V((0.0, -0.21, 0.66))
    c = lo.lerp(hold, smooth(0.5, 1.0, u)) if u > 0.5 else hold.lerp(lo, smooth(0.0, 0.45, u))
    p["_hands"] = {"L": (c + V((0.075, 0, 0)), V((0.9, 0.3, -0.4))), "R": (c + V((-0.075, 0, 0)), V((-0.9, 0.3, -0.4)))}
    p["_hide"] = ["Cane"]
    return p


def blend_hands(a, b, t, side):
    out = {}
    for k in set(a) | set(b):
        ra = a.get(k, (0, 0, 0))
        rb = b.get(k, (0, 0, 0))
        out[k] = tuple(lerp(x, y, t) for x, y in zip(rb, ra))
    return out


def clip_pickup_small(t, T):
    """One hand (left) picks a key or gem from the floor; the cane stays planted."""
    u = t / T
    a = smooth(0.0, 0.45, u) - smooth(0.6, 1.0, u)
    p = mix(stand(t), crouch_pose(a * 0.7, 1.0), blend_hands(GRAB_L, RELAXED_L, smooth(0.42, 0.5, u), "L"))
    lo = V((0.07, -0.25, 0.20))
    up = V((0.06, -0.20, 0.78))  # holds it up to look at it
    c = lo.lerp(up, smooth(0.52, 0.9, u)) if u > 0.5 else V((0.12, -0.05, 0.44)).lerp(lo, smooth(0.05, 0.45, u))
    p["_hands"] = {"L": (c, V((0.7, 0.2, -1.0)))}
    if u > 0.75:
        p["Head"] = (8, 0, 6)
    p["_feet"] = planted()
    tip = CANE_TIP_REST.copy() + V((0.0, -0.04 * a, 0))
    p["_cane"] = ("ground", tip)
    return p


def carry_hands(c):
    return {"L": (c + V((0.075, 0, 0)), V((0.9, 0.3, -0.4))), "R": (c + V((-0.075, 0, 0)), V((-0.9, 0.3, -0.4)))}


def clip_carry(t, T):
    phi = t / T
    p = mix(walk_body(phi, k=0.8, lean=3), GRAB_L, GRAB_R, {"Hand.L": (-10, 0, -6), "Hand.R": (-10, 0, 6)})
    p["_feet"] = gait(phi, WALK_D, beta=0.62, lift=0.026)
    bob = 0.006 * math.cos(4 * math.pi * (phi - 0.6))
    p["_hands"] = carry_hands(V((0.0, -0.21, 0.66 + bob)))
    p["_cane_swing"] = V((0.05 * sinw(phi - 0.1), 0.12 * cosw(2 * phi - 0.2), 0))
    p["_hide"] = ["Cane"]
    return p


def clip_carry_idle(t, T):
    p = mix(stoop(0.6), breathe(t), GRAB_L, GRAB_R, {"Hand.L": (-10, 0, -6), "Hand.R": (-10, 0, 6),
                                                     "Hips": ((0, 0, 0), (0, 0, -0.006))})
    p["_feet"] = planted()
    p["_hands"] = carry_hands(V((0.0, -0.21, 0.66 + 0.002 * math.sin(2 * math.pi * t / 3.2))))
    p["_hide"] = ["Cane"]
    return p


def clip_place(t, T):
    """Puts the object down, then takes the cane back into the fist."""
    u = t / T
    a = smooth(0.0, 0.45, u) - smooth(0.55, 1.0, u)
    p = mix(stoop(), crouch_pose(a, 1.0), {"Hand.L": (-25 * a, 0, -8 * a), "Hand.R": (-25 * a, 0, 8 * a)})
    p = mix(p, blend_hands(RELAXED_L, GRAB_L, smooth(0.45, 0.55, u), "L"), blend_hands(OPEN_R, GRAB_R, smooth(0.45, 0.55, u), "R"))
    p["_feet"] = planted()
    hold = V((0.0, -0.21, 0.66))
    lo = V((0.0, -0.24, 0.12))
    if u <= 0.5:
        c = hold.lerp(lo, smooth(0.0, 0.45, u))
        p["_hands"] = {"L": (c + V((0.075, 0, 0)), V((0.9, 0.3, -0.4))), "R": (c + V((-0.075, 0, 0)), V((-0.9, 0.3, -0.4)))}
        p["_hide"] = ["Cane"]
    else:
        # rising: the right hand slides down the forearm-hung cane and lifts it free
        k = smooth(0.5, 1.0, u)
        p["_hands"] = {"L": (lo.lerp(V((0.12, -0.04, 0.44)), k) + V((0.075, 0, 0)) * (1 - k), V((0.9, 0.3, -0.4)))}
        p = mix(p, CANE_HAND)
        p["_cane"] = ("ground", CANE_TIP_REST.copy())
        p["_hide"] = ["CaneArm"]
    return p


def clip_stairs(up):
    def f(t, T):
        phi = t / T
        lean = 12 if up else -2
        p = mix(walk_body(phi, k=0.9, lean=lean, bob=0.012), CANE_HAND, RELAXED_L, {
            "UpperArm.L": (-12 * cosw(phi - 0.79), 0, 5), "LowerArm.L": (-22, 0, 0)})
        p["_feet"] = gait(phi, STAIRS_D, beta=0.62, lift=0.07 if up else 0.05, heel=4 if up else 14, toe=14)
        p["_cane"] = ("ground", cane_walk(phi, STAIRS_D) + V((0, 0, 0.02 * (1 if up else -1))))
        p["_hide"] = ["CaneArm"]
        return p
    return f


def clip_think(t, T):
    """Strokes the beard: hand to the chin, three slow strokes, head tilted."""
    u = t / T
    a = smooth(0.0, 0.18, u) * (1 - smooth(0.85, 1.0, u))
    stroke = math.sin(2 * math.pi * 3 * clamp((u - 0.18) / 0.62)) * smooth(0.18, 0.25, u) * (1 - smooth(0.75, 0.82, u))
    p = mix(stand(t), {"Head": (-6 * a, 4 * a, 8 * a), "Neck": (-2 * a, 0, 4 * a), "Chest": (0, 0, 4 * a)},
            blend_hands({"Fingers1.L": (0, 35, 0), "Fingers2.L": (0, 40, 0), "Thumb.L": (0, 20, 0)}, RELAXED_L, a, "L"))
    chin = V((0.02, -0.175, 0.905 - 0.022 * (0.5 + 0.5 * stroke)))
    rest = V((0.17, -0.06, 0.42))
    p["_hands"] = {"L": (rest.lerp(chin, a), V((0.45, -0.1, -1.0)))}
    p["Hand.L"] = (-10 * a, 0, 18 * a)
    return p


def clip_celebrate(t, T):
    """Delighted: rises on the toes, cane lifted in a quick salute, free fist pumps."""
    u = t / T
    a = smooth(0.0, 0.2, u) * (1 - smooth(0.75, 1.0, u))
    hop = 0.025 * max(0.0, math.sin(math.pi * clamp((u - 0.15) / 0.35))) + 0.015 * max(0.0, math.sin(math.pi * clamp((u - 0.5) / 0.25)))
    p = mix(stoop(1 - a), CANE_HAND, FIST_L, {
        "Hips": ((0, 0, 0), (0, 0, -0.006 + hop)), "Chest": (-8 * a, 0, 0), "Head": (-12 * a, 0, 0),
        "UpperArm.R": (-145 * a, 0, 14 * a), "LowerArm.R": (-30 * a, 0, 0),
        "UpperArm.L": (-40 * a, 0, -10 * a), "LowerArm.L": (-100 * a - 15 * math.sin(2 * math.pi * 3 * u) * a, 0, 0),
    })
    feet = planted()
    for s in feet:
        xy, h, pitch, piv = feet[s]
        feet[s] = (xy, 0.0, 30 * hop / 0.025, "ball")
    p["_feet"] = feet
    p["_hide"] = ["CaneArm"]
    return p


def clip_ardah(t, T):
    """Win dance (ardah): the cane held high, a measured side-step, the body swaying to a
    slow drum (two beats per side), proud chest and smiling face. Loops (T = 3.2)."""
    phi = t / T
    beat = math.cos(4 * math.pi * phi)            # two dips per side
    sway = math.sin(2 * math.pi * phi)            # side to side
    raise_ = 0.5 + 0.5 * math.cos(4 * math.pi * (phi - 0.1))
    p = mix(CANE_HAND, FIST_L, {
        "Hips": ((0, 4 * sway, 0), (0.025 * sway, 0, -0.022 + 0.012 * beat)),
        "Spine": (-3, -3 * sway, 0), "Chest": (-5, -3 * sway, 4 * sway), "Neck": (2, 0, 0),
        "Head": (-8, 3 * sway, -6 * sway),
        "UpperArm.R": (-150 - 8 * raise_, 0, 16), "LowerArm.R": (-18 - 12 * raise_, 0, 0), "Hand.R": (-8 * raise_, 0, 0),
        "UpperArm.L": (-28, -36, 0), "LowerArm.L": (-55, 0, 0), "Hand.L": (0, -10, 0),
        "Skirt.L": (0, -6 * sway, 0), "Skirt.R": (0, -6 * sway, 0), "Skirt.F": (-4 * beat, 0, 0),
        "Shemagh.B2": (6 * beat, 0, 0), "Shemagh.L2": (0, 0, 5 * sway), "Shemagh.R2": (0, 0, 5 * sway),
    })
    # Side step: the leading foot steps out on the downbeat, the other closes.
    off = 0.045 * sway
    feet = {}
    for s, sg in (("L", 1), ("R", -1)):
        lift_phase = math.sin(2 * math.pi * phi) * sg
        h = 0.03 * max(0.0, math.sin(4 * math.pi * phi + (0 if sg > 0 else math.pi))) * 0.6
        feet[s] = (V((ANKLE[s].x + off + 0.015 * sg * lift_phase, ANKLE[s].y)), h, 0.0, None)
    p["_feet"] = feet
    p["_hide"] = ["CaneArm"]
    return p


def clip_reject(t, T):
    """Not this way: a short head shake, the free hand waves a gentle no."""
    u = t / T
    a = smooth(0.0, 0.2, u) * (1 - smooth(0.7, 1.0, u))
    shake = math.sin(2 * math.pi * 2.5 * u) * a
    p = mix(stand(t), {"Head": (4 * a, 0, 16 * shake), "Neck": (0, 0, 5 * shake), "Chest": (0, 0, 2 * shake)})
    p["_hands"] = {"L": (V((0.14, -0.06, 0.44)).lerp(V((0.13 + 0.04 * shake, -0.22, 0.74)), a), V((0.6, 0.0, -1.0)))}
    p = mix(p, {"Hand.L": (-60 * a, 0, 0), "Fingers1.L": (0, -18 * a, 0), "Fingers2.L": (0, -20 * a, 0)})
    p["_hands"] = {"L": (V((0.14, -0.06, 0.44)).lerp(V((0.13 + 0.04 * shake, -0.22, 0.74)), a), V((0.6, 0.0, -1.0)))}
    return p


def clip_interact(t, T):
    """Reaches out with the left hand to pull a lever or press a switch."""
    u = t / T
    a = smooth(0.0, 0.45, u) * (1 - smooth(0.7, 1.0, u))
    p = mix(stand(t), {"Spine": (6 * a, 0, 0), "Head": (6 * a, 0, 0), "Hand.L": (-20 * a, 0, 0)},
            blend_hands(GRAB_L, RELAXED_L, smooth(0.35, 0.5, u) * (1 - smooth(0.7, 0.85, u)), "L"))
    p["_hands"] = {"L": (V((0.14, -0.06, 0.44)).lerp(V((0.05, -0.34, 0.62)), a), V((0.7, 0.1, -1.0)))}
    return p


def clip_excited(t, T):
    """Near the solution: rubs the hands together (cane hooked on the forearm), bounces."""
    u = t / T
    a = smooth(0.0, 0.15, u) * (1 - smooth(0.85, 1.0, u))
    rub = math.sin(2 * math.pi * 4 * u) * a
    p = mix(stoop(), breathe(t), GRAB_L, GRAB_R, {"Hips": ((0, 0, 0), (0, 0, -0.006 + 0.008 * abs(math.sin(2 * math.pi * 2 * u)) * a)),
                                                  "Head": (-6 * a, 0, 0)})
    c = V((0.0, -0.18, 0.66))
    p["_hands"] = {"L": (c + V((0.035 + 0.012 * rub, 0, 0.01 * rub)), V((0.9, 0.3, -0.4))),
                   "R": (c + V((-0.035 + 0.012 * rub, 0, -0.01 * rub)), V((-0.9, 0.3, -0.4)))}
    p["_feet"] = planted()
    p["_hide"] = ["Cane"]
    return p


def clip_tired(t, T):
    """After the stairs: leans on the cane, other hand on the lower back, heavy breaths."""
    u = t / T
    a = smooth(0.0, 0.2, u) * (1 - smooth(0.8, 1.0, u))
    p = mix(stand(t), breathe(t, period=T / 3, k=2.6 * a), {"Spine": (8 * a, 0, 0), "Chest": (6 * a, 0, 0), "Head": (-6 * a, 0, 0),
                                                            "Hips": ((0, 0, 0), (0, 0.01 * a, -0.012 * a))})
    p["_hands"] = {"L": (V((0.14, -0.06, 0.44)).lerp(V((0.09, 0.11, 0.56)), a), V((0.9, 0.0, 0.3)))}
    p["Hand.L"] = (0, 0, -70 * a)
    p["_cane"] = ("ground", CANE_TIP_REST.copy() + V((0.02, -0.03, 0)) * a)
    return p


CLIPS = [
    # name, seconds, function, loop
    ("idle", 4.8, clip_idle, True),
    ("idle_look", 3.0, clip_idle_look, False),
    ("walk", 0.9, clip_walk, True),
    ("turn", 0.6, clip_turn, True),
    ("push", 1.0, clip_push, True),
    ("pickup", 0.8, clip_pickup, False),
    ("pickup_small", 0.9, clip_pickup_small, False),
    ("carry", 0.9, clip_carry, True),
    ("carry_idle", 3.2, clip_carry_idle, True),
    ("place", 0.9, clip_place, False),
    ("stairs_up", 0.9, clip_stairs(True), True),
    ("stairs_down", 0.9, clip_stairs(False), True),
    ("think", 2.6, clip_think, False),
    ("celebrate", 1.4, clip_celebrate, False),
    ("ardah", 3.2, clip_ardah, True),
    ("reject", 0.9, clip_reject, False),
    ("interact", 0.7, clip_interact, False),
    ("excited", 1.6, clip_excited, False),
    ("tired", 2.4, clip_tired, False),
]


def build_actions(arm, set_pose, only=None):
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        for m in o.modifiers:
            m.show_viewport = False
    arm.animation_data_create()
    for name, seconds, fn, loop in CLIPS:
        if only and name not in only:
            continue
        bake(arm, name, seconds, fn, loop, set_pose)
        print("clip", name)
    for o in meshes:
        for m in o.modifiers:
            m.show_viewport = True
    arm.animation_data.action = bpy.data.actions.get("idle")
