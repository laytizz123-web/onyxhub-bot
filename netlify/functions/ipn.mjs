import { PLANS, claimKey, json, orders } from "./lib.mjs";

/* The received body is never trusted: it only identifies the order.
   The payment is verified by asking Plisio for it with the secret key. */
async function readOrderNumber(req) {
  const text = await req.text();
  try { return String(JSON.parse(text).order_number || ""); } catch {}
  return String(new URLSearchParams(text).get("order_number") || "");
}

async function plisioOperation(txnId) {
  const res = await fetch(`https://api.plisio.net/api/v1/operations/${encodeURIComponent(txnId)}?api_key=${encodeURIComponent(process.env.PLISIO_API_KEY || "")}`);
  const body = await res.json().catch(() => ({}));
  return res.ok && body?.status === "success" ? body.data : null;
}

export default async (req) => {
  const orderId = await readOrderNumber(req);
  if (!orderId) return json({ error: "Missing order" }, 400);

  const store = orders();
  const cur = await store.getWithMetadata(orderId, { type: "json" });
  if (!cur) return json({ error: "Unknown order" }, 404);
  const order = cur.data;
  if (order.key) return json({ ok: true });
  if (!PLANS[order.plan]) return json({ error: "Unknown plan" }, 400);
  // Allow a retry if a previous run has been stuck for over a minute.
  if (order.status === "processing" && Date.now() - order.processingAt < 60_000) return json({ ok: true });

  const op = await plisioOperation(order.txnId);
  if (!op) return json({ error: "Cannot verify payment" }, 502);
  const paid =
    op.status === "completed" &&
    String(op.order_number) === orderId &&
    String(op.source_currency).toUpperCase() === "EUR" &&
    Number(op.source_amount) >= order.price - 0.01;
  if (!paid) return json({ ok: true });

  // Only one call wins this step: duplicate callbacks are ignored.
  const lock = await store.setJSON(orderId, { ...order, status: "processing", processingAt: Date.now() }, { onlyIfMatch: cur.etag });
  if (!lock.modified) return json({ ok: true });

  const key = await claimKey(order.plan);
  await store.setJSON(orderId, key ? { ...order, status: "delivered", key } : { ...order, status: "paid_no_stock" });
  if (!key) console.error("PAID BUT NO STOCK, order", orderId);
  return json({ ok: true });
};
