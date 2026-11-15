#!/usr/bin/env python3
"""Mini moteur de sculpture 3D par champs de distance (SDF) pour les pets.

Un pet = plusieurs groupes (Body, Head, Head.eye, EarL...). Chaque groupe est une forme continue :
primitives organiques (ellipsoides, cones arrondis, capsules) fusionnees en douceur (smooth union),
creusees (smooth subtraction), puis peintes (regions de couleur douces, motifs procéduraux).
Le maillage est extrait par surface nets, projete sur la surface, avec normales lissees et couleurs
par sommet.
"""
import math
import numpy as np

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
I3 = np.eye(3)

def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float) / 255

def mixc(a, b, t):
    return np.asarray(a) * (1 - t) + np.asarray(b) * t

def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

# ------------------------------------------------------------------ primitives (distance signee)
class Prim:
    def bound(self):
        raise NotImplementedError

class Ellipsoid(Prim):
    def __init__(self, c, r, R=I3):
        self.c = np.array(c, float); self.r = np.array(r, float); self.R = np.array(R, float)
    def sdf(self, P):
        q = (P - self.c) @ self.R
        k0 = np.linalg.norm(q / self.r, axis=1)
        k1 = np.linalg.norm(q / (self.r * self.r), axis=1)
        return k0 * (k0 - 1) / np.maximum(k1, 1e-9)
    def bound(self):
        return self.c, self.r.max()

class RoundCone(Prim):
    """Cone arrondi de a (rayon r1) a b (rayon r2) : membres, queues, cornes, oreilles."""
    def __init__(self, a, b, r1, r2):
        self.a = np.array(a, float); self.b = np.array(b, float); self.r1 = r1; self.r2 = r2
    def sdf(self, P):
        a, b, r1, r2 = self.a, self.b, self.r1, self.r2
        ba = b - a
        l2 = ba @ ba
        rr = r1 - r2
        a2 = l2 - rr * rr
        il2 = 1.0 / l2
        pa = P - a
        y = pa @ ba
        z = y - l2
        xv = pa * l2 - np.outer(y, ba)
        x2 = np.einsum("ij,ij->i", xv, xv)
        y2 = y * y * l2
        z2 = z * z * l2
        k = math.copysign(1, rr) * rr * rr * x2
        d1 = np.sqrt(np.maximum(x2 + z2, 0)) * il2 - r2
        d2 = np.sqrt(np.maximum(x2 + y2, 0)) * il2 - r1
        d3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + y * rr) * il2 - r1
        out = np.where(np.sign(z) * a2 * z2 > k, d1, np.where(np.sign(y) * a2 * y2 < k, d2, d3))
        return out
    def bound(self):
        c = (self.a + self.b) / 2
        return c, np.linalg.norm(self.b - self.a) / 2 + max(self.r1, self.r2)

def Capsule(a, b, r):
    return RoundCone(a, b, r, r)

class Torus(Prim):
    """Tore dans le plan XZ local (anneaux, colliers, couronnes)."""
    def __init__(self, c, R_major, r_minor, R=I3):
        self.c = np.array(c, float); self.Rm = R_major; self.rm = r_minor; self.R = np.array(R, float)
    def sdf(self, P):
        q = (P - self.c) @ self.R
        qx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - self.Rm
        return np.sqrt(qx * qx + q[:, 1] ** 2) - self.rm
    def bound(self):
        return self.c, self.Rm + self.rm

class RoundBox(Prim):
    def __init__(self, c, half, radius, R=I3):
        self.c = np.array(c, float); self.h = np.array(half, float); self.rad = radius; self.R = np.array(R, float)
    def sdf(self, P):
        q = np.abs((P - self.c) @ self.R) - self.h + self.rad
        return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(q.max(axis=1), 0) - self.rad
    def bound(self):
        return self.c, np.linalg.norm(self.h) + self.rad

