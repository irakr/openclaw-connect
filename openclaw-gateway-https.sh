#!/usr/bin/env bash
# openclaw-gateway-https.sh
# Idempotent setup for HTTPS front-end (Caddy + mkcert) to reach an OpenClaw gateway from LAN hosts.

set -euo pipefail

DEFAULT_DOMAIN="gateway.local"
DEFAULT_PORT="18789"
CERT_DIR="/etc/ssl/openclaw"
CADDYFILE="/etc/caddy/Caddyfile"
SAN_RECORD="${CERT_DIR}/.san"
MKCERT_BIN="/usr/local/bin/mkcert"
CADDY_SERVICE="caddy"
LOG_PREFIX="[openclaw-https]"

log()  { printf "%s %s\n" "$LOG_PREFIX" "$*"; }
die()  { printf "%s ERROR: %s\n" "$LOG_PREFIX" "$*" >&2; exit 1; }
run()  { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

usage() {
  cat <<EOF
Usage: $0 [-d DOMAIN] [-p PORT] [-h]
  -d DOMAIN   Hostname clients will use (default: ${DEFAULT_DOMAIN})
  -p PORT     Gateway WebSocket port (default: ${DEFAULT_PORT})
  -h          Show help
Examples:
  $0
  $0 -d ai-hub.lan
EOF
}

DOMAIN="${DEFAULT_DOMAIN}"
PORT="${DEFAULT_PORT}"

while getopts ":d:p:h" opt; do
  case "$opt" in
    d) DOMAIN="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null; then echo "apt"; return
  elif command -v dnf >/dev/null; then echo "dnf"; return
  elif command -v yum >/dev/null; then echo "yum"; return
  elif command -v pacman >/dev/null; then echo "pacman"; return
  fi
  die "Unsupported distro. Install Caddy + mkcert manually."
}

install_caddy() {
  if command -v caddy >/dev/null; then
    log "Caddy already installed."
    return
  fi
  log "Installing Caddy..."
  case "$(detect_pkg_manager)" in
    apt)
      run apt-get update
      run apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
      curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | run gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
      curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | run tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
      run apt-get update
      run apt-get install -y caddy
      ;;
    dnf|yum)
      run $pkg install -y 'dnf-command(config-manager)' || true
      run $pkg config-manager --add-repo https://dl.cloudsmith.io/public/caddy/stable/rpm.repo
      run $pkg install -y caddy
      ;;
    pacman)
      run pacman -Sy --needed --noconfirm caddy
      ;;
  esac
}

install_mkcert() {
  if [[ -x "$MKCERT_BIN" ]]; then
    log "mkcert already installed at $MKCERT_BIN"
    return
  fi
  if command -v mkcert >/dev/null; then
    log "mkcert found at $(command -v mkcert)"
    return
  fi
  log "Installing mkcert (static binary)..."
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64) URL="https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.4-linux-amd64" ;;
    arm64|aarch64) URL="https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.4-linux-arm64" ;;
    *) die "Unsupported architecture '$ARCH' for mkcert auto-install." ;;
  esac
  tmp=$(mktemp)
  curl -fsSL "$URL" -o "$tmp"
  run install -m 0755 "$tmp" "$MKCERT_BIN"
  rm -f "$tmp"
}

install_nss_tools() {
  if command -v certutil >/dev/null; then
    return
  fi
  case "$(detect_pkg_manager)" in
    apt) run apt-get install -y libnss3-tools ;;
    dnf|yum) run $pkg install -y nss-tools ;;
    pacman) run pacman -Sy --needed --noconfirm nss ;;
  esac
}

ensure_ca_installed() {
  if [[ -f "${HOME}/.local/share/mkcert/rootCA.pem" ]]; then
    log "mkcert CA already installed for user $USER."
    return
  fi
  log "Installing mkcert local CA..."
  mkcert -install >/dev/null
}

ensure_openclaw_loopback() {
  require_cmd openclaw
  local current
  current=$(openclaw config get gateway.bind 2>/dev/null || echo "")
  if [[ "$current" != "\"loopback\"" && "$current" != "loopback" ]]; then
    log "Setting gateway.bind to loopback"
    openclaw config set gateway.bind loopback >/dev/null
    log "Restarting OpenClaw gateway"
    openclaw gateway restart >/dev/null
  else
    log "gateway.bind already loopback."
  fi
}

ensure_cert_dir() {
  run mkdir -p "$CERT_DIR"
  run chown root:root "$CERT_DIR"
  run chmod 755 "$CERT_DIR"
}

current_lan_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

need_new_cert() {
  local desired="$1"
  if [[ ! -f "$SAN_RECORD" ]]; then
    return 0
  fi
  local existing
  existing=$(<"$SAN_RECORD")
  [[ "$existing" != "$desired" ]]
}

issue_cert() {
  ensure_cert_dir
  local ip san desired
  ip=$(current_lan_ip || true)
  if [[ -z "$ip" ]]; then
    log "Unable to detect LAN IP; continuing with hostname-only SAN."
  fi
  san="$DOMAIN"
  if [[ -n "$ip" ]]; then
    san="$san $ip"
  fi
  desired="$san"
  if need_new_cert "$desired"; then
    log "Generating certificate for SAN: $san"
    run "$MKCERT_BIN" -key-file "${CERT_DIR}/privkey.pem" -cert-file "${CERT_DIR}/fullchain.pem" $san >/dev/null
    run chown caddy:caddy "${CERT_DIR}/privkey.pem" "${CERT_DIR}/fullchain.pem"
    run chmod 600 "${CERT_DIR}/privkey.pem"
    printf "%s" "$desired" | run tee "$SAN_RECORD" >/dev/null
  else
    log "Existing certificate already matches SAN: $desired"
  fi
}

render_caddyfile() {
  cat <<EOF
# Managed by openclaw-gateway-https.sh — manual changes will be overwritten.
{
    http_port 18080
    https_port 443
}

https://${DOMAIN} {
    tls ${CERT_DIR}/fullchain.pem ${CERT_DIR}/privkey.pem

    encode gzip
    reverse_proxy 127.0.0.1:${PORT} {
        header_up Host {http.request.host}
        header_up X-Forwarded-For {http.request.remote}
        header_up X-Forwarded-Proto https
    }
}
EOF
}

write_caddyfile() {
  log "Writing managed Caddyfile to ${CADDYFILE}"
  render_caddyfile | run tee "$CADDYFILE" >/dev/null
}

reload_caddy() {
  log "Reloading Caddy"
  run systemctl enable --now "$CADDY_SERVICE"
  if ! run systemctl reload "$CADDY_SERVICE"; then
    log "Reload failed, restarting Caddy"
    run systemctl restart "$CADDY_SERVICE"
  fi
}

summary() {
  cat <<EOF

${LOG_PREFIX} HTTPS front-end ready.

  • URL: https://${DOMAIN}/
  • Gateway (loopback): ws://127.0.0.1:${PORT}
  • Cert files: ${CERT_DIR}/fullchain.pem, privkey.pem
  • To trust the cert on other machines, copy:
      ~/.local/share/mkcert/rootCA.pem
    …and import it into their certificate store.

Re-run this script anytime. If your LAN IP changes, it will regenerate the cert and reload Caddy automatically.
EOF
}

main() {
  require_cmd curl
  install_caddy
  install_mkcert
  install_nss_tools
  ensure_ca_installed
  ensure_openclaw_loopback
  issue_cert
  write_caddyfile
  reload_caddy
  summary
}

main "$@"
