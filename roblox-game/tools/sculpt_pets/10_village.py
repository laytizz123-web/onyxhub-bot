# Oeuf Village : Chaton, Chiot, Lapin, Renard, Hibou, Licorne

@pet
def Chaton():
    p = Pet("Chaton")
    fur = hexc("ff9338"); cream = hexc("fff0d8"); stripe = hexc("d9600f")
    HC = np.array([0, 2.92, -0.25]); HR = np.array([1.3, 1.1, 1.1])
    h = round_head(p, HC, HR, fur)
    cheek_tufts(h, HC, HR, fur, n=1, size=0.24, length=0.45)
    cheek_tufts(h, HC, HR, cream, n=1, size=0.2, length=0.36, y=-0.62, z=-0.2)
    top_tuft(h, HC, HR, fur)
    cat_muzzle(p, h, HC, HR, cream)
    h.paint(Ellipsoid(HC + [0, -0.62, -0.9], (0.62, 0.42, 0.5)), cream, soft=0.12)
    for x, l in ((0, 0.45), (-0.36, 0.34), (0.36, 0.34)):
        a, n = surf(HC, HR, x, HC[1] + 1.02 - abs(x) * 0.3)
        b, _ = surf(HC, HR, x * 1.1, HC[1] + 1.02 - abs(x) * 0.3 - l)
        h.paint(RoundCone(a, b, 0.11, 0.03), stripe, soft=0.03)
    for sx in (-1, 1):
        for i in range(2):
            h.paint(RoundCone(HC + [sx * 1.25, 0.25 - i * 0.28, -0.1], HC + [sx * 0.95, 0.18 - i * 0.28, -0.75], 0.08, 0.02), stripe, soft=0.04)
    blush(h, HC, HR, 0.92, HC[1] - 0.3)
    h.pattern(shading_variation(0.02, 0.08, 0.1, seed=2))
    eyes2(p, HC + [0, 0, 0.02], HR, 0.56, HC[1] + 0.04, (0.4, 0.48, 0.22), hexc("2fa35a"), hexc("c6f56b"), "slit",
          brow=0.25, brow_col=mixc(fur, stripe, 0.7))
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        cat_ear(p, name, HC + [sx * 0.68, 0.72, 0.0], HC + [sx * 1.12, 1.55, 0.08], 0.5, fur, tip_col=stripe)
    BC = np.array([0, 1.3, 0.3])
    tab = tabby(fur, stripe, lambda P: smoothstep(0.0, 0.35, P[:, 2] - 0.2) * smoothstep(0.5, 1.0, P[:, 1]), freq=7.5, width=0.24)
    sit_body(p, fur, cream, cream, BC, stripe_fn=tab, toe_beans=PINK)
    curve_tail(p, [0.1, 0.4, 1.05], [0.9, 0.6, 1.75], [0.55, 1.9, 1.55], [0.26, 0.28, 0.27, 0.2], fur,
               tip_col=stripe, rings=(0.35, 0.55, 0.75), ring_col=stripe)
    return p

