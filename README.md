# PostgreSQL DBRE + AI Series

# ⚡ EVERYTHING IS OPEN SOURCE
> Real PostgreSQL production problems. Real scripts. Real AI prompts. Real outputs.
> No paywalls. No signups. No fluff. Take everything.

---

## What Is This?

This repository contains every script, prompt, log, explain plan, and AI output
from the **"Can AI Replace a DBA?"** YouTube series by [postgreshelp.com](https://postgreshelp.com).

Each episode tests AI (Claude + Gemini) against a real DBRE responsibility area —
benchmarked against the **GitLab DBRE Job Description**, one of the most respected
and publicly available DBRE role definitions in the industry.

> 📋 Reference: [GitLab DBRE Job Description](https://handbook.gitlab.com/job-description-library/engineering/infrastructure/database-reliability-engineer/)

**14 years of PostgreSQL production experience. Tested against AI. Everything open source.**

---

## Why This Series Exists

AI is getting better at PostgreSQL. Fast.

But there is a gap that no model ships with out of the box —
**operational context**. The incident history, the deliberate workarounds,
the *"don't touch that replication slot"* tribal knowledge that lives only
in the DBA's head.

This series maps that gap, episode by episode, responsibility by responsibility.

> *"AI answers the question it was asked.*
> *A DBRE answers the question behind the question."*

---

## Episode Index

| Episode | Title | DBRE Area | Status |
|---------|-------|-----------|--------|
| Ep 01 | DBA vs AI | General Diagnosis | ✅ Live |
| Ep 02 | DBRE vs AI — Mini Demo | PostgreSQL 17 on AWS, 4 judgment calls | ✅ Live |
| Ep 03 | DBRE Area 1 — Infrastructure | VPC, Aurora, Secrets Manager, Terraform | 🔒 Coming Soon |
| Ep 04 | DBRE Area 2 — HA Stack | PgBouncer, replication monitoring, backup validation | 🔒 Coming Soon |
| Ep 05 | DBRE Area 3 — Observability | SLOs, CloudWatch alarms, dashboards | 🔒 Coming Soon |
| Ep 06 | DBRE Area 4 — Self-Healing | 5 Lambdas that fix the database automatically | 🔒 Coming Soon |
| Ep 07 | DBRE Area 5 — Capacity Planning | Weekly SQL queries + report Lambda | 🔒 Coming Soon |
| Ep 08 | DBRE Area 6 — Migration Safety | migration_checker.py + CI/CD pipeline | 🔒 Coming Soon |
| Ep 09 | DBRE Area 7 — Disaster Recovery | Cross-region backup + 6 runbooks | 🔒 Coming Soon |
| Ep 10 | DBRE Area 8 — Security Audit | AI audits its own code with checkov + tfsec | 🔒 Coming Soon |

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

---

## The GitLab Lesson (Why Ep 04 Matters)

January 31, 2017. A GitLab engineer ran one command on the wrong server
and wiped 300GB of production PostgreSQL data. They had 5 backup systems.
Not one worked. It took 18 hours and cost them 6 hours of user data — permanently.

The on-call engineer faced this decision at 9 PM:

> *Replication lag is spiking. Wait it out — or rebuild the secondary now?*

Ask AI that question. It gives a structured, reasonable answer.
But it doesn't know the pg_dump backups had been silently failing for months.
It doesn't know that if the secondary gets wiped, there is no fallback.

**AI answers the question it was asked.**
**The DBRE answers the question behind the question.**

Episode 4 builds the HA stack that prevents this incident.
The GitLab incident postmortem is required reading:
[https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/)

---

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
