#!/usr/bin/env python3
"""Genere les 19 modeles 3D des pets (Parts arrondies) pour Roblox.

Sorties :
  src/ReplicatedStorage/Pets/<Nom>.rbxmx   un Model par pet (dossier ReplicatedStorage.Pets)
  src/ReplicatedStorage/Shared/PetRigs.lua  pivots d'articulation et type de deplacement par pet
  assets/pets3d_preview.png                 apercu rendu de tous les pets (controle visuel)

Conventions : le pet regarde vers -Z, Y vers le haut, le sol est a Y = 0.
Nom des parts : "<Groupe>.<role>". Groupe = articulation animee (Body, Head, EarL, EarR, LegFL,
LegFR, LegBL, LegBR, Tail, WingL, WingR, Fx). Role : base (recolore par les evolutions),
accent, eye, detail, glow (neon).
Usage : python3 tools/build_pets3d.py
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "src", "ReplicatedStorage", "Pets")
RIGS = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "PetRigs.lua")
PREVIEW = os.path.join(ROOT, "assets", "pets3d_preview.png")

# ------------------------------------------------------------------ maths
def Rx(a):
    a = math.radians(a); c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def Ry(a):
    a = math.radians(a); c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def Rz(a):
    a = math.radians(a); c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
def rot(x=0, y=0, z=0):
    return Rx(x) @ Ry(y) @ Rz(z)
I3 = np.eye(3)

def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

BLACK = hexc("1b1626"); WHITE = hexc("ffffff"); PINK = hexc("ff9db8"); NOSE = hexc("3b2a2e")
GOLD = hexc("ffc93c"); GOLD2 = hexc("e8a317"); RED = hexc("e8333d")

# ------------------------------------------------------------------ primitives
class Pet:
    def __init__(self, name):
        self.name = name
        self.parts = []
        self.pivots = {}
        self.kind = "quad"
        self.hover = 0
        self.parents = {}

    def add(self, kind, name, c, s, col, R=I3, mat="SmoothPlastic", tr=0.0):
        self.parts.append(dict(kind=kind, name=name, c=np.array(c, float), s=np.array(s, float), R=np.array(R, float), col=col, mat=mat, tr=tr))

    def ell(self, name, c, s, col, R=I3, **k):
        self.add("ell", name, c, s, col, R, **k)
    def box(self, name, c, s, col, R=I3, **k):
        self.add("box", name, c, s, col, R, **k)
    def cyl(self, name, c, length, diam, col, R=I3, **k):
        # cylindre le long de l'axe X local
        self.add("cyl", name, c, (length, diam, diam), col, R, **k)
    def mirror(self, name_l, name_r, kind, c, s, col, R=I3, **k):
        """Ajoute une piece et son symetrique en X (R miroir)."""
        self.add(kind, name_l, c, s, col, R, **k)
        M = np.diag([-1, 1, 1])
        self.add(kind, name_r, (-c[0], c[1], c[2]), s, col, M @ R @ M, **k)


def surface_front(hc, hs, x, y):
    """Point sur la face avant (-Z) d'un ellipsoide (centre hc, taille hs) et normale."""
    a, b, c = hs[0] / 2, hs[1] / 2, hs[2] / 2
    dx, dy = x - hc[0], y - hc[1]
    k = max(0.0, 1 - (dx / a) ** 2 - (dy / b) ** 2)
    dz = -c * math.sqrt(k)
    n = np.array([dx / a ** 2, dy / b ** 2, dz / c ** 2])
    n /= np.linalg.norm(n)
    return np.array([x, y, hc[2] + dz]), n

def facing(n):
    """Rotation qui tourne l'axe -Z local vers la normale n."""
    th = math.degrees(math.atan2(-n[0], -n[2]))
    ph = math.degrees(math.asin(max(-1, min(1, n[1]))))
    return Ry(th) @ Rx(ph)

def on_face(p, group, role, hc, hs, x, y, s, col, depth=0.4, **k):
    pt, n = surface_front(hc, hs, x, y)
    center = pt - n * (s[2] * depth)
    p.ell(f"{group}.{role}", center, s, col, facing(n), **k)
    return pt, n

def eyes(p, hc, hs, spread, y, size=(0.62, 0.8, 0.34), iris=None, group="Head", lids=None):
    for sx in (-1, 1):
        x = hc[0] + sx * spread
        pt, n = surface_front(hc, hs, x, y)
        R = facing(n)
        base = pt - n * (size[2] * 0.42)
        if iris:
            p.ell(f"{group}.eye", base + n * 0.02, size, iris, R)
            p.ell(f"{group}.eye", base + n * 0.05 + R @ np.array([0, -0.05, 0]), (size[0] * 0.72, size[1] * 0.72, size[2]), BLACK, R)
        else:
            p.ell(f"{group}.eye", base, size, BLACK, R)
        # reflets brillants
        p.ell(f"{group}.eye", pt + R @ np.array([-0.11 * size[0] / 0.62, 0.17 * size[1] / 0.8, -0.1]), (size[0] * 0.38, size[0] * 0.38, 0.1), WHITE, R, mat="Neon")
        p.ell(f"{group}.eye", pt + R @ np.array([0.13 * size[0] / 0.62, -0.17 * size[1] / 0.8, -0.1]), (size[0] * 0.17, size[0] * 0.17, 0.08), WHITE, R, mat="Neon")
        if lids:
            p.ell(f"{group}.accent", base + R @ np.array([0, size[1] * 0.28, -0.01]), (size[0] * 1.08, size[1] * 0.45, size[2] * 1.05), lids, R)

def blush(p, hc, hs, spread, y, group="Head"):
    for sx in (-1, 1):
        on_face(p, group, "detail", hc, hs, hc[0] + sx * spread, y, (0.42, 0.22, 0.12), PINK, depth=0.2, tr=0.25)

def snout(p, hc, hs, y, col, size=(0.95, 0.62, 0.55), nose_col=NOSE, nose=(0.3, 0.2, 0.2), mouth=True, tongue=False, group="Head"):
    pt, n = on_face(p, group, "accent", hc, hs, hc[0], y, size, col, depth=0.25)
    R = facing(n)
    top = pt + n * size[2] * 0.42 + R @ np.array([0, size[1] * 0.28, 0])
    p.ell(f"{group}.detail", top, nose, nose_col, R)
    if mouth:
        for sx in (-1, 1):
            p.ell(f"{group}.detail", top + R @ np.array([sx * 0.09, -0.2, 0.02]), (0.16, 0.06, 0.06), nose_col, R @ Rz(sx * 35))
    if tongue:
        p.ell(f"{group}.detail", top + R @ np.array([0.02, -0.32, 0.0]), (0.22, 0.26, 0.1), hexc("ff6f8e"), R)

# ------------------------------------------------------------------ gabarits
HC = (0, 2.55, -0.42)          # centre de tete standard
HS = (2.35, 2.05, 1.95)        # taille de tete standard
BC = (0, 1.15, 0.32)           # centre du corps
BS = (1.65, 1.45, 1.95)

