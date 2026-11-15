#!/usr/bin/env python3
"""Les 19 pets sculptes (maillages organiques continus, visages detailles, couleurs peintes).

Conventions identiques aux anciens modeles : le pet regarde -Z, sol a Y = 0, hauteur ~4.2 studs.
Chaque piece = "<Groupe>.<role>" : Groupe = articulation animee, role = base (teinte par les
evolutions) / detail (non teinte : nez, griffes, bijoux) / eye (yeux, cligne) / glow (neon).
"""
import math
import os
import sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sculpt import *  # noqa

BLACK = hexc("1b1626"); WHITE = hexc("ffffff"); PINK = hexc("ff9db8"); NOSE = hexc("3b2a2e")
GOLD = hexc("ffc93c"); GOLD2 = hexc("d99412"); RED = hexc("e8333d"); MOUTH = hexc("5a2430")

class Pet:
    def __init__(self, name, kind="quad", hover=0.0):
        self.name = name; self.kind = kind; self.hover = hover
        self.parts = {}      # "Group.role" -> Group sculpte
        self.pivots = {}; self.parents = {}
        self.glow = set()
    def g(self, key, step=0.055, rough=None, seed=0):
        if key not in self.parts:
            self.parts[key] = Group(key, step, rough, seed)
        return self.parts[key]

def surf(hc, hr, x, y):
    """Point de la face avant (-Z) d'un ellipsoide de centre hc / rayons hr, et sa normale."""
    hc = np.asarray(hc, float); hr = np.asarray(hr, float)
    u = (x - hc[0]) / hr[0]; v = (y - hc[1]) / hr[1]
    w = math.sqrt(max(1 - u * u - v * v, 0.02))
    p = np.array([x, y, hc[2] - hr[2] * w])
    n = (p - hc) / (hr * hr); n /= np.linalg.norm(n)
    return p, n

