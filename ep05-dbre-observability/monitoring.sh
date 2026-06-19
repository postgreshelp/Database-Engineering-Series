#!/bin/bash
set -e

# ONE CLICK MONITORING STACK FOR TEACHING PURPOSES
# CentOS 9 - Prometheus + Grafana + Node Exporter + Postgres Exporter + Alertmanager
# Dashboard 9628 + Alert Rules (PostgresDown, TooManyConnections, HighCPU, ReplicationLag)

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root!"
  exit 1
fi

PROM_PORT=9090
GRAFANA_PORT=3000
NODE_PORT=9100
PG_EXP_PORT=9187
AM_PORT=9093

# -----------------------------------------------
# CONFIGURE YOUR ALERT DESTINATION HERE
# -----------------------------------------------
ALERT_EMAIL="your-email@gmail.com"
SMTP_HOST="smtp.gmail.com:587"
SMTP_FROM="your-email@gmail.com"
SMTP_USER="your-email@gmail.com"
SMTP_PASS="YOUR_16_CHAR_APP_PASSWORD"
# -----------------------------------------------

echo "=== Installing Dependencies ==="
dnf install -y wget curl tar > /dev/null

# -------------------------------
# Node Exporter
# -------------------------------
echo "Installing Node Exporter..."
NODE_VER=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep tag_name | cut -d '"' -f 4)

cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/${NODE_VER}/node_exporter-${NODE_VER#v}.linux-amd64.tar.gz
tar -xf node_exporter-${NODE_VER#v}.linux-amd64.tar.gz
cp node_exporter-${NODE_VER#v}.linux-amd64/node_exporter /usr/local/bin/

cat >/etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter --web.listen-address=":${NODE_PORT}"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node_exporter

# -------------------------------
# Postgres Exporter
# -------------------------------
echo "Installing postgres_exporter..."
PGE_URL=$(curl -s https://api.github.com/repos/prometheus-community/postgres_exporter/releases/latest | grep "browser_download_url" | grep linux-amd64 | cut -d '"' -f 4)

cd /tmp
wget -q $PGE_URL -O postgres_exporter.tar.gz
tar -xf postgres_exporter.tar.gz
EXPORTER_DIR=$(find . -maxdepth 1 -type d -name "postgres_exporter*" | head -1)
cp $EXPORTER_DIR/postgres_exporter /usr/local/bin/

cat >/etc/systemd/system/postgres_exporter.service <<EOF
[Unit]
Description=Postgres Exporter
After=network.target

[Service]
# Use 127.0.0.1 to force IPv4 - avoids IPv6 ::1 which has scram-sha-256 in pg_hba.conf
Environment="DATA_SOURCE_NAME=postgresql://postgres@127.0.0.1:5432/postgres?sslmode=disable"
ExecStart=/usr/local/bin/postgres_exporter --web.listen-address=":${PG_EXP_PORT}"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Fix pg_hba.conf IPv6 - default CentOS9+PG18 has scram-sha-256 for ::1/128
# which causes auth failure even with trust set for IPv4
HBA_FILE=$(psql -U postgres -t -c "SHOW hba_file;" 2>/dev/null | tr -d ' \n')
if [ -n "$HBA_FILE" ] && [ -f "$HBA_FILE" ]; then
  sed -i 's|^host[[:space:]]*all[[:space:]]*all[[:space:]]*::1/128[[:space:]]*scram-sha-256|host    all             all             ::1/128                 trust|g' "$HBA_FILE"
  psql -U postgres -c "SELECT pg_reload_conf();" > /dev/null 2>&1
  echo "  ✔ pg_hba.conf IPv6 updated to trust"
fi

systemctl daemon-reload
systemctl enable --now postgres_exporter


# -------------------------------
# Alertmanager
# -------------------------------
echo "Installing Alertmanager..."
AM_VER=$(curl -s https://api.github.com/repos/prometheus/alertmanager/releases/latest | grep tag_name | cut -d '"' -f 4)

cd /tmp
wget -q https://github.com/prometheus/alertmanager/releases/download/${AM_VER}/alertmanager-${AM_VER#v}.linux-amd64.tar.gz
tar -xf alertmanager-${AM_VER#v}.linux-amd64.tar.gz
cp alertmanager-${AM_VER#v}.linux-amd64/alertmanager /usr/local/bin/
cp alertmanager-${AM_VER#v}.linux-amd64/amtool /usr/local/bin/

mkdir -p /etc/alertmanager /var/lib/alertmanager

cat >/etc/alertmanager/alertmanager.yml <<EOF
global:
  smtp_smarthost: '${SMTP_HOST}'
  smtp_from: '${SMTP_FROM}'
  smtp_auth_username: '${SMTP_USER}'
  smtp_auth_password: '${SMTP_PASS}'
  smtp_require_tls: true

# Group alerts to avoid notification flood
route:
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'email-alert'

  # Critical alerts get their own route - no grouping delay
  routes:
    - match:
        severity: critical
      group_wait: 10s
      receiver: 'email-alert'

receivers:
  - name: 'email-alert'
    email_configs:
      - to: '${ALERT_EMAIL}'
        send_resolved: true
        headers:
          subject: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }} - PostgreSQL Alert'

inhibit_rules:
  # If PostgresDown fires, suppress all other postgres alerts for same instance
  - source_match:
      alertname: 'PostgresDown'
    target_match_re:
      alertname: 'TooManyConnections|ReplicationLag|LongRunningQuery'
    equal: ['instance']
EOF

cat >/etc/systemd/system/alertmanager.service <<EOF
[Unit]
Description=Alertmanager
After=network.target

[Service]
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager \
  --web.listen-address=":${AM_PORT}"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now alertmanager

# -------------------------------
# Prometheus Alert Rules
# -------------------------------
echo "Creating alert rules..."
mkdir -p /etc/prometheus

cat >/etc/prometheus/alert_rules.yml <<EOF
groups:
  - name: postgresql_alerts
    rules:

      # PostgreSQL is completely unreachable
      - alert: PostgresDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL DOWN on {{ \$labels.instance }}"
          description: "postgres_exporter cannot reach PostgreSQL. Immediate action required."

      # Connection count approaching max_connections
      - alert: TooManyConnections
        expr: >
          pg_stat_activity_count
          / pg_settings_max_connections * 100 > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Connections at {{ \$value | printf \"%.0f\" }}% of max on {{ \$labels.instance }}"
          description: "Connection pool close to exhaustion. Check for connection leaks or increase max_connections."

      # Long running queries (potential locks or runaway queries)
      - alert: LongRunningQuery
        expr: >
          pg_stat_activity_max_tx_duration{state="active"} > 300
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Query running > 5 minutes on {{ \$labels.instance }}"
          description: "A query has been running for over 5 minutes. May indicate a lock or missing index."

      # Replication lag (only fires if replication is configured)
      - alert: ReplicationLag
        expr: >
          pg_replication_lag > 60
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Replication lag {{ \$value }}s on {{ \$labels.instance }}"
          description: "Standby is falling behind. Risk of data loss if primary fails."

      # High CPU on the DB host
      - alert: HighCPU
        expr: >
          100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100) > 85
        for: 3m
        labels:
          severity: warning
        annotations:
          summary: "CPU at {{ \$value | printf \"%.0f\" }}% on {{ \$labels.instance }}"
          description: "Sustained high CPU. May indicate heavy queries or vacuum storms."

      # Disk running low
      - alert: LowDiskSpace
        expr: >
          (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Disk < 15% free on {{ \$labels.instance }}"
          description: "PostgreSQL will crash when disk is full. Immediate action needed."
EOF

# -------------------------------
# Prometheus (with alerting wired in)
# -------------------------------
echo "Installing Prometheus..."
PROM_VER=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep tag_name | cut -d '"' -f 4)

cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/${PROM_VER}/prometheus-${PROM_VER#v}.linux-amd64.tar.gz
tar -xf prometheus-${PROM_VER#v}.linux-amd64.tar.gz

cp prometheus-${PROM_VER#v}.linux-amd64/prometheus /usr/local/bin/
cp prometheus-${PROM_VER#v}.linux-amd64/promtool /usr/local/bin/

mkdir -p /etc/prometheus /var/lib/prometheus
# consoles/console_libraries were removed in Prometheus 3.x - copy only if present
[ -d prometheus-${PROM_VER#v}.linux-amd64/consoles ] && cp -r prometheus-${PROM_VER#v}.linux-amd64/consoles /etc/prometheus/
[ -d prometheus-${PROM_VER#v}.linux-amd64/console_libraries ] && cp -r prometheus-${PROM_VER#v}.linux-amd64/console_libraries /etc/prometheus/

cat >/etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 10s
  evaluation_interval: 10s

# Send alerts to Alertmanager
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:${AM_PORT}']

# Load alert rules
rule_files:
  - /etc/prometheus/alert_rules.yml

scrape_configs:
  - job_name: node
    static_configs:
      - targets: ['localhost:${NODE_PORT}']

  - job_name: postgres
    static_configs:
      - targets: ['localhost:${PG_EXP_PORT}']
EOF

# Validate rules before starting
promtool check rules /etc/prometheus/alert_rules.yml
promtool check config /etc/prometheus/prometheus.yml

cat >/etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now prometheus

# -------------------------------
# Grafana + auto-import dashboard 9628
# -------------------------------
echo "Installing Grafana..."
cat >/etc/yum.repos.d/grafana.repo <<EOF
[grafana]
name=Grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
EOF

dnf install -y grafana > /dev/null
systemctl enable --now grafana-server

# Wait for Grafana with health check loop (more reliable than sleep)
echo "Waiting for Grafana to be ready..."
for i in {1..20}; do
  if curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo "  ✔ Grafana is up!"
    break
  fi
  sleep 3
done

# Add Prometheus datasource
echo "Adding Prometheus datasource..."
DS_RESULT=$(curl -s -X POST http://admin:admin@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Prometheus\",\"type\":\"prometheus\",\"access\":\"proxy\",\"url\":\"http://localhost:${PROM_PORT}\"}")
if echo "$DS_RESULT" | grep -q '"id"'; then
  echo "  ✔ Prometheus datasource added"
else
  echo "  ✘ Datasource failed: $DS_RESULT"
fi

# Download and import Dashboard 9628
echo "Downloading Dashboard 9628 from Grafana.com..."
# Fetch latest revision number first, fallback to 8
DASH_REV=$(curl -s https://grafana.com/api/dashboards/9628 | grep -o '"revision":[0-9]*' | head -1 | cut -d: -f2)
DASH_REV=${DASH_REV:-8}
echo "  ✔ Using Dashboard 9628 revision $DASH_REV"

DASH_JSON=$(curl -s https://grafana.com/api/dashboards/9628/revisions/${DASH_REV}/download)

if [ -z "$DASH_JSON" ]; then
  echo "  ✘ Failed to download dashboard JSON — check internet access"
else
  echo "  ✔ Dashboard JSON downloaded"
  echo "Importing Dashboard 9628 into Grafana..."
  IMPORT_RESULT=$(curl -s -X POST http://admin:admin@localhost:3000/api/dashboards/import \
    -H "Content-Type: application/json" \
    -d "{\"dashboard\": ${DASH_JSON}, \"overwrite\": true, \"folderId\": 0, \"inputs\": [{\"name\":\"DS_PROMETHEUS\",\"type\":\"datasource\",\"pluginId\":\"prometheus\",\"value\":\"Prometheus\"}]}")
  if echo "$IMPORT_RESULT" | grep -q '"id"'; then
    echo "  ✔ Dashboard 9628 imported successfully"
  else
    echo "  ✘ Dashboard import failed: $IMPORT_RESULT"
  fi
fi

# -------------------------------
# Final Status Check
# -------------------------------
echo ""
echo "=== Service Status ==="
for svc in node_exporter postgres_exporter alertmanager prometheus grafana-server; do
  STATUS=$(systemctl is-active $svc)
  if [ "$STATUS" = "active" ]; then
    echo "  ✔ $svc"
  else
    echo "  ✘ $svc — check: journalctl -u $svc"
  fi
done

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=================================================="
echo " ✔ ONE-CLICK Monitoring + Alerting Installed!"
echo "--------------------------------------------------"
echo "Grafana           → http://$IP:3000  (admin/admin)"
echo "Prometheus        → http://$IP:9090"
echo "Alertmanager      → http://$IP:9093"
echo "Node Exporter     → http://$IP:9100/metrics"
echo "Postgres Exporter → http://$IP:9187/metrics"
echo "--------------------------------------------------"
echo "Alerts configured:"
echo "  • PostgresDown       (critical - 1m)"
echo "  • TooManyConnections (warning  - 2m)"
echo "  • LongRunningQuery   (warning  - instant)"
echo "  • ReplicationLag     (critical - 1m)"
echo "  • HighCPU            (warning  - 3m)"
echo "  • LowDiskSpace       (critical - 1m)"
echo "--------------------------------------------------"
echo "To test PostgresDown alert:"
echo "  systemctl stop postgresql"
echo "  # Wait 1 min, then check http://$IP:9090/alerts"
echo "=================================================="