def quad_body(p, fur, belly, leg=None, paw=None, body_s=BS, legs_len=0.85, belly_s=(1.1, 1.0, 1.0), leg_w=0.56):
    leg = leg or fur
    paw = paw or mix(fur, WHITE, 0.25)
    p.ell("Body.base", BC, body_s, fur)
    if belly:
        p.ell("Body.accent", (0, 1.05, BC[2] - body_s[2] * 0.33), belly_s, belly)
    ly = legs_len / 2
    for name, x, z in (("LegFL", 0.5, -0.32), ("LegFR", -0.5, -0.32), ("LegBL", 0.52, 0.86), ("LegBR", -0.52, 0.86)):
        p.ell(f"{name}.base", (x, ly + 0.1, z), (leg_w, legs_len + 0.15, leg_w + 0.05), leg)
        p.ell(f"{name}.accent", (x, 0.18, z - 0.06), (leg_w + 0.06, 0.34, leg_w + 0.2), paw)
        p.pivots[name] = (x, legs_len + 0.15, z)
    p.pivots["Body"] = (0, 1.0, 0.3)
    p.pivots["Head"] = (0, 1.85, -0.35)
    p.pivots["Tail"] = (0, 1.25, 1.2)

def head(p, fur, hs=HS, hc=HC):
    p.ell("Head.base", hc, hs, fur)

def cat_ears(p, fur, inner=PINK, tip=None, size=(0.78, 1.0, 0.36), y=3.38, x=0.68, tilt=22):
    for side, name in ((1, "EarL"), (-1, "EarR")):
        R = Rz(-side * tilt)
        c = np.array([side * x, y, -0.36])
        p.ell(f"{name}.base", c, size, fur, R)
        p.ell(f"{name}.detail", c + np.array([0, -0.05, -0.12]), (size[0] * 0.55, size[1] * 0.68, size[2] * 0.6), inner, R)
        if tip:
            p.ell(f"{name}.accent", c + R @ np.array([0, size[1] * 0.36, 0]), (size[0] * 0.5, size[1] * 0.3, size[2] * 1.05), tip, R)
        p.pivots[name] = (side * x * 0.8, y - size[1] * 0.4, -0.36)
        p.parents[name] = "Head"

def round_ears(p, fur, inner=None, x=0.82, y=3.32, size=0.72):
    for side, name in ((1, "EarL"), (-1, "EarR")):
        c = (side * x, y, -0.32)
        p.ell(f"{name}.base", c, (size, size, size * 0.5), fur)
        if inner:
            p.ell(f"{name}.detail", (side * x, y - 0.03, -0.46), (size * 0.55, size * 0.55, 0.15), inner)
        p.pivots[name] = (side * x * 0.8, y - size * 0.35, -0.32)
        p.parents[name] = "Head"

def tail_chain(p, segs, col, tip_col=None, name="Tail"):
    """segs : liste de (centre, taille)."""
    for i, (c, s) in enumerate(segs):
        last = i == len(segs) - 1
        p.ell(f"{name}.{'accent' if last and tip_col else 'base'}", c, s, tip_col if (last and tip_col) else col)

# ------------------------------------------------------------------ les 19 pets
PETS = []

def pet(fn):
    PETS.append(fn)
    return fn

@pet
def Chaton():
    p = Pet("Chaton"); fur = hexc("ff9a3c"); cream = hexc("ffe1b8"); stripe = hexc("e06a1b")
    quad_body(p, fur, cream, paw=cream)
    head(p, fur)
    for y, w in ((3.42, 0.5), (3.28, 0.42)):
        p.ell("Head.detail", (0, y, -0.85), (0.18, w, 0.3), stripe, Rx(-35))
    for sx in (-1, 1):
        for k in range(2):
            p.ell("Head.detail", (sx * 1.1, 2.75 - k * 0.32, -0.4), (0.12, 0.08, 0.6), stripe, Rz(sx * 10))
    for z in (0.15, 0.55):
        p.ell("Body.detail", (0, 1.82, z), (1.0, 0.16, 0.22), stripe)
    cat_ears(p, fur)
    eyes(p, HC, HS, 0.47, 2.72, iris=hexc("8a4b12"))
    snout(p, HC, HS, 2.27, cream, size=(0.85, 0.55, 0.5), nose_col=hexc("ff7b93"))
    blush(p, HC, HS, 0.82, 2.32)
    for sx in (-1, 1):  # moustaches
        for k in (0, 1):
            p.ell("Head.detail", (sx * 0.95, 2.3 - k * 0.12, -1.25), (0.55, 0.03, 0.03), WHITE, Rz(sx * (8 - k * 16)))
    tail_chain(p, [((0, 1.45, 1.3), (0.42, 0.42, 0.7)), ((0, 1.95, 1.55), (0.4, 0.75, 0.4)), ((0, 2.45, 1.45), (0.42, 0.55, 0.42))], fur, stripe)
    return p

@pet
def Chiot():
    p = Pet("Chiot"); fur = hexc("d39a5e"); light = hexc("f6dcb4"); dark = hexc("8c5a2b")
    quad_body(p, fur, light, paw=light)
    head(p, fur)
    p.ell("Head.accent", (0.35, 2.85, -1.1), (0.75, 0.75, 0.4), light)
    for side, name in ((1, "EarL"), (-1, "EarR")):
        R = Rz(side * 18) @ Rx(-10)
        p.ell(f"{name}.base", (side * 1.12, 2.55, -0.35), (0.62, 1.35, 0.42), dark, R)
        p.pivots[name] = (side * 0.95, 3.1, -0.35); p.parents[name] = "Head"
    eyes(p, HC, HS, 0.47, 2.72, iris=hexc("5a3210"))
    snout(p, HC, HS, 2.22, light, size=(1.0, 0.65, 0.58), tongue=True)
    blush(p, HC, HS, 0.85, 2.3)
    # collier rouge + medaille
    p.cyl("Body.detail", (0, 1.85, -0.38), 0.24, 1.55, RED, Rz(90) @ Rx(15))
    p.cyl("Body.detail", (0, 1.62, -1.0), 0.08, 0.32, GOLD, Ry(90))
    tail_chain(p, [((0, 1.55, 1.3), (0.35, 0.35, 0.6)), ((0, 1.95, 1.48), (0.34, 0.6, 0.34))], fur, light)
    return p

@pet
def Lapin():
    p = Pet("Lapin"); fur = hexc("f7f4f7"); inner = hexc("ffb3c7")
    quad_body(p, fur, hexc("ffffff"), legs_len=0.7, paw=hexc("ffffff"))
    head(p, fur)
    for side, name in ((1, "EarL"), (-1, "EarR")):
        R = Rz(-side * 10)
        c = np.array([side * 0.45, 4.15, -0.35])
        p.ell(f"{name}.base", c, (0.62, 2.0, 0.38), fur, R)
        p.ell(f"{name}.detail", c + np.array([0, -0.05, -0.12]), (0.36, 1.55, 0.2), inner, R)
        p.pivots[name] = (side * 0.4, 3.3, -0.35); p.parents[name] = "Head"
    eyes(p, HC, HS, 0.47, 2.72, iris=hexc("7a2f45"))
    snout(p, HC, HS, 2.25, hexc("ffffff"), size=(0.82, 0.52, 0.48), nose_col=hexc("ff7b93"))
    blush(p, HC, HS, 0.82, 2.33)
    p.ell("Tail.base", (0, 1.25, 1.35), (0.75, 0.75, 0.75), hexc("ffffff"))
    return p

