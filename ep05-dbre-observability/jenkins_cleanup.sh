#!/bin/bash
set -e

# ============================================================
# JENKINS CLEANUP SCRIPT
# Removes Jenkins + Java completely for fresh install
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root!"
  exit 1
fi

echo "=================================================="
echo " Cleaning up Jenkins..."
echo "=================================================="

# Stop Jenkins
echo ""
echo "=== Stopping Jenkins ==="
if systemctl is-active --quiet jenkins 2>/dev/null; then
  systemctl stop jenkins
  echo "  ✔ Jenkins stopped"
else
  echo "  - Jenkins was not running"
fi

if systemctl is-enabled --quiet jenkins 2>/dev/null; then
  systemctl disable jenkins
  echo "  ✔ Jenkins disabled"
fi

# Remove Jenkins package
echo ""
echo "=== Removing Jenkins ==="
if rpm -q jenkins &>/dev/null; then
  dnf remove -y jenkins > /dev/null
  echo "  ✔ Jenkins package removed"
else
  echo "  - Jenkins not installed"
fi

# Remove Jenkins data and config
echo ""
echo "=== Removing Jenkins Data ==="
for dir in /var/lib/jenkins /var/log/jenkins /var/cache/jenkins /etc/sysconfig/jenkins; do
  if [ -d "$dir" ] || [ -f "$dir" ]; then
    rm -rf "$dir"
    echo "  ✔ Removed $dir"
  fi
done

# Remove Jenkins repo and key
echo ""
echo "=== Removing Jenkins Repo ==="
rm -f /etc/yum.repos.d/jenkins.repo
rm -f /etc/pki/rpm-gpg/jenkins.io.key
rm -f /usr/share/keyrings/jenkins-keyring.asc
echo "  ✔ Jenkins repo removed"

# Remove Jenkins CLI jar
rm -f /tmp/jenkins-cli.jar
echo "  ✔ Jenkins CLI removed"

# Remove Jenkinsfile from root if exists
rm -f /root/Jenkinsfile
rm -f /tmp/pg-dbre-job.xml
echo "  ✔ Temp files removed"

# Reload systemd
systemctl daemon-reload

# Final verification
echo ""
echo "=== Verifying Cleanup ==="
if systemctl is-active --quiet jenkins 2>/dev/null; then
  echo "  ✘ Jenkins still running!"
else
  echo "  ✔ Jenkins not running"
fi

if rpm -q jenkins &>/dev/null; then
  echo "  ✘ Jenkins still installed!"
else
  echo "  ✔ Jenkins not installed"
fi

echo ""
echo "=================================================="
echo " ✔ Jenkins Cleanup Complete!"
echo " Safe to run jenkins_setup.sh again"
echo "=================================================="
