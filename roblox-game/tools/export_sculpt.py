#!/usr/bin/env python3
"""Exporte les pets sculptes en donnees compactes pour le jeu (construits au lancement via EditableMesh).

Sorties :
  src/ReplicatedStorage/Shared/PetMeshes/<Nom>.lua   maillages (base64 : positions u16, normales i8, couleurs u8, triangles u16)
  src/ReplicatedStorage/Shared/PetRigs.lua            pivots / type de deplacement (memes conventions qu'avant)
  assets/sculpt/<Nom>.png, assets/sculpt/apercu_19_pets.png   rendus de controle
Usage : python3 tools/export_sculpt.py [Nom ...]
"""
import base64
import os
import sys
import time
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pets_sculpt as ps
from meshview import render

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "PetMeshes")
RIGS = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "PetRigs.lua")
PREV = os.path.join(ROOT, "assets", "sculpt")

def v3(v):
    return "Vector3.new(%s)" % ", ".join(("%.3f" % x).rstrip("0").rstrip(".") if abs(x) > 1e-9 else "0" for x in v)

def encode_part(key, m, glow):
    V, N, C, T = m
    lo, hi = V.min(0), V.max(0)
    center = (lo + hi) / 2
    ext = np.maximum((hi - lo) / 2, 1e-3)
    q = np.clip(np.round((V - center) / ext * 32767 + 32768), 0, 65535).astype("<u2")
    n = np.clip(np.round(N * 127), -127, 127).astype("i1")
    c = np.clip(np.round(C * 255), 0, 255).astype("u1")
    assert len(V) < 65536
    t = T.astype("<u2")
    raw = q.tobytes() + n.tobytes() + c.tobytes() + t.tobytes()
    b = base64.b64encode(raw).decode()
    chunks = [b[i:i + 60000] for i in range(0, len(b), 60000)]
    body = ",\n\t\t\t".join("[[%s]]" % ch for ch in chunks)
    return (f'\t{{ name = "{key}", center = {v3(center)}, ext = {v3(ext)}, nv = {len(V)}, nt = {len(T)},'
            f'{" glow = true," if key in glow else ""}\n\t\tdata = table.concat({{\n\t\t\t{body},\n\t\t}}) }},\n'), len(raw)

def rig_lua(p):
    s = f'\t{p.name} = {{\n\t\tkind = "{p.kind}",\n\t\thover = {p.hover},\n\t\tpivots = {{\n'
    for k, v in p.pivots.items():
        s += f"\t\t\t{k} = {v3(v)},\n"
    s += "\t\t},\n\t\tparents = {\n"
    for k, v in p.parents.items():
        s += f'\t\t\t{k} = "{v}",\n'
    return s + "\t\t},\n\t},\n"

def main():
    os.makedirs(OUT, exist_ok=True); os.makedirs(PREV, exist_ok=True)
    only = set(sys.argv[1:])
    rigs = {}
    # conserve les rigs existants des pets non regeneres
    tiles = []
    total = 0
    for fn in ps.PETS:
        t0 = time.time()
        p, meshes = ps.build(fn)
        rigs[p.name] = rig_lua(p)
        if only and p.name not in only:
            continue
        src = f"-- GENERE AUTOMATIQUEMENT par tools/export_sculpt.py : maillage sculpte du pet {p.name}.\n"
        src += "-- Construit en jeu par PetMeshFactory (EditableMesh). Ne pas modifier a la main.\nreturn {\n"
        size = 0
        for key, m in meshes.items():
            part, nbytes = encode_part(key, m, p.glow)
            src += part; size += nbytes
        src += "}\n"
        open(os.path.join(OUT, p.name + ".lua"), "w").write(src)
        nt = sum(len(m[3]) for m in meshes.values())
        total += size
        print(f"{p.name:9s} {len(meshes):2d} pieces {nt:6d} triangles {size/1024:6.0f} Ko  {time.time()-t0:4.1f}s", flush=True)
        ms = list(meshes.values())
        ims = [render(ms, 400, yaw=y, pitch=-10) for y in (-28, 0, 75, 160)]
        strip = Image.new("RGB", (1600, 400), "white")
        for i, im in enumerate(ims):
            strip.paste(im, (400 * i, 0))
        strip.save(os.path.join(PREV, p.name + ".png"))
        tiles.append((p.name, render(ms, 300, yaw=-28, pitch=-10)))
    if not only:
        out = "-- GENERE AUTOMATIQUEMENT par tools/export_sculpt.py : articulations des pets sculptes.\n"
        out += "-- kind : quad (4 pattes), fly (vole), float (flotte), slither (rampe), crawl (insecte).\n\nreturn {\n"
        out += "".join(rigs.values()) + "}\n"
        open(RIGS, "w").write(out)
        cols = 5; rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * 300, rows * 330), (236, 242, 250))
        d = ImageDraw.Draw(sheet)
        for i, (name, im) in enumerate(tiles):
            x, y = (i % cols) * 300, (i // cols) * 330
            sheet.paste(im, (x, y))
            d.text((x + 130, y + 305), name, fill=(40, 30, 60))
        sheet.save(os.path.join(PREV, "apercu_19_pets.png"))
    print(f"total {total/1024/1024:.2f} Mo")

if __name__ == "__main__":
    main()
