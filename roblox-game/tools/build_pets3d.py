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

def eyes(p, hc, hs, spread, y, size=(0.82, 1.0, 0.38), iris=None, group="Head", lids=None, lash=False):
    """Grands yeux brillants style anime : fond noir, croissant colore en bas, deux reflets."""
    for sx in (-1, 1):
        x = hc[0] + sx * spread
        pt, n = surface_front(hc, hs, x, y)
        R = facing(n)
        w, h, d = size
        base = pt - n * (d * 0.42)
        p.ell(f"{group}.eye", base, size, BLACK, R)
        if iris:
            p.ell(f"{group}.eye", base + n * 0.03 + R @ np.array([0, -h * 0.13, 0]), (w * 0.66, h * 0.4, d * 0.92), iris, R)
            p.ell(f"{group}.eye", base + n * 0.045 + R @ np.array([0, -h * 0.2, 0]), (w * 0.4, h * 0.17, d * 0.92), mix(iris, WHITE, 0.45), R)
        p.ell(f"{group}.eye", pt + n * 0.02 + R @ np.array([w * 0.16, h * 0.18, 0]), (w * 0.42, w * 0.42, 0.1), WHITE, R, mat="Neon")
        p.ell(f"{group}.eye", pt + n * 0.02 + R @ np.array([-w * 0.2, -h * 0.02, 0]), (w * 0.17, w * 0.17, 0.08), WHITE, R, mat="Neon")
        if lash:
            p.ell(f"{group}.detail", pt + R @ np.array([sx * w * 0.52, h * 0.32, 0.02]), (w * 0.32, 0.09, 0.09), BLACK, R @ Rz(sx * 35))
        if lids:
            p.ell(f"{group}.accent", base + R @ np.array([0, h * 0.3, -0.01]), (w * 1.08, h * 0.42, d * 1.05), lids, R)

def blush(p, hc, hs, spread, y, group="Head"):
    for sx in (-1, 1):
        on_face(p, group, "detail", hc, hs, hc[0] + sx * spread, y, (0.5, 0.26, 0.12), hexc("ff8fb0"), depth=0.2, tr=0.2)

def snout(p, hc, hs, y, col, size=(0.82, 0.5, 0.46), nose_col=NOSE, nose=(0.28, 0.19, 0.2), mouth=True, tongue=False, group="Head"):
    pt, n = on_face(p, group, "accent", hc, hs, hc[0], y, size, col, depth=0.25)
    R = facing(n)
    top = pt + n * size[2] * 0.42 + R @ np.array([0, size[1] * 0.25, 0])
    p.ell(f"{group}.detail", top, nose, nose_col, R)
    p.ell(f"{group}.eye", top + R @ np.array([-0.05, 0.05, -0.08]), (0.09, 0.06, 0.05), WHITE, R, mat="Neon")
    if mouth:
        for sx in (-1, 1):
            p.ell(f"{group}.detail", top + R @ np.array([sx * 0.09, -0.19, 0.02]), (0.17, 0.06, 0.06), nose_col, R @ Rz(sx * 35))
    if tongue:
        p.ell(f"{group}.detail", top + R @ np.array([0.03, -0.32, 0.0]), (0.24, 0.28, 0.1), hexc("ff6f8e"), R)

def cheeks(p, col, hc, hs, y_off=-0.5, spread=1.05, size=(0.72, 0.58, 0.82), group="Head"):
    """Touffes de joues (fourrure) sur les cotes du bas de la tete, en partie dans la tete."""
    for sx in (-1, 1):
        x = hc[0] + sx * spread
        y = hc[1] + y_off
        pt, n = surface_front(hc, hs, x * 0.92, y)
        c = np.array([x, y, (pt[2] + hc[2]) / 2])
        p.ell(f"{group}.accent", c, (size[0] * 0.85, size[1], size[2] * 0.85), col, Rz(sx * 20))

# ------------------------------------------------------------------ gabarits
HC = (0, 2.95, -0.22)          # centre de tete (pets assis)
HS = (2.7, 2.35, 2.3)          # taille de tete
EYE_Y = 2.8
SNOUT_Y = 2.33
BLUSH_Y = 2.45
BC = (0, 1.3, 0.2)             # tronc assis
BS = (1.7, 1.95, 1.6)

def sit_body(p, fur, light=None, paw=None, front_leg=None, haunch=None):
    """Corps assis chibi : tronc, poitrail, cuisses rondes, pattes avant droites, gros pieds."""
    paw = paw or mix(fur, WHITE, 0.3)
    front_leg = front_leg or fur
    haunch = haunch or fur
    p.ell("Body.base", BC, BS, fur, Rx(-10))
    if light:
        pt, n = surface_front(BC, BS, 0, 1.4)
        p.ell("Body.accent", pt - n * 0.14, (1.05, 1.35, 0.5), light, facing(n))
    for side, back, front in ((1, "LegBL", "LegFL"), (-1, "LegBR", "LegFR")):
        p.ell(f"{back}.base", (side * 0.64, 0.72, 0.48), (1.05, 1.22, 1.45), haunch)
        p.ell(f"{back}.accent", (side * 0.7, 0.17, -0.12), (0.62, 0.34, 0.95), paw)
        p.pivots[back] = (side * 0.64, 1.0, 0.48)
        p.ell(f"{front}.base", (side * 0.42, 0.62, -0.46), (0.64, 1.02, 0.64), front_leg)
        p.ell(f"{front}.accent", (side * 0.42, 0.16, -0.62), (0.68, 0.34, 0.74), paw)
        for t in (-0.12, 0.12):
            p.ell(f"{front}.detail", (side * 0.42 + t, 0.2, -0.98), (0.04, 0.14, 0.04), mix(paw, BLACK, 0.45))
        p.pivots[front] = (side * 0.4, 1.18, -0.4)
    p.pivots["Body"] = (0, 0.9, 0.25)
    p.pivots["Head"] = (0, 2.0, -0.15)
    p.pivots["Tail"] = (0, 0.7, 1.05)

SHC = (0, 3.05, -0.85)         # tete des pets debout
SHS = (2.45, 2.2, 2.15)