@pet
def Chiot():
    p = Pet("Chiot")
    fur = hexc("d39556"); light = hexc("fbe8c8"); dark = hexc("8a5428"); spot = hexc("b06e33")
    HC = np.array([0, 2.9, -0.3]); HR = np.array([1.28, 1.1, 1.08])
    h = round_head(p, HC, HR, fur)
    cheek_tufts(h, HC, HR, fur, n=1, size=0.22, length=0.3)
    top_tuft(h, HC, HR, fur, n=2, size=0.18)
    dog_muzzle(p, h, HC, HR, light, length=0.62, width=0.44, y=-0.4, open_=0.11)
    h.paint(Ellipsoid(HC + [0, -0.55, -0.95], (0.55, 0.5, 0.55)), light, soft=0.14)
    h.paint(Ellipsoid(HC + [0.0, 0.3, -1.0], (0.16, 0.6, 0.3)), light, soft=0.1)   # liste blanche du front
    h.paint(Ellipsoid(HC + [0.62, 0.25, -0.8], (0.42, 0.45, 0.4)), spot, soft=0.1)  # tache autour de l'oeil
    blush(h, HC, HR, 0.95, HC[1] - 0.25)
    h.pattern(shading_variation(0.02, 0.08, 0.1, seed=3))
    eyes2(p, HC, HR, 0.55, HC[1] + 0.1, (0.38, 0.45, 0.22), hexc("4a2a10"), hexc("c88a3a"), "round",
          brow=0.15, brow_col=dark, lash=False)
    # oreilles tombantes (pivot en haut de la tete)
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        g = p.g(f"{name}.base", step=0.05, rough=(0.004, 8), seed=4)
        top = HC + [sx * 1.0, 0.62, 0.0]
        R = Rz(sx * 22) @ Rx(-6)
        g.add(Xf(RoundCone((0, 0, 0), (0, -1.15, 0), 0.3, 0.42), top + [sx * 0.18, 0, 0], R, (1, 1, 0.4)), dark, k=0)
        g.add(Ellipsoid(top + [sx * 0.05, 0.05, 0], (0.34, 0.28, 0.26)), fur, k=0.14)
        g.pattern(shading_variation(0.03, 0.1, 0.15, seed=5))
        p.pivots[name] = tuple(top); p.parents[name] = "Head"
    # collier rouge + medaille doree
    BC = np.array([0, 1.3, 0.3])
    sit_body(p, fur, light, light, BC)
    gd = p.g("Body.detail", step=0.03)
    gd.add(Torus(BC + [0, 0.5, -0.12], 0.66, 0.09, Rx(-22)), RED, k=0)
    gd.add(Ellipsoid(BC + [0, 0.26, -0.82], (0.17, 0.17, 0.07), Rx(-15)), GOLD, k=0)
    gd.paint(Ellipsoid(BC + [-0.05, 0.31, -0.88], (0.06, 0.05, 0.06)), mixc(GOLD, WHITE, 0.7), soft=0.03)
    curve_tail(p, [0.0, 0.55, 1.05], [0.15, 1.0, 1.6], [0.35, 1.65, 1.35], [0.24, 0.22, 0.14], fur, tip_col=light, bushy=False)
    return p

