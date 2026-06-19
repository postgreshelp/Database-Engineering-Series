# pg-dbre-stack

> One-command PostgreSQL observability stack for CentOS 9.  
> Built live during the **Database Engineering Series** by [postgreshelp.com](https://postgreshelp.com)

---

## ⚡ What This Does

```bash
sh monitoring.sh
```

One command deploys a full DBRE observability stack:

| Component | Port | Purpose |
|---|---|---|
| Prometheus | 9090 | Metrics collection & alert evaluation |
| Grafana | 3000 | Visualization (Dashboard 9628 auto-imported) |
| Node Exporter | 9100 | Linux host metrics |
| Postgres Exporter | 9187 | PostgreSQL internals |
| Alertmanager | 9093 | Alert routing → Gmail |

---

## 🚀 Quick Start

### Prerequisites
- CentOS 9 (or RHEL 9 / Oracle Linux 9)
- PostgreSQL running on same host
- Root access
- Gmail account with App Password

### Step 1: Clone the repo
```bash
git clone https://github.com/postgreshelp/pg-dbre-stack.git
cd pg-dbre-stack
```

### Step 2: Configure your email
```bash
# Find and replace with your details
sed -i 's/your-email@gmail.com/YOUR_ACTUAL_EMAIL@gmail.com/g' monitoring.sh
sed -i 's/YOUR_16_CHAR_APP_PASSWORD/YOUR_ACTUAL_APP_PASSWORD/g' monitoring.sh
```

### Step 3: Deploy
```bash
sh monitoring.sh
```

### Step 4: Access
```
Grafana      → http://YOUR_IP:3000  (admin/admin)
Prometheus   → http://YOUR_IP:9090
Alertmanager → http://YOUR_IP:9093
```

---

## 📧 Gmail App Password Setup

1. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
2. 2FA must be enabled on your Google account
3. Create app password → select **Mail**
4. Copy the 16-character password
5. Paste into `monitoring.sh` (no spaces)

---

## 🔔 Alert Rules

6 production-grade alerts pre-configured:

| Alert | Condition | Severity |
|---|---|---|
| PostgresDown | pg_up == 0 for 1m | Critical |
| TooManyConnections | >80% of max_connections for 2m | Warning |
| LongRunningQuery | Query > 5 minutes | Warning |
| ReplicationLag | Lag > 60s for 1m | Critical |
| HighCPU | CPU > 85% for 3m | Warning |
| LowDiskSpace | Disk < 15% free for 1m | Critical |

---

## 🧪 Test Alerts

```bash
# Trigger PostgresDown
systemctl stop postgresql-18

# Watch alert fire at :9090/alerts
# Email arrives within 1 minute

# Recover
systemctl start postgresql-18

# Watch [RESOLVED] email arrive
```

---

## 🔄 Jenkins Pipeline (DevOps Demo)

### Setup Jenkins
```bash
sh jenkins_setup.sh
```

### Pipeline stages
```
Cleanup → Deploy → Verify
```

Opens at `http://YOUR_IP:8080` (admin/admin123)

---

## 🧹 Cleanup

```bash
sh cleanup.sh
```

Removes everything — safe to re-run `monitoring.sh` after.

---

## 📚 DBRE Framework

This stack covers **Layer 1 and 2** of the DBRE framework:

```
Layer 1 — Monitoring      ← This script
Layer 2 — Alerting        ← This script  
Layer 3 — Incident Response
Layer 4 — Runbooks        ← runbooks/ folder
Layer 5 — Failure Injection
Layer 6 — Postmortem
Layer 7 — DevOps Pipeline ← Jenkins
```

See [DBRE_Framework.md](DBRE_Framework.md) for the full picture.

---

## 📁 Repo Structure

```
pg-dbre-stack/
├── monitoring.sh          # Main install script
├── cleanup.sh             # Teardown script
├── jenkins_setup.sh       # Jenkins install + pipeline
├── jenkins_cleanup.sh     # Jenkins teardown
├── Jenkinsfile            # Pipeline definition
├── DBRE_Framework.md      # 7-layer DBRE framework
├── README.md              # This file
└── runbooks/
    ├── postgres_down.md
    ├── high_cpu.md
    └── too_many_connections.md
```

---

## 🐛 Known Issues & Fixes

**IPv6 pg_hba issue (CentOS 9 + PG18)**
The script auto-fixes this — `localhost` resolves to `::1` which has
`scram-sha-256` by default. Script changes it to `trust` automatically.

**Grafana dashboard revision**
Dashboard 9628 revision 1 is empty. Script auto-detects latest revision.

**Prometheus 3.x**
Removed `consoles/` directory. Script handles this gracefully.

**Jenkins Java version**
Jenkins 2.5xx requires Java 21. Script installs Java 21 automatically.

---

## 🔧 Customize Email

```bash
# Change email address
sed -i 's/your-email@gmail.com/naresh@example.com/g' monitoring.sh

# Change app password  
sed -i 's/YOUR_16_CHAR_APP_PASSWORD/abcdefghijklmnop/g' monitoring.sh

# Re-deploy
sh cleanup.sh && sh monitoring.sh
```

---

## 📺 YouTube Series

This repo is part of the **Database Engineering Series**:
> *"Can AI Replace a DBA?"*

| Episode | Topic |
|---|---|
| Ep 01 | DBA vs AI |
| Ep 02 | DBA vs DBRE vs AI — Mini Demo |
| Ep 03 | DBRE Infrastructure (Terraform) |
| Ep 04 | HA Stack (Patroni + etcd + HAProxy) |
| **Ep 05** | **DBRE Observability — this repo! ✅** |
| Ep 06 | Self-Healing (Lambda auto-remediation) |
| Ep 07 | Capacity Planning |
| Ep 08 | Migration Safety |
| Ep 09 | Disaster Recovery |
| Ep 10 | Security Audit |

---

## 🌐 Connect

- Blog: [postgreshelp.com](https://postgreshelp.com)
- Course: [labs.postgreshelp.com](https://labs.postgreshelp.com)
- GitHub: [github.com/postgreshelp](https://github.com/postgreshelp)

---

## 📄 License

MIT — Use it, fork it, share it, build on it.

> *"AI answers the question it was asked.*  
> *A DBRE answers the question behind the question.*  
> *A DBA answers from 6 years of being paged at 2 AM."*