def stand_body(p, fur, belly=None, leg=None, hoof=None, legs_len=1.05, body_s=(1.65, 1.45, 2.05)):
    leg = leg or fur
    hoof = hoof or mix(fur, BLACK, 0.45)
    bc = (0, 0.6 + legs_len, 0.3)
    p.ell("Body.base", bc, body_s, fur)
    if belly:
        p.ell("Body.accent", (0, bc[1] - 0.15, bc[2] - body_s[2] * 0.3), (1.05, 0.95, 0.95), belly)
    for name, x, z in (("LegFL", 0.48, -0.35), ("LegFR", -0.48, -0.35), ("LegBL", 0.5, 0.9), ("LegBR", -0.5, 0.9)):
        p.ell(f"{name}.base", (x, (legs_len + 0.25) / 2, z), (0.5, legs_len + 0.35, 0.52), leg)
        p.ell(f"{name}.accent", (x, 0.16, z - 0.04), (0.56, 0.32, 0.62), hoof)
        p.pivots[name] = (x, legs_len + 0.25, z)
    p.pivots["Body"] = (0, bc[1] - 0.2, 0.3)
    p.pivots["Head"] = (0, bc[1] + 0.55, -0.45)
    p.pivots["Tail"] = (0, bc[1] + 0.1, 1.25)
    return bc

def head(p, fur, hs=HS, hc=HC):
    p.ell("Head.base", hc, hs, fur)

def cat_ears(p, fur, inner=PINK, tip=None, size=(0.88, 1.08, 0.38), y=3.95, x=0.8, tilt=20, z=-0.25):
    for side, name in ((1, "EarL"), (-1, "EarR")):
        R = Rz(-side * tilt)
        c = np.array([side * x, y, z])
        p.ell(f"{name}.base", c, size, fur, R)
        p.ell(f"{name}.detail", c + np.array([0, -0.06, -0.13]), (size[0] * 0.55, size[1] * 0.66, size[2] * 0.6), inner, R)
        if tip:
            p.ell(f"{name}.accent", c + R @ np.array([0, size[1] * 0.36, 0]), (size[0] * 0.5, size[1] * 0.3, size[2] * 1.05), tip, R)
        p.pivots[name] = (side * x * 0.8, y - size[1] * 0.4, z)
        p.parents[name] = "Head"

def round_ears(p, fur, inner=None, x=0.98, y=3.85, size=0.82):
    for side, name in ((1, "EarL"), (-1, "EarR")):
        c = (side * x, y, -0.25)
        p.ell(f"{name}.base", c, (size, size, size * 0.5), fur)
        if inner:
            p.ell(f"{name}.detail", (side * x, y - 0.03, -0.42), (size * 0.55, size * 0.55, 0.15), inner)
        p.pivots[name] = (side * x * 0.8, y - size * 0.35, -0.25)
        p.parents[name] = "Head"

def tail_chain(p, segs, col, tip_col=None, name="Tail"):
    for i, (c, s) in enumerate(segs):
        last = i == len(segs) - 1
        p.ell(f"{name}.{'accent' if last and tip_col else 'base'}", c, s, tip_col if (last and tip_col) else col)

CAT_TAIL = [((0.15, 0.55, 1.25), (0.48, 0.48, 0.8)), ((0.3, 1.05, 1.55), (0.46, 0.9, 0.46)), ((0.25, 1.6, 1.5), (0.5, 0.62, 0.5))]
BUSHY_TAIL = [((0.25, 0.55, 1.25), (0.95, 0.85, 1.2)), ((0.55, 1.15, 1.55), (1.05, 1.25, 1.05)), ((0.6, 1.85, 1.5), (0.8, 0.8, 0.8))]

def whiskers(p, hc=HC, y=2.35):
    for sx in (-1, 1):
        for k in (0, 1):
            p.ell("Head.detail", (sx * 1.18, y - k * 0.13, hc[2] - 0.85), (0.6, 0.03, 0.03), WHITE, Rz(sx * (10 - k * 18)))

# ------------------------------------------------------------------ les 19 pets
PETS = []

def pet(fn):
    PETS.append(fn)
    return fn

@pet
def Chaton():
    p = Pet("Chaton"); fur = hexc("ff9a3c"); cream = hexc("ffe8c6"); stripe = hexc("e56c17")
    sit_body(p, fur, cream, paw=cream)
    head(p, fur)
    cheeks(p, cream, HC, HS)
    for x, w in ((0, 0.55), (-0.34, 0.42), (0.34, 0.42)):
        pt, n = surface_front(HC, HS, x, 3.75 - abs(x) * 0.2)
        p.ell("Head.detail", pt - n * 0.06, (0.16, w, 0.16), stripe, facing(n) @ Rz(x * 40))
    for z in (0.0, 0.4):
        p.ell("Body.detail", (0, 2.1, z + 0.2), (1.0, 0.16, 0.24), stripe)
    for sx in (-1, 1):
        p.ell("LegBL.detail" if sx > 0 else "LegBR.detail", (sx * 1.12, 0.85, 0.45), (0.1, 0.6, 0.16), stripe)
    cat_ears(p, fur)
    eyes(p, HC, HS, 0.6, EYE_Y, iris=hexc("b0640f"), lash=True)
    snout(p, HC, HS, SNOUT_Y, cream, nose_col=hexc("ff7b93"))
    blush(p, HC, HS, 0.98, BLUSH_Y)
    whiskers(p)
    tail_chain(p, CAT_TAIL, fur, stripe)
    return p

