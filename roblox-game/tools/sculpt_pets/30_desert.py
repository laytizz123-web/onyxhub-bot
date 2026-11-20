# Oeuf Desert : Scorpion, Chameau, Cobra, Lezard, Sphinx, Genie, Pharaon

LAPIS = hexc("1f4fbf"); TURQ = hexc("27c2c9"); CARN = hexc("d4342c")

def usekh(g, c, R_out, R_in, rows, tilt=-25, thick=0.07):
    """Collier egyptien large (anneaux colores successifs)."""
    for i, col in enumerate(rows):
        r = R_in + (R_out - R_in) * i / max(len(rows) - 1, 1)
        g.add(Torus(np.asarray(c) + [0, -i * 0.06, -i * 0.025], r, thick, Rx(tilt)), col, k=0.02)

@pet
def Scorpion():
    p = Pet("Scorpion", kind="crawl")
    shell = hexc("a8652e"); light = hexc("e3a764"); dark = hexc("5e3416")
    BC = np.array([0, 0.75, 0.3])
    b = p.g("Body.base", step=0.06, seed=2)
    for i in range(4):  # segments du dos
        b.add(Ellipsoid(BC + [0, 0.05 - i * 0.03, -0.1 + i * 0.42], (0.95 - i * 0.1, 0.5 - i * 0.04, 0.42)), shell, k=0.1)
    def bands(P, c):
        m = 1 - smoothstep(0.0, 0.07, np.abs(((P[:, 2] - BC[2] + 0.1) % 0.42) - 0.21))
        m = m * smoothstep(0.85, 1.05, P[:, 1])
        return c * (1 - 0.0 * m[:, None]) + dark[None, :] * 0.0 * m[:, None]
    b.paint(Ellipsoid(BC + [0, 0.35, 0.4], (0.55, 0.3, 1.0)), light, soft=0.2)
    for i in range(1, 4):
        b.sub(Torus(BC + [0, 0.0, -0.1 + i * 0.42 - 0.21], 0.86 - i * 0.08, 0.04), k=0.04)
    b.pattern(shading_variation(0.02, 0.1, 0.15, seed=3))
    HC = np.array([0, 1.25, -0.45]); HR = np.array([0.98, 0.72, 0.72])
    h = p.g("Head.base", step=0.055, seed=1)
    h.add(Ellipsoid(HC, HR), shell)
    h.paint(Ellipsoid(HC + [0, 0.45, 0.1], (0.6, 0.3, 0.5)), light, soft=0.15)
    smile(h, HC + [0, -0.35, -0.68], frame((0, -0.4, -1)), width=0.22, curve=0.4)
    blush(h, HC, HR, 0.68, HC[1] - 0.18, size=0.18)
    h.pattern(shading_variation(0.02, 0.08, 0.1, seed=4))
    eyes2(p, HC, HR, 0.38, HC[1] + 0.08, (0.3, 0.36, 0.18), hexc("1a1a1a"), hexc("8a5a2a"), "round", brow=-0.25, brow_col=dark, tilt=5)
    # pinces articulees (groupes WingL / WingR)
    for sx, name in ((1, "WingL"), (-1, "WingR")):
        g = p.g(f"{name}.base", step=0.045, seed=7)
        sh = HC + [sx * 0.75, -0.25, 0.2]
        el = sh + [sx * 0.55, 0.0, -0.45]
        wr = el + [-sx * 0.1, 0.1, -0.55]
        tube(g, [sh, el, wr], [0.17, 0.15, 0.18], shell, k=0.06)
        claw = wr + [0, 0.05, -0.35]
        g.add(Ellipsoid(claw, (0.33, 0.24, 0.42)), shell, k=0.1)
        g.add(Xf(RoundCone((0, 0, 0), (0, 0.65, 0), 0.16, 0.04), claw + [sx * 0.12, 0.08, -0.15], frame((0, 1, 0), [-sx * 0.25, 0.1, -1]), (1, 1, 0.65)), shell, k=0.06)
        g.add(Xf(RoundCone((0, 0, 0), (0, 0.55, 0), 0.13, 0.035), claw + [-sx * 0.1, -0.06, -0.15], frame((0, 1, 0), [sx * 0.25, -0.05, -1]), (1, 1, 0.65)), light, k=0.06)
        g.sub(Ellipsoid(claw + [0, 0.0, -0.62], (0.08, 0.06, 0.22)), k=0.05)
        g.pattern(shading_variation(0.02, 0.08, 0.1, seed=8))
        p.pivots[name] = tuple(sh)
    # 8 pattes (2 par groupe)
    for name, sx, zs in (("LegFL", 1, (-0.1, 0.3)), ("LegFR", -1, (-0.1, 0.3)), ("LegBL", 1, (0.7, 1.1)), ("LegBR", -1, (0.7, 1.1))):
        g = p.g(f"{name}.base", step=0.04)
        for z in zs:
            a = np.array([sx * 0.6, 0.65, z])
            k_ = a + [sx * 0.55, 0.25, 0.05]
            f_ = k_ + [sx * 0.3, -0.85, 0.05]
            tube(g, [a, k_, f_], [0.1, 0.09, 0.05], dark if z > 0.5 else shell, k=0.04)
        p.pivots[name] = (sx * 0.6, 0.7, sum(zs) / 2)
    # queue recourbee + dard
    t = p.g("Tail.base", step=0.05, seed=9)
    a = BC + [0, 0.1, 1.35]
    pts = [a, a + [0, 0.55, 0.4], a + [0, 1.25, 0.35], a + [0, 1.85, 0.0], a + [0, 2.05, -0.5]]
    rr = [0.3, 0.28, 0.25, 0.22, 0.2]
    for i in range(len(pts) - 1):
        t.add(Ellipsoid((pts[i] + pts[i + 1]) / 2, (rr[i], rr[i] * 1.0, np.linalg.norm(pts[i + 1] - pts[i]) * 0.6), frame(pts[i + 1] - pts[i] + [0, 0, 1e-3], [1, 0, 0]) if False else I3), shell, k=0.06)
    tube(t, pts, rr, shell, k=0.08)
    bulb = pts[-1] + [0, -0.05, -0.15]
    t.add(Ellipsoid(bulb, (0.27, 0.25, 0.3)), light, k=0.08)
    gd = p.g("Tail.detail", step=0.025)
    gd.add(RoundCone(bulb + [0, -0.05, -0.2], bulb + [0, -0.4, -0.45], 0.1, 0.012), hexc("3a1f0e"), k=0)
    t.pattern(shading_variation(0.02, 0.08, 0.1, seed=10))
    p.pivots["Body"] = tuple(BC); p.pivots["Head"] = (0, 1.1, -0.2); p.pivots["Tail"] = tuple(a)
    return p

