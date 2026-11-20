# Oeuf Foret : Cerf, Loup, Ours, Panda, Phenix, Dragon

@pet
def Cerf():
    p = Pet("Cerf")
    fur = hexc("b9773f"); light = hexc("f6e2c4"); dark = hexc("5a3418"); antler = hexc("e9cf9b")
    BC = np.array([0, 1.8, 0.45])
    b = stand_body(p, fur, belly=light, hoof=hexc("3d2516"), BC=BC, body_r=(0.82, 0.78, 1.15), leg_r=(0.24, 0.16))
    # taches blanches du faon sur le dos
    rng = np.random.RandomState(3)
    for i in range(12):
        x = (rng.rand() - 0.5) * 1.0; z = BC[2] - 0.7 + rng.rand() * 1.5
        q = np.array([x, BC[1] + 0.7 - abs(x) * 0.4, z])
        b.paint(Ellipsoid(q, (0.11, 0.08, 0.11)), WHITE, soft=0.04)
    HC = np.array([0, 3.35, -0.5]); HR = np.array([1.1, 1.0, 1.02])
    h = round_head(p, HC, HR, fur)
    mz = HC + [0, -0.45, -0.72]
    h.add(Ellipsoid(mz, (0.5, 0.42, 0.5)), light, k=0.28)
    glossy_nose(p, mz + [0, 0.12, -0.45], (0.17, 0.12, 0.1), dark)
    smile(h, mz + [0, -0.18, -0.44], frame((0, -0.3, -1)), width=0.17, curve=0.4)
    h.paint(Ellipsoid(HC + [0, 0.35, -0.95], (0.22, 0.35, 0.2)), mixc(fur, dark, 0.3), soft=0.1)
    blush(h, HC, HR, 0.8, HC[1] - 0.22)
    h.pattern(shading_variation(0.02, 0.06, 0.1, seed=4))
    eyes2(p, HC, HR, 0.5, HC[1] + 0.08, (0.37, 0.45, 0.21), hexc("4a2810"), hexc("b97a3a"), "round", brow=0.15, brow_col=dark)
    # oreilles larges horizontales
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        g = p.g(f"{name}.base", step=0.045, seed=5)
        base = HC + [sx * 0.75, 0.55, 0.1]
        tip = base + [sx * 0.85, 0.25, 0.0]
        R = frame((0, 0, -1), tip - base)
        g.add(Xf(Ellipsoid((0, 0.45, 0), (0.3, 0.5, 0.3)), base, R, (1, 1, 0.45)), fur, k=0)
        g.sub(Xf(Ellipsoid((0, 0.48, 0), (0.2, 0.38, 0.2)), base + [0, 0, -0.08], R, (1, 1, 0.3)), k=0.04)
        g.paint(Xf(Ellipsoid((0, 0.48, 0), (0.22, 0.4, 0.4)), base + [0, 0, -0.06], R, (1, 1, 0.5)), hexc("ffc9b5"), soft=0.04)
        p.pivots[name] = tuple(base); p.parents[name] = "Head"
    # bois ramifies
    gd = p.g("Head.detail", step=0.03, seed=6)
    for sx in (-1, 1):
        a = HC + [sx * 0.4, 0.82, 0.0]
        b1 = a + [sx * 0.25, 0.75, 0.05]
        b2 = b1 + [sx * 0.35, 0.45, 0.1]
        tube(gd, [a, b1, b2], [0.11, 0.085, 0.05], antler, k=0.05)
        for q, d in ((a + (b1 - a) * 0.55, [-sx * 0.15, 0.4, -0.15]), (b1, [sx * 0.05, 0.45, -0.2]), (b1 + (b2 - b1) * 0.5, [sx * 0.35, 0.15, 0.0])):
            gd.add(RoundCone(q, q + np.array(d), 0.07, 0.035), antler, k=0.05)
    t = p.g("Tail.base", step=0.04)
    tc = BC + [0, 0.45, 1.25]
    t.add(Ellipsoid(tc, (0.22, 0.3, 0.18), Rx(-30)), fur, k=0)
    t.paint(Ellipsoid(tc + [0, -0.1, 0.12], (0.2, 0.25, 0.15)), WHITE, soft=0.06)
    p.pivots["Head"] = tuple(BC + [0, 0.95, -0.85])
    return p