# ------------------------------------------------------------------ groupe sculpte
class Group:
    def __init__(self, name, step=0.05, rough=None, seed=0):
        self.name = name
        self.step = step
        self.rough = rough  # (amplitude, echelle) : relief de fourrure / peau
        self.seed = seed
        self.ops = []      # ("add", prim, color, k) | ("sub", prim, k)
        self.paints = []   # (prim, color, soft) ou ("fn", fonction)

    def add(self, prim, color, k=0.15):
        self.ops.append(("add", prim, np.asarray(color, float), k)); return self
    def sub(self, prim, k=0.05):
        self.ops.append(("sub", prim, None, k)); return self
    def paint(self, prim, color, soft=0.04):
        self.paints.append((prim, np.asarray(color, float), soft)); return self
    def pattern(self, fn):
        self.paints.append(("fn", fn)); return self

    def field(self, P, with_color=False):
        d = None; col = None
        for op in self.ops:
            kind, prim, c, k = op
            e = prim.sdf(P)
            if kind == "add":
                if d is None:
                    d = e
                    if with_color:
                        col = np.tile(c, (len(P), 1))
                    continue
                if k <= 0:
                    h = (e < d).astype(float)
                    nd = np.minimum(d, e)
                else:
                    h = np.clip(0.5 + 0.5 * (d - e) / k, 0, 1)
                    nd = d * (1 - h) + e * h - k * h * (1 - h)
                if with_color:
                    col = col * (1 - h[:, None]) + c[None, :] * h[:, None]
                d = nd
            else:
                if k <= 0:
                    d = np.maximum(d, -e)
                else:
                    h = np.clip(0.5 - 0.5 * (d + e) / k, 0, 1)
                    d = d * (1 - h) + (-e) * h + k * h * (1 - h)
        if self.rough is not None:
            amp, sc = self.rough
            d = d - amp * (noise3(P, sc, self.seed) - 0.5) * 2
        if with_color:
            for p in self.paints:
                if p[0] == "fn":
                    col = p[1](P, col)
                else:
                    prim, c, soft = p
                    w = 1 - smoothstep(-soft, soft, prim.sdf(P))
                    col = col * (1 - w[:, None]) + c[None, :] * w[:, None]
            return d, col
        return d

    def bounds(self):
        lo = np.full(3, np.inf); hi = np.full(3, -np.inf)
        for kind, prim, c, k in self.ops:
            if kind != "add":
                continue
            cc, r = prim.bound()
            lo = np.minimum(lo, cc - r - 0.1); hi = np.maximum(hi, cc + r + 0.1)
        return lo, hi

    def mesh(self):
        lo, hi = self.bounds()
        h = self.step
        n = np.ceil((hi - lo) / h).astype(int) + 3
        xs = lo[0] - h + np.arange(n[0]) * h
        ys = lo[1] - h + np.arange(n[1]) * h
        zs = lo[2] - h + np.arange(n[2]) * h
        X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
        P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
        d = self.field(P).reshape(X.shape)
        verts, quads = surface_nets(-d)
        if len(verts) == 0:
            return None
        V = lo - h + verts * h
        # projection sur la surface (2 pas de Newton)
        for _ in range(2):
            g = gradient(self, V)
            dv = self.field(V)
            V = V - (dv / np.maximum((g * g).sum(1), 1e-9))[:, None] * g
        N = gradient(self, V)
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
        _, C = self.field(V, with_color=True)
        tris = np.concatenate([quads[:, [0, 1, 2]], quads[:, [0, 2, 3]]])
        # oriente les triangles comme la normale de surface
        fn = np.cross(V[tris[:, 1]] - V[tris[:, 0]], V[tris[:, 2]] - V[tris[:, 0]])
        vn = N[tris].sum(1)
        flip = np.einsum("ij,ij->i", fn, vn) < 0
        tris[flip] = tris[flip][:, ::-1]
        # supprime les triangles degeneres
        a, b, c = V[tris[:, 0]], V[tris[:, 1]], V[tris[:, 2]]
        area = np.linalg.norm(np.cross(b - a, c - a), axis=1)
        tris = tris[area > 1e-7]
        return V.astype(np.float32), N.astype(np.float32), np.clip(C, 0, 1).astype(np.float32), tris.astype(np.int32)


