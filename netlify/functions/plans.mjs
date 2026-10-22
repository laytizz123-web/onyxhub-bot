import { PLANS, json, stockCount } from "./lib.mjs";

export default async () => {
  const out = [];
  for (const [id, p] of Object.entries(PLANS)) {
    out.push({ id, ...p, inStock: (await stockCount(id)) > 0 });
  }
  return json(out);
};