@pet
def Chiot():
    p = Pet("Chiot"); fur = hexc("d6964f"); light = hexc("f8e3c0"); dark = hexc("8a5428")
    sit_body(p, fur, light, paw=light)
    head(p, fur)
    p.ell("Head.accent", (0, 3.25, -1.05), (0.7, 1.0, 0.45), light)
    for side, name in ((1, "EarL"), (-1, "EarR")):
        R = Rz(side * 15) @ Rx(-8)
        p.ell(f"{name}.base", (side * 1.35, 2.85, -0.15), (0.7, 1.55, 0.48), dark, R)
        p.pivots[name] = (side * 1.15, 3.5, -0.15); p.parents[name] = "Head"
    eyes(p, HC, HS, 0.6, EYE_Y, iris=hexc("6a3a12"))
    snout(p, HC, HS, 2.3, light, size=(1.0, 0.62, 0.55), tongue=True)
    blush(p, HC, HS, 1.0, BLUSH_Y)
    p.cyl("Body.detail", (0, 2.08, -0.25), 0.26, 1.62, RED, Rz(90) @ Rx(18))
    p.ell("Body.glow", (0, 1.82, -0.98), (0.34, 0.34, 0.12), GOLD)
    p.ell("Body.detail", (0, 1.82, -1.04), (0.14, 0.14, 0.05), GOLD2)
    tail_chain(p, [((0, 0.85, 1.25), (0.4, 0.4, 0.65)), ((0, 1.35, 1.48), (0.38, 0.7, 0.38))], fur, light)
    return p

@pet
def Lapin():
    p = Pet("Lapin"); fur = hexc("faf6fa"); inner = hexc("ffb3c9"); shade = hexc("efe4ee")
    sit_body(p, fur, hexc("ffffff"), paw=shade)
    head(p, fur)
    cheeks(p, hexc("ffffff"), HC, HS, spread=1.08)
    for side, name in ((1, "EarL"), (-1, "EarR")):
        R = Rz(-side * 9)
        c = np.array([side * 0.52, 4.75, -0.25])
        p.ell(f"{name}.base", c, (0.7, 2.15, 0.42), fur, R)
        p.ell(f"{name}.detail", c + np.array([0, -0.05, -0.13]), (0.4, 1.65, 0.22), inner, R)
        p.pivots[name] = (side * 0.45, 3.85, -0.25); p.parents[name] = "Head"
    eyes(p, HC, HS, 0.6, EYE_Y, iris=hexc("9a3858"), lash=True)
    snout(p, HC, HS, SNOUT_Y, hexc("ffffff"), size=(0.75, 0.45, 0.42), nose_col=hexc("ff7b93"))
    blush(p, HC, HS, 0.98, BLUSH_Y)
    p.ell("Tail.base", (0, 0.75, 1.35), (0.85, 0.85, 0.85), hexc("ffffff"))
    return p

@pet
def Renard():
    p = Pet("Renard"); fur = hexc("ff6d1f"); white = hexc("fff4e6"); dark = hexc("3b2418")
    sit_body(p, fur, white, paw=dark, front_leg=dark)
    head(p, fur)
    cheeks(p, white, HC, HS, size=(0.85, 0.65, 0.9))
    for sx in (-1, 1):
        on_face(p, "Head", "accent", HC, HS, sx * 0.48, 2.3, (0.78, 0.58, 0.42), white, depth=0.32)
    cat_ears(p, fur, inner=white, tip=dark, size=(1.0, 1.35, 0.4), y=4.05, x=0.82, tilt=16)
    eyes(p, HC, HS, 0.6, EYE_Y, iris=hexc("8c4a0c"), lash=True)
    snout(p, HC, HS, SNOUT_Y - 0.05, white, size=(0.8, 0.5, 0.55))
    blush(p, HC, HS, 1.0, BLUSH_Y)
    tail_chain(p, BUSHY_TAIL, fur, white)
    return p

@pet
def Hibou():
    p = Pet("Hibou"); p.kind = "fly"; p.hover = 1.4
    brown = hexc("8b5a32"); light = hexc("efd3a8"); face = hexc("f6e6c9"); dark = hexc("6a4022")
    c = (0, 1.95, 0.1); s = (2.9, 3.4, 2.6)
    p.ell("Body.base", c, s, brown)
    p.ell("Body.accent", (0, 1.35, -0.72), (1.95, 2.0, 1.2), light)
    for (x, y) in ((0, 1.75), (-0.38, 1.3), (0.38, 1.3), (0, 0.85), (-0.5, 1.8), (0.5, 1.8)):
        pt, n = surface_front((0, 1.35, -0.72), (1.95, 2.0, 1.2), x, y)
        p.ell("Body.detail", pt - n * 0.05, (0.32, 0.2, 0.08), mix(brown, light, 0.3), facing(n))
    hc = (0, 2.75, 0.0); hs = (2.9, 2.6, 2.6)
    for sx in (-1, 1):
        on_face(p, "Body", "accent", hc, hs, sx * 0.6, 2.8, (1.35, 1.45, 0.5), face, depth=0.3)
    eyes(p, hc, (hs[0] + 0.5, hs[1] + 0.3, hs[2] + 0.75), 0.6, 2.82, size=(0.95, 1.05, 0.38), iris=hexc("ffb21c"), group="Body")
    pt, n = surface_front(hc, hs, 0, 2.3)
    p.ell("Body.detail", pt + n * 0.12, (0.32, 0.45, 0.35), hexc("ff9e1b"), facing(n) @ Rx(-20))
    blush(p, (0, 2.6, -0.05), (3.0, 2.6, 2.8), 1.05, 2.3, group="Body")
    for side, name in ((1, "EarL"), (-1, "EarR")):
        p.ell(f"{name}.base", (side * 0.95, 3.85, -0.05), (0.45, 0.95, 0.38), dark, Rz(-side * 25))
        p.pivots[name] = (side * 0.85, 3.45, -0.05); p.parents[name] = "Body"
    for side, name in ((1, "WingL"), (-1, "WingR")):
        p.ell(f"{name}.base", (side * 1.48, 1.85, 0.3), (0.6, 2.15, 1.7), brown, Rz(side * 12))
        for k in range(3):
            p.ell(f"{name}.accent", (side * 1.6, 1.25 - k * 0.32, 0.3 + k * 0.08), (0.4, 0.45, 1.3 - k * 0.15), dark, Rz(side * 12))
        p.pivots[name] = (side * 1.2, 2.55, 0.3)
    for sx in (-1, 1):
        for t in (-0.15, 0, 0.15):
            p.ell("Body.detail", (sx * 0.5 + t, 0.28, -0.45), (0.16, 0.2, 0.42), hexc("ff9e1b"))
    p.ell("Tail.base", (0, 0.75, 1.35), (1.0, 0.35, 0.8), dark, Rx(-25))
    p.pivots["Body"] = (0, 1.5, 0.1); p.pivots["Head"] = (0, 2.0, 0.1); p.pivots["Tail"] = (0, 0.9, 1.1)
    return p

