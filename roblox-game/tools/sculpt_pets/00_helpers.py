# Briques communes de sculpture (execute dans l'espace de noms de pets_sculpt).

def smile(g, c, R, width=0.2, depth=0.1, col=MOUTH, open_=0.0, tongue_col=None, curve=0.45):
    """Sourire creuse en arc (+ bouche ouverte optionnelle avec langue)."""
    pts = [c + R @ np.array([x * width, -curve * width * (1 - x * x) + curve * width * 0.5, 0]) for x in np.linspace(-1, 1, 7)]
    for i in range(len(pts) - 1):
        g.sub(Capsule(pts[i], pts[i + 1], 0.032), k=0.015)
        g.paint(Capsule(pts[i], pts[i + 1], 0.065), col, soft=0.02)
    if open_ > 0:
        m = c + R @ np.array([0, -width * 0.15, 0])
        g.sub(Ellipsoid(m, (width * 0.62, open_, depth * 1.4), R), k=0.04)
        g.paint(Ellipsoid(m, (width * 0.7, open_ * 1.15, depth * 2.2), R), col, soft=0.03)
        if tongue_col is not None:
            g.paint(Ellipsoid(m + R @ np.array([0, -open_ * 0.55, 0]), (width * 0.45, open_ * 0.55, depth * 2.5), R), tongue_col, soft=0.03)

def glossy_nose(p, c, size, col, group="Head", R=None):
    R = frame((0, -0.2, -1)) if R is None else R
    gd = p.g(f"{group}.detail", step=0.03)
    gd.add(Ellipsoid(c, size, R), col, k=0)
    gd.add(Ellipsoid(c + R @ np.array([-size[0] * 0.3, size[1] * 0.35, -size[2] * 0.8]), (size[0] * 0.28, size[1] * 0.2, 0.03), R), mixc(col, WHITE, 0.75), k=0)

def eyes2(p, HC, HR, dx, y, size, iris, iris2=None, pupil="round", lash=True, brow=None, brow_col=None, sink=0.5, lid=None, tilt=0.0):
    for sx in (-1, 1):
        eye(p, HC, HR, HC[0] + sx * dx, y, size=size, iris=iris, iris2=iris2, pupil=pupil, lash=lash,
            brow=brow, brow_col=brow_col, sink=sink, lid=lid, tilt=-sx * tilt)
    # orbites : les yeux se logent dans la tete
    h = p.g("Head.base")
    for sx in (-1, 1):
        q, n = surf(HC, HR, HC[0] + sx * dx, y)
        h.sub(Ellipsoid(q + n * 0.02, (size[0] * 0.95, size[1] * 0.95, 0.12), frame(n)), k=0.1)

def round_head(p, HC, HR, fur, jowl=True, step=0.065, rough=0.004, seed=1):
    h = p.g("Head.base", step=step, rough=(rough, 7), seed=seed)
    h.add(Ellipsoid(HC, HR), fur)
    if jowl:
        h.add(Ellipsoid(HC + [0, -HR[1] * 0.32, 0.02], (HR[0] * 1.03, HR[1] * 0.65, HR[2] * 0.9)), fur, k=0.25)
    return h

def cheek_tufts(h, HC, HR, col, n=2, size=0.22, length=0.45, y=-0.42, z=-0.15):
    for sx in (-1, 1):
        for i in range(n):
            a = HC + [sx * HR[0] * 0.82, y * HR[1] - i * 0.24, z + i * 0.05]
            b = a + [sx * length * (1 - i * 0.2), -0.22 - i * 0.05, 0.08]
            h.add(RoundCone(a, b, size * (1 - i * 0.15), 0.035), col, k=0.15)

def top_tuft(h, HC, HR, col, n=1, size=0.22):
    for i in range(n):
        off = (i - (n - 1) / 2) * 0.22
        a = HC + [off, HR[1] * 0.72, 0.02]
        h.add(RoundCone(a, a + [off * 0.8 + 0.1, 0.48 - abs(off), 0.15], size, 0.03), col, k=0.16)

