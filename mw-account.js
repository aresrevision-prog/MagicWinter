/* MagicWinter account — one account for every MagicWinter Studio app (this site, Frontline Warzone, Floof AI…).
   Accounts are real online accounts (Supabase Auth), so they work on any device.
   Add to any MagicWinter site with a script tag:  src="mw-account.js" defer
   Put <span data-mw-account> inside your nav to place the button there; otherwise it floats. Options (on the script tag): data-position="bottom-left" (or top-left, bottom-right) to move the button.
   Listen for sign-in:  addEventListener("mwaccount", e => e.detail.user)   // username or null
   © MagicWinter Studio. All rights reserved. */
(() => {
  if (window.MWAccount) return;
  const ARES = "https://lakjmdyzuqrwcncxybcw.supabase.co", ARES_KEY = "sb_publishable__m0zTZ3-ThJVk0pktI65Ag_yDFPPD5s";
  const ARES_SITE = "https://ares-revision.vercel.app", SESS = "mw.session";
  const FLOOF = window.MW_FLOOF_URL || (document.querySelector("[data-mw-account]") ? "/floof/" : ""); // set window.MW_FLOOF_URL to Floof's own website
  const me = document.currentScript, pos = (me && me.dataset.position) || "top-right";
  const HEX = '<svg viewBox="0 0 100 100" fill="none" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M50 5l39 22.5v45L50 95 11 72.5v-45z" stroke="#3ddc84" stroke-width="6" fill="#0d1f16"/><path d="M16 38l18 26 16-28 16 28 18-26" stroke="#3ddc84" stroke-width="8"/><path d="M28 68V31l22 24 22-24v37" stroke="#0d1f16" stroke-width="12.5"/><path d="M28 68V31l22 24 22-24v37" stroke="#3ddc84" stroke-width="7.5"/></svg>';
  const MINI = '<svg viewBox="0 0 100 100" fill="none" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="width:15px;height:15px;vertical-align:-3px"><path d="M50 5l39 22.5v45L50 95 11 72.5v-45z" stroke="#3ddc84" stroke-width="7" fill="#0d1f16"/><path d="M28 68V31l22 24 22-24v37" stroke="#3ddc84" stroke-width="9"/></svg>';
  const P = { "top-right": "top:14px;right:max(14px,2vw)", "top-left": "top:14px;left:max(14px,2vw)", "bottom-left": "bottom:14px;left:max(14px,2vw)", "bottom-right": "bottom:14px;right:max(14px,2vw)" }[pos] || "top:14px;right:max(14px,2vw)";
  const M = pos.startsWith("bottom") ? P.replace(/bottom:14px/, "bottom:58px") : P.replace(/top:14px/, "top:58px");
  const css = `
.mwa-pill,.mwa-menu,.mwa-box,.mwa-box *{text-transform:none;letter-spacing:normal;box-sizing:border-box}
.mwa-pill{position:fixed;${P};z-index:9999;display:flex;align-items:center;gap:8px;padding:7px 14px 7px 8px;border-radius:999px;border:1px solid #21452f;background:rgba(13,31,22,.84);backdrop-filter:blur(10px);color:#e9f5ec;font:600 13px "Manrope",system-ui,sans-serif;cursor:pointer;box-shadow:0 8px 30px rgba(0,0,0,.35);transition:opacity .2s}
.mwa-pill:hover,.mwa-pill:focus-visible{border-color:#3ddc84;outline:none}.mwa-pill svg{width:22px;height:22px}.mwa-pill.away{opacity:0;pointer-events:none}
.mwa-av{width:22px;height:22px;border-radius:50%;display:grid;place-items:center;background:linear-gradient(135deg,#3ddc84,#c6f06b);color:#07130d;font:800 12px "Syne",system-ui,sans-serif}
.mwa-menu{position:fixed;${M};z-index:9999;min-width:230px;background:#0d1f16;border:1px solid #21452f;border-radius:14px;padding:6px;box-shadow:0 20px 50px rgba(0,0,0,.45);display:none;font:14px "Manrope",system-ui,sans-serif}
.mwa-menu.on{display:block}.mwa-menu a,.mwa-menu button{display:flex;gap:10px;align-items:center;width:100%;padding:9px 10px;border:0;border-radius:9px;background:none;color:#e9f5ec;text-decoration:none;font:inherit;cursor:pointer;text-align:left}
.mwa-menu a:hover,.mwa-menu button:hover{background:#12291d}.mwa-menu .who{padding:8px 10px 10px;color:#8fb29b;font-size:12px;border-bottom:1px solid #21452f;margin-bottom:4px}.mwa-menu .who b{color:#e9f5ec;font-size:14px}
.mwa-ov{position:fixed;inset:0;z-index:10000;background:rgba(3,10,6,.78);backdrop-filter:blur(6px);display:none;place-items:center;padding:16px}.mwa-ov.on{display:grid}
.mwa-box{position:relative;width:100%;max-width:380px;box-sizing:border-box;background:linear-gradient(160deg,#12291d,#0d1f16);border:1px solid #21452f;border-radius:22px;padding:26px;display:flex;flex-direction:column;gap:12px;color:#e9f5ec;font:15px "Manrope",system-ui,sans-serif;box-shadow:0 30px 80px rgba(0,0,0,.5)}
.mwa-box .lg{width:58px;height:58px;margin:0 auto;filter:drop-shadow(0 0 10px rgba(61,220,132,.35))}.mwa-box .lg svg{width:100%;height:100%}
.mwa-box .mwa-eb{font:600 11px ui-monospace,Consolas,monospace;letter-spacing:.14em;text-transform:uppercase;color:#3ddc84;text-align:center}
.mwa-box h2{margin:0;text-align:center;font:800 26px/1.1 "Syne",system-ui,sans-serif}
.mwa-sub{text-align:center;color:#8fb29b;font-size:13px}.mwa-sub b{color:#e9f5ec}
.mwa-box input[type=text],.mwa-box input[type=password]{width:100%;box-sizing:border-box;background:#12291d;border:1px solid #21452f;border-radius:10px;padding:11px 12px;color:#e9f5ec;font:inherit;outline:none}
.mwa-box input:focus{border-color:#3ddc84}
.mwa-row{display:flex;gap:8px;align-items:center}.mwa-sm{font-size:12px;color:#8fb29b}.mwa-sm a{color:#3ddc84}
.mwa-go{border:0;border-radius:10px;padding:11px;font:700 15px "Manrope",system-ui,sans-serif;color:#07130d;background:linear-gradient(135deg,#3ddc84,#c6f06b);cursor:pointer}.mwa-go:disabled{opacity:.5}
.mwa-x{position:absolute;top:12px;right:12px;border:1px solid #21452f;background:#12291d;color:#e9f5ec;border-radius:9px;width:30px;height:30px;cursor:pointer}
.mwa-err{color:#ff7a8a;font-size:12px;min-height:16px}
.mwa-tabs{display:flex;gap:4px;background:#0d1f16;border:1px solid #21452f;border-radius:12px;padding:3px;align-self:center}
.mwa-tabs button{border:0;background:none;color:#8fb29b;padding:6px 14px;border-radius:9px;font:inherit;font-size:14px;cursor:pointer}.mwa-tabs button.on{background:#12291d;color:#3ddc84}
.mwa-apps{display:flex;justify-content:center;gap:6px;flex-wrap:wrap}.mwa-apps span{font-size:11px;color:#8fb29b;border:1px solid #21452f;border-radius:99px;padding:3px 9px}
.mwa-pill.inline{position:static;box-shadow:none;padding:5px 12px 5px 6px;margin-left:6px;vertical-align:middle}
@media(max-width:520px){.mwa-pill .mwa-nm{display:none}}`;
  const st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);
  if (!document.querySelector('link[href*="family=Syne"]')) { const l = document.createElement("link"); l.rel = "stylesheet"; l.href = "https://fonts.googleapis.com/css2?family=Syne:wght@700;800&family=Manrope:wght@400;600;700&display=swap"; document.head.appendChild(l); }

  const esc = s => String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  function current() {
    for (const s of [sessionStorage, localStorage]) { try { const v = JSON.parse(s.getItem(SESS)); if (v && v.user && v.kind === "mw" && (!v.until || v.until > Date.now())) return v; } catch {} }
    return null;
  }
  const emit = () => dispatchEvent(new CustomEvent("mwaccount", { detail: { user: current()?.user || null } }));

  // MagicWinter accounts: username + password, checked by database functions on the account server (no emails)
  async function mwAuth(kind, username, password) {
    const fn = kind === "up" ? "mw_signup" : "mw_login";
    try {
      let r, lastErr; const bases = [ARES]; if (/^https?:$/.test(location.protocol)) bases.push(location.origin); // own-site route for networks that block the server
      for (const b of bases) { try { r = await fetch(b + "/rest/v1/rpc/" + fn, { method: "POST", headers: { "Content-Type": "application/json", apikey: ARES_KEY }, body: JSON.stringify({ p_username: username, p_password: password }) }); if (r.status === 404 && b !== ARES) { r = null; continue; } break; } catch (e) { lastErr = e; } }
      if (!r) throw lastErr || new Error("network");
      let j = {}; try { j = await r.json(); } catch {}
      if (r.status === 404 || /could not find the function|schema cache/i.test(j.message || "")) return { error: "MagicWinter accounts aren't switched on yet — the studio needs to run magicwinter-accounts.sql in Supabase." };
      if (j.ok && j.token) return { ok: true, user: j.username || username, token: j.token };
      return { error: j.error || j.message || "Something went wrong (" + r.status + ").", bad: /wrong username/i.test(j.error || "") };
    } catch { return { error: "Can't reach the account server — check your internet and try again." }; }
  }

  // button + menu
  const pill = document.createElement("button"); pill.className = "mwa-pill"; pill.type = "button";
  const menu = document.createElement("div"); menu.className = "mwa-menu";
  const slot = document.querySelector("[data-mw-account]"); // optional: sit inside the site's own nav bar
  if (slot) { pill.classList.add("inline"); slot.appendChild(pill); } else document.body.appendChild(pill);
  document.body.appendChild(menu);
  const placeMenu = () => { if (!slot) return; const r = pill.getBoundingClientRect(); Object.assign(menu.style, { top: r.bottom + 8 + "px", bottom: "auto", left: "auto", right: Math.max(8, innerWidth - r.right) + "px" }); };
  function render() {
    const s = current(), u = s && s.user;
    pill.innerHTML = u ? `<span class="mwa-av">${esc(u[0].toUpperCase())}</span><span class="mwa-nm">${esc(u)}</span><span style="opacity:.6">▾</span>` : `${HEX}<span>Sign in</span>`;
    pill.setAttribute("aria-label", u ? "MagicWinter account: " + u : "Sign in with your MagicWinter account");
    menu.innerHTML = u ? `<div class="who">MagicWinter account<br><b>${esc(u)}</b></div><a href="${ARES_SITE}" target="_blank" rel="noopener">📚 Ares Revision ↗</a><a href="https://frontlineswarfare.vercel.app" target="_blank" rel="noopener">🎖️ Frontline Warzone ↗</a>${FLOOF ? `<a href="${FLOOF}">☁️ Floof AI</a>` : ""}<button type="button" data-out>↩ Sign out</button>` : "";
    const o = menu.querySelector("[data-out]"); if (o) o.onclick = () => { localStorage.removeItem(SESS); sessionStorage.removeItem(SESS); menu.classList.remove("on"); render(); emit(); };
  }
  pill.onclick = e => { e.stopPropagation(); if (current()) { placeMenu(); menu.classList.toggle("on"); } else open(); };
  document.addEventListener("click", e => { if (!menu.contains(e.target)) menu.classList.remove("on"); });
  addEventListener("storage", e => { if (e.key === SESS) { render(); emit(); } });
  const away = () => pill.classList.toggle("away", !!(document.pointerLockElement || document.fullscreenElement)); // keep out of the way in games
  document.addEventListener("pointerlockchange", away); document.addEventListener("fullscreenchange", away);

  // sign-in window
  const ov = document.createElement("div"); ov.className = "mwa-ov";
  ov.innerHTML = `<form class="mwa-box" autocomplete="on"><button type="button" class="mwa-x" aria-label="Close">✕</button>
    <div class="lg">${HEX}</div><div class="mwa-eb">MagicWinter account</div><h2>Welcome</h2>
    <div class="mwa-sub">One account for every <b>MagicWinter Studio</b> app.</div>
    <div class="mwa-apps"><span>${MINI} MagicWinter</span><span>🎖️ Frontline</span><span>☁️ Floof AI</span></div>
    <div class="mwa-tabs"><button type="button" class="on" data-m="in">Sign in</button><button type="button" data-m="up">Create account</button></div>
    <input type="text" name="u" placeholder="Username" autocomplete="username" maxlength="20" required>
    <input type="password" name="p" placeholder="Password" autocomplete="current-password" required>
    <input type="password" name="p2" placeholder="Confirm password" autocomplete="new-password" style="display:none">
    <label class="mwa-row mwa-sm" style="cursor:pointer"><input type="checkbox" name="k" checked> Keep me signed in on this device</label>
    <div class="mwa-err" role="alert"></div><button class="mwa-go" type="submit">Sign in</button>
    </form>`;
  document.body.appendChild(ov);
  const f = ov.querySelector("form"), err = t => ov.querySelector(".mwa-err").textContent = t;
  let fails = 0, lock = 0, mode = "in";
  const setMode = m => { mode = m; ov.querySelectorAll(".mwa-tabs button").forEach(b => b.classList.toggle("on", b.dataset.m === m)); f.p2.style.display = m === "up" ? "" : "none"; f.p.autocomplete = m === "up" ? "new-password" : "current-password"; f.querySelector(".mwa-go").textContent = m === "up" ? "Create account" : "Sign in"; err(""); };
  ov.querySelectorAll(".mwa-tabs button").forEach(b => b.onclick = () => setMode(b.dataset.m));
  function open() { setMode(mode); ov.classList.add("on"); setTimeout(() => f.u.focus(), 50); }
  const close = () => { ov.classList.remove("on"); f.p.value = ""; };
  ov.querySelector(".mwa-x").onclick = close; ov.addEventListener("click", e => { if (e.target === ov) close(); });
  addEventListener("keydown", e => { if (e.key === "Escape") { close(); menu.classList.remove("on"); } });
  f.onsubmit = async e => {
    e.preventDefault();
    const username = f.u.value.trim(), pw = f.p.value, go = f.querySelector(".mwa-go");
    if (!/^[a-zA-Z0-9][a-zA-Z0-9_]{2,19}$/.test(username)) return err("Username: 3–20 letters, numbers or _.");
    if (!pw) return err("Enter your password.");
    if (mode === "up") { if (pw.length < 6) return err("Password needs at least 6 characters."); if (pw !== f.p2.value) return err("Passwords don't match."); }
    if (Date.now() < lock) return err(`Too many tries — wait ${Math.ceil((lock - Date.now()) / 1000)}s.`);
    go.disabled = true; go.textContent = "Checking…";
    try {
      const r = await mwAuth(mode, username, pw);
      if (!r.ok) { if (r.bad && ++fails >= 5) { lock = Date.now() + 60000; fails = 0; } return err(r.error); }
      fails = 0;
      const keep = f.k.checked, rec = JSON.stringify({ kind: "mw", user: r.user, token: r.token, until: keep ? Date.now() + 30 * 864e5 : 0 });
      (keep ? localStorage : sessionStorage).setItem(SESS, rec);
      close(); render(); emit();
    } finally { go.disabled = false; go.textContent = mode === "up" ? "Create account" : "Sign in"; }
  };
  window.MWAccount = { user: () => current()?.user || null, signIn: open, signOut: () => menu.querySelector("[data-out]")?.click() };
  render(); emit();
})();
