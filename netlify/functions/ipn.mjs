import { createHmac, timingSafeEqual } from "node:crypto";
import { PLANS, claimKey, json, orders } from "./lib.mjs";

const sortKeys = (o) =>
  o && typeof o === "object" && !Array.isArray(o)
    ? Object.fromEntries(Object.keys(o).sort().map((k) => [k, sortKeys(o[k])]))
    : o;

function validSignature(body, sig) {
  if (!sig || !process.env.NOWPAYMENTS_IPN_SECRET) return false;
  const expected = createHmac("sha512", process.env.NOWPAYMENTS_IPN_SECRET)
    .update(JSON.stringify(sortKeys(body)))
    .digest("hex");
  const a = Buffer.from(expected), b = Buffer.from(sig);
  return a.length === b.length && timingSafeEqual(a, b);
}

export default async (req) => {
  const body = await req.json().catch(() => null);
  if (!body || !validSignature(body, req.headers.get("x-nowpayments-sig"))) {
    return json({ error: "Bad signature" }, 401);
  }
  if (body.payment_status !== "finished") return json({ ok: true });

  const store = orders();
  const cur = await store.getWithMetadata(String(body.order_id), { type: "json" });
  if (!cur) return json({ error: "Unknown order" }, 404);
  const order = cur.data;
  if (order.key) return json({ ok: true });
  if (Number(body.price_amount) !== order.price || !PLANS[order.plan]) return json({ error: "Amount mismatch" }, 400);
  // Reprise possible si un traitement précédent est resté bloqué plus d'une minute.
  if (order.status === "processing" && Date.now() - order.processingAt < 60_000) return json({ ok: true });

  // Un seul appel gagne ce passage : les doublons d'IPN sont ignorés.
  const lock = await store.setJSON(String(body.order_id), { ...order, status: "processing", processingAt: Date.now() }, { onlyIfMatch: cur.etag });
  if (!lock.modified) return json({ ok: true });

  const key = await claimKey(order.plan);
  await store.setJSON(String(body.order_id), key
    ? { ...order, status: "delivered", key }
    : { ...order, status: "paid_no_stock" });
  if (!key) console.error("PAID BUT NO STOCK, order", body.order_id);
  return json({ ok: true });
};
