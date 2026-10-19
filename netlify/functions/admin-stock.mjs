import { timingSafeEqual } from "node:crypto";
import { PLANS, addKeys, json, stockCount } from "./lib.mjs";

function isAdmin(req) {
  const given = Buffer.from(req.headers.get("x-admin-token") || "");
  const real = Buffer.from(process.env.ADMIN_TOKEN || "");
  return real.length > 0 && given.length === real.length && timingSafeEqual(given, real);
}

export default async (req) => {
  if (!isAdmin(req)) return json({ error: "Mot de passe incorrect" }, 401);
  if (req.method === "POST") {
    const { plan, keys } = await req.json().catch(() => ({}));
    const clean = (keys || []).map((k) => String(k).trim()).filter(Boolean);
    if (!PLANS[plan] || !clean.length) return json({ error: "Données invalides" }, 400);
    await addKeys(plan, clean);
  }
  const counts = {};
  for (const id of Object.keys(PLANS)) counts[id] = await stockCount(id);
  return json({ plans: Object.fromEntries(Object.entries(PLANS).map(([id, p]) => [id, p.name])), counts });
};