@pet
def Lapin():
    p = Pet("Lapin")
    fur = hexc("fbf7fb"); pinkin = hexc("ffb3c9"); grey = hexc("e4dcea")
    HC = np.array([0, 2.85, -0.3]); HR = np.array([1.25, 1.08, 1.05])
    h = round_head(p, HC, HR, fur)
    cheek_tufts(h, HC, HR, fur, n=2, size=0.24, length=0.35)
    top_tuft(h, HC, HR, fur, n=3, size=0.15)
    mz = HC + [0, -0.48, -HR[2] * 0.86]
    for sx in (-1, 1):
        h.add(Ellipsoid(mz + [sx * 0.19, 0, 0], (0.26, 0.21, 0.2)), fur, k=0.12)
    glossy_nose(p, mz + [0, 0.16, -0.19], (0.12, 0.08, 0.07), hexc("ff86a6"))
    cat_mouth(h, mz + [0, -0.03, -0.2], frame((0, -0.15, -1)), width=0.12)
    gd = p.g("Head.detail", step=0.03)
    for sx in (-0.07, 0.07):  # dents de lapin
        gd.add(RoundBox(mz + [sx, -0.2, -0.17], (0.055, 0.075, 0.025), 0.02), WHITE, k=0)
    blush(h, HC, HR, 0.9, HC[1] - 0.28, size=0.27)
    h.pattern(shading_variation(0.015, 0.05, 0.12, seed=4))
    for sx in (-1, 1):
        whiskers(p, mz + [sx * 0.3, 0.02, -0.08], frame((0, 0, -1)), sx, n=2, length=0.6, col=grey)
    eyes2(p, HC, HR, 0.56, HC[1] + 0.06, (0.4, 0.48, 0.22), hexc("d1407a"), hexc("ffb0d4"), "round", brow=0.2, brow_col=grey)
    # longues oreilles (une un peu pliee)
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        g = p.g(f"{name}.base", step=0.05, rough=(0.003, 8), seed=6)
        base = HC + [sx * 0.42, 0.85, 0.05]
        mid = base + [sx * 0.15, 0.95, 0.12]
        tip = mid + ([sx * 0.55, 0.35, 0.1] if sx < 0 else [sx * 0.1, 0.85, 0.05])
        R = Rz(-sx * 8)
        g.add(Xf(RoundCone((0, 0, 0), (0, 1.0, 0), 0.26, 0.33), base, frame((0, 0, -1), mid - base), (1, np.linalg.norm(mid - base), 0.5)), fur, k=0)
        g.add(RoundCone(mid, tip, 0.3 * 1.0, 0.2), fur, k=0.1) if False else None
        g.add(Xf(RoundCone((0, 0, 0), (0, 1.0, 0), 0.32, 0.18), mid, frame((0, 0, -1), tip - mid), (1, np.linalg.norm(tip - mid), 0.5)), fur, k=0.12)
        g.sub(Xf(RoundCone((0, 0, 0), (0, 1.0, 0), 0.17, 0.12), base + [0, 0.2, -0.1], frame((0, 0, -1), mid - base), (1, np.linalg.norm(mid - base) * 1.05, 0.35)), k=0.05)
        g.paint(Xf(RoundCone((0, 0, 0), (0, 1.0, 0), 0.19, 0.13), base + [0, 0.15, -0.08], frame((0, 0, -1), mid - base), (1, np.linalg.norm(mid - base) * 1.1, 1.0)), pinkin, soft=0.04)
        g.paint(Xf(RoundCone((0, 0, 0), (0, 1.0, 0), 0.2, 0.1), mid, frame((0, 0, -1), tip - mid), (1, np.linalg.norm(tip - mid) * 0.9, 0.6)), pinkin, soft=0.04) if sx > 0 else None
        p.pivots[name] = tuple(base); p.parents[name] = "Head"
    BC = np.array([0, 1.25, 0.32])
    sit_body(p, fur, fur, fur, BC, body_r=(0.92, 0.98, 0.9))
    gb = p.g("LegBL.base"); gb.add(Ellipsoid([0.7, 0.16, -0.22], (0.3, 0.16, 0.62)), fur, k=0.1)
    gb = p.g("LegBR.base"); gb.add(Ellipsoid([-0.7, 0.16, -0.22], (0.3, 0.16, 0.62)), fur, k=0.1)
    t = p.g("Tail.base", step=0.05, rough=(0.012, 8), seed=7)
    t.add(Ellipsoid([0, 0.75, 1.2], (0.42, 0.42, 0.4)), fur, k=0)
    for a in range(6):
        ang = a / 6 * 2 * math.pi
        t.add(Ellipsoid([0.25 * math.cos(ang), 0.75 + 0.25 * math.sin(ang), 1.32], (0.2, 0.2, 0.2)), fur, k=0.15)
    t.pattern(shading_variation(0.03, 0.05, 0.1, seed=8))
    return p

