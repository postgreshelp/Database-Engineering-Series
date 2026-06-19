# Runbook: TooManyConnections Alert

**Alert:** `TooManyConnections`  
**Severity:** Warning  
**Detection:** Active connections > 80% of max_connections for 2 minutes  

---

## 1. Immediate Investigation

```bash
# How many connections right now?
psql -U postgres -c "
SELECT count(*), state
FROM pg_stat_activity
GROUP BY state;"

# What is max_connections?
psql -U postgres -c "SHOW max_connections;"

# Who is holding idle connections?
psql -U postgres -c "
SELECT pid, usename, application_name, client_addr,
       state, now() - state_change AS idle_duration
FROM pg_stat_activity
WHERE state = 'idle'
ORDER BY idle_duration DESC
LIMIT 20;"
```

---

## 2. Emergency Fix

```bash
# Terminate idle connections older than 10 minutes
psql -U postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
AND now() - state_change > interval '10 minutes';"
```

---

## 3. Long Term Fix

- Deploy **pgBouncer** for connection pooling
- Tune `max_connections` in postgresql.conf
- Fix application connection leaks

---
*Runbook v1.0 | June 2026 | PostgreSQL Production Labs*