@pet
def Renard():
    p = Pet("Renard"); fur = hexc("ff6a1f"); white = hexc("fff4e8"); dark = hexc("3a2318")
    quad_body(p, fur, white, leg=dark, paw=dark)
    head(p, fur)
    for sx in (-1, 1):
        on_face(p, "Head", "accent", HC, HS, sx * 0.55, 2.25, (0.95, 0.75, 0.5), white, depth=0.3)
    cat_ears(p, fur, inner=white, tip=dark, size=(0.9, 1.25, 0.38), y=3.5, x=0.72, tilt=18)
    eyes(p, HC, HS, 0.48, 2.75, iris=hexc("7b3a0c"))
    snout(p, HC, HS, 2.2, white, size=(0.85, 0.55, 0.6))
    blush(p, HC, HS, 0.84, 2.3)
    tail_chain(p, [((0, 1.5, 1.4), (0.85, 0.85, 1.1)), ((0, 2.25, 1.75), (1.0, 1.25, 1.0)), ((0, 2.95, 1.75), (0.75, 0.75, 0.75))], fur, white)
    return p

@pet
def Hibou():
    p = Pet("Hibou"); p.kind = "fly"; p.hover = 1.4
    brown = hexc("8b5a32"); light = hexc("e6c8a0"); face = hexc("f3e3c6")
    c = (0, 1.9, 0.1); s = (2.6, 3.2, 2.4)
    p.ell("Body.base", c, s, brown)
    p.ell("Body.accent", (0, 1.45, -0.62), (1.8, 2.0, 1.2), light)
    for (x, y) in ((0, 1.8), (-0.35, 1.3), (0.35, 1.3), (0, 0.85), (-0.45, 1.85), (0.45, 1.85)):
        pt, n = surface_front((0, 1.45, -0.62), (1.8, 2.0, 1.2), x, y)
        p.ell("Body.detail", pt - n * 0.05, (0.3, 0.18, 0.08), brown, facing(n) @ Rz(0))
    hc = (0, 2.55, 0.05); hs = (2.6, 2.4, 2.4)
    for sx in (-1, 1):
        on_face(p, "Body", "accent", hc, hs, sx * 0.55, 2.6, (1.25, 1.35, 0.5), face, depth=0.3)
    eyes(p, hc, (hs[0] + 0.5, hs[1] + 0.3, hs[2] + 0.75), 0.55, 2.62, size=(0.82, 0.92, 0.36), iris=hexc("ffb21c"), group="Body")
    pt, n = surface_front(hc, hs, 0, 2.2)
    p.ell("Body.detail", pt + n * 0.1, (0.3, 0.42, 0.35), hexc("ff9e1b"), facing(n) @ Rx(-20))
    for side, name in ((1, "EarL"), (-1, "EarR")):
        p.ell(f"{name}.base", (side * 0.85, 3.55, -0.1), (0.42, 0.85, 0.35), brown, Rz(-side * 25))
        p.pivots[name] = (side * 0.75, 3.2, -0.1); p.parents[name] = "Body"
    for side, name in ((1, "WingL"), (-1, "WingR")):
        p.ell(f"{name}.base", (side * 1.35, 1.75, 0.25), (0.55, 2.0, 1.55), brown, Rz(side * 12))
        p.ell(f"{name}.accent", (side * 1.45, 1.35, 0.25), (0.45, 1.0, 1.2), hexc("6d4223"), Rz(side * 12))
        p.pivots[name] = (side * 1.1, 2.4, 0.25)
    for sx in (-1, 1):
        p.ell("Body.detail", (sx * 0.45, 0.32, -0.25), (0.45, 0.25, 0.6), hexc("ff9e1b"))
    p.pivots["Body"] = (0, 1.5, 0.1)
    p.pivots["Head"] = (0, 2.0, 0.1)
    return p

@pet
def Licorne():
    p = Pet("Licorne"); fur = hexc("fdf3f8"); mane = hexc("ff5fb7"); mane2 = hexc("ff9ad5")
    quad_body(p, fur, None, leg=fur, paw=GOLD, legs_len=1.05, body_s=(1.6, 1.4, 2.05))
    for k in p.parts:
        if k["name"].endswith(".accent") and k["name"].startswith("Leg"):
            k["mat"] = "SmoothPlastic"
    head(p, fur, hs=(2.2, 2.05, 2.05))
    hs = (2.2, 2.05, 2.05)
    snout(p, HC, hs, 2.15, hexc("ffe6f2"), size=(1.15, 0.75, 0.7), nose_col=hexc("e58fb4"), mouth=True)
    eyes(p, HC, hs, 0.5, 2.75, iris=hexc("8c3dff"), lids=None)
    blush(p, HC, hs, 0.82, 2.35)
    # corne doree en spirale
    for i in range(5):
        p.ell("Head.glow" if i == 4 else "Head.detail", (0, 3.62 + i * 0.22, -0.95 - i * 0.05), (0.42 - i * 0.07, 0.36, 0.42 - i * 0.07), GOLD if i % 2 == 0 else GOLD2, Rx(-15))
    p.ell("Head.detail", (0, 3.55, -0.78), (0.55, 0.3, 0.4), GOLD)
    cat_ears(p, fur, inner=PINK, size=(0.55, 0.8, 0.3), y=3.45, x=0.62, tilt=15)
    # criniere
    for i, (x, y, z, s) in enumerate(((0.55, 3.35, -0.1, 0.85), (0.75, 2.95, 0.25, 0.95), (0.75, 2.45, 0.45, 0.9), (0.65, 2.0, 0.55, 0.8), (-0.55, 3.35, -0.1, 0.85), (-0.75, 2.95, 0.25, 0.95), (-0.75, 2.45, 0.45, 0.9), (-0.65, 2.0, 0.55, 0.8), (0, 3.5, 0.05, 0.9))):
        p.ell("Head.accent", (x, y, z), (s, s, s), mane if i % 2 == 0 else mane2)
    p.ell("Head.accent", (0, 3.2, -1.05), (0.7, 0.55, 0.45), mane2)
    tail_chain(p, [((0, 1.55, 1.35), (0.7, 0.7, 0.8)), ((0, 1.25, 1.75), (0.8, 1.0, 0.8)), ((0, 0.8, 1.85), (0.7, 0.8, 0.7))], mane, mane2)
    for x, z in ((0.82, 0.5), (0.78, 0.85)):
        p.ell("Body.glow", (x, 1.35, z), (0.1, 0.24, 0.24), GOLD, mat="Neon")
    return p

