#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
RESTIC_VER="0.19.1"
CONF_DIR="/gleba/.restic-comp"
REPO_FILE="${CONF_DIR}/repo"
KEY_FILE="${CONF_DIR}/key"
DEFAULT_PATHS=("/etc" "/var/www" "/opt" "/srv")

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 '<REPO_URL>' '<REPO_KEY>' [path1 path2 ...]"
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: sudo $0 '<REPO_URL>' '<REPO_KEY>' [path1 path2 ...]"
  echo "Example: sudo $0 'rest:https://skerja:PASS@example.tea-mobile.com/skerja/' 'KEY123' /etc /var/www"
  exit 1
fi

REPO_URL="$1"
REPO_KEY="$2"
shift 2

# Use custom paths if provided, otherwise filter DEFAULT_PATHS to ones that exist
TARGETS=()
if [[ $# -gt 0 ]]; then
  for p in "$@"; do [[ -e "$p" ]] && TARGETS+=("$p"); done
else
  for p in "${DEFAULT_PATHS[@]}"; do [[ -e "$p" ]] && TARGETS+=("$p"); done
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "[!] None of the target paths exist on this host."
  exit 1
fi

# --- 1. Install static restic binary if missing ---
if ! command -v restic >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac

  echo "[*] Downloading restic v${RESTIC_VER} (${ARCH})..."
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  URL="https://github.com/restic/restic/releases/download/v${RESTIC_VER}/restic_${RESTIC_VER}_linux_${ARCH}.bz2"
  curl -fsSL "$URL" -o "${TMP_DIR}/restic.bz2"
  bunzip2 -f "${TMP_DIR}/restic.bz2"
  install -m 0755 "${TMP_DIR}/restic" /usr/local/bin/restic
fi

# --- 2. Store credentials securely on disk ---
mkdir -p "$CONF_DIR"
chmod 700 "$CONF_DIR"
printf '%s\n' "$REPO_URL" > "$REPO_FILE"
printf '%s\n' "$REPO_KEY" > "$KEY_FILE"
chmod 600 "$REPO_FILE" "$KEY_FILE"

# --- 3. Initialize repository (idempotent) ---
echo "[*] Checking repository..."
if ! restic --repository-file "$REPO_FILE" --password-file "$KEY_FILE" -o rest.connections=2 cat config >/dev/null 2>&1; then
  echo "[*] Initializing new repository..."
  restic --repository-file "$REPO_FILE" --password-file "$KEY_FILE" -o rest.connections=2 init
fi

# --- 4. Take Minute-0 Baseline Snapshot ---
echo "[*] Taking baseline snapshot of: ${TARGETS[*]}"
restic --repository-file "$REPO_FILE" --password-file "$KEY_FILE" \
  -o rest.connections=2 \
  backup "${TARGETS[@]}" \
  --tag baseline \
  --one-file-system \
  --exclude-caches

# --- 5. Install 'bkp' helper wrapper ---
cat <<'EOF' > /usr/local/bin/bkp
#!/usr/bin/env bash
set -euo pipefail

REPO_FILE="/gleba/.restic-comp/repo"
KEY_FILE="/gleba/.restic-comp/key"
RESTIC=(restic --repository-file "$REPO_FILE" --password-file "$KEY_FILE" -o rest.connections=2)

case "${1:-help}" in
  snap)
    shift
    "${RESTIC[@]}" backup "$@" --one-file-system --exclude-caches
    ;;
  list)
    "${RESTIC[@]}" snapshots
    ;;
  diff)
    # Diffs the oldest 'baseline' snapshot against the latest snapshot
    BASE_ID=$("${RESTIC[@]}" snapshots --tag baseline --json | grep -oE '"short_id":"[^"]+"' | head -n1 | cut -d'"' -f4)
    LATEST_ID=$("${RESTIC[@]}" snapshots --latest 1 --json | grep -oE '"short_id":"[^"]+"' | tail -n1 | cut -d'"' -f4)
    echo "[*] Diffing baseline (${BASE_ID}) -> latest (${LATEST_ID})"
    "${RESTIC[@]}" diff "$BASE_ID" "$LATEST_ID"
    ;;
  restore)
    # Restores a specific path from baseline into /tmp/restore
    TARGET_PATH="${2:?Usage: bkp restore <path-to-restore>}"
    BASE_ID=$("${RESTIC[@]}" snapshots --tag baseline --json | grep -oE '"short_id":"[^"]+"' | head -n1 | cut -d'"' -f4)
    mkdir -p /tmp/restore
    "${RESTIC[@]}" restore "$BASE_ID" --target /tmp/restore --include "$TARGET_PATH"
    echo "[*] Restored to /tmp/restore${TARGET_PATH}"
    ;;
  *)
    echo "Usage: bkp {snap <paths...>|list|diff|restore <path>}"
    ;;
esac
EOF
chmod 700 /usr/local/bin/bkp

echo "[+] Done. Baseline uploaded. Use 'bkp list', 'bkp snap <paths>', 'bkp diff', or 'bkp restore <path>'."
