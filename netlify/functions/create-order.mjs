import { randomBytes } from "node:crypto";
import { PLANS, json, orders, stockCount } from "./lib.mjs";

export default async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const { plan } = await req.json().catch(() => ({}));
  const p = PLANS[plan];
  if (!p) return json({ error: "Offre inconnue" }, 400);
  if ((await stockCount(plan)) < 1) return json({ error: "Rupture de stock pour cette offre." }, 409);

  const id = randomBytes(8).toString("hex");
  const token = randomBytes(16).toString("hex");
  const origin = new URL(req.url).origin;

  const res = await fetch("https://api.nowpayments.io/v1/invoice", {
    method: "POST",
    headers: { "x-api-key": process.env.NOWPAYMENTS_API_KEY, "content-type": "application/json" },
    body: JSON.stringify({
      price_amount: p.price,
      price_currency: "eur",
      order_id: id,
      order_description: `Onyx Hub - ${p.name}`,
      ipn_callback_url: `${origin}/.netlify/functions/ipn`,
      success_url: `${origin}/order.html?id=${id}&t=${token}`,
      cancel_url: `${origin}/#plans`
    })
  });
  const invoice = await res.json().catch(() => ({}));
  if (!res.ok || !invoice.invoice_url) {
    console.error("NOWPayments error", res.status, invoice);
    return json({ error: "Paiement indisponible, réessaie plus tard." }, 502);
  }

  await orders().setJSON(id, { plan, price: p.price, token, status: "pending", created: Date.now() });
  return json({ url: invoice.invoice_url });
};