@pet
def Cerf():
    p = Pet("Cerf"); fur = hexc("b5703a"); light = hexc("f3dcbd"); dark = hexc("5b3519")
    quad_body(p, fur, light, paw=dark, legs_len=1.0)
    for x, y, z in ((0.55, 1.5, 0.2), (0.7, 1.2, 0.6), (0.5, 1.65, 0.75), (-0.55, 1.5, 0.2), (-0.7, 1.2, 0.6), (-0.5, 1.65, 0.75), (0.2, 1.85, 0.45), (-0.25, 1.85, 0.1)):
        p.ell("Body.detail", (x, y, z), (0.2, 0.2, 0.2), WHITE)
    head(p, fur)
    for side, name in ((1, "EarL"), (-1, "EarR")):
        R = Rz(-side * 60)
        p.ell(f"{name}.base", (side * 1.25, 3.05, -0.35), (0.55, 1.0, 0.32), fur, R)
        p.ell(f"{name}.detail", (side * 1.25, 3.05, -0.47), (0.32, 0.65, 0.15), PINK, R)
        p.pivots[name] = (side * 1.0, 2.95, -0.35); p.parents[name] = "Head"
    antler = hexc("8a5a2c")
    for sx in (-1, 1):
        p.cyl("Head.detail", (sx * 0.5, 3.75, -0.3), 0.75, 0.2, antler, Rz(90 - sx * 25))
        p.cyl("Head.detail", (sx * 0.72, 4.15, -0.3), 0.5, 0.17, antler, Rz(90 + sx * 30))
        p.cyl("Head.detail", (sx * 0.85, 3.95, -0.3), 0.45, 0.15, antler, Rz(sx * 15))
        p.ell("Head.detail", (sx * 0.62, 4.38, -0.3), (0.2, 0.2, 0.2), antler)
    eyes(p, HC, HS, 0.48, 2.72, iris=hexc("4a2508"))
    snout(p, HC, HS, 2.2, light, size=(0.9, 0.6, 0.55))
    blush(p, HC, HS, 0.84, 2.3)
    p.ell("Tail.base", (0, 1.65, 1.35), (0.45, 0.55, 0.4), fur, Rx(-30))
    p.ell("Tail.accent", (0, 1.55, 1.48), (0.35, 0.4, 0.3), WHITE, Rx(-30))
    return p

@pet
def Loup():
    p = Pet("Loup"); fur = hexc("8a8d9c"); white = hexc("eef0f5"); dark = hexc("5b5e6e")
    quad_body(p, fur, white, paw=white)
    head(p, fur)
    for sx in (-1, 1):
        on_face(p, "Head", "accent", HC, HS, sx * 0.5, 2.25, (0.9, 0.75, 0.5), white, depth=0.3)
    cat_ears(p, fur, inner=white, tip=dark, size=(0.85, 1.15, 0.38), y=3.48, x=0.72, tilt=15)
    eyes(p, HC, HS, 0.48, 2.75, iris=hexc("3fa2ff"))
    snout(p, HC, HS, 2.2, white, size=(0.95, 0.6, 0.62))
    blush(p, HC, HS, 0.84, 2.3)
    p.ell("Body.accent", (0, 1.85, -0.55), (1.45, 0.75, 0.7), white)
    tail_chain(p, [((0, 1.5, 1.4), (0.75, 0.75, 1.0)), ((0, 2.15, 1.7), (0.9, 1.15, 0.9)), ((0, 2.8, 1.72), (0.65, 0.65, 0.65))], fur, white)
    return p

@pet
def Ours():
    p = Pet("Ours"); fur = hexc("7a4a2a"); light = hexc("d2a074")
    quad_body(p, fur, light, body_s=(1.95, 1.65, 2.05), belly_s=(1.3, 1.15, 1.1), leg_w=0.68)
    hs = (2.45, 2.15, 2.0)
    head(p, fur, hs=hs)
    round_ears(p, fur, inner=light)
    eyes(p, HC, hs, 0.5, 2.78, iris=hexc("3f8fe0"))
    snout(p, HC, hs, 2.25, light, size=(1.05, 0.75, 0.6))
    blush(p, HC, hs, 0.88, 2.35)
    p.ell("Tail.base", (0, 1.15, 1.35), (0.5, 0.5, 0.5), fur)
    return p

@pet
def Panda():
    p = Pet("Panda"); white = hexc("f7f5f2"); black = hexc("22202a")
    quad_body(p, white, None, leg=black, paw=black, body_s=(1.95, 1.65, 2.05), leg_w=0.68)
    p.cyl("Body.accent", (0, 1.55, 0.05), 1.1, 1.85, black, Rz(0) @ Ry(90))
    hs = (2.45, 2.15, 2.0)
    head(p, white, hs=hs)
    round_ears(p, black)
    for sx in (-1, 1):
        on_face(p, "Head", "detail", HC, hs, sx * 0.52, 2.72, (0.85, 1.0, 0.4), black, depth=0.3)
    eyes(p, HC, hs, 0.52, 2.78, size=(0.58, 0.72, 0.34), iris=hexc("3d8bff"))
    snout(p, HC, hs, 2.22, white, size=(0.95, 0.65, 0.55), nose_col=black)
    blush(p, HC, hs, 0.92, 2.3)
    p.ell("Tail.base", (0, 1.15, 1.35), (0.45, 0.45, 0.45), white)
    return p

@pet
def Phenix():
    p = Pet("Phenix"); p.kind = "fly"; p.hover = 1.8
    red = hexc("ff3d1f"); orange = hexc("ff8a1c"); yellow = hexc("ffd23a")
    p.ell("Body.base", (0, 1.55, 0.25), (1.5, 1.8, 1.9), red, Rx(-15))
    p.ell("Body.accent", (0, 1.35, -0.35), (1.0, 1.3, 0.9), yellow)
    hc = (0, 2.75, -0.35); hs = (1.9, 1.8, 1.8)
    p.ell("Head.base", hc, hs, orange)
    eyes(p, hc, hs, 0.42, 2.85, size=(0.55, 0.7, 0.3), iris=hexc("8a2b00"))
    pt, n = surface_front(hc, hs, 0, 2.5)
    p.ell("Head.detail", pt + n * 0.15, (0.35, 0.3, 0.55), hexc("ffc341"), facing(n) @ Rx(-25))
    blush(p, hc, hs, 0.68, 2.5)
    for i, (x, y, z, a) in enumerate(((0, 3.75, -0.2, 0), (0.3, 3.65, 0.05, -20), (-0.3, 3.65, 0.05, 20), (0, 3.6, 0.35, 0))):
        p.ell("Head.glow", (x, y, z), (0.35, 0.95, 0.35), yellow if i % 2 else orange, Rz(a) @ Rx(-25), mat="Neon")
    for side, name in ((1, "WingL"), (-1, "WingR")):
        sh = np.array([side * 0.62, 1.95, 0.35])
        for k, (length, col) in enumerate(((1.9, red), (1.7, orange), (1.45, yellow), (1.15, hexc("fff08a")))):
            R = Rz(-side * (35 + k * 22)) @ Rx(18)
            glow = k >= 2
            p.ell(f"{name}.{'glow' if glow else 'base'}", sh + R @ np.array([0, length / 2, 0]), (0.5, length, 0.28), col, R, mat="Neon" if glow else "SmoothPlastic")
        p.pivots[name] = tuple(sh)
    for k in range(5):
        a2 = (k - 2) * 18
        R = Ry(a2) @ Rx(115)
        col = (red, orange, yellow, orange, red)[k]
        base = np.array([0, 1.05, 1.0])
        p.ell("Tail.glow" if k in (1, 2, 3) else "Tail.base", base + R @ np.array([0, 0.85, 0]), (0.35, 1.7, 0.22), col, R, mat="Neon" if k == 2 else "SmoothPlastic")
    for sx in (-1, 1):
        p.ell("Body.detail", (sx * 0.35, 0.45, -0.1), (0.3, 0.45, 0.3), hexc("ffb12b"))
    p.pivots["Body"] = (0, 1.5, 0.2); p.pivots["Head"] = (0, 2.1, -0.2); p.pivots["Tail"] = (0, 1.2, 1.0)
    return p

