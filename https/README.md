# HTTPS Front-End Connector

This module (`openclaw-gateway-https.sh`) automates a LAN-hardened HTTPS front
end for the OpenClaw gateway. It keeps the gateway loopback-only while exposing
it to other LAN hosts via Caddy + mkcert, and documents a tested Mac Safari
onboarding flow.

---

## Quick start (HTTPS module)

```bash
chmod +x openclaw-gateway-https.sh
./openclaw-gateway-https.sh -d gateway-proxy.local   # pick any hostname
```

Re-run the script any time. It is idempotent: only regenerates certs when the
hostname/IP set changes, only rewrites config when needed, and auto reloads
Caddy. Options:

- `-d <domain>` – hostname clients use (default `gateway.local`)
- `-p <port>` – OpenClaw gateway WS port if not 18789
- `-h` – help text

The script prints a summary with the HTTPS URL and cert locations.

---

## What the script handles

1. **Prereqs** – Installs Caddy, mkcert, and NSS tools if missing.
2. **Gateway bind** – Forces `gateway.bind = "loopback"` and restarts the
   gateway if required.
3. **TLS assets** – Detects your current LAN IP + hostname, issues certs into
   `/etc/ssl/openclaw/` (`fullchain.pem`, `privkey.pem`, `.san` tracker).
4. **Reverse proxy** – Writes `/etc/caddy/Caddyfile` with a managed block,
   reserves port 443 for HTTPS (internal HTTP helper runs on 18080), proxies to
   `127.0.0.1:<port>`.
5. **Service reload** – Enables/reloads Caddy, then prints the summary.

If ports 80/443 are already taken (e.g., nginx), move that service to alternate
ports (8080/8443 or similar) before running the script, or adapt the script to
skip Caddy and use nginx as the TLS proxy.

---

## Trust + browser onboarding (Mac example)

1. **Export the CA** – From the gateway host: `~/.local/share/mkcert/rootCA.pem`.
2. **Copy to the Mac** – e.g., `scp user@gateway:~/.local/share/mkcert/rootCA.pem ~/Downloads/`.
3. **Install + trust** – Double-click the file → Keychain Access → add to the
   *System* keychain → open the certificate, expand **Trust**, set **When using
   this certificate = Always Trust**, save (enter password if prompted).
4. **Host resolution** – Add an `/etc/hosts` entry on the Mac pointing your
   chosen hostname to the gateway’s current LAN IP (e.g., `192.168.1.48   gateway-proxy.local`).
5. **Open Control UI** – Visit `https://<hostname>/` in the browser. When the UI
   prompts for auth, paste your gateway token (e.g., `token123`).
6. **Pair the device** – First-time remote browsers trigger “pairing required.”
   On the gateway host, run `openclaw devices list` and approve the pending
   request: `openclaw devices approve <requestId> --name "MacBook Safari"`. Once
   paired, click **Connect** in the UI; subsequent visits reuse the pairing.

Repeat steps 1–6 for any other LAN devices.

---

## Cert management + DHCP changes

- The current hostname/IP SAN list is tracked in `/etc/ssl/openclaw/.san`.
- Re-run the script whenever your LAN IP changes; it auto-regenerates the cert
  only when the SAN list differs.
- To force a fresh cert, delete `.san` and rerun the script.

---

## Logs + troubleshooting

| Component  | How to inspect |
| ---------- | -------------- |
| Script     | Run output in the terminal |
| Caddy      | `journalctl -xeu caddy.service` |
| OpenClaw   | `journalctl -xeu openclaw-gateway.service` |
| nginx (if used)| `journalctl -xeu nginx.service` |

Common fixes:
- **Port in use**: `sudo ss -tulpn | grep ':80'` / `:443`, move the conflicting
  service (nginx) to other ports.
- **Browser says device identity required**: ensure HTTPS with trusted cert +
  approve the device via `openclaw devices approve ...`.
- **Unauthorized/token missing**: paste the gateway token in the Control UI
  settings (top-right gear) and click **Connect**.

---

## Security notes

- Gateway remains loopback-only; only Caddy talks to it. Never expose
  `ws://<host>:18789` externally.
- TLS key (`/etc/ssl/openclaw/privkey.pem`) is `600` owned by `caddy`.
- Changing `gateway.auth.token` requires `openclaw gateway install --force`
  followed by `openclaw gateway restart` so the systemd service uses the new
  secret.

---

## Connector context

This HTTPS module is part of the broader **OpenClaw Connect** project. Other
connection types (SSH tunnels, Tailscale, reverse proxies) live alongside this
folder, each with their own README. See the repo root for the full index.

---

## Extras

- Schedule the script via cron/systemd timer for automatic renewal checks.
- Extend the script or this README with host-specific notes (e.g., notifying via
  WhatsApp when the gateway IP changes).

This document should make it easy for anyone (future you included) to rerun the
setup, trust the cert on new devices, and pair browsers securely.