@pet
def Chameau():
    p = Pet("Chameau")
    fur = hexc("e2b97a"); light = hexc("f6e3bf"); dark = hexc("a8743c")
    BC = np.array([0, 1.9, 0.45])
    b = stand_body(p, fur, belly=light, hoof=hexc("8a5a2a"), BC=BC, body_r=(0.85, 0.75, 1.2), leg_r=(0.25, 0.18))
    b.add(Ellipsoid(BC + [0, 0.75, -0.3], (0.5, 0.55, 0.45)), fur, k=0.3)   # bosses
    b.add(Ellipsoid(BC + [0, 0.7, 0.6], (0.48, 0.5, 0.42)), fur, k=0.3)
    gd = p.g("Body.detail", step=0.035)
    # couverture de selle rouge a motifs + franges dorees
    blanket = Xf(Ellipsoid((0, 0, 0), (0.96, 0.6, 0.8)), BC + [0, 0.42, 0.15], I3, (1, 1, 1))
    gd.add(blanket, CARN, k=0)
    gd.sub(Ellipsoid(BC + [0, -0.55, 0.15], (2, 0.95, 2)), k=0.02)
    gd.sub(Ellipsoid(BC + [0, 1.0, -0.3], (0.42, 0.5, 0.38)), k=0.04)
    gd.sub(Ellipsoid(BC + [0, 1.0, 0.6], (0.42, 0.45, 0.36)), k=0.04)
    def motif(P, c):
        y = P[:, 1] - BC[1]
        m1 = 1 - smoothstep(0.03, 0.07, np.abs(y - 0.05))
        m2 = (1 - smoothstep(0.05, 0.1, np.abs(y - 0.22))) * smoothstep(0.3, 0.6, np.sin(P[:, 2] * 14 + np.abs(P[:, 0]) * 3))
        c = c * (1 - m1[:, None]) + GOLD[None, :] * m1[:, None]
        return c * (1 - m2[:, None]) + LAPIS[None, :] * m2[:, None]
    gd.pattern(motif)
    for i in range(10):
        z = BC[2] - 0.6 + i * 0.15
        for sx in (-1, 1):
            q = np.array([sx * 0.92, BC[1] - 0.12, z])
            gd.add(Ellipsoid(q, (0.05, 0.08, 0.05)), GOLD, k=0.01)
    HC = np.array([0, 3.55, -0.85]); HR = np.array([0.95, 0.85, 0.95])
    h = round_head(p, HC, HR, fur)
    mz = HC + [0, -0.38, -0.65]
    h.add(Ellipsoid(mz, (0.5, 0.42, 0.5)), light, k=0.28)
    h.add(Ellipsoid(mz + [0, -0.2, -0.15], (0.36, 0.2, 0.3)), light, k=0.12)   # levre pendante
    for sx in (-1, 1):
        h.sub(Ellipsoid(mz + [sx * 0.17, 0.12, -0.45], (0.05, 0.03, 0.08), Rz(sx * 25)), k=0.02)
        h.paint(Ellipsoid(mz + [sx * 0.17, 0.12, -0.45], (0.07, 0.05, 0.12), Rz(sx * 25)), dark, soft=0.02)
    smile(h, mz + [0, -0.12, -0.46], frame((0, -0.3, -1)), width=0.2, curve=0.35)
    top_tuft(h, HC, HR, dark, n=3, size=0.17)
    blush(h, HC, HR, 0.7, HC[1] - 0.2)
    h.pattern(shading_variation(0.02, 0.06, 0.1, seed=4))
    eyes2(p, HC, HR, 0.42, HC[1] + 0.1, (0.32, 0.4, 0.19), hexc("4a2810"), hexc("c08a4a"), "round", lid=8, brow_col=fur)
    for sx, name in ((1, "EarL"), (-1, "EarR")):
        round_ear(p, name, HC + [sx * 0.72, 0.55, 0.15], 0.2, fur, inner=hexc("e8a68a"))
    # long cou
    b.add(RoundCone(BC + [0, 0.6, -0.95], HC + [0, -0.5, 0.25], 0.48, 0.38), fur, k=0.2)
    t = p.g("Tail.base", step=0.04)
    a = BC + [0, 0.3, 1.2]
    tube(t, [a, a + [0, -0.5, 0.2]], [0.09, 0.08], fur, k=0)
    t.add(Ellipsoid(a + [0, -0.65, 0.22], (0.15, 0.22, 0.15)), dark, k=0.06)
    p.pivots["Head"] = tuple(BC + [0, 0.7, -1.0]); p.pivots["Tail"] = tuple(a)
    return p