@pet
def Loup():
    p = Pet("Loup")
    fur = hexc("8d93a8"); white = hexc("f3f4f8"); dark = hexc("4f5468")
    HC = np.array([0, 2.95, -0.3]); HR = np.array([1.28, 1.05, 1.08])
    h = round_head(p, HC, HR, fur)
    cheek_tufts(h, HC, HR, white, n=3, size=0.25, length=0.55, y=-0.35)
    top_tuft(h, HC, HR, fur, n=3, size=0.16)
    base = HC + [0, -0.38, -HR[2] * 0.6]
    h.add(Xf(RoundCone((0, 0, 0), (0, 0, -0.7), 0.45, 0.22), base, I3, (1.0, 0.78, 1.0)), white, k=0.2)
    tip = base + [0, 0, -0.7]
    glossy_nose(p, tip + [0, 0.1, -0.18], (0.17, 0.12, 0.12), hexc("26222e"))
    smile(h, tip + [0, -0.1, -0.12], frame((0, -0.5, -1)), width=0.2, curve=0.55, open_=0.07, tongue_col=hexc("ff7d97"))
    gd = p.g("Head.detail", step=0.025)
    for sx in (-1, 1):  # petits crocs
        a = tip + [sx * 0.11, -0.13, -0.11]
        gd.add(RoundCone(a, a + [0, -0.09, -0.01], 0.035, 0.01), WHITE, k=0)
    h.paint(Ellipsoid(HC + [0, 0.7, -0.4], (1.1, 0.5, 0.9)), dark, soft=0.2)
    h.paint(Ellipsoid(HC + [0, -0.5, -0.9], (0.7, 0.45, 0.55)), white, soft=0.12)
    for sx in (-1, 1):
        h.paint(Ellipsoid(HC + [sx * 0.55, 0.42, -1.0], (0.3, 0.1, 0.2), Rz(sx * -15)), white, soft=0.06)  # sourcils clairs
    h.pattern(shading_variation(0.02, 0.08, 0.1, seed=5))
    eyes2(p, HC, HR, 0.55, HC[1] + 0.1, (0.37, 0.42, 0.21), hexc("1f7fd6"), hexc("9ce8ff"), "round", brow=-0.35, brow_col=dark, tilt=12)
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        cat_ear(p, name, HC + [sx * 0.65, 0.7, 0.08], HC + [sx * 1.05, 1.75, 0.15], 0.5, fur, inner=hexc("e9c6d0"), tip_col=dark)
    BC = np.array([0, 1.3, 0.3])
    b = sit_body(p, fur, white, mixc(fur, white, 0.3), BC, claws=dark)
    b.paint(Ellipsoid(BC + [0, 0.7, 0.45], (0.95, 0.5, 0.7)), dark, soft=0.2)
    curve_tail(p, [0.1, 0.5, 1.05], [1.2, 0.3, 1.7], [1.3, 1.4, 1.6], [0.3, 0.48, 0.5, 0.26], fur, tip_col=white, bushy=True, n=8)
    return p

@pet
def Ours():
    p = Pet("Ours")
    fur = hexc("7a4826"); light = hexc("d8a46f"); dark = hexc("4a2914"); claw = hexc("f3e6d0")
    HC = np.array([0, 2.9, -0.3]); HR = np.array([1.3, 1.12, 1.1])
    h = round_head(p, HC, HR, fur, rough=0.012)
    cheek_tufts(h, HC, HR, fur, n=2, size=0.22, length=0.3)
    top_tuft(h, HC, HR, fur, n=2, size=0.15)
    bear_muzzle(p, h, HC, HR, light, nose_col=hexc("2a1a14"), size=(0.52, 0.38, 0.38))
    blush(h, HC, HR, 0.95, HC[1] - 0.28)
    h.pattern(shading_variation(0.04, 0.08, 0.12, seed=6))
    eyes2(p, HC, HR, 0.58, HC[1] + 0.1, (0.36, 0.42, 0.21), hexc("3a1d0c"), hexc("b0703a"), "round", brow=0.1, brow_col=dark, lash=False)
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        round_ear(p, name, HC + [sx * 0.95, 0.85, 0.05], 0.38, fur, inner=light)
    BC = np.array([0, 1.3, 0.3])
    b = sit_body(p, fur, light, fur, BC, chest_fluff=False, rough=0.012, body_r=(0.95, 1.02, 0.9), claws=claw)
    b.paint(Ellipsoid(BC + [0, -0.1, -0.7], (0.6, 0.75, 0.4)), light, soft=0.12)
    for leg in ("LegFL", "LegFR", "LegBL", "LegBR"):
        g = p.parts[f"{leg}.base"]
        g.rough = (0.01, 6)
    gb = p.g("LegBL.base"); gb.paint(Ellipsoid([0.74, 0.17, -0.58], (0.25, 0.15, 0.08)), light, soft=0.04)
    gb = p.g("LegBR.base"); gb.paint(Ellipsoid([-0.74, 0.17, -0.58], (0.25, 0.15, 0.08)), light, soft=0.04)
    t = p.g("Tail.base", step=0.05, rough=(0.012, 8))
    t.add(Ellipsoid([0, 0.55, 1.15], (0.3, 0.28, 0.25)), fur, k=0)
    return p

