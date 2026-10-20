import { getStore } from "@netlify/blobs";

/* PRICES AND OFFERS: edit here (in EUR). These are example values. */
export const PLANS = {
  lifetime: { name: "Lifetime", price: 1.20, perks: ["Lifetime access", "Priority support", "Updates included"] }
};

export const stock = () => getStore({ name: "stock", consistency: "strong" });
export const orders = () => getStore({ name: "orders", consistency: "strong" });

export const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" }
  });

export async function stockCount(plan) {
  const list = (await stock().get(plan, { type: "json" })) || [];
  return list.length;
}

export async function addKeys(plan, keys) {
  for (let i = 0; i < 10; i++) {
    const cur = await stock().getWithMetadata(plan, { type: "json" });
    const list = [...(cur?.data || []), ...keys];
    const res = cur
      ? await stock().setJSON(plan, list, { onlyIfMatch: cur.etag })
      : await stock().setJSON(plan, list, { onlyIfNew: true });
    if (res.modified) return list.length;
  }
  throw new Error("Stock busy, retry");
}

/* Takes a key out of the stock without ever giving it twice (conditional write). */
export async function claimKey(plan) {
  for (let i = 0; i < 10; i++) {
    const cur = await stock().getWithMetadata(plan, { type: "json" });
    if (!cur || !cur.data.length) return null;
    const [key, ...rest] = cur.data;
    const res = await stock().setJSON(plan, rest, { onlyIfMatch: cur.etag });
    if (res.modified) return key;
  }
  return null;
}
