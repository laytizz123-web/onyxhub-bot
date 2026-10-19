import { json, orders } from "./lib.mjs";

export default async (req) => {
  const u = new URL(req.url);
  const order = await orders().get(u.searchParams.get("id") || "-", { type: "json" });
  if (!order || order.token !== u.searchParams.get("t")) return json({ error: "Commande introuvable" }, 404);
  return json({ status: order.status, key: order.key || null });
};