@pet
def Panda():
    p = Pet("Panda")
    white = hexc("f9f7f4"); black = hexc("26232d"); bamboo = hexc("6fc04a")
    HC = np.array([0, 2.9, -0.3]); HR = np.array([1.35, 1.12, 1.1])
    h = round_head(p, HC, HR, white, rough=0.008)
    cheek_tufts(h, HC, HR, white, n=1, size=0.22, length=0.3)
    bear_muzzle(p, h, HC, HR, white, nose_col=black, size=(0.48, 0.34, 0.34))
    for sx in (-1, 1):  # taches des yeux en goutte inclinee
        q, n = surf(HC, HR, sx * 0.55, HC[1] + 0.02)
        h.add(Xf(Ellipsoid((0, 0, 0), (0.42, 0.55, 0.12)), q + [sx * 0.04, -0.06, 0] - n * 0.06, frame(n) @ Rz(sx * 30)), black, k=0.04)
    blush(h, HC, HR, 1.0, HC[1] - 0.35, size=0.22)
    h.pattern(shading_variation(0.015, 0.05, 0.1, seed=7))
    eyes2(p, HC, HR, 0.56, HC[1] + 0.06, (0.33, 0.38, 0.2), hexc("3b2a1a"), hexc("9a7a5a"), "round", lash=False, sink=0.45)
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        round_ear(p, name, HC + [sx * 0.98, 0.85, 0.05], 0.4, black)
    BC = np.array([0, 1.3, 0.3])
    b = sit_body(p, white, white, black, BC, chest_fluff=False, rough=0.008, body_r=(0.95, 1.02, 0.9), thigh_col=black)
    b.add(Ellipsoid(BC + [0, 0.55, 0.0], (1.0, 0.38, 0.92)), black, k=0.12)   # bande noire des epaules
    for leg in ("LegFL", "LegFR"):
        sx = 1 if leg.endswith("L") else -1
        g = p.parts[f"{leg}.base"]
        g.paint(Ellipsoid([sx * 0.42, 0.8, -0.45], (0.5, 0.9, 0.6)), black, soft=0.05)
    # tige de bambou tenue entre les pattes
    gd = p.g("LegFL.detail", step=0.03)
    tube(gd, [np.array([0.0, 0.45, -0.75]), np.array([0.1, 1.6, -0.95])], [0.08, 0.08], bamboo, k=0)
    for yy in (0.8, 1.25):
        gd.add(Torus([0.05 * (yy - 0.45) / 1.15 * 2, yy, -0.75 - 0.2 * (yy - 0.45) / 1.15], 0.085, 0.022), hexc("4c9a32"), k=0.01)
    gd.add(Xf(Ellipsoid((0, 0, 0), (0.1, 0.3, 0.03)), [0.25, 1.6, -0.95], Rz(-45)), bamboo, k=0.02)
    t = p.g("Tail.base", step=0.05)
    t.add(Ellipsoid([0, 0.5, 1.15], (0.26, 0.24, 0.22)), white, k=0)
    return p