@pet
def Renard():
    p = Pet("Renard")
    fur = hexc("ff7a1f"); white = hexc("fff6ea"); dark = hexc("3b2420"); deep = hexc("e0560c")
    HC = np.array([0, 2.9, -0.3]); HR = np.array([1.3, 1.05, 1.08])
    h = round_head(p, HC, HR, fur)
    cheek_tufts(h, HC, HR, white, n=2, size=0.26, length=0.55, y=-0.38)
    top_tuft(h, HC, HR, fur, n=2, size=0.17)
    # museau fin et pointu
    base = HC + [0, -0.4, -HR[2] * 0.6]
    h.add(Xf(RoundCone((0, 0, 0), (0, 0, -0.72), 0.42, 0.16), base, I3, (1.0, 0.75, 1.0)), white, k=0.2)
    tip = base + [0, -0.03, -0.72]
    glossy_nose(p, tip + [0, 0.05, -0.12], (0.14, 0.1, 0.1), dark)
    smile(h, tip + [0, -0.12, 0.02], frame((0, -0.5, -1)), width=0.18, curve=0.5)
    h.paint(Ellipsoid(HC + [0, -0.55, -0.9], (0.75, 0.42, 0.6)), white, soft=0.1)
    for sx in (-1, 1):
        h.paint(Ellipsoid(HC + [sx * 0.45, 0.35, -1.0], (0.15, 0.4, 0.15)), deep, soft=0.1)
    blush(h, HC, HR, 0.95, HC[1] - 0.18)
    h.pattern(shading_variation(0.02, 0.08, 0.1, seed=5))
    eyes2(p, HC, HR, 0.56, HC[1] + 0.1, (0.38, 0.44, 0.21), hexc("c27b06"), hexc("ffe07a"), "round", brow=-0.25, brow_col=deep, tilt=10)
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        cat_ear(p, name, HC + [sx * 0.66, 0.68, 0.05], HC + [sx * 1.12, 1.78, 0.1], 0.55, fur, inner=white, tip_col=dark)
    BC = np.array([0, 1.3, 0.3])
    sit_body(p, fur, white, dark, BC)
    for leg in ("LegFL", "LegFR"):
        g = p.g(f"{leg}.base")
        sx = 1 if leg.endswith("L") else -1
        g.paint(Ellipsoid([sx * 0.42, 0.5, -0.55], (0.4, 0.45, 0.45)), dark, soft=0.12)
    curve_tail(p, [0.15, 0.45, 1.05], [1.4, 0.5, 1.6], [1.25, 1.75, 1.3], [0.3, 0.52, 0.55, 0.28], fur, tip_col=white, bushy=True, n=8)
    return p

