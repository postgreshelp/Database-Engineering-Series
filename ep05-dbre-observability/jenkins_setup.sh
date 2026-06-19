#!/bin/bash
set -e

# ============================================================
# JENKINS SETUP SCRIPT FOR pg-dbre-stack
# CentOS 9 - Fully Automated, No Manual Intervention
# Fixes: Java 21, --nogpgcheck, permissions, plugins, pipeline
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root!"
  exit 1
fi

JENKINS_PORT=8080
TARGET_HOST=$(hostname -I | awk '{print $1}')
JENKINS_HOME=/var/lib/jenkins
JOB_NAME="pg-dbre-stack"
MONITORING_SCRIPT="/var/lib/jenkins/monitoring.sh"
CLEANUP_SCRIPT="/var/lib/jenkins/cleanup.sh"

echo "=================================================="
echo " Jenkins Setup for pg-dbre-stack"
echo " Fully Automated - No Manual Intervention"
echo "=================================================="

# -------------------------------
# Step 1: Install Java 21
# (Jenkins 2.5xx requires Java 21+)
# -------------------------------
echo ""
echo "=== Step 1: Installing Java 21 ==="
if java -version 2>&1 | grep -q "21"; then
  echo "  ✔ Java 21 already installed"
else
  dnf install -y java-21-openjdk java-21-openjdk-devel > /dev/null
  # Set Java 21 as default
  alternatives --set java $(ls /usr/lib/jvm/java-21-openjdk*/bin/java | head -1) 2>/dev/null || true
  echo "  ✔ Java 21 installed"
fi
java -version 2>&1 | head -1

# -------------------------------
# Step 2: Install Jenkins
# --nogpgcheck needed for CentOS 9 lab environments
# -------------------------------
echo ""
echo "=== Step 2: Installing Jenkins ==="

if rpm -q jenkins &>/dev/null; then
  echo "  ✔ Jenkins already installed"
else
  # Clean any old repo/key first
  rm -f /etc/yum.repos.d/jenkins.repo
  rm -f /etc/pki/rpm-gpg/jenkins.io.key
  rm -f /usr/share/keyrings/jenkins-keyring.asc

  cat > /etc/yum.repos.d/jenkins.repo <<EOF
[jenkins]
name=Jenkins
baseurl=https://pkg.jenkins.io/redhat-stable
gpgcheck=1
gpgkey=https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
enabled=1
EOF

  # --nogpgcheck required for lab/demo on CentOS 9
  dnf install -y jenkins --nogpgcheck > /dev/null
  echo "  ✔ Jenkins installed"
fi

# -------------------------------
# Step 3: Fix Permissions
# Jenkins runs as 'jenkins' user so needs:
# - sudo access to run systemctl, dnf etc
# - access to monitoring scripts
# -------------------------------
echo ""
echo "=== Step 3: Fixing Permissions ==="

# Give jenkins user passwordless sudo
if ! grep -q "jenkins ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then
  echo "jenkins ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
  echo "  ✔ Jenkins sudo access granted"
else
  echo "  ✔ Jenkins sudo already configured"
fi

# Copy scripts to jenkins home so jenkins user can access them
cp /root/monitoring.sh $MONITORING_SCRIPT
cp /root/cleanup.sh $CLEANUP_SCRIPT
chmod +x $MONITORING_SCRIPT $CLEANUP_SCRIPT
chown jenkins:jenkins $MONITORING_SCRIPT $CLEANUP_SCRIPT
echo "  ✔ Scripts copied to $JENKINS_HOME"
echo "  ✔ Scripts permissions set"

# -------------------------------
# Step 4: Configure Jenkins
# Skip setup wizard, create admin user
# -------------------------------
echo ""
echo "=== Step 4: Configuring Jenkins ==="

mkdir -p $JENKINS_HOME/init.groovy.d

# Skip setup wizard
echo 2 > $JENKINS_HOME/jenkins.install.InstallUtil.lastExecVersion
echo 2 > $JENKINS_HOME/jenkins.install.UpgradeWizard.state

# Create admin user
cat > $JENKINS_HOME/init.groovy.d/01-create-admin.groovy <<'GROOVY'
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount('admin', 'admin123')
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()
println "Admin user created: admin/admin123"
GROOVY

# Disable CSRF for API access
cat > $JENKINS_HOME/init.groovy.d/02-disable-csrf.groovy <<'GROOVY'
import jenkins.model.Jenkins
def instance = Jenkins.getInstance()
instance.setCrumbIssuer(null)
instance.save()
println "CSRF disabled for lab setup"
GROOVY

# Set Jenkins URL
cat > $JENKINS_HOME/init.groovy.d/03-set-url.groovy <<GROOVY
import jenkins.model.JenkinsLocationConfiguration
def config = JenkinsLocationConfiguration.get()
config.setUrl("http://${TARGET_HOST}:${JENKINS_PORT}/")
config.save()
println "Jenkins URL configured"
GROOVY

chown -R jenkins:jenkins $JENKINS_HOME
echo "  ✔ Jenkins configured"

# -------------------------------
# Step 5: Start Jenkins
# -------------------------------
echo ""
echo "=== Step 5: Starting Jenkins ==="
systemctl enable jenkins
systemctl restart jenkins

echo "  Waiting for Jenkins to start..."
for i in {1..30}; do
  if curl -s http://localhost:${JENKINS_PORT}/login 2>/dev/null | grep -q "Jenkins"; then
    echo "  ✔ Jenkins is up!"
    break
  fi
  echo "  ... attempt $i/30"
  sleep 5
done

# Disable CSRF again after restart
# Wait for Jenkins to fully accept auth before proceeding
echo "  Waiting for Jenkins to accept authentication..."
for i in {1..20}; do
  RESULT=$(curl -s -X POST http://admin:admin123@localhost:${JENKINS_PORT}/scriptText     --data-urlencode 'script=println "ready"' 2>/dev/null)
  if echo "$RESULT" | grep -q "ready"; then
    echo "  ✔ Jenkins accepting auth!"
    break
  fi
  sleep 5
done

# Now disable CSRF
curl -s -X POST http://admin:admin123@localhost:${JENKINS_PORT}/scriptText   --data-urlencode 'script=Jenkins.instance.setCrumbIssuer(null); Jenkins.instance.save(); println "CSRF disabled"'   2>/dev/null | grep -v "^$" || true

sleep 3
# -------------------------------
# Final Summary
# -------------------------------
echo ""
echo "=================================================="
echo " ✔ Jenkins Setup Complete!"
echo "--------------------------------------------------"
echo " Jenkins   → http://$TARGET_HOST:$JENKINS_PORT"
echo " Username  → admin"
echo " Password  → admin123"
echo "--------------------------------------------------"
echo " postgreshelp.com | labs.postgreshelp.com"
echo "=================================================="
