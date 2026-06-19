# Runbook: HighCPU Alert

**Alert:** `HighCPU`  
**Severity:** Warning  
**Detection:** CPU > 85% sustained for 3 minutes  

---

## 1. Immediate Investigation

```bash
# What's consuming CPU?
top -b -n 1 | head -20

# Which PostgreSQL queries are running?
psql -U postgres -c "
SELECT pid, now() - pg_stat_activity.query_start AS duration,
       query, state
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC
LIMIT 10;"

# Check for vacuum storms
psql -U postgres -c "
SELECT schemaname, relname, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 10;"
```

---

## 2. Common Causes & Fixes

| Cause | Fix |
|---|---|
| Heavy query / missing index | `EXPLAIN ANALYZE` → add index |
| Autovacuum storm | Tune `autovacuum_vacuum_cost_delay` |
| Bulk load / ETL | Schedule off-peak |
| Connection storm | Check `max_connections`, use pgBouncer |

---

## 3. Emergency: Kill Runaway Query

```bash
# Cancel query gracefully (SIGINT)
psql -U postgres -c "SELECT pg_cancel_backend(PID);"

# Terminate if cancel doesn't work (SIGTERM)
psql -U postgres -c "SELECT pg_terminate_backend(PID);"

# NEVER use kill -9 on PostgreSQL processes!
```

---
*Runbook v1.0 | June 2026 | PostgreSQL Production Labs*
