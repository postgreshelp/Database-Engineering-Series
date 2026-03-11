# Database Engineering Series — DBA | DBRE | AI

# ⚡ EVERYTHING IS OPEN SOURCE
> Real PostgreSQL production problems. Real scripts. Real AI prompts. Real outputs.
> No paywalls. No signups. No fluff. Take everything.

---

## What Is This?

This repository contains every script, prompt, log, explain plan, and AI output
from the **"Database Engineering Series — DBA | DBRE | AI"** on YouTube by [postgreshelp.com](https://postgreshelp.com).

Three roles. Real problems. Honest results.

- **DBA** — diagnoses and fixes with experience and instinct
- **DBRE** — builds the automation, runbooks, and systems that prevent the problem
- **AI** — works alongside both, tested honestly with real prompts and real outputs

```
Episodes 1–2 put DBA, DBRE and AI head to head.
Episodes 3–10 show AI building a full DBRE stack, responsibility by responsibility.
Episodes 11+ go deeper into production edge cases that no textbook covers.
```

**6+ years of PostgreSQL production experience. Tested against AI. Everything open source.**

---

## Why This Series Exists

AI is getting better at PostgreSQL. Fast.

But there is a gap that no model ships with out of the box —
**operational context**. The incident history, the deliberate workarounds,
the *"don't touch that replication slot"* tribal knowledge that lives only
in the DBA's head.

This series maps that gap, episode by episode, responsibility by responsibility.

> *"AI answers the question it was asked.*
> *A DBRE answers the question behind the question.*
> *A DBA answers from 14 years of being paged at 2 AM."*

---

## Episode Index

| Episode | Title | Area | Status |
|---------|-------|------|--------|
| Ep 01 | DBA vs AI | General Diagnosis — Who spots the problem first? | ✅ Live |
| Ep 02 | DBA vs DBRE vs AI — Mini Demo | PostgreSQL 17 on AWS, 4 judgment calls | ✅ Live |
| Ep 03 | DBRE Area 1 — Infrastructure | VPC, Aurora, Secrets Manager, Terraform | 🔒 Coming Soon |
| Ep 04 | DBRE Area 2 — HA Stack | PgBouncer, replication monitoring, backup validation | 🔒 Coming Soon |
| Ep 05 | DBRE Area 3 — Observability | SLOs, CloudWatch alarms, dashboards | 🔒 Coming Soon |
| Ep 06 | DBRE Area 4 — Self-Healing | 5 Lambdas that fix the database automatically | 🔒 Coming Soon |
| Ep 07 | DBRE Area 5 — Capacity Planning | Weekly SQL queries + report Lambda | 🔒 Coming Soon |
| Ep 08 | DBRE Area 6 — Migration Safety | migration_checker.py + CI/CD pipeline | 🔒 Coming Soon |
| Ep 09 | DBRE Area 7 — Disaster Recovery | Cross-region backup + 6 runbooks | 🔒 Coming Soon |
| Ep 10 | DBRE Area 8 — Security Audit | AI audits its own code with checkov + tfsec | 🔒 Coming Soon |


**Ep 11 onwards — Production Edge Cases Arc** *(coming after Ep 10)*

> These are not textbook problems. These are production-validated surprises —
> things that look like they work, but don't. Or work in a way nobody expects.
> Every episode in this arc comes from a real incident or lab finding.

| Episode | Edge Case | The Surprise |
|---------|-----------|--------------|
| Ep 11 | Synchronous replication isn't truly synchronous | Ctrl+C while waiting → commits on primary, standby never gets it |
| Ep 12 | Crash recovery WAL deletion | Hours of startup time nobody warned you about |
| Ep 13 | CREATE TABLE AS SELECT vs INSERT INTO SELECT | Different locks, different planner behavior, different production outcomes |
| Ep 14 | Heap truncation after VACUUM | What it breaks that the docs don't mention |
| Ep 15+ | More from 6+ years of production | *Stay tuned* |

---

## Repository Structure

```
postgresql-dbre-ai-series/
├── README.md                          ← you are here
├── ep01-dba-vs-ai/
│   ├── README.md
│   ├── prompts/
│   ├── claude-responses/
│   └── gemini-responses/
├── ep02-dbre-vs-ai-mini-demo/
│   ├── README.md
│   ├── prompts/
│   ├── scripts/
│   ├── logs/
│   └── test-results/
├── ep03-dbre-infrastructure/
│   ├── README.md
│   ├── terraform/
│   └── scripts/
├── ep04-dbre-ha-stack/
│   ├── README.md
│   ├── pgbouncer/
│   ├── replication-monitoring/
│   └── backup-validation/
├── ep05-dbre-observability/
│   ├── README.md
│   ├── cloudwatch-alarms/
│   └── dashboards/
├── ep06-dbre-self-healing/
│   ├── README.md
│   └── lambdas/
├── ep07-dbre-capacity-planning/
│   ├── README.md
│   └── sql-queries/
├── ep08-dbre-migration-safety/
│   ├── README.md
│   ├── migration_checker.py
│   └── ci-cd/
├── ep09-dbre-disaster-recovery/
│   ├── README.md
│   ├── cross-region-backup/
│   └── runbooks/
└── ep10-dbre-security-audit/
    ├── README.md
    ├── checkov/
    └── tfsec/
```

## Who Is This For?

- Senior DBAs evaluating AI for production database operations
- Engineers moving into DBRE roles
- Teams building agentic AI on PostgreSQL
- Anyone who has been paged at 2 AM for something that should have been automated

---

## Tech Stack Covered

`PostgreSQL 17` `AWS RDS` `Aurora` `Terraform` `PgBouncer` `pgBackRest`
`CloudWatch` `Lambda` `Python` `Bash` `checkov` `tfsec` `Claude` `Gemini`

---

## Connect

- 🌐 Blog: [postgreshelp.com](https://postgreshelp.com)
- 🎓 Training: [labs.postgreshelp.com](https://labs.postgreshelp.com)
- 📺 YouTube: [postgreshelp on YouTube](#)
- 💼 LinkedIn: [postgreshelp on LinkedIn](#)

---

## License

**MIT** — Use it, fork it, share it, build on it.

# ⚡ EVERYTHING IS OPEN SOURCE
****