@pet
def Cobra():
    p = Pet("Cobra", kind="slither")
    green = hexc("34b24a"); belly = hexc("f2e48c"); dark = hexc("1d6e33"); hood_in = hexc("f7d65a")
    b = p.g("Body.base", step=0.065, seed=2)
    # anneaux enroules au sol
    pts = []
    for i in range(22):
        a = i / 21 * 2 * math.pi * 1.35
        r = 1.05 - i / 21 * 0.25
        pts.append(np.array([r * math.cos(a), 0.36 + i * 0.012, 0.25 + r * math.sin(a)]))
    rr = list(np.linspace(0.38, 0.4, len(pts)))
    tube(b, pts, rr, green, k=0.1)
    # cou qui se dresse
    a = pts[-1]
    neck = [a, a + [0.15, 0.55, -0.25], np.array([0, 1.75, -0.35]), np.array([0, 2.35, -0.35])]
    tube(b, neck, [0.4, 0.38, 0.34, 0.32], green, k=0.12)
    def scale_pat(P, c):
        u = np.sin(P[:, 0] * 13) * np.sin(P[:, 2] * 13 + P[:, 1] * 7)
        m = smoothstep(0.5, 0.9, u) * 0.3
        return c * (1 - m[:, None]) + dark[None, :] * m[:, None]
    b.pattern(scale_pat)
    b.paint(Capsule([0, 1.0, -0.72], [0, 2.3, -0.62], 0.28), belly, soft=0.08)
    b.pattern(shading_variation(0.02, 0.1, 0.15, seed=3))
    HC = np.array([0, 2.95, -0.45]); HR = np.array([0.95, 0.75, 0.85])
    h = p.g("Head.base", step=0.055, seed=1)
    h.add(Ellipsoid(HC, HR), green)
    h.add(Ellipsoid(HC + [0, -0.18, -0.45], (0.75, 0.5, 0.6)), green, k=0.2)
    # capuchon deploye derriere la tete
    hood = Xf(Ellipsoid((0, 0, 0), (1.45, 1.35, 0.28)), HC + [0, -0.55, 0.45], Rx(-12))
    h.add(hood, green, k=0.15)
    h.paint(Xf(Ellipsoid((0, 0, 0), (1.1, 1.0, 0.5)), HC + [0, -0.6, 0.3], Rx(-12)), hood_in, soft=0.1)
    for sx in (-1, 1):  # motif "lunettes" du capuchon
        h.paint(Torus(HC + [sx * 0.62, -0.5, 0.18], 0.2, 0.06, Rx(80)), dark, soft=0.03)
    h.paint(Ellipsoid(HC + [0, -0.45, -0.85], (0.5, 0.25, 0.4)), belly, soft=0.1)
    smile(h, HC + [0, -0.38, -1.02], frame((0, -0.3, -1)), width=0.3, curve=0.3)
    for sx in (-1, 1):
        h.sub(Ellipsoid(HC + [sx * 0.15, -0.05, -1.08], (0.04, 0.03, 0.06)), k=0.01)
    blush(h, HC, HR, 0.62, HC[1] - 0.2, size=0.18)
    h.pattern(shading_variation(0.02, 0.06, 0.1, seed=4))
    eyes2(p, HC, HR, 0.38, HC[1] + 0.15, (0.32, 0.38, 0.19), hexc("c79a00"), hexc("fff27a"), "slit", brow=-0.3, brow_col=dark, tilt=8)
    gd = p.g("Head.detail", step=0.025)
    tg = HC + [0, -0.4, -1.03]
    tube(gd, [tg, tg + [0, -0.06, -0.3]], [0.035, 0.03], hexc("e8334a"), k=0)
    for sx in (-1, 1):
        gd.add(RoundCone(tg + [0, -0.06, -0.3], tg + [sx * 0.08, -0.12, -0.42], 0.03, 0.01), hexc("e8334a"), k=0.01)
    gd.add(Torus(HC + [0, 0.6, 0.1], 0.32, 0.05, Rx(-15)), GOLD, k=0)   # petit anneau dore (bijou)
    gem(gd, HC + [0, 0.62, -0.62], 0.11, CARN, frame((0, 0.5, -1)))
    t = p.g("Tail.base", step=0.05)
    a = pts[0]
    tube(t, [a, a + [0.0, 0.0, 0.6], a + [-0.35, 0.25, 0.95]], [0.36, 0.22, 0.06], green, k=0.08)
    p.pivots["Body"] = (0, 0.4, 0.2); p.pivots["Head"] = (0, 2.3, -0.35); p.pivots["Tail"] = tuple(a)
    return p