@pet
def Licorne():
    p = Pet("Licorne"); fur = hexc("fff4fa"); mane = hexc("ff4fae"); mane2 = hexc("ff9ad6")
    bc = stand_body(p, fur, None, hoof=GOLD, legs_len=1.0)
    head(p, fur, hs=SHS, hc=SHC)
    snout(p, SHC, SHS, 2.5, hexc("ffe4f1"), size=(1.15, 0.72, 0.68), nose_col=hexc("e58fb4"))
    eyes(p, SHC, SHS, 0.52, 3.0, iris=hexc("9a46ff"), lash=True)
    blush(p, SHC, SHS, 0.88, 2.65)
    for i in range(5):
        p.ell("Head.glow" if i == 4 else "Head.detail", (0, 4.2 + i * 0.22, -1.3 - i * 0.06), (0.42 - i * 0.07, 0.36, 0.42 - i * 0.07), GOLD if i % 2 == 0 else GOLD2, Rx(-15))
    cat_ears(p, fur, inner=PINK, size=(0.6, 0.85, 0.32), y=4.05, x=0.68, tilt=14, z=-0.75)
    for i, (x, y, z, sz) in enumerate(((0.62, 3.95, -0.45, 0.95), (0.85, 3.5, -0.1, 1.0), (0.85, 3.0, 0.15, 0.95), (0.7, 2.55, 0.3, 0.85),
                                        (-0.62, 3.95, -0.45, 0.95), (-0.85, 3.5, -0.1, 1.0), (-0.85, 3.0, 0.15, 0.95), (-0.7, 2.55, 0.3, 0.85),
                                        (0, 4.1, -0.35, 1.0), (0, 3.7, 0.05, 0.95))):
        p.ell("Head.accent", (x, y, z), (sz, sz, sz), mane if i % 2 == 0 else mane2)
    p.ell("Head.accent", (0, 3.75, -1.45), (0.75, 0.55, 0.45), mane2)
    tail_chain(p, [((0, bc[1] + 0.1, 1.45), (0.75, 0.75, 0.85)), ((0, bc[1] - 0.3, 1.85), (0.85, 1.05, 0.85)), ((0, bc[1] - 0.8, 1.95), (0.75, 0.85, 0.75))], mane, mane2)
    for x, z in ((0.83, 0.45), (0.8, 0.8)):
        p.ell("Body.glow", (x, bc[1], z), (0.1, 0.26, 0.26), GOLD, mat="Neon")
    return p

@pet
def Cerf():
    p = Pet("Cerf"); fur = hexc("b8733d"); light = hexc("f5dfc0"); dark = hexc("4f2e16")
    bc = stand_body(p, fur, light, hoof=dark, legs_len=1.1)
    for x, y, z in ((0.55, 0.3, 0.2), (0.7, 0.0, 0.6), (0.5, 0.45, 0.8), (-0.55, 0.3, 0.2), (-0.7, 0.0, 0.6), (-0.5, 0.45, 0.8), (0.2, 0.65, 0.5), (-0.25, 0.65, 0.15)):
        p.ell("Body.detail", (x, bc[1] + y, z), (0.2, 0.2, 0.2), WHITE)
    head(p, fur, hs=SHS, hc=SHC)
    cheeks(p, light, SHC, SHS, spread=1.0, size=(0.6, 0.5, 0.7))
    for side, name in ((1, "EarL"), (-1, "EarR")):
        R = Rz(-side * 60)
        p.ell(f"{name}.base", (side * 1.35, 3.55, -0.75), (0.6, 1.1, 0.34), fur, R)
        p.ell(f"{name}.detail", (side * 1.35, 3.55, -0.88), (0.34, 0.72, 0.15), PINK, R)
        p.pivots[name] = (side * 1.1, 3.45, -0.75); p.parents[name] = "Head"
    antler = hexc("7a4b22")
    for sx in (-1, 1):
        p.cyl("Head.detail", (sx * 0.5, 4.35, -0.7), 0.75, 0.2, antler, Rz(90 - sx * 25))
        p.cyl("Head.detail", (sx * 0.72, 4.75, -0.7), 0.5, 0.17, antler, Rz(90 + sx * 30))
        p.cyl("Head.detail", (sx * 0.85, 4.55, -0.7), 0.45, 0.15, antler, Rz(sx * 15))
        p.ell("Head.detail", (sx * 0.62, 4.98, -0.7), (0.2, 0.2, 0.2), antler)
    eyes(p, SHC, SHS, 0.52, 3.0, iris=hexc("5a2d08"), lash=True)
    snout(p, SHC, SHS, 2.55, light, size=(0.85, 0.55, 0.55))
    blush(p, SHC, SHS, 0.9, 2.68)
    p.ell("Tail.base", (0, bc[1] + 0.35, 1.4), (0.45, 0.55, 0.4), fur, Rx(-30))
    p.ell("Tail.accent", (0, bc[1] + 0.25, 1.52), (0.35, 0.4, 0.3), WHITE, Rx(-30))
    return p

@pet
def Loup():
    p = Pet("Loup"); fur = hexc("8a8ea0"); white = hexc("f1f2f7"); dark = hexc("575b6d")
    sit_body(p, fur, white, paw=white)
    head(p, fur)
    cheeks(p, white, HC, HS, size=(0.85, 0.7, 0.9))
    for sx in (-1, 1):
        on_face(p, "Head", "accent", HC, HS, sx * 0.5, 2.32, (0.95, 0.75, 0.5), white, depth=0.3)
    p.ell("Body.accent", (0, 2.2, -0.45), (1.6, 0.8, 0.75), white)
    cat_ears(p, fur, inner=white, tip=dark, size=(0.95, 1.25, 0.4), y=4.05, x=0.82, tilt=14)
    eyes(p, HC, HS, 0.6, EYE_Y, iris=hexc("3fa8ff"))
    snout(p, HC, HS, SNOUT_Y - 0.05, white, size=(0.85, 0.52, 0.6))
    blush(p, HC, HS, 1.0, BLUSH_Y)
    tail_chain(p, BUSHY_TAIL, fur, white)
    return p