@pet
def Dragon():
    p = Pet("Dragon"); p.kind = "fly"; p.hover = 1.2
    green = hexc("36c24a"); belly = hexc("f2e27a"); dark = hexc("1f8a33"); horn = hexc("f0c060")
    quad_body(p, green, None, paw=dark, body_s=(1.75, 1.55, 2.0))
    for i in range(4):
        y = 1.55 - i * 0.27
        pt, n = surface_front(BC, (1.75, 1.55, 2.0), 0, y)
        p.ell("Body.accent", pt - n * 0.08, (0.95 - i * 0.08, 0.26, 0.22), belly, facing(n))
    hs = (2.3, 2.0, 2.05)
    head(p, green, hs=hs)
    snout(p, HC, hs, 2.2, hexc("5fdb6a"), size=(1.2, 0.75, 0.75), nose_col=dark)
    eyes(p, HC, hs, 0.5, 2.8, iris=hexc("ffcf1a"))
    blush(p, HC, hs, 0.85, 2.35)
    for sx in (-1, 1):
        p.ell("Head.detail", (sx * 0.55, 3.55, 0.0), (0.32, 0.9, 0.32), horn, Rz(-sx * 20) @ Rx(30))
    for i in range(4):
        p.ell("Body.detail", (0, 3.3 - i * 0.55 if i == 0 else 2.05 - (i - 1) * 0.05, 0.25 + i * 0.35 if i else 0.5), (0.18, 0.5, 0.35), dark)
    for side, name in ((1, "WingL"), (-1, "WingR")):
        sh = np.array([side * 0.65, 1.95, 0.6])
        R = Rz(-side * 50) @ Rx(25)
        p.ell(f"{name}.accent", sh + R @ np.array([0, 0.85, 0.35]), (0.14, 1.6, 1.25), hexc("b6f06a"), R)
        p.cyl(f"{name}.base", sh + R @ np.array([0, 0.85, -0.2]), 1.7, 0.2, dark, R @ Rz(90))
        p.ell(f"{name}.base", sh + R @ np.array([0, 1.7, -0.2]), (0.28, 0.28, 0.28), dark)
        p.pivots[name] = tuple(sh)
    tail_chain(p, [((0, 1.0, 1.35), (0.7, 0.65, 0.9)), ((0, 0.75, 1.9), (0.5, 0.48, 0.8)), ((0, 0.75, 2.35), (0.38, 0.36, 0.6))], green)
    p.ell("Tail.detail", (0, 0.85, 2.7), (0.6, 0.45, 0.2), dark, Rx(-20))
    return p

@pet
def Scorpion():
    p = Pet("Scorpion"); p.kind = "crawl"
    brown = hexc("6e3b1f"); light = hexc("a8643a"); dark = hexc("3e2012")
    p.ell("Body.base", (0, 0.85, 0.35), (1.7, 0.9, 2.0), brown)
    hc = (0, 1.2, -0.75); hs = (1.9, 1.5, 1.6)
    p.ell("Head.base", hc, hs, brown)
    eyes(p, hc, hs, 0.42, 1.38, size=(0.55, 0.65, 0.3), iris=hexc("4a2410"))
    blush(p, hc, hs, 0.72, 0.98)
    for i in range(3):
        p.ell("Body.detail", (0, 1.22, -0.2 + i * 0.5), (1.25 - i * 0.15, 0.15, 0.3), light)
    for side in (1, -1):
        legs = "LegFL" if side == 1 else "LegFR"
        legs2 = "LegBL" if side == 1 else "LegBR"
        for k in range(3):
            g = legs if k < 2 else legs2
            p.cyl(f"{g}.base", (side * 1.05, 0.55, -0.1 + k * 0.5), 0.9, 0.18, dark, Rz(side * -35) @ Ry(side * (k - 1) * 20))
        p.pivots[legs] = (side * 0.7, 0.75, 0.15); p.pivots[legs2] = (side * 0.7, 0.75, 0.9)
        # pinces
        p.cyl(f"Head.base", (side * 0.95, 0.85, -1.55), 0.8, 0.28, brown, Ry(side * 50))
        p.ell("Head.accent", (side * 1.25, 0.95, -2.05), (0.75, 0.55, 0.85), light)
        p.ell("Head.accent", (side * 1.05, 0.95, -2.45), (0.22, 0.35, 0.6), light, Ry(side * 20))
        p.ell("Head.accent", (side * 1.45, 0.95, -2.45), (0.22, 0.35, 0.6), light, Ry(-side * 20))
    segs = [((0, 1.15, 1.45), 0.62), ((0, 1.7, 1.75), 0.58), ((0, 2.3, 1.7), 0.55), ((0, 2.8, 1.35), 0.5), ((0, 3.0, 0.85), 0.45)]
    for c, s in segs:
        p.ell("Tail.base", c, (s, s, s), brown)
    p.ell("Tail.accent", (0, 2.85, 0.45), (0.3, 0.55, 0.3), hexc("ffb347"), Rx(-60))
    p.pivots["Tail"] = (0, 1.0, 1.25); p.pivots["Body"] = (0, 0.8, 0.3); p.pivots["Head"] = (0, 1.0, -0.4)
    return p

@pet
def Chameau():
    p = Pet("Chameau"); fur = hexc("e3b26e"); light = hexc("f6dcad"); dark = hexc("9a6a34")
    quad_body(p, fur, None, paw=dark, legs_len=1.25, body_s=(1.7, 1.45, 2.3))
    for z in (-0.05, 0.75):
        p.ell("Body.base", (0, 2.05, z), (1.05, 1.0, 0.9), fur)
    p.box("Body.detail", (0, 1.9, 0.35), (1.85, 0.12, 0.7), RED)
    for sx in (-1, 1):
        p.box("Body.detail", (sx * 0.92, 1.45, 0.35), (0.1, 0.9, 0.7), RED)
        for k in range(3):
            p.ell("Body.glow", (sx * 0.98, 1.0, 0.1 + k * 0.25), (0.12, 0.28, 0.12), GOLD, mat="Neon")
    hs = (2.0, 1.9, 2.1); hc = (0, 3.05, -0.9)
    p.ell("Head.base", (0, 2.3, -0.6), (0.8, 1.4, 0.8), fur, Rx(25))
    p.ell("Head.base", hc, hs, fur)
    snout(p, hc, hs, 2.78, light, size=(1.15, 0.8, 0.8), nose_col=dark)
    eyes(p, hc, hs, 0.45, 3.32, size=(0.55, 0.7, 0.3), iris=hexc("5a3210"), lids=fur)
    blush(p, hc, hs, 0.75, 2.85)
    for side, name in ((1, "EarL"), (-1, "EarR")):
        p.ell(f"{name}.base", (side * 0.8, 3.85, -0.7), (0.35, 0.5, 0.25), fur, Rz(-side * 30))
        p.pivots[name] = (side * 0.7, 3.7, -0.7); p.parents[name] = "Head"
    p.pivots["Head"] = (0, 1.9, -0.5)
    p.ell("Tail.base", (0, 1.4, 1.5), (0.22, 0.75, 0.22), dark, Rx(25))
    return p