def gradient(group, V, e=0.004):
    g = np.zeros_like(V)
    for k in range(3):
        o = np.zeros(3); o[k] = e
        g[:, k] = (group.field(V + o) - group.field(V - o)) / (2 * e)
    return g


def surface_nets(f):
    """f > 0 a l'interieur. Retourne sommets (coordonnees de grille) et quads."""
    nx, ny, nz = f.shape
    inside = f > 0
    corners = [(a, b, c) for a in (0, 1) for b in (0, 1) for c in (0, 1)]
    cin = np.stack([inside[a:nx - 1 + a, b:ny - 1 + b, c:nz - 1 + c] for a, b, c in corners])
    active = cin.any(0) & ~cin.all(0)
    edges = [((0, 0, 0), (1, 0, 0)), ((0, 1, 0), (1, 1, 0)), ((0, 0, 1), (1, 0, 1)), ((0, 1, 1), (1, 1, 1)),
             ((0, 0, 0), (0, 1, 0)), ((1, 0, 0), (1, 1, 0)), ((0, 0, 1), (0, 1, 1)), ((1, 0, 1), (1, 1, 1)),
             ((0, 0, 0), (0, 0, 1)), ((1, 0, 0), (1, 0, 1)), ((0, 1, 0), (0, 1, 1)), ((1, 1, 0), (1, 1, 1))]
    acc = np.zeros(active.shape + (3,)); cnt = np.zeros(active.shape)
    for a, b in edges:
        fa = f[a[0]:nx - 1 + a[0], a[1]:ny - 1 + a[1], a[2]:nz - 1 + a[2]]
        fb = f[b[0]:nx - 1 + b[0], b[1]:ny - 1 + b[1], b[2]:nz - 1 + b[2]]
        cross = (fa > 0) != (fb > 0)
        t = np.clip(-fa / np.where(np.abs(fb - fa) < 1e-12, 1e-12, fb - fa), 0, 1)
        for k in range(3):
            acc[..., k] += np.where(cross, a[k] + t * (b[k] - a[k]), 0)
        cnt += cross
    idx = -np.ones(active.shape, np.int64)
    ci = np.argwhere(active)
    idx[tuple(ci.T)] = np.arange(len(ci))
    verts = ci + acc[tuple(ci.T)] / cnt[tuple(ci.T)][:, None]
    quads = []
    for axis in range(3):
        o1, o2 = [a for a in range(3) if a != axis]
        sa = [slice(1, -1)] * 3; sb = [slice(1, -1)] * 3
        sa[axis] = slice(0, -1); sb[axis] = slice(1, None)
        fa = inside[tuple(sa)]; fb = inside[tuple(sb)]
        pts = np.argwhere(fa != fb)
        if len(pts) == 0:
            continue
        q = pts.copy(); q[:, o1] += 1; q[:, o2] += 1
        cells = []
        for d1, d2 in ((-1, -1), (0, -1), (0, 0), (-1, 0)):
            cc = q.copy(); cc[:, o1] += d1; cc[:, o2] += d2
            cc[:, axis] = pts[:, axis]
            cells.append(idx[tuple(cc.T)])
        cells = np.stack(cells, 1)
        ok = (cells >= 0).all(1)
        quads.append(cells[ok])
    return verts, (np.concatenate(quads) if quads else np.zeros((0, 4), np.int64))


