# Runbook: PostgresDown Alert

**Alert:** `PostgresDown`  
**Severity:** Critical  
**Detection:** `pg_up == 0` for 1 minute  

---

## 1. Who Receives It?
- Email → kumarboina1t@gmail.com
- Alertmanager → http://SERVER_IP:9093
- Prometheus → http://SERVER_IP:9090/alerts

---

## 2. Immediate Investigation (First 5 minutes)

```bash
# Is PostgreSQL running?
systemctl status postgresql-18

# Check last 50 lines of PostgreSQL log
tail -50 /var/lib/pgsql/18/data/log/postgresql-*.log

# Check disk space (full disk = common cause)
df -h

# Check memory pressure
free -h

# Check if port is listening
ss -tlnp | grep 5432

# Check if OOM killer struck
dmesg | grep -i "killed process"
```

---

## 3. Common Causes & Fixes

| Cause | How to Confirm | Fix |
|---|---|---|
| Service crashed | `systemctl status postgresql-18` | `systemctl start postgresql-18` |
| Disk full | `df -h` shows 100% | Clean WAL, logs, or expand disk |
| OOM killed | `dmesg | grep kill` | Tune `shared_buffers`, add RAM |
| Corrupted data | PANIC in pg_log | Initiate PITR recovery |
| pg_hba misconfigured | Auth errors in log | Fix pg_hba.conf, reload |

---

## 4. Restore Service

```bash
# Start PostgreSQL
systemctl start postgresql-18

# Verify accepting connections
psql -U postgres -c "SELECT version();"

# Verify replication is streaming (HA setup)
psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Confirm pg_up is 1 again
curl -s http://localhost:9187/metrics | grep pg_up
```

---

## 5. Verify Alert Resolved

```bash
# Should return empty alerts
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool

# Check Grafana dashboard
# http://SERVER_IP:3000 → PostgreSQL Database dashboard
```

---

## 6. Prevent Recurrence

- [ ] Disk cause? → Lower `LowDiskSpace` alert threshold to 20%
- [ ] OOM cause? → Tune `shared_buffers`, `work_mem`, `max_connections`
- [ ] Crash cause? → Check pg_log for recurring PANIC/FATAL patterns
- [ ] Document in postmortem log

---

## 7. Postmortem Template

```
Incident: PostgresDown
Date:
Duration:

Timeline:
  HH:MM - Alert fired
  HH:MM - Engineer acknowledged
  HH:MM - Root cause identified
  HH:MM - Service restored
  HH:MM - Alert resolved

Root Cause:

Impact:
  - Downtime: X minutes
  - Detection time: X minutes
  - Recovery time: X minutes

Action Items:
  1.
  2.
  3.

What can we automate?
```

---

## 8. DBRE Reliability Metrics to Track

```
MTTR (Mean Time To Recover)  = Time alert fired → Time service restored
MTTD (Mean Time To Detect)   = Time incident started → Time alert fired
Availability %               = (Total time - Downtime) / Total time × 100
```

---
*Runbook v1.0 | June 2026 | PostgreSQL Production Labs*
