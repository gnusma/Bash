#!/bin/bash
set -e

echo "=== Zabbix SMART setup for Debian / Proxmox ==="

# ---- checks ----
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run this script as root"
  exit 1
fi

# ---- variables ----
ZABBIX_USER="zabbix"
SUDOERS_SMART="/etc/sudoers.d/zabbix-smartctl"
SUDOERS_TTY="/etc/sudoers.d/zabbix-requiretty"
SUDOERS_PATH="/etc/sudoers.d/zabbix-path"

# ---- install smartmontools ----
echo "[1/7] Installing smartmontools..."
apt update -qq
apt install -y smartmontools sudo

# ---- detect smartctl path ----
SMARTCTL_PATH="$(command -v smartctl)"

if [[ -z "$SMARTCTL_PATH" ]]; then
  echo "ERROR: smartctl not found"
  exit 1
fi

SMARTCTL_PATH="$(readlink -f "$SMARTCTL_PATH")"
echo "Detected smartctl path: $SMARTCTL_PATH"

# ---- create sudoers rule ----
echo "[2/7] Creating sudoers rule for smartctl..."

cat <<EOF > "$SUDOERS_SMART"
${ZABBIX_USER} ALL=(ALL) NOPASSWD: ${SMARTCTL_PATH} *
EOF

chmod 440 "$SUDOERS_SMART"

# ---- disable requiretty if present ----
echo "[3/7] Checking requiretty..."
if grep -R "requiretty" /etc/sudoers /etc/sudoers.d/* &>/dev/null; then
  echo "requiretty detected – disabling for zabbix"
  cat <<EOF > "$SUDOERS_TTY"
Defaults:${ZABBIX_USER} !requiretty
EOF
  chmod 440 "$SUDOERS_TTY"
else
  echo "requiretty not present – OK"
fi

# ---- fix secure_path ----
echo "[4/7] Ensuring secure_path includes sbin..."
cat <<EOF > "$SUDOERS_PATH"
Defaults:${ZABBIX_USER} secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF

chmod 440 "$SUDOERS_PATH"

# ---- restart agent ----
echo "[5/7] Restarting Zabbix Agent 2..."
systemctl restart zabbix-agent2
systemctl is-active --quiet zabbix-agent2 && echo "Agent restarted successfully"

# ---- test smartctl as zabbix ----
echo "[6/7] Testing smartctl discovery as zabbix user..."
if sudo -u "$ZABBIX_USER" sudo smartctl --scan-open; then
  echo "SMART discovery test: OK"
else
  echo "ERROR: SMART discovery still failing"
  exit 1
fi

# ---- test health read if possible ----
FIRST_DISK="$(smartctl --scan-open | awk 'NR==1 {print $1}')"
if [[ -n "$FIRST_DISK" ]]; then
  echo "[7/7] Testing SMART health on $FIRST_DISK..."
  sudo -u "$ZABBIX_USER" sudo smartctl -H "$FIRST_DISK" || true
fi

echo "=== SMART by Zabbix agent 2 setup COMPLETE ==="