def cat_muzzle(p, h, HC, HR, cream, nose_col=hexc("ff7d97"), whisk=WHITE, y=-0.5, dy=0.0):
    mz = HC + [0, y, -HR[2] * 0.86]
    for sx in (-1, 1):
        h.add(Ellipsoid(mz + [sx * 0.2, 0, 0], (0.27, 0.2, 0.2)), cream, k=0.12)
    h.add(Ellipsoid(mz + [0, -0.24, 0.1], (0.24, 0.16, 0.16)), cream, k=0.1)
    nose_c = mz + [0, 0.17, -0.2]
    gd = p.g("Head.detail", step=0.03)
    gd.add(Xf(RoundCone((0, 0.05, 0), (0, -0.07, 0), 0.12, 0.04), nose_c, frame((0, -0.25, -1)), (1.15, 1, 0.75)), nose_col, k=0)
    gd.add(Ellipsoid(nose_c + [-0.04, 0.05, -0.08], (0.045, 0.025, 0.02)), mixc(nose_col, WHITE, 0.7), k=0)
    cat_mouth(h, nose_c + [0, -0.19, 0.02], frame((0, -0.15, -1)), width=0.13)
    if whisk is not None:
        for sx in (-1, 1):
            whiskers(p, mz + [sx * 0.32, 0.02, -0.1], frame((0, 0, -1)), sx, n=3, length=0.72, col=whisk)
    return mz

def dog_muzzle(p, h, HC, HR, col, nose_col=NOSE, length=0.55, width=0.42, y=-0.45, tongue=True, open_=0.09, nose_size=(0.2, 0.14, 0.14)):
    base = HC + [0, y, -HR[2] * 0.62]
    tip = base + [0, -0.08, -length]
    h.add(Xf(RoundCone((0, 0, 0), (0, 0, -length), width, width * 0.72), base, I3, (1.0, 0.8, 1.0)), col, k=0.18)
    for sx in (-1, 1):
        h.add(Ellipsoid(tip + [sx * width * 0.42, -0.06, 0.12], (width * 0.5, width * 0.42, width * 0.45)), col, k=0.12)
    r = width * 0.72
    nose_c = tip + [0, r * 0.45, -r * 0.82]
    glossy_nose(p, nose_c, nose_size, nose_col)
    mR = frame((0, -0.45, -1))
    smile(h, tip + [0, -r * 0.35, -r * 0.9], mR, width=width * 0.5, open_=open_, tongue_col=hexc("ff7d97") if tongue else None, curve=0.5)
    return tip

def bear_muzzle(p, h, HC, HR, col, nose_col=NOSE, y=-0.42, size=(0.5, 0.38, 0.36), open_=0.06):
    mz = HC + [0, y, -HR[2] * 0.84]
    h.add(Ellipsoid(mz, size), col, k=0.16)
    glossy_nose(p, mz + [0, size[1] * 0.45, -size[2] * 0.82], (0.2, 0.13, 0.12), nose_col)
    smile(h, mz + [0, -size[1] * 0.25, -size[2] * 0.92], frame((0, -0.2, -1)), width=0.2, open_=open_, tongue_col=hexc("ff7d97"))
    return mz

def pointed_ear(p, name, base, tip, w, fur, inner=PINK, tip_col=None, tuft=None, depth=0.42):
    cat_ear(p, name, base, tip, w, fur, inner=inner, tuft=tuft, tip_col=tip_col)