# ------------------------------------------------------------------ visage
def eye(pet, hc, hr, x, y, size=(0.36, 0.44, 0.2), iris=hexc("b0640f"), iris2=None, pupil="round",
        sink=0.55, lash=True, lid=None, group="Head", brow=None, brow_col=None, tilt=0.0):
    """Oeil brillant : globe sombre, iris en degrade, pupille, anneau, 2 reflets en relief, cils, sourcil."""
    p, n = surf(hc, hr, x, y)
    n = n * np.array([1, 1, 1]); n /= np.linalg.norm(n)
    R = frame(n) @ Rz(tilt)
    w, h, d = size
    c = p - n * d * sink
    iris2 = iris2 if iris2 is not None else mixc(iris, WHITE, 0.55)
    dark = hexc("150f22")
    ge = pet.g(f"{group}.eye", step=0.034)
    ge.add(Ellipsoid(c, (w, h, d), R), dark, k=0)

    def paint(P, col, c=c, R=R, w=w, h=h):
        q = (P - c) @ R
        u = q[:, 0] / w; v = q[:, 1] / h
        # iris (moitie basse, degrade du haut sombre vers le bas lumineux)
        ri = np.sqrt((u / 0.78) ** 2 + ((v + 0.18) / 0.74) ** 2)
        t = np.clip((v + 0.9) / 1.3, 0, 1)
        ic = mixc(iris2[None, :], iris[None, :] * 0.75, t[:, None])
        a = 1 - smoothstep(0.92, 1.0, ri)
        col = col * (1 - a[:, None]) + ic * a[:, None]
        # anneau sombre de l'iris
        ring = smoothstep(0.8, 0.9, ri) * (1 - smoothstep(0.98, 1.04, ri))
        col = col * (1 - 0.7 * ring[:, None]) + dark * 0.7 * ring[:, None]
        # pupille
        if pupil == "slit":
            rp = np.sqrt((u / 0.26) ** 2 + ((v + 0.1) / 0.6) ** 2)
        elif pupil == "none":
            rp = np.full(len(u), 9.0)
        else:
            rp = np.sqrt((u / 0.36) ** 2 + ((v + 0.12) / 0.42) ** 2)
        pa = 1 - smoothstep(0.85, 1.0, rp)
        col = col * (1 - pa[:, None]) + dark * pa[:, None]
        # lueur basse (reflet de l'iris)
        gl = (1 - smoothstep(0.0, 1.0, np.sqrt((u / 0.5) ** 2 + ((v + 0.62) / 0.16) ** 2))) * 0.6
        col = col * (1 - gl[:, None]) + mixc(iris2, WHITE, 0.6)[None, :] * gl[:, None]
        return col
    ge.pattern(paint)
    # reflets (geometrie : nets meme de pres)
    for (ox, oy, rw, rh) in ((-0.34, 0.4, 0.3, 0.26), (0.36, -0.36, 0.13, 0.11)):
        q = c + R @ np.array([ox * w, oy * h, 0])
        # pose le reflet sur la surface avant de l'oeil
        zz = -d * math.sqrt(max(1 - ox * ox - oy * oy, 0.05))
        q = c + R @ np.array([ox * w, oy * h, zz * 0.92])
        ge.add(Ellipsoid(q, (rw * w, rh * h, 0.05), R), WHITE, k=0)
    gd = pet.g(f"{group}.detail", step=0.03)
    side = 1 if x > hc[0] else -1
    if lash:
        # trait de paupiere superieure + petit cil vers l'exterieur
        pts = []
        for a in np.linspace(0.18, 0.82, 6) * math.pi:
            lx, ly = math.cos(a) * w * 1.04, math.sin(a) * h * 1.02
            lz = -d * math.sqrt(max(1 - (lx / w) ** 2 * 0.9 - (ly / h) ** 2 * 0.9, 0.02)) + 0.01
            pts.append(c + R @ np.array([lx, ly, lz]))
        tube(gd, pts, [0.04, 0.05, 0.055, 0.055, 0.05, 0.04], BLACK, k=0.02)
        o = pts[0] if side > 0 else pts[-1]
        o2 = o + R @ np.array([side * 0.16, 0.08, 0.02])
        gd.add(RoundCone(o, o2, 0.045, 0.02), BLACK, k=0.02)
    if lid is not None:
        # paupiere de fourrure (regard doux / determine)
        gl = pet.g(f"{group}.base")
        gl.add(Ellipsoid(c + R @ np.array([0, h * 0.72, -d * 0.1]), (w * 1.12, h * 0.5, d * 1.1), R @ Rz(side * lid)), brow_col if brow_col is not None else WHITE, k=0.03)
    if brow is not None:
        bc = c + R @ np.array([side * w * 0.1, h * 1.45, -d * 0.55])
        a = bc + R @ np.array([-side * w * 0.55, -brow * h * 0.2, 0])
        b = bc + R @ np.array([side * w * 0.55, brow * h * 0.2, 0])
        pet.g(f"{group}.base").paint(RoundCone(a, b, 0.07, 0.045), brow_col, soft=0.03)
    return c, R

def cat_mouth(g, c, R, col=MOUTH, width=0.12, open_=0.0):
    """Bouche en 'w' creusee + peinte."""
    pts = [c + R @ np.array([x, y, 0]) for x, y in ((-2, 0.3), (-1, -0.35), (0, 0.15), (1, -0.35), (2, 0.3))]
    pts = [c + (q - c) * np.array([1, 1, 1]) for q in pts]
    pts = [c + R @ np.array([x * width / 2, y * width * 0.6, 0]) for x, y in ((-2, 0.4), (-1, -0.45), (0, 0.15), (1, -0.45), (2, 0.4))]
    for i in range(4):
        g.sub(Capsule(pts[i], pts[i + 1], 0.03), k=0.015)
        g.paint(Capsule(pts[i], pts[i + 1], 0.06), col, soft=0.02)
    if open_ > 0:
        m = c + R @ np.array([0, -width * 0.9, 0])
        g.sub(Ellipsoid(m, (width * 0.8, open_, 0.12), R), k=0.03)
        g.paint(Ellipsoid(m, (width * 0.85, open_ * 1.1, 0.2), R), col, soft=0.02)
        g.paint(Ellipsoid(m + R @ np.array([0, -open_ * 0.5, 0]), (width * 0.5, open_ * 0.6, 0.25), hexc("ff6f8e")), hexc("ff6f8e"), soft=0.02) if False else None

