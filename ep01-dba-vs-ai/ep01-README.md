# Ep 01 — Can AI Replace a DBA?
### Database Engineering Series — DBA | DBRE | AI
**by [postgreshelp.com](https://postgreshelp.com)**

---

## The Experiment

One database. 21 production problems. Three AI rounds. Only the prompt changed.

| Round | Player | Prompt |
|-------|--------|--------|
| Baseline | — | 21 problems planted |
| Round 1 | Gemini CLI | Basic |
| Round 2 | Claude | Basic |
| Round 3 | Claude | Detailed |

---

## The Result

| Round | Issues Fixed | Reduction | Rating |
|-------|-------------|-----------|--------|
| Planted | — | — | CRITICAL |
| Gemini (Basic) | ~5 | ~23% | POOR |
| Claude (Basic) | ~5 | ~23% | POOR |
| Claude (Detailed) | ~17 | ~80% | FAIR |

**Same AI. Same database. Basic prompt: 23%. Detailed prompt: 80%.**

> The DBA who writes the prompt IS the value. AI is the multiplier.

---

## What AI Does Well

These are mechanical, repeatable tasks — AI's core strength:

- VACUUM & ANALYZE — dead tuple cleanup, statistics refresh
- Rebuild invalid indexes, drop duplicates and overlapping indexes
- Create missing FK indexes, fix sequence exhaustion
- Validate NOT VALID constraints, re-enable disabled triggers
- Kill idle sessions, rollback orphaned prepared transactions
- ALTER SYSTEM for runtime-reloadable configuration parameters

**60–70% of a junior DBA's daily work — done in minutes.**

---

## What AI Cannot Do

Judgment calls that require context, risk assessment, and business knowledge:

- **Drop replication slot?** Is the standby coming back or decommissioned?
- **Revoke PUBLIC grants?** Will the application break?
- **Convert UNLOGGED table?** Can we tolerate 10 min downtime for a rewrite?
- **Fix NULL financial data?** Is NULL = ₹0 or NULL = unknown?
- **Change search_path?** Will 50 applications break immediately?
- **Restart PostgreSQL?** Is the CEO's demo running right now?

These need CONTEXT — business, historical, relationship. AI doesn't have this.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `plant_problem.sh` | Plants 21 production problems into `demohealth` database |
| `pg_health_report_html.sh` | Generates AWR-style HTML health check report |
| `pg_health_compare.sh` | Before vs After comparison report |
| `pg_health_compare_detail.sh` | Detailed before vs after with DBA analysis |
| `pg_health_battle.sh` | Multi-AI battle report — all rounds side by side |

---

## How to Reproduce This

```bash
# Step 1: Plant the mess
./plant_problem.sh -h <IP> -U postgres -d demohealth

# Step 2: BEFORE report
./pg_health_report_html.sh -h <IP> -U postgres -d demohealth -t before

# Step 3: Gemini fixes (basic prompt) — then capture result
./pg_health_report_html.sh -h <IP> -U postgres -d demohealth -t gemini_solved

# Step 4: Reset database, re-plant mess, Claude fixes (basic prompt)
./pg_health_report_html.sh -h <IP> -U postgres -d demohealth -t claude_basic

# Step 5: Reset database, re-plant mess, Claude fixes (detailed prompt)
./pg_health_report_html.sh -h <IP> -U postgres -d demohealth -t claude_detailed

# Step 6: Battle report — all rounds in one shot
./pg_health_battle.sh \
  -l "Planted|Gemini (Basic)|Claude (Basic)|Claude (Detailed)" \
  pg_health_before_*.html \
  pg_health_gemini_solved_*.html \
  pg_health_claude_basic_*.html \
  pg_health_claude_detailed_*.html
```

---

## Prompts Used

### Basic Prompt
```
Password is "postgres" for postgres user.
Connect: psql -h <IP> -p 5432 -U postgres -d demohealth
The database is sick. Scan everything. Fix everything. Don't ask me anything.
```

### Detailed Prompt
```
Password is "postgres" for postgres user.
Connect: psql -h <IP> -p 5432 -U postgres -d demohealth

This is a test/demo database — not production. Nothing here matters. Be aggressive.

Do a full health check and FIX every single issue. Specifically:
- Re-enable autovacuum on all tables, then VACUUM ANALYZE all tables
- Drop ALL unused indexes (idx_scan=0), duplicate indexes, and rebuild invalid ones
- Create missing indexes on all foreign key columns
- Drop ALL inactive replication slots (physical and logical)
- ALTER sequences near exhaustion to BIGINT or increase MAXVALUE with CYCLE
- ALTER all UNLOGGED tables to LOGGED
- Fix ALL postgresql.conf settings via ALTER SYSTEM + pg_reload_conf()
- REVOKE ALL grants from PUBLIC, drop SECURITY DEFINER functions
- Validate all NOT VALID constraints, clean bad data (NULLs, negatives)
- Create missing partitions for sales_log through end of 2026, move data from DEFAULT
- Re-enable all disabled triggers
- Revoke CREATEROLE/CREATEDB from non-superuser roles, fix role escalation chains
- Fix search_path: remove public from before pg_catalog
- Drop FDW user mappings with hardcoded passwords
- Kill blocked/idle sessions, rollback orphaned prepared transactions
- Refresh stale materialized views

After every fix, verify it worked. Give me a final report.
```

---

## The Key Finding

| Prompt Quality | Result |
|----------------|--------|
| Basic — "Fix everything" | 23% reduction |
| Detailed — exact instructions | 80% reduction |

**Prompt quality matters more than which AI you use.**
Gemini and Claude performed identically on the basic prompt.
Claude with a detailed prompt nearly quadrupled the result.

---

## The Real Answer

The future-proof DBA role combines three things:

- **Deep PostgreSQL knowledge** — the judgment calls, the 3 AM instincts, what AI can't learn
- **System design thinking** — architecture decisions, capacity planning, trade-off analysis
- **AI as force multiplier** — let AI write the code, you make the decisions — 10x productivity

> *AI doesn't replace the DBA.*
> *AI replaces the DBA who doesn't adapt.*

---

## Prerequisites

- PostgreSQL instance accessible via psql
- `bash` 4.0+
- Gemini CLI installed (for Gemini rounds)
- Claude with computer use or terminal access (for Claude rounds)

---

## ⚡ Everything Is Open Source

All scripts, prompts, and outputs are free.
No paywalls. No signups. Take everything.

**[← Back to Series](../README.md)**
