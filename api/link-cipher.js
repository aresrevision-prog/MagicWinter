// MagicWinter Studio — Cipher account linking checker (Vercel serverless function).
// Proves that the person linking really owns a Cipher number, without ever seeing their Cipher password:
//   GET  /api/link-cipher?num=0001  -> a one-time challenge (ticket) + the number's locked key from Cipher
//   POST /api/link-cipher           -> { ticket, num, token, proof }  checks the proof, then saves the link
// Needs the LINK_SECRET environment variable in Vercel (same secret as in magicwinter-links.sql).
// © MagicWinter Studio. All rights reserved.

const { subtle } = globalThis.crypto;
const MW_URL = process.env.MW_SUPABASE_URL || "https://lakjmdyzuqrwcncxybcw.supabase.co";
const MW_KEY = process.env.MW_SUPABASE_KEY || "sb_publishable__m0zTZ3-ThJVk0pktI65Ag_yDFPPD5s";
const CIPHER_SITE = process.env.CIPHER_SITE || "https://cipher-six-blue.vercel.app";
const ECDH = { name: "ECDH", namedCurve: "P-256" };
const TICKET_MS = 5 * 60 * 1000;
const CUTOFF = Date.parse("2026-11-27T21:30:00Z"); // Cipher switched to MagicWinter sign-in
const te = new TextEncoder(), td = new TextDecoder();

const b64u = buf => Buffer.from(buf).toString("base64url");
const unb64u = s => new Uint8Array(Buffer.from(String(s || ""), "base64url"));
const unb64 = s => new Uint8Array(Buffer.from(String(s || ""), "base64"));

let cipherCfg = null;
async function cipherConfig() {
  if (process.env.CIPHER_URL && process.env.CIPHER_KEY) return { url: process.env.CIPHER_URL, key: process.env.CIPHER_KEY };
  if (cipherCfg) return cipherCfg;
  const js = await (await fetch(CIPHER_SITE + "/config.js")).text(); // Cipher's public browser config
  const url = (js.match(/url\s*:\s*["']([^"']+)["']/) || [])[1], key = (js.match(/anonKey\s*:\s*["']([^"']+)["']/) || [])[1];
  if (!url || !key) throw new Error("Couldn't read Cipher's settings.");
  return (cipherCfg = { url: url.replace(/\/$/, ""), key });
}
async function cipherNumber(num) {
  const c = await cipherConfig();
  const r = await fetch(`${c.url}/rest/v1/docs?select=data&path=eq.${encodeURIComponent("numbers/" + num)}`,
    { headers: { apikey: c.key, Authorization: "Bearer " + c.key } });
  if (!r.ok) throw new Error("Couldn't reach Cipher. Try again in a minute.");
  const rows = await r.json();
  return rows && rows[0] && rows[0].data || null;
}
async function ticketKey() {
  const raw = await subtle.digest("SHA-256", te.encode(process.env.LINK_SECRET + "|mw-link-ticket"));
  return subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}
const noOps = jwk => { const j = { ...jwk }; delete j.key_ops; return j; };

