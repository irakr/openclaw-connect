# OpenClaw Connect

Utilities, scripts, and reference configs that help you connect OpenClaw
Gateways to clients (operators, browsers, tailnet nodes, etc.). Each connector
lives in its own subdirectory at the repo root with its own README, scripts, and
assets. This top-level README is the index.

## Current connectors

| Connector | Path | Status | Notes |
|-----------|------|--------|-------|
| HTTPS front-end (Caddy + mkcert) | `https/` | ✅ Implemented | Locks the gateway to loopback, serves HTTPS on LAN, documents Mac Safari onboarding. |
| SSH tunnel bridge | `ssh-tunnel/` | 🛠 Planned | Automate SSH port forwards / remote CLI defaults. |
| Tailscale Serve/Funnel | `tailscale/` | 🛠 Planned | Opinionated Tailnet exposure with identity headers. |
| Reverse proxy presets | `reverse-proxy/` | 🛠 Planned | nginx/Traefik recipes for WAN exposure. |

> Status legend: ✅ available · 🛠 planned/in-progress · 🔬 experimental

## Using a connector

1. Change into the connector directory you want, e.g. `cd https`.
2. Read its `README.md` for architecture, prerequisites, and usage.
3. Run the provided scripts or adapt the configs to your environment.
4. Improve the connector by editing its README/scripts directly; each folder is
   self-contained to keep diffs focused.

## Repository layout

```
openclaw-connect/
├── README.md         # Project overview + connector index
├── https/            # HTTPS/TLS front-end connector (current module)
│   ├── README.md
│   └── openclaw-gateway-https.sh
├── ssh-tunnel/       # (planned) SSH tunnel helper scripts
├── tailscale/        # (planned) Tailnet Serve/Funnel presets
└── reverse-proxy/    # (planned) nginx/Traefik recipes
```

Feel free to add new connectors as peer directories and update the table above
so readers can discover them from the root README.