@pet
def Cobra():
    p = Pet("Cobra"); p.kind = "slither"
    green = hexc("2fae4e"); belly = hexc("f3e48a"); dark = hexc("1d7a35")
    for i in range(14):
        a = i / 14 * math.pi * 2
        r = 1.05
        p.ell("Body.base", (math.cos(a) * r, 0.45 + i * 0.012, math.sin(a) * r + 0.4), (0.9, 0.85, 0.9), green if i % 3 else dark)
    for i in range(10):
        a = i / 10 * math.pi * 2
        p.ell("Body.base", (math.cos(a) * 0.6, 1.1, math.sin(a) * 0.6 + 0.4), (0.75, 0.7, 0.75), green)
    for i, y in enumerate((1.6, 2.1, 2.6, 3.05)):
        p.ell("Head.base", (0, y, 0.15 - i * 0.12), (0.8, 0.75, 0.8), green)
        p.ell("Head.accent", (0, y, -0.18 - i * 0.12), (0.5, 0.6, 0.3), belly)
    p.ell("Head.accent", (0, 3.15, 0.1), (2.0, 1.7, 0.4), dark, Rx(-10))
    p.ell("Head.base", (0, 3.15, 0.0), (1.75, 1.45, 0.45), green, Rx(-10))
    hc = (0, 3.75, -0.35); hs = (1.6, 1.3, 1.55)
    p.ell("Head.base", hc, hs, green)
    eyes(p, hc, hs, 0.38, 3.88, size=(0.5, 0.6, 0.28), iris=hexc("ffd21f"))
    blush(p, hc, hs, 0.58, 3.55)
    pt, n = surface_front(hc, hs, 0, 3.45)
    p.ell("Head.detail", pt - n * 0.02 + np.array([0, -0.12, -0.12]), (0.08, 0.3, 0.08), hexc("ff3b5c"))
    p.pivots["Head"] = (0, 1.4, 0.2); p.pivots["Body"] = (0, 0.5, 0.4)
    return p

@pet
def Lezard():
    p = Pet("Lezard"); green = hexc("8fe05a"); belly = hexc("e5f7a0"); spot = hexc("4fb83a")
    quad_body(p, green, belly, paw=hexc("6fcb45"), legs_len=0.6, body_s=(1.6, 1.25, 2.2), leg_w=0.6)
    for x, z in ((0.45, 0.1), (-0.4, 0.55), (0.3, 0.85), (-0.2, 0.0)):
        p.ell("Body.detail", (x, 1.72, z), (0.32, 0.12, 0.32), spot)
    hs = (2.3, 1.85, 2.1)
    head(p, green, hs=hs, hc=(0, 2.35, -0.5))
    hc = (0, 2.35, -0.5)
    eyes(p, hc, hs, 0.52, 2.62, iris=hexc("3a9a1a"))
    blush(p, hc, hs, 0.85, 2.15)
    pt, n = surface_front(hc, hs, 0, 2.0)
    for sx in (-1, 1):
        p.ell("Head.detail", pt + facing(n) @ np.array([sx * 0.12, 0, 0]), (0.18, 0.05, 0.05), hexc("2a6a1a"), facing(n) @ Rz(sx * 25))
    for side, name in ((1, "WingL"), (-1, "WingR")):
        p.ell(f"{name}.accent", (side * 0.95, 2.05, 0.3), (0.12, 1.0, 1.1), hexc("c7f59a"), Rz(side * 40), tr=0.15)
        p.pivots[name] = (side * 0.65, 1.7, 0.3)
    for i in range(3):
        p.ell("Body.detail", (0, 1.8, -0.1 + i * 0.4), (0.12, 0.4, 0.3), spot)
    tail_chain(p, [((0, 0.85, 1.45), (0.75, 0.7, 1.0)), ((0.25, 0.6, 2.1), (0.55, 0.5, 0.9)), ((0.55, 0.5, 2.6), (0.4, 0.38, 0.7))], green)
    return p

@pet
def Sphinx():
    p = Pet("Sphinx"); gold = hexc("f1b53f"); light = hexc("ffdc8a"); blue = hexc("2b56c9")
    quad_body(p, gold, light, paw=light)
    head(p, gold)
    # coiffe nemes rayee
    for i in range(7):
        y = 3.55 - i * 0.28
        for sx in (-1, 1):
            p.ell("Head.accent", (sx * (1.08 + i * 0.03), y, -0.2), (0.4, 0.32, 1.4), GOLD if i % 2 == 0 else blue)
    for i in range(5):
        p.ell("Head.accent", (0, 3.55 - 0.02 * i, -0.15 + i * 0.25), (2.25 - i * 0.05, 0.5, 0.35), GOLD if i % 2 == 0 else blue)
    p.ell("Head.glow", (0, 3.55, -0.98), (0.32, 0.42, 0.25), hexc("2fb6ff"), mat="Neon")
    p.ell("Head.detail", (0, 3.55, -0.92), (0.5, 0.6, 0.2), GOLD)
    eyes(p, HC, HS, 0.47, 2.72, iris=hexc("1f6e3a"))
    snout(p, HC, HS, 2.25, light, size=(0.85, 0.55, 0.5), nose_col=hexc("a85a2a"))
    blush(p, HC, HS, 0.82, 2.32)
    p.cyl("Body.detail", (0, 1.85, -0.42), 0.3, 1.6, GOLD, Rz(90) @ Rx(15))
    for sx in (-0.35, 0, 0.35):
        p.ell("Body.glow", (sx, 1.6, -1.05), (0.18, 0.22, 0.12), hexc("2fb6ff"), mat="Neon")
    tail_chain(p, [((0, 1.4, 1.35), (0.35, 0.35, 0.7)), ((0, 1.85, 1.6), (0.32, 0.65, 0.32)), ((0, 2.3, 1.55), (0.45, 0.45, 0.45))], gold, hexc("8a5a20"))
    return p