@pet
def Phenix():
    p = Pet("Phenix", kind="fly", hover=1.8)
    red = hexc("ff3d1f"); orange = hexc("ff8a1a"); yellow = hexc("ffd23a"); deep = hexc("c41a2a")
    BC = np.array([0, 1.6, 0.2])
    b = p.g("Body.base", step=0.07, seed=2)
    b.add(Ellipsoid(BC, (0.95, 1.1, 0.95)), red)
    b.add(Ellipsoid(BC + [0, 0.8, -0.15], (0.65, 0.5, 0.6)), red, k=0.3)
    b.paint(Ellipsoid(BC + [0, -0.15, -0.65], (0.6, 0.85, 0.45)), yellow, soft=0.2)
    def plumage(P, c):
        u = P[:, 1] * 6 + np.abs(P[:, 0]) * 3
        m = smoothstep(0.8, 0.98, np.sin(u)) * smoothstep(-0.1, 0.3, P[:, 2] - BC[2])
        return c * (1 - 0.5 * m[:, None]) + orange[None, :] * 0.5 * m[:, None]
    b.pattern(plumage)
    b.pattern(shading_variation(0.02, 0.06, 0.12, seed=3))
    HC = np.array([0, 3.0, -0.2]); HR = np.array([1.15, 1.0, 1.0])
    h = round_head(p, HC, HR, red, jowl=False)
    h.add(Ellipsoid(HC + [0, -0.25, 0.0], (1.2, 0.75, 0.95)), red, k=0.3)
    h.paint(Ellipsoid(HC + [0, -0.5, -0.7], (0.8, 0.45, 0.5)), orange, soft=0.2)
    for sx in (-1, 1):  # masque dore autour des yeux
        q, n = surf(HC, HR, sx * 0.5, HC[1] + 0.05)
        h.paint(Ellipsoid(q, (0.55, 0.42, 0.4), frame(n) @ Rz(sx * 20)), hexc("ffb21f"), soft=0.08)
    h.pattern(shading_variation(0.02, 0.06, 0.1, seed=4))
    eyes2(p, HC, HR, 0.5, HC[1] + 0.06, (0.36, 0.42, 0.21), hexc("c46a00"), hexc("fff06a"), "round", brow=-0.3, brow_col=deep, tilt=8)
    gd = p.g("Head.detail", step=0.03)
    bk = HC + [0, -0.32, -0.98]
    gd.add(RoundCone(bk, bk + [0, -0.3, -0.18], 0.17, 0.03), GOLD, k=0)
    gd.add(RoundCone(bk + [0, -0.06, 0.02], bk + [0, -0.18, -0.06], 0.1, 0.03), GOLD2, k=0.02)
    # crete de flammes (lumineuse)
    gg = p.g("Head.glow", step=0.04)
    p.glow.add("Head.glow")
    for j, (dx, h_, c) in enumerate(((0, 1.25, yellow), (-0.3, 0.95, orange), (0.3, 0.95, orange), (0, 0.9, orange))):
        a = HC + [dx, 0.75, 0.05 + j * 0.12]
        tip = a + [dx * 0.8, h_, 0.45 + j * 0.15]
        mid = (a + tip) / 2 + [dx * 0.3, 0, -0.2]
        tube(gg, [a, mid, tip], [0.2, 0.15, 0.03], c, k=0.08)
    for sx, name in ((1, "WingL"), (-1, "WingR")):
        feather_wing(p, name, BC + [sx * 0.85, 0.75, 0.1], sx, length=2.3, col=red, tip_col=yellow, n=6, spread=80, down=-5, back=0.45, width=0.28, covert_col=orange)
    # longues plumes de queue enroulees
    t = p.g("Tail.base", step=0.05, seed=9)
    for j, ang in enumerate((-30, -10, 10, 30)):
        a = BC + [0, -0.5, 0.75]
        s = math.sin(math.radians(ang)); 
        p1 = a + [s * 1.0, -0.6, 1.1]; p2 = a + [s * 1.8, 0.1, 1.9]
        pts = [bezier(a, p1, p2, u) for u in np.linspace(0, 1, 6)]
        tube(t, pts, [0.2, 0.2, 0.18, 0.15, 0.17, 0.2], red, k=0.08)
        t.add(Ellipsoid(p2 + [0, 0.05, 0.05], (0.26, 0.26, 0.26)), yellow, k=0.12)
    t.pattern(lambda P, c: c * (1 - smoothstep(1.6, 2.6, P[:, 2])[:, None]) + yellow[None, :] * smoothstep(1.6, 2.6, P[:, 2])[:, None])
    for sx, name in ((1, "LegFL"), (-1, "LegFR")):
        g = p.g(f"{name}.base", step=0.04)
        top = BC + [sx * 0.4, -1.0, -0.1]
        g.add(RoundCone(top, top + [0, -0.35, 0], 0.13, 0.1), GOLD, k=0)
        for tt in (-0.13, 0.0, 0.13):
            g.add(RoundCone(top + [0, -0.38, 0], top + [tt, -0.45, -0.28], 0.07, 0.04), GOLD, k=0.05)
        p.pivots[name] = tuple(top)
    p.pivots["Body"] = tuple(BC); p.pivots["Head"] = (0, 2.2, -0.15); p.pivots["Tail"] = tuple(BC + [0, -0.5, 0.75])
    return p

