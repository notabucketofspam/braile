#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
REST_SERVER_VER="0.14.0"
DATA_DIR="/srv/restic"
MAX_SIZE_BYTES="21474836480" # 20 GiB total cap
LISTEN_ADDR="127.0.0.1:8000"
CREDS_DIR="/gleba"

CREDS_OUT="$CREDS_DIR/creds.txt"


if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 <tunnel-domain> <host1> [host2 ...]"
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: sudo $0 <tunnel-domain> <host1> [host2 ...]"
  echo "Example: sudo $0 example.tea-mobile.com web01 db01 dc01"
  exit 1
fi

mkdir -p "$CREDS_DIR"
chmod 755 "$CREDS_DIR"

TUNNEL_DOMAIN="${1#https://}"
TUNNEL_DOMAIN="${TUNNEL_DOMAIN%/}"
shift

# --- 1. Detect architecture ---
case "$(uname -m)" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# --- 2. Install prerequisites (Arch) ---
echo "[*] Installing prerequisites via pacman..."
pacman -Sy --noconfirm --needed curl tar apache openssl

# --- 3. Download rest-server ---
echo "[*] Downloading rest-server v${REST_SERVER_VER} (${ARCH})..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REST_URL="https://github.com/restic/rest-server/releases/download/v${REST_SERVER_VER}/rest-server_${REST_SERVER_VER}_linux_${ARCH}.tar.gz"
curl -fsSL "$REST_URL" -o "${TMP_DIR}/rest-server.tar.gz"
tar -xzf "${TMP_DIR}/rest-server.tar.gz" -C "$TMP_DIR"
install -m 0755 "${TMP_DIR}/rest-server_${REST_SERVER_VER}_linux_${ARCH}/rest-server" /usr/local/bin/rest-server

# --- 4. Create unprivileged user & data directory ---
if ! id -u restic >/dev/null 2>&1; then
  useradd -r -s /usr/bin/nologin -d "$DATA_DIR" restic
fi

mkdir -p "$DATA_DIR"
chown restic:restic "$DATA_DIR"
chmod 0700 "$DATA_DIR"

# --- 5. Generate isolated per-host credentials ---
HTPASSWD_FILE="${DATA_DIR}/.htpasswd"
rm -f "$HTPASSWD_FILE"
touch "$HTPASSWD_FILE"
chown restic:restic "$HTPASSWD_FILE"
chmod 0600 "$HTPASSWD_FILE"

declare -A HOST_HTTP_PASS
declare -A HOST_REPO_KEY

echo "[*] Generating isolated credentials for $# host(s)..."
for HOST in "$@"; do
  HTTP_PASS="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20)"
  REPO_KEY="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 28)"
  htpasswd -B -b "$HTPASSWD_FILE" "$HOST" "$HTTP_PASS" >/dev/null 2>&1
  HOST_HTTP_PASS["$HOST"]="$HTTP_PASS"
  HOST_REPO_KEY["$HOST"]="$REPO_KEY"
done

# --- 6. Create systemd unit for rest-server ---
cat <<EOF > /etc/systemd/system/rest-server.service
[Unit]
Description=Restic REST Server on spoilage (Append-Only, Private Repos)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=restic
Group=restic
ExecStart=/usr/local/bin/rest-server \\
  --path ${DATA_DIR} \\
  --listen ${LISTEN_ADDR} \\
  --append-only \\
  --private-repos \\
  --max-size ${MAX_SIZE_BYTES} \\
  --log -
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=${DATA_DIR}

[Install]
WantedBy=multi-user.target
EOF

# --- 7. Start service ---
systemctl daemon-reload
systemctl enable --now rest-server.service
systemctl restart rest-server.service
# --- 8. Save & print credential sheet ---
{
  echo "=========================================="
  echo "  SPOILAGE REST-SERVER CREDENTIALS"
  echo "  Endpoint: https://${TUNNEL_DOMAIN}"
  echo "=========================================="
  echo ""
  for HOST in "$@"; do
    echo "Host: ${HOST}"
    echo "  Repo URL : rest:https://${HOST}:${HOST_HTTP_PASS[$HOST]}@${TUNNEL_DOMAIN}/${HOST}/"
    echo "  Repo Key : ${HOST_REPO_KEY[$HOST]}"
    echo ""
  done
} | tee "$CREDS_OUT"

# this used to be chmod 0600, but that was too secure :^)
chmod 0644 "$CREDS_OUT"
echo "[*] Saved credentials to ${CREDS_OUT} (chmod 644)."