@pet
def Ours():
    p = Pet("Ours"); fur = hexc("7d4b2a"); light = hexc("d9a774")
    sit_body(p, fur, light, paw=light)
    hs = (2.85, 2.45, 2.35)
    head(p, fur, hs=hs)
    round_ears(p, fur, inner=light)
    eyes(p, HC, hs, 0.58, EYE_Y, iris=hexc("3f8fe0"))
    snout(p, HC, hs, SNOUT_Y, light, size=(1.05, 0.7, 0.6))
    blush(p, HC, hs, 1.02, BLUSH_Y)
    p.ell("Tail.base", (0, 0.65, 1.3), (0.55, 0.55, 0.55), fur)
    return p

@pet
def Panda():
    p = Pet("Panda"); white = hexc("f8f6f3"); black = hexc("26232d")
    sit_body(p, white, None, paw=black, front_leg=black, haunch=black)
    p.cyl("Body.accent", (0, 1.95, 0.15), 0.9, 1.95, black, Ry(90))
    hs = (2.85, 2.45, 2.35)
    head(p, white, hs=hs)
    round_ears(p, black)
    for sx in (-1, 1):
        on_face(p, "Head", "detail", HC, hs, sx * 0.58, EYE_Y - 0.05, (0.95, 1.12, 0.42), black, depth=0.3)
    eyes(p, HC, hs, 0.58, EYE_Y, size=(0.68, 0.84, 0.36), iris=hexc("3d8bff"))
    snout(p, HC, hs, SNOUT_Y, white, size=(0.95, 0.62, 0.55), nose_col=black)
    blush(p, HC, hs, 1.08, BLUSH_Y)
    p.ell("Tail.base", (0, 0.6, 1.3), (0.5, 0.5, 0.5), white)
    return p

@pet
def Phenix():
    p = Pet("Phenix"); p.kind = "fly"; p.hover = 1.8
    red = hexc("ff3d1f"); orange = hexc("ff8a1c"); yellow = hexc("ffd23a")
    p.ell("Body.base", (0, 1.55, 0.25), (1.6, 1.9, 1.95), red, Rx(-15))
    p.ell("Body.accent", (0, 1.35, -0.38), (1.05, 1.35, 0.9), yellow)
    hc = (0, 2.9, -0.35); hs = (2.2, 2.05, 2.0)
    p.ell("Head.base", hc, hs, orange)
    eyes(p, hc, hs, 0.47, 2.95, size=(0.62, 0.78, 0.32), iris=hexc("b23b00"), lash=True)
    pt, n = surface_front(hc, hs, 0, 2.55)
    p.ell("Head.detail", pt + n * 0.15, (0.38, 0.32, 0.6), hexc("ffc341"), facing(n) @ Rx(-25))
    blush(p, hc, hs, 0.78, 2.62)
    for i, (x, y, z, a) in enumerate(((0, 4.05, -0.2, 0), (0.32, 3.95, 0.05, -20), (-0.32, 3.95, 0.05, 20), (0, 3.9, 0.35, 0))):
        p.ell("Head.glow", (x, y, z), (0.38, 1.05, 0.38), yellow if i % 2 else orange, Rz(a) @ Rx(-25), mat="Neon")
    for side, name in ((1, "WingL"), (-1, "WingR")):
        sh = np.array([side * 0.65, 1.95, 0.35])
        for k, (length, col) in enumerate(((2.0, red), (1.8, orange), (1.55, yellow), (1.25, hexc("fff08a")))):
            R = Rz(-side * (35 + k * 22)) @ Rx(18)
            glow = k >= 2
            p.ell(f"{name}.{'glow' if glow else 'base'}", sh + R @ np.array([0, length / 2, 0]), (0.52, length, 0.28), col, R, mat="Neon" if glow else "SmoothPlastic")
        p.pivots[name] = tuple(sh)
    for k in range(5):
        R = Ry((k - 2) * 18) @ Rx(115)
        col = (red, orange, yellow, orange, red)[k]
        p.ell("Tail.glow" if k in (1, 2, 3) else "Tail.base", np.array([0, 1.05, 1.0]) + R @ np.array([0, 0.9, 0]), (0.36, 1.8, 0.22), col, R, mat="Neon" if k == 2 else "SmoothPlastic")
    for sx in (-1, 1):
        p.ell("Body.detail", (sx * 0.35, 0.45, -0.1), (0.3, 0.45, 0.3), hexc("ffb12b"))
    p.pivots["Body"] = (0, 1.5, 0.2); p.pivots["Head"] = (0, 2.1, -0.2); p.pivots["Tail"] = (0, 1.2, 1.0)
    return p