def tongue(pet, c, R, group="Head", length=0.14):
    pet.g(f"{group}.detail").add(Ellipsoid(c + R @ np.array([0, -length * 0.4, -0.02]), (0.11, length, 0.05), R), hexc("ff6f8e"), k=0)

def blush(g, hc, hr, x, y, col=hexc("ff8fb0"), size=0.24):
    for sx in (-1, 1):
        p, n = surf(hc, hr, hc[0] + sx * x, y)
        g.paint(Ellipsoid(p, (size, size * 0.6, size), frame(n)), col, soft=0.12)

def whiskers(pet, base, R, side, n=3, length=0.75, col=WHITE, group="Head"):
    gd = pet.g(f"{group}.detail", step=0.03)
    for i in range(n):
        a = base + R @ np.array([side * 0.05, 0.05 - i * 0.07, 0])
        b = a + R @ np.array([side * length, (0.12 - i * 0.12), 0.18])
        m = (a + b) / 2 + np.array([0, 0.05, 0])
        tube(gd, [a, m, b], [0.032, 0.025, 0.016], col, k=0.0)

# ------------------------------------------------------------------ morceaux de corps
def fluffy(g, c, r, col, n=7, amp=0.22, k=0.12, axis=(0, 0, -1), seed=0, spread=1.0):
    """Collerette / touffe de poils : couronne de petites meches pointues."""
    rng = np.random.RandomState(seed)
    c = np.asarray(c, float); ax = np.asarray(axis, float); ax /= np.linalg.norm(ax)
    R = frame(ax)
    for i in range(n):
        a = (i / max(n - 1, 1) - 0.5) * math.pi * spread
        d = R @ np.array([math.sin(a), -math.cos(a) * 0.9, -0.35])
        base = c + d * r * 0.55
        tip = c + d * (r + amp * (0.8 + 0.4 * rng.rand()))
        g.add(RoundCone(base, tip, r * 0.38, 0.03), col, k=k)

def cat_ear(pet, name, base, tip, w, fur, inner=PINK, tuft=None, tip_col=None, side=1):
    g = pet.g(f"{name}.base", step=0.045, rough=(0.003, 9), seed=3)
    base = np.asarray(base, float); tip = np.asarray(tip, float)
    ax = tip - base; L = np.linalg.norm(ax)
    up = ax / L
    R = frame((0, 0, -1), up)  # axe y local = vers la pointe, -z = devant
    flat = Xf(RoundCone((0, 0, 0), (0, L, 0), w, 0.06), base, R, (1, 1, 0.42))
    g.add(flat, fur, k=0)
    # creux interieur (face avant) + peinture rose
    inn = Xf(RoundCone((0, 0, 0), (0, L * 0.82, 0), w * 0.66, 0.03), base + R @ np.array([0, L * 0.1, -0.12]), R, (1, 1, 0.3))
    g.sub(inn, k=0.04)
    g.paint(Xf(RoundCone((0, 0, 0), (0, L * 0.8, 0), w * 0.72, 0.04), base + R @ np.array([0, L * 0.08, -0.1]), R, (1, 1, 0.6)), inner, soft=0.03)
    if tip_col is not None:
        g.paint(Ellipsoid(tip, (0.22, 0.28, 0.22)), tip_col, soft=0.08)
    if tuft is not None:
        # meches de poils dans l'oreille
        for k_, off in enumerate((-0.12, 0.0, 0.12)):
            a = base + R @ np.array([off, L * 0.05, -0.06])
            b = base + R @ np.array([off * 1.6, L * 0.48 + abs(off) * -0.8, -0.1])
            g.add(RoundCone(a, b, 0.08, 0.015), tuft, k=0.03)
    pet.pivots[name] = tuple(base + up * 0.1)
    pet.parents[name] = "Head"