module.exports = async (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  const origin = String(req.headers.origin || "");
  if (/^https:\/\/(cipher-six-blue|magicwinter)\.vercel\.app$/i.test(origin) || /^https:\/\/cipher[a-z0-9-]*\.vercel\.app$/i.test(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin); res.setHeader("Vary", "Origin");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS"); res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  }
  if (req.method === "OPTIONS") return res.status(204).end();
  const send = (code, obj) => res.status(code).json(obj);
  if (!process.env.LINK_SECRET) return send(503, { error: "Cipher linking isn't switched on yet (the studio needs to add LINK_SECRET in Vercel)." });
  try {
    if (req.method === "GET") {
      const num = String(req.query.num || "");
      if (!/^\d{4,12}$/.test(num)) return send(400, { error: "Enter your Cipher number (digits only)." });
      const d = await cipherNumber(num);
      if (!d || !d.pub || !d.wk) return send(404, { error: "No Cipher account has number " + num + "." });
      const kp = await subtle.generateKey(ECDH, true, ["deriveKey"]);
      const iv = globalThis.crypto.getRandomValues(new Uint8Array(12));
      const body = te.encode(JSON.stringify({ d: await subtle.exportKey("jwk", kp.privateKey), n: num, t: Date.now() }));
      const ct = await subtle.encrypt({ name: "AES-GCM", iv }, await ticketKey(), body);
      const ticket = b64u(Buffer.concat([Buffer.from(iv), Buffer.from(ct)]));
      return send(200, { ticket, pub: await subtle.exportKey("jwk", kp.publicKey), wk: d.wk, salt: d.salt, iv: d.iv, name: String(d.name || "") });
    }
    if (req.method === "POST") {
      let b = req.body; if (typeof b === "string") { try { b = JSON.parse(b); } catch { b = {}; } }
      const { ticket, num, token, proof } = b || {};
      if (!/^\d{4,12}$/.test(String(num || "")) || !ticket || !token || !proof) return send(400, { error: "Something's missing. Try again." });
      let t;
      try {
        const raw = unb64u(ticket);
        t = JSON.parse(td.decode(await subtle.decrypt({ name: "AES-GCM", iv: raw.slice(0, 12) }, await ticketKey(), raw.slice(12))));
      } catch { return send(400, { error: "That link attempt expired. Try again." }); }
      if (t.n !== num || Date.now() - t.t > TICKET_MS) return send(400, { error: "That link attempt expired. Try again." });
      const d = await cipherNumber(num);
      if (!d || !d.pub) return send(404, { error: "No Cipher account has number " + num + "." });
      const mine = await subtle.importKey("jwk", noOps(t.d), ECDH, false, ["deriveKey"]);
      const theirs = await subtle.importKey("jwk", noOps(d.pub), ECDH, false, []);
      const hk = await subtle.deriveKey({ name: "ECDH", public: theirs }, mine, { name: "HMAC", hash: "SHA-256", length: 256 }, false, ["verify"]);
      const ok = await subtle.verify("HMAC", hk, unb64(proof), te.encode(`${ticket}|${num}|${token}`));
      if (!ok) return send(403, { error: "Wrong Cipher password." });
      const r = await fetch(MW_URL + "/rest/v1/rpc/mw_link_cipher", {
        method: "POST", headers: { "Content-Type": "application/json", apikey: MW_KEY },
        body: JSON.stringify({ p_secret: process.env.LINK_SECRET, p_token: token, p_num: num, p_name: String(d.name || "") }),
      });
      let j = {}; try { j = await r.json(); } catch {}
      if (r.status === 404 || /could not find the function|schema cache/i.test(j.message || "")) return send(503, { error: "Linking isn't switched on yet (the studio needs to run magicwinter-links.sql)." });
      if (j.ok) {
        // numbers made before MagicWinter sign-in became the only way in earn the +100 transfer bonus (once per number)
        const old = !d.terms || Number(d.terms) < CUTOFF;
        if (old) {
          try {
            const b2 = await fetch(MW_URL + "/rest/v1/rpc/mw_cipher_bonus", { method: "POST", headers: { "Content-Type": "application/json", apikey: MW_KEY },
              body: JSON.stringify({ p_secret: process.env.LINK_SECRET, p_token: token, p_num: num }) }).then(x => x.json());
            if (b2 && b2.got) j.bonus = b2.got;
          } catch {}
        }
      }
      return send(j.ok ? 200 : 400, j.ok ? j : { error: j.error || "Couldn't save the link." });
    }
    res.setHeader("Allow", "GET, POST");
    return send(405, { error: "Method not allowed" });
  } catch (e) {
    return send(500, { error: "Something went wrong. Try again in a minute." });
  }
};