# ------------------------------------------------------------------ helpers de peinture
def noise3(P, scale=3.0, seed=0):
    """Bruit de valeur lisse (variations subtiles de couleur)."""
    rng = np.random.RandomState(seed)
    g = rng.rand(17, 17, 17)
    q = P * scale + 50
    i = np.floor(q).astype(int); f = q - i
    f = f * f * (3 - 2 * f)
    def at(dx, dy, dz):
        return g[(i[:, 0] + dx) % 17, (i[:, 1] + dy) % 17, (i[:, 2] + dz) % 17]
    x00 = at(0, 0, 0) * (1 - f[:, 0]) + at(1, 0, 0) * f[:, 0]
    x10 = at(0, 1, 0) * (1 - f[:, 0]) + at(1, 1, 0) * f[:, 0]
    x01 = at(0, 0, 1) * (1 - f[:, 0]) + at(1, 0, 1) * f[:, 0]
    x11 = at(0, 1, 1) * (1 - f[:, 0]) + at(1, 1, 1) * f[:, 0]
    y0 = x00 * (1 - f[:, 1]) + x10 * f[:, 1]
    y1 = x01 * (1 - f[:, 1]) + x11 * f[:, 1]
    return y0 * (1 - f[:, 2]) + y1 * f[:, 2]

def shading_variation(amount=0.06, top=0.06, bottom=0.12, seed=1, scale=2.5):
    """Degrade naturel (plus clair en haut, plus sombre en dessous) + legere variation."""
    def fn(P, col):
        n = (noise3(P, scale, seed) - 0.5) * 2 * amount
        y = P[:, 1]
        yn = (y - y.min()) / max(np.ptp(y), 1e-6)
        light = 1 + n + (yn - 0.5) * top * 2 - (1 - yn) ** 3 * bottom
        return np.clip(col * light[:, None], 0, 1)
    return fn


# ------------------------------------------------------------------ extensions
class Xf(Prim):
    """Primitive definie autour de l'origine, puis echelle non uniforme s, rotation R (colonnes = axes locaux), translation c."""
    def __init__(self, prim, c=(0, 0, 0), R=I3, s=(1, 1, 1)):
        self.p = prim; self.c = np.array(c, float); self.R = np.array(R, float); self.s = np.array(s, float)
    def sdf(self, P):
        q = ((P - self.c) @ self.R) / self.s
        return self.p.sdf(q) * self.s.min()
    def bound(self):
        c, r = self.p.bound()
        return self.c + self.R @ (c * self.s), r * self.s.max()

def frame(forward, up=(0, 1, 0)):
    """Matrice dont l'axe local -Z pointe vers 'forward' (colonnes = axes locaux x, y, z)."""
    f = np.asarray(forward, float); f = f / np.linalg.norm(f)
    z = -f
    x = np.cross(np.asarray(up, float), z)
    if np.linalg.norm(x) < 1e-6:
        x = np.array([1.0, 0, 0])
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return np.stack([x, y, z], 1)

def bezier(p0, p1, p2, t):
    p0, p1, p2 = map(lambda v: np.asarray(v, float), (p0, p1, p2))
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2

def tube(group, pts, radii, color, k=0.12):
    """Chaine de cones arrondis (queues, cous, trompes, cornes courbes)."""
    for i in range(len(pts) - 1):
        group.add(RoundCone(pts[i], pts[i + 1], radii[i], radii[i + 1]), color, k=k)
    return group


