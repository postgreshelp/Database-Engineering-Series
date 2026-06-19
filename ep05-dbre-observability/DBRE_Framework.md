# DBRE Area 3 — Observability
## Episode 05: From Monitoring to Reliability Engineering
*Database Engineering Series — postgreshelp.com | labs.postgreshelp.com*

---

## The Core Idea

> "A script provides observability.  
> Observability + Alerting + Runbooks + Incident Response + Processes = DBRE."

---

## Layer 1 — Monitoring (Observability)

**Tools:**
- Prometheus — collects and stores metrics
- Grafana — visualizes metrics (Dashboard 9628)
- postgres_exporter — PostgreSQL internals → metrics
- node_exporter — Linux host metrics

**What you can see:**
- Active connections
- Cache hit ratio
- Transaction rate
- CPU, Memory, Disk
- Replication lag

**One command to deploy:**
```bash
sh monitoring.sh
```

---

## Layer 2 — Alerting

**6 alerts configured out of the box:**

| Alert | Threshold | Severity |
|---|---|---|
| PostgresDown | pg_up == 0 for 1m | Critical |
| TooManyConnections | >80% of max_connections for 2m | Warning |
| LongRunningQuery | Query > 5 minutes | Warning |
| ReplicationLag | Lag > 60s for 1m | Critical |
| HighCPU | CPU > 85% for 3m | Warning |
| LowDiskSpace | Disk < 15% free for 1m | Critical |

**Alert pipeline:**
```
Prometheus evaluates rules every 10s
    ↓
Condition true → pending
    ↓
Sustained → firing
    ↓
Alertmanager routes to Gmail
    ↓
Email arrives in < 30 seconds
```

---

## Layer 3 — Incident Response

**When an alert fires, answer these questions:**

```
Alert Fired
    ↓
Who receives it?        ← Alertmanager routing
    ↓
Who owns it?            ← On-call rotation
    ↓
How do we investigate?  ← Runbooks
    ↓
How do we fix it?       ← Known solutions
    ↓
How do we prevent it?   ← Action items
```

**Demo — PostgresDown in action:**
```bash
# Trigger
systemctl stop postgresql-18

# Observe
# 1. Grafana dashboard → panels go blank
# 2. :9090/alerts → pending → firing
# 3. Gmail → alert email arrives
# 4. :9093 → Alertmanager shows active alert

# Recover
systemctl start postgresql-18

# Observe recovery
# 1. pg_up returns to 1
# 2. Alert resolves
# 3. Gmail → [RESOLVED] email arrives
```

---

## Layer 4 — Runbooks

**One runbook per alert. Located in:** `runbooks/`

```
runbooks/
├── postgres_down.md          ← Who, What, How to fix, Postmortem
├── high_cpu.md               ← Query analysis, vacuum storms
├── too_many_connections.md   ← Connection pooling, pgBouncer
├── replication_lag.md        ← Streaming replication recovery
├── low_disk_space.md         ← WAL cleanup, disk expansion
└── long_running_query.md     ← pg_cancel_backend, index analysis
```

**What a runbook contains:**
1. Who receives the alert
2. Immediate investigation steps
3. Common causes and fixes
4. Recovery verification
5. Postmortem template
6. Reliability metrics (MTTR, MTTD)

---

## Layer 5 — Failure Injection (Chaos Engineering)

**Practice before production surprises you:**

### Demo 1: PostgreSQL Down
```bash
systemctl stop postgresql-18
# Watch: alert fires, email arrives, Grafana blanks
systemctl start postgresql-18
# Watch: alert resolves, recovery email
```

### Demo 2: CPU Stress
```bash
dnf install -y stress-ng
stress-ng --cpu 4 --timeout 300s
# Watch: HighCPU alert fires after 3 minutes
```

### Demo 3: Connection Exhaustion
```bash
# Open 100 idle connections
for i in $(seq 1 100); do
  psql -U postgres -c "SELECT pg_sleep(300);" &
done
# Watch: TooManyConnections alert fires
```

### Demo 4: Disk Pressure
```bash
# Fill disk to trigger LowDiskSpace
fallocate -l 40G /tmp/bigfile
# Watch: LowDiskSpace alert fires
rm /tmp/bigfile
```

---

## Layer 6 — Postmortem & Reliability Metrics

**After every incident, measure:**

```
MTTD = Time incident started → Time alert fired
       (how fast did we detect?)

MTTR = Time alert fired → Time service restored
       (how fast did we recover?)

Availability = (Total time - Downtime) / Total time × 100
```

**Postmortem template:**
```
Incident: PostgresDown
Date/Duration:

Timeline:
  HH:MM - Incident started
  HH:MM - Alert fired        ← MTTD ends here
  HH:MM - Engineer on it
  HH:MM - Root cause found
  HH:MM - Service restored   ← MTTR ends here

Root Cause:
Impact:
Action Items:
What can we automate?
```

---

## Layer 7 — DevOps for DBAs (Bonus)

**Option A: Terraform**
```
terraform apply
    ↓
EC2/VM provisioned
    ↓
monitoring.sh runs via user_data
    ↓
Full stack live in < 5 minutes
```

**Option B: Jenkins**
```
Git push monitoring.sh
    ↓
Jenkins pipeline triggered
    ↓
Deploy to target DB servers
    ↓
Verify health checks pass
    ↓
Slack/email notification
```

**The message:**
> "DevOps teams provision the server.  
> DBRE teams own what runs on it."

---

## The Full Picture

```
Your postgreshelp.com articles (2019 → 2026)
              +
   monitoring.sh (one command)
              +
   6 alert rules
              +
   Runbooks (operational discipline)
              +
   Incident response process
              +
   Postmortem culture
              +
   Failure injection (chaos engineering)
              +
   DevOps pipeline (Terraform/Jenkins)
              =
         DBRE in practice
```

---

## What Students Take Away

1. **Observability** — they can deploy monitoring in minutes
2. **Alerting** — they understand the alert pipeline
3. **Operations** — they have runbooks to follow
4. **Reliability** — they can measure MTTR and MTTD
5. **Automation** — they see the DevOps pipeline
6. **Mindset** — DBA → DBRE transition is a process, not a title

---

*Database Engineering Series — Episode 05: DBRE Observability*  
*"Can AI Replace a DBA?" — YouTube Series by postgreshelp.com*  
*labs.postgreshelp.com | github.com/postgreshelp*
