#!/bin/bash
set -e

# CLEANUP SCRIPT - Monitoring Stack
# Removes: Node Exporter, Postgres Exporter, Alertmanager, Prometheus, Grafana
# Run this BEFORE re-running monitoring.sh for a clean install

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root!"
  exit 1
fi

echo "=================================================="
echo " Cleaning up Monitoring Stack..."
echo "=================================================="

# -------------------------------
# Stop & Disable All Services
# -------------------------------
echo ""
echo "=== Stopping Services ==="
for svc in grafana-server prometheus alertmanager postgres_exporter node_exporter; do
  if systemctl is-active --quiet $svc 2>/dev/null; then
    systemctl stop $svc
    echo "  ✔ Stopped $svc"
  else
    echo "  - $svc was not running"
  fi

  if systemctl is-enabled --quiet $svc 2>/dev/null; then
    systemctl disable $svc
    echo "  ✔ Disabled $svc"
  fi
done

# -------------------------------
# Remove Systemd Unit Files
# -------------------------------
echo ""
echo "=== Removing Systemd Units ==="
for unit in node_exporter postgres_exporter alertmanager prometheus; do
  if [ -f /etc/systemd/system/${unit}.service ]; then
    rm -f /etc/systemd/system/${unit}.service
    echo "  ✔ Removed ${unit}.service"
  fi
done
systemctl daemon-reload

# -------------------------------
# Remove Binaries
# -------------------------------
echo ""
echo "=== Removing Binaries ==="
for bin in node_exporter postgres_exporter alertmanager amtool prometheus promtool; do
  if [ -f /usr/local/bin/$bin ]; then
    rm -f /usr/local/bin/$bin
    echo "  ✔ Removed /usr/local/bin/$bin"
  fi
done

# -------------------------------
# Remove Config & Data Directories
# -------------------------------
echo ""
echo "=== Removing Config & Data ==="

dirs=(
  /etc/prometheus
  /var/lib/prometheus
  /etc/alertmanager
  /var/lib/alertmanager
)

for dir in "${dirs[@]}"; do
  if [ -d "$dir" ]; then
    rm -rf "$dir"
    echo "  ✔ Removed $dir"
  fi
done

# -------------------------------
# Remove Grafana
# -------------------------------
echo ""
echo "=== Removing Grafana ==="
if rpm -q grafana &>/dev/null; then
  dnf remove -y grafana > /dev/null
  echo "  ✔ Grafana package removed"
fi

# Remove Grafana repo
if [ -f /etc/yum.repos.d/grafana.repo ]; then
  rm -f /etc/yum.repos.d/grafana.repo
  echo "  ✔ Grafana repo removed"
fi

# Remove Grafana data
for dir in /var/lib/grafana /etc/grafana /var/log/grafana; do
  if [ -d "$dir" ]; then
    rm -rf "$dir"
    echo "  ✔ Removed $dir"
  fi
done

# -------------------------------
# Clean up /tmp leftovers
# -------------------------------
echo ""
echo "=== Cleaning /tmp ==="
rm -f /tmp/node_exporter*.tar.gz
rm -f /tmp/postgres_exporter*.tar.gz
rm -f /tmp/alertmanager*.tar.gz
rm -f /tmp/prometheus*.tar.gz
rm -rf /tmp/node_exporter*/
rm -rf /tmp/postgres_exporter*/
rm -rf /tmp/alertmanager*/
rm -rf /tmp/prometheus*/
echo "  ✔ /tmp cleaned"

# -------------------------------
# Final Verification
# -------------------------------
echo ""
echo "=== Verifying Cleanup ==="
ALL_CLEAN=true

for svc in node_exporter postgres_exporter alertmanager prometheus grafana-server; do
  if systemctl is-active --quiet $svc 2>/dev/null; then
    echo "  ✘ $svc still running!"
    ALL_CLEAN=false
  else
    echo "  ✔ $svc not running"
  fi
done

for bin in node_exporter postgres_exporter alertmanager prometheus; do
  if [ -f /usr/local/bin/$bin ]; then
    echo "  ✘ Binary still exists: /usr/local/bin/$bin"
    ALL_CLEAN=false
  else
    echo "  ✔ /usr/local/bin/$bin removed"
  fi
done

echo ""
if [ "$ALL_CLEAN" = true ]; then
  echo "=================================================="
  echo " ✔ Cleanup complete! Safe to run monitoring.sh"
  echo "=================================================="
else
  echo "=================================================="
  echo " ✘ Some components may still remain - check above"
  echo "=================================================="
fi