# ------------------------------------------------------------------ simplification (QEM par lots)
def decimate(V, C, T, target, color_w=12.0, max_iter=80):
    """Reduction de maillage par effondrement d'aretes (erreur quadrique + ecart de couleur),
    par lots d'aretes independantes. Protege les bords, refuse les retournements de faces."""
    V = V.astype(float).copy(); C = C.astype(float).copy(); T = T.astype(np.int64).copy()
    for _ in range(max_iter):
        if len(T) <= target:
            break
        nv = len(V)
        a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
        fn = np.cross(b - a, c - a)
        ar = np.linalg.norm(fn, axis=1)
        n = fn / np.maximum(ar, 1e-12)[:, None]
        pl = np.concatenate([n, -(n * a).sum(1, keepdims=True)], 1)
        K = pl[:, :, None] * pl[:, None, :] * (ar[:, None, None] + 1e-6)
        Q = np.zeros((nv, 4, 4))
        for i in range(3):
            np.add.at(Q, T[:, i], K)
        E = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), 1)
        E, ecount = np.unique(E, axis=0, return_counts=True)
        bnd = np.zeros(nv, bool); bnd[E[ecount != 2].ravel()] = True
        Eu, Ev = E[:, 0], E[:, 1]
        Qs = Q[Eu] + Q[Ev]
        cands = [V[Eu], V[Ev], (V[Eu] + V[Ev]) / 2]
        costs = []
        for P in cands:
            h = np.concatenate([P, np.ones((len(P), 1))], 1)
            costs.append(np.einsum("ei,eij,ej->e", h, Qs, h))
        costs = np.stack(costs, 1)
        pick = costs.argmin(1)
        cost = costs[np.arange(len(E)), pick]
        L2 = ((V[Eu] - V[Ev]) ** 2).sum(1)
        cost = cost + color_w * ((C[Eu] - C[Ev]) ** 2).sum(1) * L2
        cost[bnd[Eu] | bnd[Ev]] = np.inf
        newp = np.where(pick[:, None] == 0, V[Eu], np.where(pick[:, None] == 1, V[Ev], (V[Eu] + V[Ev]) / 2))
        newc = np.where(pick[:, None] == 0, C[Eu], np.where(pick[:, None] == 1, C[Ev], (C[Eu] + C[Ev]) / 2))
        # voisinages
        order_nb = np.argsort(np.concatenate([E[:, 0], E[:, 1]]), kind="stable")
        src = np.concatenate([E[:, 0], E[:, 1]])[order_nb]
        dst = np.concatenate([E[:, 1], E[:, 0]])[order_nb]
        start = np.searchsorted(src, np.arange(nv + 1))
        want = (len(T) - target) // 2 + 1
        order = np.argsort(cost)
        order = order[np.isfinite(cost[order])][: max(want * 3, 16)]
        lock = np.zeros(nv, bool)
        chosen = []
        for e in order:
            u, v = Eu[e], Ev[e]
            if lock[u] or lock[v]:
                continue
            nu = dst[start[u]:start[u + 1]]; nvv = dst[start[v]:start[v + 1]]
            if len(np.intersect1d(nu, nvv, assume_unique=False)) != 2:
                continue
            chosen.append(e)
            lock[nu] = True; lock[nvv] = True; lock[u] = True; lock[v] = True
            if len(chosen) >= want:
                break
        if not chosen:
            break
        chosen = np.array(chosen)
        for _rep in range(3):
            mp = np.arange(nv); P2 = V.copy()
            mp[Eu[chosen]] = Ev[chosen]; P2[Ev[chosen]] = newp[chosen]
            T2 = mp[T]
            keep = (T2[:, 0] != T2[:, 1]) & (T2[:, 1] != T2[:, 2]) & (T2[:, 0] != T2[:, 2])
            a2, b2, c2 = P2[T2[:, 0]], P2[T2[:, 1]], P2[T2[:, 2]]
            fn2 = np.cross(b2 - a2, c2 - a2)
            n2 = fn2 / np.maximum(np.linalg.norm(fn2, axis=1), 1e-12)[:, None]
            bad = keep & ((n2 * n).sum(1) < 0.3) & (np.linalg.norm(fn2, axis=1) > 0)
            bad |= keep & (np.linalg.norm(fn2, axis=1) < 1e-10)
            if not bad.any():
                break
            badv = np.unique(T[bad].ravel())
            isbad = np.zeros(nv, bool); isbad[badv] = True
            chosen = chosen[~(isbad[Eu[chosen]] | isbad[Ev[chosen]])]
            if len(chosen) == 0:
                break
        if len(chosen) == 0:
            break
        mp = np.arange(nv)
        mp[Eu[chosen]] = Ev[chosen]
        V[Ev[chosen]] = newp[chosen]; C[Ev[chosen]] = newc[chosen]
        T = mp[T]
        T = T[(T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 0] != T[:, 2])]
    used = np.unique(T)
    remap = -np.ones(len(V), np.int64); remap[used] = np.arange(len(used))
    return V[used], C[used], remap[T]