@pet
def Dragon():
    p = Pet("Dragon", kind="fly", hover=1.2)
    green = hexc("3fbf4a"); belly = hexc("f3e48a"); dark = hexc("23803a"); horn = hexc("fff1cf"); wing = hexc("8fe07a")
    BC = np.array([0, 1.55, 0.35])
    b = p.g("Body.base", step=0.07, seed=2)
    b.add(Ellipsoid(BC, (0.95, 1.05, 1.0)), green)
    b.add(Ellipsoid(BC + [0, 0.75, -0.25], (0.6, 0.5, 0.55)), green, k=0.3)
    # ventre a plaques
    b.add(Ellipsoid(BC + [0, -0.05, -0.35], (0.72, 0.9, 0.7)), belly, k=0.08)
    def plates(P, c):
        m = smoothstep(0.75, 0.9, np.sin(P[:, 1] * 9.0)) * smoothstep(-0.3, -0.75, P[:, 2] - BC[2]) * (1 - smoothstep(0.4, 0.6, np.abs(P[:, 0])))
        return c * (1 - 0.35 * m[:, None]) + hexc("d9b84a")[None, :] * 0.35 * m[:, None]
    b.pattern(plates)
    def scales(P, c):
        u = np.sin(P[:, 0] * 11 + np.floor(P[:, 1] * 5.5) * 1.6) * np.sin(P[:, 1] * 17.3)
        m = smoothstep(0.55, 0.85, u) * smoothstep(-0.2, 0.2, P[:, 2] - BC[2] + 0.3)
        return c * (1 - 0.25 * m[:, None]) + dark[None, :] * 0.25 * m[:, None]
    b.pattern(scales)
    for j in range(4):  # pics du dos
        a = BC + [0, 1.0 - j * 0.32, 0.25 + j * 0.3]
        b.add(RoundCone(a, a + [0, 0.32, 0.2], 0.15, 0.03), horn if False else dark, k=0.05)
    b.pattern(shading_variation(0.02, 0.06, 0.12, seed=3))
    HC = np.array([0, 3.0, -0.25]); HR = np.array([1.2, 1.0, 1.02])
    h = round_head(p, HC, HR, green, jowl=True)
    sn = HC + [0, -0.35, -0.75]
    h.add(Xf(RoundCone((0, 0, 0), (0, 0, -0.55), 0.55, 0.45), sn, I3, (1.0, 0.75, 1.0)), green, k=0.25)
    tip = sn + [0, 0, -0.55]
    for sx in (-1, 1):
        h.sub(Ellipsoid(tip + [sx * 0.17, 0.12, -0.36], (0.05, 0.04, 0.08)), k=0.02)
        h.paint(Ellipsoid(tip + [sx * 0.17, 0.12, -0.36], (0.07, 0.06, 0.12)), dark, soft=0.02)
    h.paint(Ellipsoid(sn + [0, -0.3, -0.3], (0.55, 0.22, 0.6)), belly, soft=0.1)
    smile(h, tip + [0, -0.12, -0.28], frame((0, -0.4, -1)), width=0.3, curve=0.35, open_=0.06, tongue_col=hexc("ff6f8e"))
    gd = p.g("Head.detail", step=0.025)
    for sx in (-1, 1):
        a = tip + [sx * 0.2, -0.12, -0.27]
        gd.add(RoundCone(a, a + [0, -0.1, 0], 0.04, 0.01), WHITE, k=0)
    h.pattern(shading_variation(0.02, 0.06, 0.1, seed=4))
    blush(h, HC, HR, 0.85, HC[1] - 0.3)
    eyes2(p, HC, HR, 0.52, HC[1] + 0.18, (0.36, 0.42, 0.21), hexc("d07a00"), hexc("ffe86a"), "slit", brow=-0.2, brow_col=dark, tilt=6)
    for sx in (-1, 1):  # cornes courbes
        a = HC + [sx * 0.45, 0.78, 0.2]
        pts = [bezier(a, a + [sx * 0.2, 0.55, 0.2], a + [sx * 0.15, 0.7, 0.7], u) for u in np.linspace(0, 1, 5)]
        tube(gd, pts, [0.16, 0.13, 0.1, 0.07, 0.03], horn, k=0.03)
    for sx, name in ((1, "EarL"), (-1, "EarR")):  # oreilles-nageoires
        g = p.g(f"{name}.base", step=0.04)
        base = HC + [sx * 0.95, 0.25, 0.1]
        g.add(Xf(RoundCone((0, 0, 0), (0, 0.6, 0), 0.22, 0.04), base, Rz(-sx * 70) @ Rx(-10), (1, 1, 0.3)), wing, k=0)
        p.pivots[name] = tuple(base); p.parents[name] = "Head"
    for sx, name in ((1, "WingL"), (-1, "WingR")):
        g = p.g(f"{name}.base", step=0.04, seed=11)
        sh = BC + [sx * 0.7, 0.75, 0.35]
        el = sh + [sx * 0.9, 0.55, 0.25]
        tips = [el + [sx * 0.9, 0.35, 0.35], el + [sx * 1.0, -0.25, 0.45], el + [sx * 0.65, -0.8, 0.4]]
        tube(g, [sh, el], [0.13, 0.1], dark, k=0.05)
        for tp in tips:
            g.add(RoundCone(el, tp, 0.08, 0.03), dark, k=0.05)
        # membrane : surfaces fines entre les doigts
        pts_all = [sh] + [el] + tips
        for a_, b_ in ((sh, tips[2]), (tips[0], tips[1]), (tips[1], tips[2])):
            c3 = (el + a_ + b_) / 3
            n_ = np.cross(a_ - el, b_ - el); n_ /= np.linalg.norm(n_)
            u_ = (a_ + b_) / 2 - el
            L = np.linalg.norm(u_)
            R = frame(n_, u_ / L)
            w_ = np.linalg.norm(a_ - b_) / 2
            g.add(Xf(Ellipsoid((0, 0, 0), (w_ * 0.95, L * 0.62, 0.05)), el + u_ * 0.55, R), wing, k=0.06)
        p.pivots[name] = tuple(sh)
    t = p.g("Tail.base", step=0.06, seed=9)
    a = BC + [0, -0.55, 0.8]
    pts = [bezier(a, a + [0.9, -0.5, 0.6], a + [1.1, 0.4, 1.3], u) for u in np.linspace(0, 1, 7)]
    tube(t, pts, [0.42, 0.36, 0.3, 0.24, 0.18, 0.13, 0.1], green, k=0.1)
    end = pts[-1]; d = pts[-1] - pts[-2]; d /= np.linalg.norm(d)
    t.add(Xf(RoundCone((0, 0, 0), (0, 0.5, 0), 0.32, 0.03), end, frame((1, 0, 0), d), (1, 1, 0.35)), dark, k=0.05)
    for leg, sx, z in (("LegFL", 1, -0.25), ("LegFR", -1, -0.25), ("LegBL", 1, 0.55), ("LegBR", -1, 0.55)):
        g = p.g(f"{leg}.base", step=0.05)
        top = BC + [sx * 0.6, -0.55, z]
        g.add(RoundCone(top, top + [sx * 0.08, -0.6, -0.1], 0.3, 0.22), green, k=0)
        g.add(Ellipsoid(top + [sx * 0.08, -0.72, -0.25], (0.24, 0.15, 0.3)), green, k=0.1)
        gc = p.g(f"{leg}.detail", step=0.025)
        for tt in (-0.12, 0.0, 0.12):
            q = top + [sx * 0.08 + tt, -0.75, -0.52]
            gc.add(RoundCone(q, q + [0, -0.05, -0.1], 0.05, 0.012), horn, k=0)
        p.pivots[leg] = tuple(top)
    p.pivots["Body"] = tuple(BC); p.pivots["Head"] = (0, 2.2, -0.2); p.pivots["Tail"] = tuple(a)
    return p