@pet
def Dragon():
    p = Pet("Dragon"); p.kind = "fly"; p.hover = 1.2
    green = hexc("38c64c"); belly = hexc("f4e47c"); dark = hexc("1f8a33"); horn = hexc("f3c25e")
    sit_body(p, green, None, paw=hexc("2aa83c"))
    for i in range(5):
        y = 1.95 - i * 0.3
        pt, n = surface_front(BC, BS, 0, y)
        p.ell("Body.accent", pt - n * 0.06, (1.0 - abs(i - 2) * 0.08, 0.28, 0.24), belly, facing(n))
    hs = (2.7, 2.3, 2.35)
    head(p, green, hs=hs)
    snout(p, HC, hs, 2.28, hexc("62de70"), size=(1.2, 0.72, 0.75), nose_col=dark)
    eyes(p, HC, hs, 0.58, EYE_Y, iris=hexc("ffcf1a"))
    blush(p, HC, hs, 1.0, BLUSH_Y)
    for sx in (-1, 1):
        p.ell("Head.detail", (sx * 0.62, 4.1, 0.05), (0.34, 0.95, 0.34), horn, Rz(-sx * 22) @ Rx(30))
        p.ell("Head.accent", (sx * 1.3, 3.15, -0.2), (0.3, 0.75, 0.35), hexc("b6f06a"), Rz(-sx * 50))
    for i in range(5):
        p.ell("Body.detail", (0, 2.3 - i * 0.38, 0.95 + i * 0.12), (0.18, 0.48, 0.38), dark, Rx(-20))
    for side, name in ((1, "WingL"), (-1, "WingR")):
        sh = np.array([side * 0.6, 2.05, 0.75])
        for k, (ang, ln) in enumerate(((-55, 1.9), (-25, 1.6), (5, 1.25))):
            R = Ry(side * 28) @ Rz(side * ang)
            p.ell(f"{name}.accent", sh + R @ np.array([0, ln / 2, 0]) * 1.0 + np.array([side * 0.15, 0, 0]), (0.85, ln, 0.12), hexc("b6f06a") if k != 1 else hexc("a2e45a"), R)
        R = Ry(side * 28) @ Rz(side * -55)
        p.ell(f"{name}.base", sh + R @ np.array([0, 1.0, 0]), (0.2, 2.0, 0.2), dark, R)
        p.ell(f"{name}.base", sh + R @ np.array([0, 2.0, 0]), (0.3, 0.3, 0.3), dark)
        p.pivots[name] = tuple(sh)
    tail_chain(p, [((0.3, 0.4, 1.35), (0.75, 0.65, 0.95)), ((0.7, 0.35, 1.85), (0.55, 0.5, 0.85)), ((1.0, 0.35, 2.25), (0.4, 0.38, 0.65))], green)
    p.ell("Tail.detail", (1.2, 0.45, 2.55), (0.6, 0.45, 0.2), dark, Rx(-20) @ Ry(30))
    return p

@pet
def Scorpion():
    p = Pet("Scorpion"); p.kind = "crawl"
    brown = hexc("6e3b1f"); light = hexc("ab673b"); dark = hexc("3e2012")
    p.ell("Body.base", (0, 0.85, 0.35), (1.75, 0.95, 2.05), brown)
    for i in range(3):
        p.ell("Body.detail", (0, 1.28, -0.15 + i * 0.5), (1.3 - i * 0.15, 0.15, 0.3), light)
    hc = (0, 1.3, -0.75); hs = (2.15, 1.7, 1.75)
    p.ell("Head.base", hc, hs, brown)
    eyes(p, hc, hs, 0.48, 1.5, size=(0.64, 0.76, 0.32), iris=hexc("c06a2a"))
    blush(p, hc, hs, 0.8, 1.05)
    pt, n = surface_front(hc, hs, 0, 1.05)
    for sx in (-1, 1):
        p.ell("Head.detail", pt + facing(n) @ np.array([sx * 0.09, 0, 0]), (0.16, 0.05, 0.05), dark, facing(n) @ Rz(sx * 30))
    for side in (1, -1):
        fl = "LegFL" if side == 1 else "LegFR"
        bl = "LegBL" if side == 1 else "LegBR"
        for k in range(3):
            g = fl if k < 2 else bl
            p.cyl(f"{g}.base", (side * 1.05, 0.55, -0.1 + k * 0.5), 0.95, 0.2, dark, Rz(side * -35) @ Ry(side * (k - 1) * 20))
            p.ell(f"{g}.accent", (side * 1.45, 0.22, -0.1 + k * 0.5), (0.22, 0.22, 0.22), dark)
        p.pivots[fl] = (side * 0.7, 0.75, 0.15); p.pivots[bl] = (side * 0.7, 0.75, 0.9)
        p.cyl("Head.base", (side * 1.0, 0.9, -1.55), 0.85, 0.3, brown, Ry(side * 50))
        p.ell("Head.accent", (side * 1.3, 1.0, -2.1), (0.85, 0.62, 0.95), light)
        p.ell("Head.accent", (side * 1.1, 1.0, -2.55), (0.24, 0.38, 0.65), light, Ry(side * 20))
        p.ell("Head.accent", (side * 1.52, 1.0, -2.55), (0.24, 0.38, 0.65), light, Ry(-side * 20))
    for c, sz in (((0, 1.2, 1.45), 0.66), ((0, 1.78, 1.75), 0.62), ((0, 2.4, 1.7), 0.58), ((0, 2.92, 1.35), 0.54), ((0, 3.15, 0.85), 0.48)):
        p.ell("Tail.base", c, (sz, sz, sz), brown)
    p.ell("Tail.glow", (0, 3.0, 0.45), (0.32, 0.58, 0.32), hexc("ffb347"), Rx(-60))
    p.pivots["Tail"] = (0, 1.0, 1.25); p.pivots["Body"] = (0, 0.8, 0.3); p.pivots["Head"] = (0, 1.0, -0.4)
    return p

@pet
def Chameau():
    p = Pet("Chameau"); fur = hexc("e6b16a"); light = hexc("f8dfb0"); dark = hexc("9a6a34")
    bc = stand_body(p, fur, None, hoof=dark, legs_len=1.2, body_s=(1.7, 1.45, 2.3))
    for z in (-0.05, 0.75):
        p.ell("Body.base", (0, bc[1] + 0.85, z), (1.1, 1.05, 0.95), fur)
    p.box("Body.detail", (0, bc[1] + 0.72, 0.35), (1.85, 0.14, 0.75), RED)
    for sx in (-1, 1):
        p.box("Body.detail", (sx * 0.93, bc[1] + 0.25, 0.35), (0.1, 0.95, 0.75), RED)
        p.box("Body.detail", (sx * 0.95, bc[1] + 0.68, 0.35), (0.1, 0.12, 0.78), GOLD)
        for k in range(3):
            p.ell("Body.glow", (sx * 1.0, bc[1] - 0.25, 0.1 + k * 0.25), (0.13, 0.3, 0.13), GOLD, mat="Neon")
    hc = (0, 3.55, -1.05); hs = (2.15, 2.0, 2.2)
    p.ell("Head.base", (0, 2.7, -0.75), (0.85, 1.5, 0.85), fur, Rx(25))
    p.ell("Head.base", hc, hs, fur)
    snout(p, hc, hs, 3.2, light, size=(1.2, 0.85, 0.85), nose_col=dark)
    eyes(p, hc, hs, 0.5, 3.75, size=(0.62, 0.78, 0.32), iris=hexc("6a3a12"), lash=True)
    blush(p, hc, hs, 0.82, 3.35)
    p.ell("Head.accent", (0, 4.55, -0.95), (0.9, 0.45, 0.8), mix(fur, dark, 0.3))
    for side, name in ((1, "EarL"), (-1, "EarR")):
        p.ell(f"{name}.base", (side * 0.88, 4.35, -0.85), (0.38, 0.55, 0.28), fur, Rz(-side * 30))
        p.pivots[name] = (side * 0.75, 4.2, -0.85); p.parents[name] = "Head"
    p.pivots["Head"] = (0, 2.2, -0.6)
    p.ell("Tail.base", (0, bc[1] + 0.1, 1.55), (0.22, 0.8, 0.22), dark, Rx(25))
    return p