@pet
def Lezard():
    p = Pet("Lezard")
    green = hexc("8fe05a"); belly = hexc("f2f7b0"); spot = hexc("4fa83a"); crest = hexc("ff9a3a")
    BC = np.array([0, 0.95, 0.4])
    b = p.g("Body.base", step=0.065, seed=2)
    b.add(Ellipsoid(BC, (0.85, 0.62, 1.2)), green)
    b.add(Ellipsoid(BC + [0, 0.25, -0.85], (0.6, 0.5, 0.55)), green, k=0.3)
    b.paint(Ellipsoid(BC + [0, -0.45, 0], (0.65, 0.3, 1.1)), belly, soft=0.15)
    rng = np.random.RandomState(5)
    for i in range(14):
        x = (rng.rand() - 0.5) * 1.2; z = BC[2] - 0.8 + rng.rand() * 1.8
        b.paint(Ellipsoid([x, BC[1] + 0.55 - abs(x) * 0.5, z], (0.1, 0.06, 0.1)), spot, soft=0.03)
    for j in range(6):  # petite crete orange
        a = BC + [0, 0.58 - j * 0.02, -0.75 + j * 0.32]
        b.add(Xf(RoundCone((0, 0, 0), (0, 0.32, 0), 0.12, 0.03), a, Rx(25), (0.45, 1, 1)), crest, k=0.04)
    b.pattern(shading_variation(0.02, 0.08, 0.12, seed=3))
    HC = np.array([0, 2.05, -0.85]); HR = np.array([1.08, 0.9, 1.0])
    h = round_head(p, HC, HR, green)
    h.add(Ellipsoid(HC + [0, -0.3, -0.55], (0.85, 0.5, 0.6)), green, k=0.25)
    h.paint(Ellipsoid(HC + [0, -0.6, -0.5], (0.7, 0.25, 0.7)), belly, soft=0.1)
    smile(h, HC + [0, -0.38, -1.1], frame((0, -0.2, -1)), width=0.45, curve=0.3, open_=0.07, tongue_col=hexc("ff6f8e"))
    for sx in (-1, 1):
        h.sub(Ellipsoid(HC + [sx * 0.16, -0.05, -1.15], (0.035, 0.03, 0.06)), k=0.01)
    for j in range(3):
        a = HC + [0, 0.85 - j * 0.05, -0.2 + j * 0.3]
        h.add(Xf(RoundCone((0, 0, 0), (0, 0.38, 0), 0.13, 0.03), a, Rx(20), (0.45, 1, 1)), crest, k=0.04)
    blush(h, HC, HR, 0.8, HC[1] - 0.25)
    h.pattern(shading_variation(0.02, 0.06, 0.1, seed=4))
    eyes2(p, HC + [0, 0.1, 0], HR, 0.48, HC[1] + 0.28, (0.38, 0.44, 0.22), hexc("d06a00"), hexc("ffd84a"), "slit", brow=0.25, brow_col=spot)
    # pattes ecartees sur les cotes
    for name, sx, z in (("LegFL", 1, -0.4), ("LegFR", -1, -0.4), ("LegBL", 1, 1.0), ("LegBR", -1, 1.0)):
        g = p.g(f"{name}.base", step=0.05)
        a = np.array([sx * 0.6, 0.95, z])
        k_ = a + [sx * 0.45, -0.1, 0]
        f_ = k_ + [sx * 0.1, -0.65, -0.05]
        tube(g, [a, k_, f_], [0.24, 0.2, 0.16], green, k=0.1)
        for tt in (-0.4, 0, 0.4):
            d = np.array([sx * math.sin(tt) * 0.3, -0.05, -math.cos(tt) * 0.3])
            g.add(RoundCone(f_ + [0, -0.12, 0], f_ + [0, -0.15, 0] + d, 0.08, 0.06), green, k=0.05)
        p.pivots[name] = tuple(a)
    curve_tail(p, BC + [0, -0.1, 1.05], BC + [0.2, -0.6, 2.3], BC + [1.3, -0.65, 2.2], [0.42, 0.3, 0.18, 0.08], green, n=8)
    p.parts["Tail.base"].paint(Ellipsoid(BC + [0.9, -0.5, 2.3], (0.2, 0.15, 0.2)), spot, soft=0.05)
    p.pivots["Body"] = tuple(BC); p.pivots["Head"] = tuple(BC + [0, 0.4, -0.9]); p.pivots["Tail"] = tuple(BC + [0, -0.1, 1.05])
    return p