def round_ear(p, name, c, r, fur, inner=None, step=0.045):
    g = p.g(f"{name}.base", step=step, rough=(0.003, 9), seed=4)
    c = np.asarray(c, float)
    g.add(Ellipsoid(c, (r, r, r * 0.55)), fur, k=0)
    if inner is not None:
        g.sub(Ellipsoid(c + [0, -0.03, -r * 0.42], (r * 0.62, r * 0.6, r * 0.3)), k=0.05)
        g.paint(Ellipsoid(c + [0, -0.03, -r * 0.4], (r * 0.66, r * 0.64, r * 0.5)), inner, soft=0.04)
    p.pivots[name] = tuple(c + [0, -r * 0.6, 0])
    p.parents[name] = "Head"

def sit_body(p, fur, chest=None, paw=None, BC=(0, 1.3, 0.3), chest_fluff=True, stripe_fn=None, rough=0.005,
             body_r=(0.88, 1.0, 0.85), thigh_col=None, claws=None, toe_beans=None):
    """Corps assis organique + 4 pattes separees (cuisses rondes, pattes avant, coussinets, doigts)."""
    BC = np.asarray(BC, float)
    chest = chest if chest is not None else fur
    paw = paw if paw is not None else fur
    b = p.g("Body.base", step=0.075, rough=(rough, 6), seed=2)
    b.add(Ellipsoid(BC, body_r, Rx(-12)), fur)
    b.add(Ellipsoid(BC + [0, -0.45, 0.05], (body_r[0] * 1.13, 0.65, body_r[2] * 1.12)), fur, k=0.3)
    b.add(Ellipsoid(BC + [0, 0.55, -0.15], (0.62, 0.45, 0.6)), fur, k=0.3)
    if chest_fluff:
        fluffy(b, BC + [0, 0.45, -0.55], 0.42, chest, n=7, amp=0.2, k=0.14, spread=1.3)
    b.paint(Ellipsoid(BC + [0, 0.1, -0.75], (0.55, 1.0, 0.45)), chest, soft=0.12)
    if stripe_fn is not None:
        b.pattern(stripe_fn)
    b.pattern(shading_variation(0.025, 0.06, 0.18, seed=3))
    for sx, back, front in ((1, "LegBL", "LegFL"), (-1, "LegBR", "LegFR")):
        gb = p.g(f"{back}.base", step=0.07, rough=(0.004, 6), seed=5)
        gb.add(Ellipsoid([sx * 0.66, 0.68, 0.5], (0.5, 0.6, 0.72), Rx(-20)), thigh_col if thigh_col is not None else fur)
        gb.add(Ellipsoid([sx * 0.74, 0.17, -0.1], (0.33, 0.18, 0.5)), paw, k=0.18)
        for t in (-0.11, 0.11):
            gb.sub(Capsule([sx * 0.74 + t, 0.3, -0.62], [sx * 0.74 + t, 0.05, -0.62], 0.025), k=0.03)
        if stripe_fn is not None:
            gb.pattern(stripe_fn)
        gb.pattern(shading_variation(0.025, 0.05, 0.15, seed=6))
        p.pivots[back] = (sx * 0.64, 1.0, 0.48)
        gf = p.g(f"{front}.base", step=0.06, rough=(0.004, 6), seed=7)
        gf.add(RoundCone([sx * 0.42, 1.3, -0.35], [sx * 0.42, 0.32, -0.52], 0.3, 0.24), fur)
        gf.add(Ellipsoid([sx * 0.42, 0.17, -0.66], (0.3, 0.18, 0.33)), paw, k=0.14)
        for t in (-0.1, 0.1):
            gf.sub(Capsule([sx * 0.42 + t, 0.32, -0.97], [sx * 0.42 + t, 0.05, -0.97], 0.024), k=0.03)
        gf.paint(Ellipsoid([sx * 0.42, 0.35, -0.6], (0.34, 0.25, 0.4)), paw, soft=0.08)
        gf.pattern(shading_variation(0.025, 0.05, 0.12, seed=8))
        if claws is not None:
            gd = p.g(f"{front}.detail", step=0.025)
            for t in (-0.15, 0.0, 0.15):
                a = np.array([sx * 0.42 + t, 0.14, -0.92])
                gd.add(RoundCone(a, a + [0, -0.08, -0.12], 0.05, 0.015), claws, k=0)
            gd2 = p.g(f"{back}.detail", step=0.025)
            for t in (-0.15, 0.0, 0.15):
                a = np.array([sx * 0.74 + t, 0.14, -0.55])
                gd2.add(RoundCone(a, a + [0, -0.08, -0.12], 0.05, 0.015), claws, k=0)
        p.pivots[front] = (sx * 0.4, 1.18, -0.4)
    p.pivots["Body"] = (0, 0.9, 0.25); p.pivots["Head"] = (0, 2.0, -0.15); p.pivots["Tail"] = (0, 0.7, 1.05)
    return b