@pet
def Cobra():
    p = Pet("Cobra"); p.kind = "slither"
    green = hexc("30b350"); belly = hexc("f5e68c"); dark = hexc("1d7a35")
    for i in range(14):
        a = i / 14 * math.pi * 2
        p.ell("Body.base", (math.cos(a) * 1.1, 0.48 + i * 0.012, math.sin(a) * 1.1 + 0.45), (0.95, 0.9, 0.95), green if i % 3 else dark)
    for i in range(10):
        a = i / 10 * math.pi * 2
        p.ell("Body.base", (math.cos(a) * 0.62, 1.15, math.sin(a) * 0.62 + 0.45), (0.8, 0.75, 0.8), green)
    for i, y in enumerate((1.7, 2.2, 2.7, 3.15)):
        p.ell("Head.base", (0, y, 0.2 - i * 0.12), (0.85, 0.8, 0.85), green)
        p.ell("Head.accent", (0, y, -0.15 - i * 0.12), (0.55, 0.65, 0.32), belly)
    p.ell("Head.accent", (0, 3.3, 0.12), (2.2, 1.85, 0.4), dark, Rx(-10))
    p.ell("Head.base", (0, 3.3, 0.02), (1.95, 1.6, 0.45), green, Rx(-10))
    hc = (0, 4.0, -0.35); hs = (1.95, 1.6, 1.75)
    p.ell("Head.base", hc, hs, green)
    eyes(p, hc, hs, 0.46, 4.12, size=(0.62, 0.74, 0.3), iris=hexc("ffd21f"))
    blush(p, hc, hs, 0.72, 3.78)
    pt, n = surface_front(hc, hs, 0, 3.7)
    for sx in (-1, 1):
        p.ell("Head.detail", pt + facing(n) @ np.array([sx * 0.1, 0, 0.02]), (0.18, 0.05, 0.05), dark, facing(n) @ Rz(sx * 25))
    p.ell("Head.detail", pt + np.array([0, -0.18, -0.12]), (0.08, 0.32, 0.08), hexc("ff3b5c"))
    p.pivots["Head"] = (0, 1.5, 0.2); p.pivots["Body"] = (0, 0.5, 0.4)
    return p

@pet
def Lezard():
    p = Pet("Lezard"); green = hexc("8fe05a"); belly = hexc("eaf9a8"); spot = hexc("4cb53a")
    sit_body(p, green, belly, paw=hexc("74cf47"))
    for x, y, z in ((0.5, 1.9, 0.2), (-0.45, 1.6, 0.55), (0.3, 1.3, 0.75), (-0.2, 2.1, 0.45)):
        p.ell("Body.detail", (x, y, z), (0.34, 0.34, 0.14), spot, Ry(0))
    hs = (2.8, 2.15, 2.4)
    head(p, green, hs=hs)
    for x, y in ((0.4, 3.85), (-0.5, 3.75), (0.0, 4.0)):
        p.ell("Head.detail", (x, y, -0.3), (0.42, 0.18, 0.42), spot)
    eyes(p, HC, hs, 0.62, EYE_Y + 0.05, size=(0.8, 0.95, 0.38), iris=hexc("2f9a1a"))
    blush(p, HC, hs, 1.05, BLUSH_Y)
    pt, n = surface_front(HC, hs, 0, 2.3)
    for sx in (-1, 1):
        p.ell("Head.detail", pt + facing(n) @ np.array([sx * 0.15, 0, 0]), (0.22, 0.05, 0.05), hexc("2a6a1a"), facing(n) @ Rz(sx * 22))
    for side, name in ((1, "WingL"), (-1, "WingR")):
        p.ell(f"{name}.accent", (side * 1.0, 2.25, 0.5), (0.12, 1.1, 1.2), hexc("c7f59a"), Rz(side * 40), tr=0.1)
        p.pivots[name] = (side * 0.7, 1.9, 0.5)
    tail_chain(p, [((0.3, 0.35, 1.4), (0.75, 0.6, 1.0)), ((0.75, 0.3, 1.95), (0.55, 0.45, 0.9)), ((1.1, 0.3, 2.4), (0.4, 0.35, 0.7))], green)
    return p