@pet
def Genie():
    p = Pet("Genie"); p.kind = "float"; p.hover = 1.2
    blue = hexc("3d7dff"); light = hexc("7fb2ff"); dark = hexc("1d3f9e")
    p.ell("Body.base", (0, 1.9, 0.15), (1.9, 1.6, 1.4), blue)
    p.ell("Body.base", (0, 2.45, 0.15), (1.5, 0.8, 1.2), blue)
    for k, (y, z, s) in enumerate(((1.1, 0.25, 1.2), (0.6, 0.45, 0.85), (0.25, 0.75, 0.55), (0.12, 1.1, 0.35))):
        p.ell("Tail.base", (0.1 * k, y, z), (s, s * 1.1, s), blue if k < 2 else light)
    for sx in (-1, 1):  # bras croises
        p.ell("Body.base", (sx * 0.85, 2.2, 0.0), (0.6, 0.75, 0.6), blue)
        p.ell("Body.base", (sx * 0.2, 1.85, -0.6), (1.2, 0.48, 0.5), blue, Rz(sx * 12))
        p.cyl("Body.detail", (sx * 0.62, 1.88, -0.62), 0.25, 0.55, GOLD, Ry(0))
    hc = (0, 3.45, -0.1); hs = (1.85, 1.9, 1.75)
    p.ell("Head.base", hc, hs, blue)
    eyes(p, hc, hs, 0.42, 3.55, size=(0.52, 0.66, 0.3), iris=hexc("1a2a6e"))
    blush(p, hc, hs, 0.7, 3.2)
    pt, n = surface_front(hc, hs, 0, 3.08)
    p.ell("Head.detail", pt - n * 0.03, (0.45, 0.1, 0.08), dark, facing(n))
    for sx in (-1, 1):
        p.ell("Head.base", (sx * 1.0, 3.55, -0.1), (0.25, 0.7, 0.35), blue, Rz(-sx * 55))
        p.ell("Head.glow", (sx * 0.95, 3.15, -0.15), (0.18, 0.25, 0.18), GOLD, mat="Neon")
    p.ell("Head.detail", (0, 4.45, 0.05), (0.75, 0.55, 0.75), BLACK)
    p.ell("Head.detail", (0, 4.85, 0.1), (0.4, 0.55, 0.4), BLACK)
    p.cyl("Head.detail", (0, 4.6, 0.07), 0.15, 0.55, GOLD, Rz(90))
    p.pivots["Head"] = (0, 2.7, 0); p.pivots["Body"] = (0, 1.8, 0.1); p.pivots["Tail"] = (0, 1.4, 0.2)
    return p

@pet
def Pharaon():
    p = Pet("Pharaon"); gold = hexc("ffb43a"); light = hexc("ffe0a0"); stripe = hexc("e8862a")
    quad_body(p, gold, light, paw=light)
    head(p, gold)
    for y, w in ((3.35, 0.45),):
        p.ell("Head.detail", (0, y, -0.85), (0.16, w, 0.3), stripe, Rx(-35))
    cat_ears(p, gold, size=(0.75, 0.95, 0.34))
    # couronne
    p.cyl("Head.glow", (0, 3.55, -0.35), 0.4, 1.7, GOLD, Rz(90), mat="SmoothPlastic")
    for k in range(5):
        a = math.radians(-60 + k * 30)
        x, z = math.sin(a) * 0.8, -0.35 - math.cos(a) * 0.8
        p.ell("Head.glow", (x, 4.0, z), (0.3, 0.6, 0.3), GOLD)
        p.ell("Head.glow", (x, 4.38, z), (0.2, 0.2, 0.2), hexc("ff3b8d") if k % 2 else hexc("37c6ff"), mat="Neon")
    p.ell("Head.glow", (0, 3.6, -1.17), (0.36, 0.45, 0.2), hexc("b23bff"), mat="Neon")
    eyes(p, HC, HS, 0.47, 2.72, iris=hexc("2a9a4a"))
    snout(p, HC, HS, 2.27, light, size=(0.85, 0.55, 0.5), nose_col=hexc("ff7b93"))
    blush(p, HC, HS, 0.82, 2.32)
    # collier joaillerie
    p.cyl("Body.detail", (0, 1.85, -0.42), 0.32, 1.65, hexc("ff4d6d"), Rz(90) @ Rx(15))
    for sx in (-0.45, 0, 0.45):
        p.ell("Body.glow", (sx, 1.62, -1.07), (0.2, 0.26, 0.14), GOLD if sx else hexc("b23bff"), mat="Neon" if sx == 0 else "SmoothPlastic")
    tail_chain(p, [((0, 1.45, 1.3), (0.42, 0.42, 0.7)), ((0, 1.95, 1.55), (0.4, 0.75, 0.4)), ((0, 2.45, 1.45), (0.42, 0.55, 0.42))], gold, stripe)
    return p

# ------------------------------------------------------------------ rendu d'apercu
MAT_NEON = "Neon"

def render(pet, size=260, cam=(4.2, 3.9, -9.2), look=(0, 2.2, 0.2)):
    cam = np.array(cam, float); look = np.array(look, float)
    fwd = look - cam; fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    fov = math.tan(math.radians(19))
    ys, xs = np.mgrid[0:size, 0:size]
    u = (xs / size - 0.5) * 2 * fov
    v = -(ys / size - 0.5) * 2 * fov
    dirs = fwd[None, None, :] + u[..., None] * right + v[..., None] * up
    dirs /= np.linalg.norm(dirs, axis=2, keepdims=True)
    D = dirs.reshape(-1, 3); N = D.shape[0]
    depth = np.full(N, np.inf); color = np.zeros((N, 3)); hitn = np.zeros((N, 3)); neon = np.zeros(N, bool)
    trans = []
    for pr in pet.parts:
        R = pr["R"]; c = pr["c"]; s = pr["s"] / 2
        o = (cam - c) @ R  # R^T (cam - c)
        d = D @ R
        if pr["kind"] == "ell":
            oo = o / s; dd = d / s
            a = (dd * dd).sum(1); b = 2 * (dd @ oo); cc = oo @ oo - 1
            disc = b * b - 4 * a * cc
            ok = disc > 0
            t = np.where(ok, (-b - np.sqrt(np.maximum(disc, 0))) / (2 * a), np.inf)
            t = np.where(t > 0, t, np.inf)
            p = o[None, :] + d * t[:, None]
            nl = p / (s * s)
        elif pr["kind"] == "box":
            with np.errstate(divide="ignore", invalid="ignore"):
                t1 = (-s - o) / d; t2 = (s - o) / d
            tmin = np.nanmax(np.minimum(t1, t2), axis=1); tmax = np.nanmin(np.maximum(t1, t2), axis=1)
            ok = (tmax >= tmin) & (tmax > 0)
            t = np.where(ok, np.where(tmin > 0, tmin, tmax), np.inf)
            p = o[None, :] + d * np.where(np.isfinite(t), t, 0)[:, None]
            q = np.abs(p) / s
            nl = np.zeros_like(p); idx = np.argmax(q, axis=1)
            nl[np.arange(N), idx] = np.sign(p[np.arange(N), idx])
        else:
            r = min(s[1], s[2]); hl = s[0]
            oy, oz = o[1], o[2]; dy, dz = d[:, 1], d[:, 2]
            a = dy * dy + dz * dz; b = 2 * (oy * dy + oz * dz); cc = oy * oy + oz * oz - r * r
            disc = b * b - 4 * a * cc
            with np.errstate(divide="ignore", invalid="ignore"):
                tc = np.where(disc > 0, (-b - np.sqrt(np.maximum(disc, 0))) / (2 * a), np.inf)
                xc = o[0] + d[:, 0] * tc
                tc = np.where((tc > 0) & (np.abs(xc) <= hl), tc, np.inf)
                tcap = np.where(o[0] > 0, (hl - o[0]) / d[:, 0], (-hl - o[0]) / d[:, 0])
                pc = o[None, :] + d * tcap[:, None]
                tcap = np.where((tcap > 0) & (pc[:, 1] ** 2 + pc[:, 2] ** 2 <= r * r), tcap, np.inf)
            t = np.minimum(tc, tcap)
            p = o[None, :] + d * np.where(np.isfinite(t), t, 0)[:, None]
            nl = np.where((tcap <= tc)[:, None], np.array([1, 0, 0]) * np.sign(p[:, :1]), np.stack([np.zeros(N), p[:, 1], p[:, 2]], 1))
        nl = np.nan_to_num(nl, nan=0.0, posinf=0.0, neginf=0.0)
        nw = nl @ R.T
        nw /= np.maximum(np.linalg.norm(nw, axis=1, keepdims=True), 1e-9)
        col = np.array(pr["col"], float) / 255
        if pr["tr"] > 0:
            trans.append((t, col, pr["tr"]))
            continue
        closer = t < depth
        depth = np.where(closer, t, depth)
        color[closer] = col; hitn[closer] = nw[closer]; neon[closer] = pr["mat"] == MAT_NEON
    L = np.array([-0.45, 0.8, -0.55]); L /= np.linalg.norm(L)
    lam = np.clip(hitn @ L, 0, 1)
    view = -D
    h = (L + view); h /= np.linalg.norm(h, axis=1, keepdims=True)
    spec = np.clip((hitn * h).sum(1), 0, 1) ** 40 * 0.35
    rim = np.clip(1 - np.abs((hitn * view).sum(1)), 0, 1) ** 3 * 0.25
    shade = color * (0.5 + 0.6 * lam[:, None]) + spec[:, None] + rim[:, None]
    shade = np.where(neon[:, None], np.minimum(color * 1.15 + 0.1, 1), shade)
    for t, col, tr in trans:
        m = t < depth
        shade[m] = shade[m] * tr + col * (1 - tr)
    bg = np.array([0.42, 0.62, 0.95])
    img = np.where(np.isfinite(depth)[:, None], np.clip(shade, 0, 1), bg)
    return Image.fromarray((img.reshape(size, size, 3) * 255).astype(np.uint8))