@pet
def Hibou():
    p = Pet("Hibou", kind="fly", hover=1.4)
    fur = hexc("9a6232"); light = hexc("f2dcb4"); dark = hexc("5c3517"); disc = hexc("e8c48f")
    HC = np.array([0, 3.05, -0.15]); HR = np.array([1.38, 1.12, 1.12])
    h = round_head(p, HC, HR, fur, jowl=False)
    h.add(Ellipsoid(HC + [0, -0.2, -0.05], (1.42, 0.85, 1.05)), fur, k=0.3)
    # disque facial (deux cercles clairs en relief) + sourcils en V
    for sx in (-1, 1):
        q, n = surf(HC, HR, sx * 0.55, HC[1] + 0.0)
        h.add(Ellipsoid(q + n * -0.12, (0.56, 0.6, 0.25), frame(n)), disc, k=0.2)
        a = HC + [sx * 0.12, 0.62, -1.02]; b = HC + [sx * 1.0, 0.82, -0.72]
        h.add(RoundCone(a, b, 0.13, 0.07), dark, k=0.1)
    h.paint(Ellipsoid(HC + [0, -0.75, -0.6], (0.75, 0.38, 0.6)), light, soft=0.12)
    h.pattern(shading_variation(0.02, 0.08, 0.1, seed=3))
    blush(h, HC, HR, 1.0, HC[1] - 0.42, size=0.2)
    eyes2(p, HC, HR, 0.55, HC[1] + 0.0, (0.43, 0.46, 0.23), hexc("e08a00"), hexc("ffe36a"), "round", lash=False)
    gd = p.g("Head.detail", step=0.03)
    bk = HC + [0, -0.3, -1.12]
    gd.add(RoundCone(bk, bk + [0, -0.32, -0.12], 0.17, 0.035), hexc("f0a63a"), k=0)
    gd.paint(Ellipsoid(bk + [-0.05, 0.02, -0.12], (0.05, 0.08, 0.06)), hexc("ffe0a0"), soft=0.03)
    # aigrettes (oreilles)
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        g = p.g(f"{name}.base", step=0.04, seed=5)
        base = HC + [sx * 0.85, 0.8, 0.0]
        for j, off in enumerate((-0.12, 0.08)):
            g.add(Xf(RoundCone((0, 0, 0), (0, 0.75 - j * 0.15, 0), 0.2, 0.03), base + [sx * off * 0.5, 0, off], Rz(-sx * (28 + j * 12)), (1, 1, 0.5)), fur if j == 0 else dark, k=0.06)
        p.pivots[name] = tuple(base); p.parents[name] = "Head"
    BC = np.array([0, 1.55, 0.1])
    b = p.g("Body.base", step=0.07, rough=(0.003, 6), seed=2)
    b.add(Ellipsoid(BC, (1.15, 1.2, 1.0)), fur)
    b.add(Ellipsoid(BC + [0, 0.9, -0.05], (0.8, 0.5, 0.75)), fur, k=0.3)
    b.paint(Ellipsoid(BC + [0, -0.1, -0.7], (0.8, 1.0, 0.5)), light, soft=0.15)
    def chevrons(P, c):
        u = P[:, 1] * 5.2 + np.abs(P[:, 0]) * 2.6
        m = smoothstep(0.75, 0.95, np.sin(u)) * smoothstep(-0.2, -0.5, P[:, 2] - BC[2]) * (1 - smoothstep(0.55, 0.75, np.abs(P[:, 0])))
        return c * (1 - 0.55 * m[:, None]) + mixc(fur, light, 0.3)[None, :] * 0.55 * m[:, None]
    b.pattern(chevrons)
    b.pattern(shading_variation(0.025, 0.06, 0.15, seed=3))
    for sx, name in ((1, "WingL"), (-1, "WingR")):
        feather_wing(p, name, BC + [sx * 1.0, 0.55, 0.15], sx, length=1.55, col=fur, tip_col=dark, n=5, spread=55, down=-62, back=0.3, width=0.26)
    for sx, name in ((1, "LegFL"), (-1, "LegFR")):
        g = p.g(f"{name}.base", step=0.04)
        top = BC + [sx * 0.42, -1.0, -0.2]
        g.add(RoundCone(top, top + [0, -0.3, -0.05], 0.18, 0.13), hexc("f2a03d"), k=0)
        for t in (-0.15, 0.0, 0.15):
            g.add(RoundCone(top + [0, -0.33, -0.05], top + [t, -0.38, -0.32], 0.09, 0.05), hexc("f2a03d"), k=0.06)
        gd2 = p.g(f"{name}.detail", step=0.025)
        for t in (-0.15, 0.0, 0.15):
            a = top + [t * 1.05, -0.38, -0.33]
            gd2.add(RoundCone(a, a + [0, -0.08, -0.08], 0.045, 0.012), dark, k=0)
        p.pivots[name] = tuple(top)
    t = p.g("Tail.base", step=0.05)
    for j, a in enumerate((-25, 0, 25)):
        d = np.array([math.sin(math.radians(a)) * 0.6, -0.45, 1.0])
        t.add(Xf(RoundCone((0, 0, 0), (0, 0.85, 0), 0.22, 0.14), BC + [0, -0.55, 0.75], frame((0, 1, 0), d), (1, 1, 0.35)), fur, k=0.05)
    t.pattern(lambda P, c: c * (1 - 0.4 * smoothstep(1.4, 1.9, P[:, 2])[:, None]) + dark[None, :] * 0.4 * smoothstep(1.4, 1.9, P[:, 2])[:, None])
    p.pivots["Body"] = tuple(BC); p.pivots["Head"] = (0, 2.25, -0.1); p.pivots["Tail"] = tuple(BC + [0, -0.5, 0.7])
    return p