@pet
def Sphinx():
    p = Pet("Sphinx"); gold = hexc("f2b440"); light = hexc("ffe09a"); blue = hexc("2a55cc")
    sit_body(p, gold, light, paw=light)
    head(p, gold)
    for i in range(7):
        y = 4.0 - i * 0.3
        for sx in (-1, 1):
            p.ell("Head.accent", (sx * (1.25 + i * 0.03), y, -0.05), (0.45, 0.34, 1.55), GOLD if i % 2 == 0 else blue)
    for i in range(5):
        p.ell("Head.accent", (0, 4.05 - 0.02 * i, -0.05 + i * 0.27), (2.55 - i * 0.05, 0.55, 0.38), GOLD if i % 2 == 0 else blue)
    p.ell("Head.glow", (0, 4.05, -0.95), (0.34, 0.44, 0.25), hexc("2fb6ff"), mat="Neon")
    p.ell("Head.detail", (0, 4.05, -0.88), (0.52, 0.62, 0.2), GOLD)
    eyes(p, HC, HS, 0.6, EYE_Y, iris=hexc("1f8a4a"), lash=True)
    snout(p, HC, HS, SNOUT_Y, light, nose_col=hexc("a85a2a"))
    blush(p, HC, HS, 0.98, BLUSH_Y)
    p.cyl("Body.detail", (0, 2.08, -0.25), 0.32, 1.7, GOLD, Rz(90) @ Rx(18))
    for k, sx in enumerate((-0.38, 0, 0.38)):
        p.ell("Body.glow", (sx, 1.85, -0.95), (0.2, 0.24, 0.12), hexc("2fb6ff"), mat="Neon")
    tail_chain(p, CAT_TAIL, gold, hexc("8a5a20"))
    return p

@pet
def Genie():
    p = Pet("Genie"); p.kind = "float"; p.hover = 1.2
    blue = hexc("3d7dff"); light = hexc("86b8ff"); dark = hexc("1d3f9e")
    p.ell("Body.base", (0, 1.95, 0.15), (2.0, 1.7, 1.45), blue)
    p.ell("Body.base", (0, 2.5, 0.15), (1.6, 0.85, 1.25), blue)
    for k, (y, z, sz) in enumerate(((1.1, 0.25, 1.25), (0.6, 0.45, 0.9), (0.25, 0.75, 0.6), (0.12, 1.1, 0.38))):
        p.ell("Tail.base" if k < 2 else "Tail.accent", (0.1 * k, y, z), (sz, sz * 1.1, sz), blue if k < 2 else light)
    for sx in (-1, 1):
        p.ell("Body.base", (sx * 0.9, 2.25, 0.0), (0.62, 0.78, 0.62), blue)
        p.ell("Body.base", (sx * 0.2, 1.88, -0.62), (1.25, 0.5, 0.52), blue, Rz(sx * 12))
        p.cyl("Body.glow", (sx * 0.65, 1.9, -0.64), 0.26, 0.58, GOLD, Ry(0))
    hc = (0, 3.55, -0.1); hs = (2.15, 2.15, 1.95)
    p.ell("Head.base", hc, hs, blue)
    eyes(p, hc, hs, 0.48, 3.62, size=(0.62, 0.78, 0.32), iris=hexc("1a2a6e"))
    blush(p, hc, hs, 0.8, 3.25)
    pt, n = surface_front(hc, hs, 0, 3.1)
    p.ell("Head.detail", pt - n * 0.03, (0.5, 0.11, 0.08), dark, facing(n))
    p.ell("Head.detail", pt + facing(n) @ np.array([0, -0.06, 0.0]), (0.28, 0.1, 0.06), hexc("ff6f8e"), facing(n))
    for sx in (-1, 1):
        p.ell("Head.base", (sx * 1.15, 3.65, -0.1), (0.28, 0.78, 0.38), blue, Rz(-sx * 55))
        p.ell("Head.glow", (sx * 1.08, 3.2, -0.15), (0.2, 0.28, 0.2), GOLD, mat="Neon")
    p.ell("Head.detail", (0, 4.6, 0.05), (0.85, 0.6, 0.85), BLACK)
    p.ell("Head.detail", (0, 5.05, 0.1), (0.45, 0.6, 0.45), BLACK)
    p.cyl("Head.glow", (0, 4.78, 0.07), 0.15, 0.6, GOLD, Rz(90))
    p.pivots["Head"] = (0, 2.8, 0); p.pivots["Body"] = (0, 1.8, 0.1); p.pivots["Tail"] = (0, 1.4, 0.2)
    return p

@pet
def Pharaon():
    p = Pet("Pharaon"); gold = hexc("ffb43a"); light = hexc("ffe2a6"); stripe = hexc("e8822a")
    sit_body(p, gold, light, paw=light)
    head(p, gold)
    cheeks(p, light, HC, HS)
    for x, w in ((0, 0.45), (-0.32, 0.36), (0.32, 0.36)):
        pt, n = surface_front(HC, HS, x, 3.65 - abs(x) * 0.2)
        p.ell("Head.detail", pt - n * 0.06, (0.15, w, 0.15), stripe, facing(n) @ Rz(x * 40))
    cat_ears(p, gold)
    p.cyl("Head.glow", (0, 4.12, -0.25), 0.42, 1.85, GOLD, Rz(90), mat="SmoothPlastic")
    for k in range(5):
        a = math.radians(-60 + k * 30)
        x, z = math.sin(a) * 0.88, -0.25 - math.cos(a) * 0.88
        p.ell("Head.glow", (x, 4.58, z), (0.32, 0.62, 0.32), GOLD)
        p.ell("Head.glow", (x, 4.98, z), (0.22, 0.22, 0.22), hexc("ff3b8d") if k % 2 else hexc("37c6ff"), mat="Neon")
    p.ell("Head.glow", (0, 4.15, -1.17), (0.38, 0.46, 0.2), hexc("b23bff"), mat="Neon")
    eyes(p, HC, HS, 0.6, EYE_Y, iris=hexc("2aa04f"), lash=True)
    snout(p, HC, HS, SNOUT_Y, light, nose_col=hexc("ff7b93"))
    blush(p, HC, HS, 0.98, BLUSH_Y)
    whiskers(p)
    p.cyl("Body.detail", (0, 2.08, -0.25), 0.34, 1.75, hexc("ff4d6d"), Rz(90) @ Rx(18))
    for sx in (-0.42, 0, 0.42):
        p.ell("Body.glow", (sx, 1.83, -0.98), (0.22, 0.28, 0.14), GOLD if sx else hexc("b23bff"), mat="Neon" if sx == 0 else "SmoothPlastic")
    tail_chain(p, CAT_TAIL, gold, stripe)
    return p

# ------------------------------------------------------------------ rendu d'apercu
MAT_NEON = "Neon"

def render(pet, size=260, cam=(4.4, 4.2, -9.8), look=(0, 2.4, 0.2)):
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