def tabby(col, stripe, region, freq=7.0, width=0.28, seed=4, axis=1):
    """Rayures de chat tigre (bandes ondulees) limitees a une region (fonction P->poids)."""
    def fn(P, c):
        nz = noise3(P, 2.2, seed)
        s = np.sin(P[:, axis] * freq + nz * 4.0 + np.abs(P[:, 0]) * 1.5)
        m = smoothstep(1 - width * 2, 1 - width * 2 + 0.25, s) * region(P)
        return c * (1 - m[:, None]) + stripe[None, :] * m[:, None]
    return fn

def fur_tint(base_col, light_col, dark_col=None, top=0.08, seed=1, amount=0.05):
    return shading_variation(amount=amount, top=top, bottom=0.12, seed=seed)

# ------------------------------------------------------------------ pets (definis dans tools/sculpt_pets/*.py)
PETS = []
def pet(fn):
    PETS.append(fn); return fn

_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sculpt_pets")
for _f in sorted(os.listdir(_DIR)):
    if _f.endswith(".py"):
        exec(compile(open(os.path.join(_DIR, _f)).read(), os.path.join(_DIR, _f), "exec"), globals())
ORDER = ["Chaton", "Chiot", "Lapin", "Renard", "Hibou", "Licorne", "Cerf", "Loup", "Ours", "Panda", "Phenix",
         "Dragon", "Scorpion", "Chameau", "Cobra", "Lezard", "Sphinx", "Genie", "Pharaon"]
PETS.sort(key=lambda f: ORDER.index(f.__name__) if f.__name__ in ORDER else 99)

# ------------------------------------------------------------------ construction
def build(petfn):
    p = petfn()
    meshes = {}
    for key, g in p.parts.items():
        m = g.mesh()
        if m is not None:
            meshes[key] = m
    # retire les triangles caches a l'interieur de la piece de base du meme groupe (yeux, nez...)
    for key, m in list(meshes.items()):
        grp, role = key.split(".")
        base = p.parts.get(grp + ".base")
        if role == "base" or base is None:
            continue
        V, N, C, T = m
        inside = base.field(V.astype(float)) < -0.02
        T = T[~inside[T].all(1)]
        used = np.unique(T)
        remap = -np.ones(len(V), np.int64); remap[used] = np.arange(len(used))
        meshes[key] = (V[used], N[used], C[used], remap[T].astype(np.int32))
    # simplification : budget de triangles par piece, puis normales et couleurs exactes recalculees
    for key, m in list(meshes.items()):
        V, N, C, T = m
        tgt = budget(key, p)
        if len(T) > tgt * 1.1:
            V, C2, T = decimate(V, C, T, tgt)
            g = p.parts[key]
            Vd = V.astype(float)
            N = gradient(g, Vd); N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
            _, C = g.field(Vd, with_color=True)
            meshes[key] = (V.astype(np.float32), N.astype(np.float32), np.clip(C, 0, 1).astype(np.float32), T.astype(np.int32))
    return p, meshes

BUDGET = {"Head.base": 3400, "Head.eye": 5000, "Head.detail": 1500, "Body.base": 1800, "Tail.base": 700,
          "EarL.base": 550, "EarR.base": 550, "WingL.base": 900, "WingR.base": 900}
def budget(key, p):
    if key in getattr(p, "budget", {}):
        return p.budget[key]
    if key in BUDGET:
        return BUDGET[key]
    grp, role = key.split(".")
    if grp.startswith("Leg"):
        return 520 if role == "base" else 300
    return 900 if role == "base" else 700

if __name__ == "__main__":
    import time
    from meshview import render
    from PIL import Image
    names = sys.argv[1:] or [f.__name__ for f in PETS]
    for fn in PETS:
        if fn.__name__ not in names:
            continue
        t0 = time.time()
        p, meshes = build(fn)
        nt = sum(len(m[3]) for m in meshes.values()); nv = sum(len(m[0]) for m in meshes.values())
        print(p.name, f"{nv} sommets, {nt} triangles, {time.time()-t0:.1f}s")
        ms = list(meshes.values())
        ims = [render(ms, 420, yaw=y, pitch=-10) for y in (-28, 0, 70, 160)]
        out = Image.new("RGB", (420 * 4, 420), "white")
        for i, im in enumerate(ims):
            out.paste(im, (420 * i, 0))
        out.save(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sculpt", f"{p.name}.png"))