def curve_tail(p, p0, p1, p2, radii, col, tip_col=None, rings=None, ring_col=None, n=7, step=0.065, k=0.1, bushy=False):
    t = p.g("Tail.base", step=step, rough=(0.004, 6), seed=9)
    pts = [bezier(p0, p1, p2, s) for s in np.linspace(0, 1, n)]
    rr = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, len(radii)), radii)
    tube(t, pts, list(rr), col, k=k)
    if bushy:
        for i in range(2, n):
            d = pts[i] - pts[i - 1]; d /= np.linalg.norm(d)
            side = np.cross(d, [0, 0, 1.0]);
            if np.linalg.norm(side) < 1e-3:
                side = np.array([1.0, 0, 0])
            side /= np.linalg.norm(side)
            for sgn in (-1, 1):
                t.add(RoundCone(pts[i] - d * 0.1, pts[i] + side * sgn * rr[i] * 0.9 + d * 0.15, rr[i] * 0.45, 0.04), col, k=0.12)
    if rings:
        for s_ in rings:
            q = bezier(p0, p1, p2, s_)
            r = np.interp(s_, np.linspace(0, 1, len(radii)), radii)
            t.paint(Ellipsoid(q, (r * 1.3, 0.1, r * 1.3)), ring_col, soft=0.03)
    if tip_col is not None:
        t.paint(Ellipsoid(pts[-1], (rr[-1] * 1.7, rr[-1] * 1.5, rr[-1] * 1.7)), tip_col, soft=0.1)
    t.pattern(shading_variation(0.02, 0.05, 0.1, seed=10))
    return t

def feather_wing(p, name, shoulder, side, length=1.5, col=WHITE, tip_col=None, n=5, spread=70, down=-35,
                 back=0.35, width=0.24, step=0.045, covert_col=None, sweep=0.0, thick=0.32):
    """Aile en eventail de plumes (plumes aplaties fusionnees + couvertures a l'epaule)."""
    g = p.g(f"{name}.base", step=step, rough=(0.002, 9), seed=11)
    sh = np.asarray(shoulder, float)
    for i in range(n):
        a = math.radians(down + (i / max(n - 1, 1) - 0.5) * spread)
        L = length * (0.75 + 0.25 * math.sin(math.pi * (i + 0.5) / n)) * (1.0 - 0.06 * i)
        d = np.array([side * math.cos(a), math.sin(a), back + sweep * i / n])
        d /= np.linalg.norm(d)
        tip = sh + d * L
        up = np.cross(d, [0, 0, 1.0]) if abs(d[2]) < 0.9 else np.array([0, 1.0, 0])
        R = frame(np.cross(d, up) * side if np.linalg.norm(np.cross(d, up)) > 1e-3 else [0, 0, -1], d)
        f = Xf(RoundCone((0, 0, 0), (0, L, 0), width, width * 0.55), sh + d * 0.1, R, (1, 1, thick))
        c = col if tip_col is None else mixc(col, tip_col, i / max(n - 1, 1) * 0.0)
        g.add(f, c, k=0.06)
    g.add(Ellipsoid(sh + [side * 0.25, -0.1, 0.05], (0.42, 0.5, 0.3)), covert_col if covert_col is not None else col, k=0.12)
    if tip_col is not None:
        def tipfade(P, c, sh=sh, L=length):
            dd = np.linalg.norm(P - sh, axis=1) / L
            t = smoothstep(0.55, 1.0, dd)
            return c * (1 - t[:, None]) + tip_col[None, :] * t[:, None]
        g.pattern(tipfade)
    g.pattern(shading_variation(0.02, 0.06, 0.08, seed=12))
    p.pivots[name] = tuple(sh)
    return g

