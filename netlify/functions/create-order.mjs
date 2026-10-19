import { randomBytes } from "node:crypto";
import { PLANS, json, orders, stockCount } from "./lib.mjs";

export default async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const { plan } = await req.json().catch(() => ({}));
  const p = PLANS[plan];
  if (!p) return json({ error: "Unknown offer" }, 400);
  if ((await stockCount(plan)) < 1) return json({ error: "This offer is out of stock." }, 409);

  const id = randomBytes(8).toString("hex");
  const token = randomBytes(16).toString("hex");
  const origin = new URL(req.url).origin;

  const params = new URLSearchParams({
    api_key: process.env.PLISIO_API_KEY || "",
    source_currency: "EUR",
    source_amount: String(p.price),
    order_number: id,
    order_name: `Onyx Hub - ${p.name}`,
    callback_url: `${origin}/.netlify/functions/ipn?json=true`,
    success_callback_url: `${origin}/order.html?id=${id}&t=${token}`,
    fail_callback_url: `${origin}/#plans`
  });
  const res = await fetch(`https://api.plisio.net/api/v1/invoices/new?${params}`);
  const body = await res.json().catch(() => ({}));
  const invoice = body?.data;
  if (!res.ok || body?.status !== "success" || !invoice?.invoice_url || !invoice?.txn_id) {
    console.error("Plisio error", res.status, JSON.stringify(body));
    return json({ error: "Payment unavailable, please try again later." }, 502);
  }

  await orders().setJSON(id, { plan, price: p.price, token, txnId: invoice.txn_id, status: "pending", created: Date.now() });
  return json({ url: invoice.invoice_url });
};
