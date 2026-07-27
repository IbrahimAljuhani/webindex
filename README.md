```
██╗    ██╗███████╗██████╗ ██╗███╗   ██╗██████╗ ███████╗██╗  ██╗
██║    ██║██╔════╝██╔══██╗██║████╗  ██║██╔══██╗██╔════╝╚██╗██╔╝
██║ █╗ ██║█████╗  ██████╔╝██║██╔██╗ ██║██║  ██║█████╗   ╚███╔╝
██║███╗██║██╔══╝  ██╔══██╗██║██║╚██╗██║██║  ██║██╔══╝   ██╔██╗
╚███╔███╔╝███████╗██████╔╝██║██║ ╚████║██████╔╝███████╗██╔╝ ██╗
 ╚══╝╚══╝ ╚══════╝╚═════╝ ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝
```

**Secure, isolated, multi-domain Nginx + Cloudflare + Let's Encrypt setup for static sites — in one script**

[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/) [![Platform](https://img.shields.io/badge/platform-Ubuntu%2024.04-E95420?style=flat-square&logo=ubuntu&logoColor=white)](https://ubuntu.com) [![Cloudflare](https://img.shields.io/badge/proxy-Cloudflare-F38020?style=flat-square&logo=cloudflare&logoColor=white)](https://cloudflare.com) [![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

> **📌 Scope: static websites only.** This project serves plain HTML/CSS/JS files — landing pages, portfolios, documentation sites, brochure sites. It does **not** run PHP, Node.js, Python, databases, WordPress, or any other server-side application. If your site needs a backend or an app server, this isn't the right tool.

---

## What is webindex?

`webindex` is a single Bash script (`nginx-cf-setup.sh`) that turns a fresh Ubuntu server into a hardened, Cloudflare-only host **for static pages** — with a free, auto-renewing SSL certificate, isolated file permissions per site, and a firewall that only trusts Cloudflare's edge network.

Run it, answer a few prompts, drop your `index.html` (and assets) into the generated folder, and you get a production-ready static site host with an A-grade security posture — no manual Nginx or Certbot configuration required.

```bash
sudo ./nginx-cf-setup.sh
```

---

## The Problem

Standing up a simple static site "the right way" usually means manually:

- Installing and configuring Nginx, Certbot, and a firewall
- Figuring out Cloudflare's real-IP headers so your logs and rate-limiting don't just show Cloudflare's own IPs
- Locking the origin server so it only accepts traffic from Cloudflare — not the raw internet
- Getting file permissions right so one compromised site's files aren't world-readable
- Remembering to hide the Nginx version banner, add HSTS, and set the other security headers
- Not breaking everything the second time you run the same setup for a second domain

`webindex` automates all of it, and is designed from the ground up to be **re-run safely** for additional domains on the same server.

---

## Features

| Feature | Details |
|---|---|
| **One command, full setup** | Installs Nginx, Certbot, UFW, and issues a real Let's Encrypt certificate |
| **Cloudflare-only firewall** | UFW is configured to accept ports 80/443 only from Cloudflare's published IP ranges |
| **Real visitor IPs** | `real_ip_header CF-Connecting-IP` configured automatically so logs show actual visitors, not Cloudflare edge IPs |
| **Multi-domain safe** | A shared catch-all config blocks direct-IP access once — re-running for a new domain never causes an Nginx `duplicate default_server` error |
| **Optional `www` support** | Choose to include `www.yourdomain.com` in the certificate and config with a single prompt |
| **Per-site file isolation** | Each site's files are owned by a dedicated user, `750`/`640` permissions, zero access for "others" |
| **Hardened by default** | `server_tokens off`, HSTS, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` |
| **No login shell by default** | The web file owner is created with `/usr/sbin/nologin` — it only needs to own files, not log in |
| **Idempotent firewall rules** | Re-running the script doesn't pile up duplicate UFW rules |
| **Fail-fast validation** | Invalid domain/email formats, missing dependencies, and failed Cloudflare IP lookups all stop the script immediately with a clear message — instead of silently continuing in a broken state |

### Out of Scope

`webindex` intentionally does **not** handle:

- PHP, Node.js, Python, or any server-side runtime
- Databases (MySQL, PostgreSQL, MongoDB, etc.)
- WordPress or other CMS platforms that need an app server
- Reverse-proxying to a backend app

If you need any of the above, look at a general-purpose Nginx + app-server setup instead — this script is deliberately scoped to static files only, which is also what keeps its security model (isolated, read-mostly file permissions, no execution) simple and solid.

---

## How It Works

```
                    ┌─────────────────────┐
                    │      Visitor        │
                    └──────────┬──────────┘
                               │ HTTPS
                               ▼
                    ┌─────────────────────┐
                    │   Cloudflare Edge    │  ← DNS: Proxied (orange cloud)
                    │  (CDN / SSL / WAF)   │
                    └──────────┬──────────┘
                               │ HTTPS (Full Strict)
                               ▼
              ┌───────────────────────────────────┐
              │         Your Ubuntu Server          │
              │  ┌─────────────────────────────┐  │
              │  │  UFW  — Cloudflare IPs only  │  │
              │  └───────────────┬─────────────┘  │
              │                  ▼                  │
              │  ┌─────────────────────────────┐  │
              │  │  Nginx (real_ip + HSTS +     │  │
              │  │  security headers)           │  │
              │  └───────────────┬─────────────┘  │
              │                  ▼                  │
              │   /var/www/yourdomain.com/html      │
              │   (owned by isolated site user)     │
              └───────────────────────────────────┘
```

**Important:** during the setup itself, DNS must be **DNS Only** (grey cloud) so Let's Encrypt can validate domain ownership directly. Only *after* the certificate is issued do you switch DNS to **Proxied** (orange cloud) — the script tells you this at the end, and reminds you every time.

---

## Requirements

- Ubuntu 22.04 or 24.04 (tested on 24.04)
- Root / sudo access
- A domain with its nameservers pointed at Cloudflare
- The domain's A record already created and pointing at your server's IP
- A static site (HTML/CSS/JS) ready to drop into the generated web root — no build/runtime step needed

---

## Quick Start

```bash
git clone https://github.com/IbrahimAljuhani/webindex.git
cd webindex
chmod +x nginx-cf-setup.sh
sudo ./nginx-cf-setup.sh
```

You'll be asked for:

1. **Domain name** (e.g. `example.com`)
2. Whether to also include `www.example.com`
3. **Email** for Let's Encrypt renewal notices
4. **System username** to own the site's files (created automatically if it doesn't exist)
5. Confirmation that DNS is set to **DNS Only** and already points at this server

The script then installs everything, configures the firewall, issues the certificate, and applies the final hardened Nginx config — all in one run. It also drops a placeholder `index.html` into the web root so you can confirm the site loads immediately; replace it with your own static files at `/var/www/yourdomain.com/html`.

### Adding a second domain

Just run it again:

```bash
sudo ./nginx-cf-setup.sh
```

Enter the new domain when prompted. The shared catch-all block and firewall rules are reused automatically — no conflicts, no manual cleanup.

---

## Post-Setup (required)

Once the script finishes, it will remind you to:

1. Open the Cloudflare dashboard → **DNS**
2. Switch the domain's cloud icon from 🩶 grey (DNS Only) to 🟠 orange (**Proxied**)
3. Go to **SSL/TLS → Overview** and set the mode to **Full (Strict)**

Until you do this, your site will be unreachable from browsers — the firewall only accepts connections from Cloudflare's network, so DNS must actually route through Cloudflare.

---

## Troubleshooting

**Certbot fails with a `403` error mentioning an IP like `2606:4700:...` or `104.21.x.x`**
That IP range belongs to Cloudflare, not your server. It means the domain (often the `www` record) is still set to **Proxied** during initial setup. Switch it to **DNS Only**, wait for DNS to propagate, and re-run the script.

**Site works from the server itself (`curl -H "Host: yourdomain.com" http://127.0.0.1`) but not from a browser**
This almost always means DNS is still on **DNS Only** *after* setup finished. Switch it to **Proxied** in Cloudflare — see [Post-Setup](#post-setup-required) above. Propagation can take a minute or two.

**`ERR_TOO_MANY_REDIRECTS` in the browser**
Your Cloudflare SSL/TLS mode is set to **Flexible**. Change it to **Full (Strict)** — the origin already has a real Let's Encrypt certificate.

---

## Roadmap

- [x] Cloudflare-only UFW firewall with idempotent rule management
- [x] Automatic Let's Encrypt certificate issuance and renewal
- [x] Multi-domain safe catch-all config (no `duplicate default_server`)
- [x] Optional `www` subdomain support
- [x] Per-site file isolation with dedicated, shell-less users
- [x] Security headers (HSTS, nosniff, frame options, referrer policy)
- [x] Nginx version banner hidden (`server_tokens off`)
- [ ] Pre-flight DNS check before calling Certbot
- [ ] Config backup before overwrite

---

## Contributing

Issues and pull requests are welcome. For significant changes, please open an issue first to discuss what you'd like to change.

---

## License

Released under the [MIT License](LICENSE).

Copyright © 2026 Ibrahim Aljuhani · [ia.sa](https://ia.sa)

---

**[GitHub](https://github.com/IbrahimAljuhani/webindex)** · **[Ibrahim Aljuhani](https://github.com/IbrahimAljuhani)**