def stand_body(p, fur, belly=None, hoof=None, BC=(0, 1.75, 0.4), body_r=(0.88, 0.82, 1.2), leg_len=1.15,
               leg_r=(0.27, 0.2), neck=True, neck_col=None, rough=0.004, hoof_h=0.22):
    BC = np.asarray(BC, float)
    b = p.g("Body.base", step=0.075, rough=(rough, 6), seed=2)
    b.add(Ellipsoid(BC, body_r), fur)
    b.add(Ellipsoid(BC + [0, 0.05, body_r[2] * 0.55], (body_r[0] * 0.95, body_r[1] * 0.95, body_r[2] * 0.6)), fur, k=0.25)  # croupe
    if neck:
        b.add(RoundCone(BC + [0, 0.2, -body_r[2] * 0.55], BC + [0, 1.0, -body_r[2] * 0.8], 0.55, 0.45), neck_col if neck_col is not None else fur, k=0.3)
    if belly is not None:
        b.paint(Ellipsoid(BC + [0, -body_r[1] * 0.75, -0.1], (body_r[0] * 0.7, body_r[1] * 0.45, body_r[2] * 0.9)), belly, soft=0.15)
    b.pattern(shading_variation(0.025, 0.08, 0.15, seed=3))
    hoof = hoof if hoof is not None else mixc(fur, BLACK, 0.5)
    top_y = BC[1] - body_r[1] * 0.35
    for name, x, z in (("LegFL", 0.45, -body_r[2] * 0.55), ("LegFR", -0.45, -body_r[2] * 0.55),
                       ("LegBL", 0.47, body_r[2] * 0.55), ("LegBR", -0.47, body_r[2] * 0.55)):
        g = p.g(f"{name}.base", step=0.055, rough=(0.003, 6), seed=5)
        top = np.array([x, top_y + 0.2, z])
        bot = np.array([x, hoof_h + 0.05, z - 0.04])
        g.add(Ellipsoid(top + [0, -0.1, 0], (leg_r[0] * 1.45, 0.5, leg_r[0] * 1.6)), fur, k=0)  # epaule / cuisse
        g.add(RoundCone(top, bot, leg_r[0], leg_r[1]), fur, k=0.18)
        g.add(RoundCone(bot + [0, -0.02, 0], [x, hoof_h * 0.5, z - 0.06], leg_r[1] * 1.12, leg_r[1] * 1.28), hoof, k=0.04)
        g.pattern(shading_variation(0.02, 0.06, 0.12, seed=6))
        p.pivots[name] = tuple(top)
    p.pivots["Body"] = tuple(BC + [0, -0.3, 0])
    p.pivots["Head"] = tuple(BC + [0, 0.75, -body_r[2] * 0.7])
    p.pivots["Tail"] = tuple(BC + [0, 0.25, body_r[2] * 0.95])
    return b

def gem(g, c, r, col, R=I3):
    """Pierre precieuse facettee (octaedre arrondi) + reflet."""
    g.add(Xf(RoundBox((0, 0, 0), (r * 0.6, r * 0.6, r * 0.6), r * 0.15), c, R @ Rz(45) @ Rx(35), (1, 1.2, 0.6)), col, k=0)
    g.paint(Ellipsoid(np.asarray(c) + R @ np.array([-r * 0.3, r * 0.35, -r * 0.4]), (r * 0.3, r * 0.25, r * 0.3)), mixc(col, WHITE, 0.8), soft=0.03)