# ------------------------------------------------------------------ export Roblox
MATERIALS = {"SmoothPlastic": 272, "Neon": 288, "Glass": 1568}

def f(v):
    return f"{v:.4f}".rstrip("0").rstrip(".") if "." in f"{v:.4f}" else f"{v}"

def part_xml(pr, ref, extra_ref):
    c, s, R = pr["c"], pr["s"], pr["R"]
    r, g, b = pr["col"]
    color = (0xFF << 24) | (r << 16) | (g << 8) | b
    shape = 1 if pr["kind"] != "cyl" else 2
    cf = "".join(f"<{k}>{f(v)}</{k}>" for k, v in zip(["X", "Y", "Z"], c))
    cf += "".join(f"<R{i}{j}>{f(R[i][j])}</R{i}{j}>" for i in range(3) for j in range(3))
    sz = "".join(f"<{k}>{f(v)}</{k}>" for k, v in zip(["X", "Y", "Z"], s))
    mesh = ""
    if pr["kind"] == "ell":
        mesh = (f'<Item class="SpecialMesh" referent="{extra_ref}"><Properties>'
                f'<string name="Name">Mesh</string><token name="MeshType">3</token>'
                f'<Vector3 name="Scale"><X>1</X><Y>1</Y><Z>1</Z></Vector3></Properties></Item>')
    return (f'<Item class="Part" referent="{ref}"><Properties>'
            f'<string name="Name">{pr["name"]}</string>'
            f'<bool name="Anchored">true</bool><bool name="CanCollide">false</bool>'
            f'<bool name="CanQuery">false</bool><bool name="CanTouch">false</bool><bool name="Massless">true</bool>'
            f'<CoordinateFrame name="CFrame">{cf}</CoordinateFrame>'
            f'<Vector3 name="size">{sz}</Vector3>'
            f'<Color3uint8 name="Color3uint8">{color}</Color3uint8>'
            f'<token name="Material">{MATERIALS.get(pr["mat"], 272)}</token>'
            f'<token name="shape">{shape}</token>'
            f'<float name="Transparency">{f(pr["tr"])}</float>'
            f'<token name="TopSurface">0</token><token name="BottomSurface">0</token>'
            f'</Properties>{mesh}</Item>')

def export(pet):
    items = []
    for i, pr in enumerate(pet.parts):
        items.append(part_xml(pr, f"RBXPET{pet.name.upper()}{i:03d}", f"RBXPET{pet.name.upper()}M{i:03d}"))
    body = "".join(items)
    xml = (f'<roblox version="4"><Item class="Model" referent="RBXPET{pet.name.upper()}"><Properties>'
           f'<string name="Name">{pet.name}</string></Properties>{body}</Item></roblox>\n')
    with open(os.path.join(OUT_DIR, pet.name + ".rbxmx"), "w") as fh:
        fh.write(xml)

def lua_vec(v):
    return f"Vector3.new({f(v[0])}, {f(v[1])}, {f(v[2])})"

def write_rigs(pets):
    lines = ["-- GENERE AUTOMATIQUEMENT par tools/build_pets3d.py : articulations des modeles 3D des pets.",
             "-- kind : quad (4 pattes), fly (vole), float (flotte), slither (rampe), crawl (insecte).", "", "return {"]
    for p in pets:
        lines.append(f"\t{p.name} = {{")
        lines.append(f'\t\tkind = "{p.kind}",')
        lines.append(f"\t\thover = {f(p.hover)},")
        lines.append("\t\tpivots = {")
        for k, v in p.pivots.items():
            lines.append(f"\t\t\t{k} = {lua_vec(v)},")
        lines.append("\t\t},")
        lines.append("\t\tparents = {")
        for k, v in p.parents.items():
            lines.append(f'\t\t\t{k} = "{v}",')
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    with open(RIGS, "w") as fh:
        fh.write("\n".join(lines) + "\n")

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    pets = [fn() for fn in PETS]
    sheet = Image.new("RGB", (7 * 260, 3 * 290), (40, 50, 90))
    d = ImageDraw.Draw(sheet)
    layout = [6, 6, 7]
    k = 0
    for row, n in enumerate(layout):
        for col in range(n):
            pt = pets[k]
            sheet.paste(render(pt), (col * 260, row * 290))
            d.text((col * 260 + 8, row * 290 + 264), f"{pt.name}  ({len(pt.parts)} parts)", fill=(255, 255, 255))
            export(pt)
            k += 1
    sheet.save(PREVIEW)
    write_rigs(pets)
    total = sum(len(p.parts) for p in pets)
    print(f"{len(pets)} pets, {total} parts au total -> {PREVIEW}")

if __name__ == "__main__":
    main()