@pet
def Licorne():
    p = Pet("Licorne")
    fur = hexc("fff0f7"); muzzle = hexc("fde6f0"); hoof = GOLD
    manes = [hexc("ff6fb5"), hexc("c58bff"), hexc("7fc8ff"), hexc("ffb36b"), hexc("ff8fd1")]
    BC = np.array([0, 1.8, 0.45])
    stand_body(p, fur, belly=hexc("fbe3f0"), hoof=hoof, BC=BC, body_r=(0.85, 0.78, 1.15), leg_len=1.2)
    HC = np.array([0, 3.35, -0.55]); HR = np.array([1.12, 1.0, 1.05])
    h = round_head(p, HC, HR, fur)
    mz = HC + [0, -0.48, -0.75]
    h.add(Ellipsoid(mz, (0.6, 0.44, 0.5)), muzzle, k=0.3)
    for sx in (-1, 1):
        h.sub(Ellipsoid(mz + [sx * 0.2, 0.06, -0.47], (0.045, 0.06, 0.08)), k=0.03)
        h.paint(Ellipsoid(mz + [sx * 0.2, 0.06, -0.47], (0.06, 0.075, 0.12)), hexc("e7a3bf"), soft=0.02)
    smile(h, mz + [0, -0.2, -0.43], frame((0, -0.3, -1)), width=0.2, curve=0.4)
    blush(h, HC, HR, 0.82, HC[1] - 0.25, size=0.25)
    h.pattern(shading_variation(0.015, 0.06, 0.1, seed=4))
    eyes2(p, HC, HR, 0.5, HC[1] + 0.1, (0.36, 0.45, 0.21), hexc("8a3fd1"), hexc("f0b8ff"), "round", brow=0.2, brow_col=hexc("f7c6dd"))
    # cils longs supplementaires
    gd = p.g("Head.detail", step=0.025)
    for sx in (-1, 1):
        q, n = surf(HC, HR, sx * 0.86, HC[1] + 0.3)
        for j in range(2):
            gd.add(RoundCone(q, q + [sx * (0.2 + j * 0.06), 0.06 + j * 0.1, -0.02], 0.035, 0.012), BLACK, k=0)
    # corne doree en spirale
    hb = HC + [0, 0.85, -0.55]
    ht = hb + [0, 1.05, -0.35]
    gd2 = p.g("Head.detail", step=0.025)
    gd2.add(RoundCone(hb, ht, 0.2, 0.035), GOLD, k=0)
    for j in range(4):
        q = hb + (ht - hb) * (0.12 + j * 0.2)
        gd2.add(Torus(q, 0.17 * (1 - j * 0.2), 0.035, frame((0, 0, -1), ht - hb) @ Rx(90) @ Rz(18)), GOLD2, k=0.02)
    # diademe avec pierre
    gem(gd2, HC + [0, 0.5, -1.02], 0.11, hexc("ff4fae"), frame((0, 0.3, -1)))
    # criniere pastel (meches sur la tete et la nuque)
    for j in range(8):
        a = HC + [0.15, 0.95 - j * 0.24, 0.1 + j * 0.2]
        b = a + [0.55, -0.35 - j * 0.03, 0.25]
        h.add(RoundCone(a, b, 0.34 - j * 0.015, 0.07), manes[j % len(manes)], k=0.1)
        if j < 5:
            h.add(RoundCone(a + [-0.2, 0, 0], a + [-0.45, -0.2, 0.3], 0.26, 0.06), manes[(j + 2) % len(manes)], k=0.1)
    for sx in (-1, 1):
        h.add(RoundCone(HC + [sx * 0.3, 0.8, -0.65], HC + [sx * 0.6, 0.35, -1.0], 0.2, 0.05), manes[0 if sx > 0 else 1], k=0.08)
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        cat_ear(p, name, HC + [sx * 0.55, 0.72, 0.1], HC + [sx * 0.8, 1.35, 0.2], 0.27, fur, inner=hexc("ffb6d5"))
    # queue arc-en-ciel
    t = p.g("Tail.base", step=0.06, seed=9)
    for j, c in enumerate(manes[:4]):
        off = (j - 1.5) * 0.12
        pts = [bezier(BC + [off, 0.3, 1.1], BC + [off * 2 + 0.2, 0.0, 1.9], BC + [off * 3 + 0.3, -1.1, 1.7], s) for s in np.linspace(0, 1, 6)]
        tube(t, pts, [0.2, 0.26, 0.28, 0.26, 0.2, 0.08], c, k=0.12)
    # collier dore + pierre
    gb = p.g("Body.detail", step=0.03)
    gb.add(Torus(BC + [0, 0.62, -0.95], 0.5, 0.06, Rx(-40)), GOLD, k=0)
    gem(gb, BC + [0, 0.32, -1.33], 0.12, hexc("7fc8ff"), frame((0, -0.2, -1)))
    p.pivots["Head"] = tuple(BC + [0, 0.95, -0.85])
    return p
