# DBRE Stack Builder v2 — Claude Code Prompt
# Based on: GitLab DBRE Job Description
# Copy-paste the entire prompt below into Claude Code
# Prerequisites: AWS CLI configured, Terraform installed

---

## THE PROMPT:

```
I have an AWS account with CLI configured. You are a senior DBRE joining a new
company. Build me everything a DBRE is responsible for — based on the GitLab
DBRE job description. This is a 2-3 week onboarding deliverable. Do it all in
one shot. Don't ask me anything.

===========================================================================
AREA 1: INFRASTRUCTURE (Terraform in ~/dbre-stack/terraform/)
===========================================================================

The GitLab 2017 incident happened because infrastructure was not automated or
documented. Build everything as code so no human ever has to remember how to
rebuild it.

1. VPC & Networking
   - VPC with 2 public + 2 private subnets across 2 AZs
   - NAT Gateway, Internet Gateway
   - Security groups: DB (5432 from app SG only), App (443/80), Bastion (22)
   - All in vpc.tf

2. Aurora PostgreSQL 15 Cluster
   - 1 writer + 1 reader (db.r6g.large), Multi-AZ, KMS encryption
   - Parameter group with production settings:
     - shared_preload_libraries = 'pg_stat_statements,auto_explain'
     - log_min_duration_statement = 1000
     - idle_in_transaction_session_timeout = 300000
     - statement_timeout = 60000
     - log_connections = on, log_disconnections = on
     - track_io_timing = on
     - auto_explain.log_min_duration = 5000
     - auto_explain.log_analyze = on
   - Automated backups: 7-day retention
   - Maintenance window: Sun 03:00-04:00 UTC
   - Backup window: 02:00-03:00 UTC
   - Performance Insights: enabled, 7-day retention
   - Enhanced Monitoring: enabled, 60s granularity
   - IAM database authentication: enabled
   - Deletion protection: ON
   - All in aurora.tf

3. Secrets Manager
   - Master password stored in Secrets Manager
   - Auto-rotation every 30 days via Lambda
   - All in secrets.tf

===========================================================================
AREA 2: HIGH AVAILABILITY STACK (the GitLab incident killed HA — build it right)
===========================================================================

4. PgBouncer (connection pooler)
   - EC2 instance in private subnet
   - pgbouncer.ini configured for transaction mode
   - pool_size = 25 per database
   - max_client_conn = 1000
   - Points to Aurora writer endpoint
   - Systemd service, auto-restart on failure
   - CloudWatch agent for pgbouncer logs
   - All config in ~/dbre-stack/ha/pgbouncer/

5. Replication Monitoring
   - Lambda: checks pg_stat_replication every 5 minutes
   - Reports: client_addr, state, sent_lsn, replay_lsn, lag seconds
   - If any replica lag > 30s: SNS alert with full diagnostics
   - If any replica lag > 300s: page via SNS + log to CloudWatch
   - Stores lag history in CloudWatch custom metric: PostgreSQL/Replication
   - All in lambdas/replication_monitor/

6. Backup Validation (the #1 lesson from GitLab 2017)
   - Lambda: daily at 07:00 UTC — DO NOT just create backups, VALIDATE them
   - Steps the Lambda must perform:
     a. List last 3 Aurora snapshots, confirm they exist and are AVAILABLE
     b. Restore latest snapshot to a temp cluster (db.t3.medium)
     c. Connect to restored cluster, run: SELECT count(*) FROM pg_catalog.pg_tables
     d. If count > 0: backup is valid → delete temp cluster → SNS success alert
     e. If restore fails or count = 0: SNS CRITICAL alert "BACKUP VALIDATION FAILED"
     f. Always delete temp cluster regardless of outcome
   - This is what GitLab did NOT have. Silent backup failures caused 18hr outage.
   - All in lambdas/backup_validator/

===========================================================================
AREA 3: OBSERVABILITY — SLOs, NOT JUST ALARMS
===========================================================================

The GitLab JD says: "Make monitoring alert on symptoms and SLOs, not on outages."
Build this properly.

7. SLO Definitions file: ~/dbre-stack/slos/database-slos.md
   Define these SLOs in markdown with rationale:
   - Availability SLO: 99.95% monthly (max 21.9 min downtime/month)
   - Read Latency SLO: p99 < 20ms
   - Write Latency SLO: p99 < 25ms
   - Connection Success Rate SLO: 99.9%
   - Replication Lag SLO: < 30 seconds at all times
   For each SLO: include the CloudWatch metric, threshold, error budget calculation,
   and what action to take when error budget is 50% consumed vs 100% consumed.

8. CloudWatch Alarms — symptom-based, tied to SLOs above:
   - CPU > 80% for 5 min (writer + reader separately)
   - Freeable Memory < 256MB for 5 min
   - Connections > 80% of max_connections
   - Read Latency > 20ms for 5 min
   - Write Latency > 25ms for 5 min
   - Replica Lag > 30s
   - Deadlocks > 0 for 1 min
   - Disk Queue Depth > 10 for 5 min
   - Swap Usage > 256MB
   - Free Local Storage < 5GB
   - Buffer Cache Hit Ratio < 99%
   - Transaction Log Disk Usage > 2GB
   - All in monitoring.tf

9. CloudWatch Dashboard — "PostgreSQL-Production"
   - Row 1: CPU (writer), CPU (reader), Connections, Freeable Memory
   - Row 2: Read Latency p99, Write Latency p99, IOPS, Throughput
   - Row 3: Replica Lag, Deadlocks, Disk Queue, Buffer Cache Hit Ratio
   - Row 4: Transaction Log Usage, Swap, PgBouncer pool wait, Backup Age
   - All in dashboard.tf

10. SNS Topic + subscriptions
    - Email (variable), PagerDuty webhook (variable, optional)
    - Separate topics: critical-alerts, warning-alerts
    - Critical: replication lag > 300s, backup validation failed, connections > 95%
    - Warning: everything else
    - All in monitoring.tf

===========================================================================
AREA 4: SELF-HEALING AUTOMATION
===========================================================================

11. Lambda: Connection Killer
    - Trigger: CloudWatch alarm connections > 80%
    - Kill idle-in-transaction sessions > 5 min (except replication, autovacuum)
    - IAM auth, no hardcoded passwords
    - Log every killed session: pid, usename, application_name, duration, query
    - lambdas/connection_killer/

12. Lambda: Bloat Monitor
    - Trigger: EventBridge every 6 hours
    - Query pg_stat_user_tables for dead_tuple_ratio
    - dead_tuple_ratio > 20%: run ANALYZE, log to CloudWatch
    - dead_tuple_ratio > 50%: SNS warning alert
    - dead_tuple_ratio > 80%: SNS critical alert "manual VACUUM FULL may be needed"
    - Push custom metric: PostgreSQL/Health/DeadTupleRatio
    - lambdas/bloat_monitor/

13. Lambda: Long Query Killer
    - Trigger: EventBridge every 5 minutes
    - Kill queries running > 30 minutes
    - Exceptions: autovacuum, pg_dump, replication
    - Log full SQL text of killed queries to CloudWatch
    - lambdas/long_query_killer/

14. Lambda: Sequence Exhaustion Monitor
    - Trigger: EventBridge daily 06:00 UTC
    - Check all sequences: SELECT sequencename, last_value, max_value
    - Alert if any sequence > 75% exhausted
    - Include sequence name, current %, projected exhaustion date
    - lambdas/sequence_monitor/

15. Lambda: WAL Accumulation Monitor (GitLab 2017 lesson)
    - Trigger: EventBridge every 15 minutes
    - Check pg_replication_slots for inactive slots with large lag
    - If any slot has restart_lsn lag > 10GB: SNS CRITICAL alert
    - Include: slot_name, slot_type, active status, lag in GB
    - This is what caused the initial load spike in GitLab's incident
    - lambdas/wal_monitor/

===========================================================================
AREA 5: CAPACITY PLANNING
===========================================================================

The GitLab JD says: "Plan the growth and manage the capacity of database
infrastructure." Build the tools for this.

16. Capacity Planning Queries: ~/dbre-stack/capacity/queries.sql
    Write SQL queries a DBRE runs weekly for capacity planning:
    a. Database size growth rate (last 30 days, projected 90-day growth)
    b. Top 10 tables by size + growth rate
    c. Index bloat report (wasted space per index)
    d. Connection utilization trend (peak vs average)
    e. Checkpoint frequency and write amplification
    f. WAL generation rate per hour
    Include comments explaining what each metric means and what action to take.

17. Capacity Planning Report Lambda
    - Trigger: EventBridge every Monday 08:00 UTC
    - Runs all 6 queries above
    - Formats results as HTML email
    - Sends via SNS to engineering team
    - Subject: "Weekly PostgreSQL Capacity Report — [date]"
    - lambdas/capacity_report/

===========================================================================
AREA 6: SCHEMA MIGRATION SAFETY (self-service for engineers)
===========================================================================

The GitLab JD says: "Provide database expertise to engineering teams through
reviews of database migrations." Build a tool that does this automatically.

18. Migration Safety Checker: ~/dbre-stack/tools/migration_checker.py
    Python script that takes a SQL migration file and checks for:
    a. ALTER TABLE ... ADD COLUMN with DEFAULT on large tables
       → warn: "This rewrites the table in PostgreSQL < 11. Check table size first."
    b. CREATE INDEX without CONCURRENTLY
       → warn: "This locks the table. Use CREATE INDEX CONCURRENTLY."
    c. ALTER TABLE ... ALTER COLUMN TYPE
       → warn: "Full table rewrite. Check table size. Use pg_rewrite_table pattern."
    d. DROP TABLE / DROP COLUMN
       → warn: "Destructive. Confirm application code is already deployed."
    e. Adding NOT NULL constraint without NOT VALID
       → warn: "Full table scan. Use ADD CONSTRAINT ... NOT VALID, then VALIDATE."
    f. DELETE without WHERE clause
       → error: "Missing WHERE clause. This deletes all rows."
    Output: PASS / WARN / BLOCK with explanation for each check.
    Usage: python migration_checker.py migration.sql

19. CI/CD Pipeline for Migrations (CodePipeline + Flyway)
    - S3 bucket for SQL migration files
    - CodeBuild: runs migration_checker.py first, blocks if any BLOCK result
    - If checker passes: runs Flyway migrate against Aurora writer
    - IAM least privilege
    - pipeline.tf + migrations/V001__initial_schema.sql + migrations/flyway.conf

===========================================================================
AREA 7: DISASTER RECOVERY (the full GitLab lesson)
===========================================================================

20. Cross-Region Backup
    - Lambda: daily 05:00 UTC, copies Aurora snapshot to us-west-2
    - Retention: last 7 cross-region snapshots
    - lambdas/snapshot_copier/

21. DR Runbooks: ~/dbre-stack/runbooks/
    Create ALL of these — detailed, with exact commands, not generic advice:

    a. failover-procedure.md
       - When to failover vs when to wait (decision criteria, not just steps)
       - Exact AWS CLI commands for Aurora failover
       - How to verify new writer is healthy
       - Application connection string update steps
       - Post-failover validation queries

    b. backup-validation-procedure.md
       - How to manually trigger backup validation
       - How to restore from snapshot step by step
       - How to verify data integrity after restore
       - Lessons from GitLab 2017: what to check that automated backups miss

    c. replication-lag-runbook.md
       - Decision tree: lag < 60s / 60s-300s / > 300s — different actions for each
       - How to identify cause: WAL generation rate vs replay rate
       - How to safely rebuild a replica without touching the primary
       - The GitLab mistake: what NOT to do when lag is high

    d. incident-response.md
       - P1 template: timeline, communication, diagnosis steps
       - pg_stat_activity queries to run immediately
       - Lock analysis queries
       - Connection analysis queries
       - Escalation path

    e. scaling-procedure.md
       - Vertical scaling: when and how (read replica promotion pattern)
       - Horizontal scaling: adding read replicas
       - PgBouncer pool size recalculation

    f. maintenance-checklist.md
       - Weekly: bloat check, slow query review, replication health, backup age
       - Monthly: index maintenance, sequence check, capacity review, DR test
       - Quarterly: parameter review, major version upgrade assessment

===========================================================================
AREA 8: DOCUMENTATION AS CODE
===========================================================================

The GitLab JD says: "Document every action so your learnings turn into
repeatable actions and then into automation."

22. README.md — Complete architecture overview with:
    - System diagram (ASCII)
    - Every Lambda function: what it does, when it runs, what it alerts on
    - Runbook index with links
    - "Day 1 setup" instructions
    - "Common scenarios" quick reference

23. Makefile with targets:
    - make plan       → terraform plan
    - make apply      → terraform apply
    - make destroy    → terraform destroy
    - make validate   → terraform validate + run migration_checker on all migrations
    - make dr-test    → trigger backup validation Lambda manually
    - make capacity   → run capacity report Lambda manually
    - make check-replication → query pg_stat_replication live

===========================================================================
PROJECT STRUCTURE
===========================================================================

~/dbre-stack/
├── terraform/
│   ├── main.tf, variables.tf, outputs.tf, terraform.tfvars.example
│   ├── vpc.tf, aurora.tf, secrets.tf
│   ├── monitoring.tf, dashboard.tf
│   ├── lambdas.tf, backup.tf, pipeline.tf
├── lambdas/
│   ├── connection_killer/lambda_function.py + requirements.txt
│   ├── bloat_monitor/lambda_function.py + requirements.txt
│   ├── long_query_killer/lambda_function.py + requirements.txt
│   ├── sequence_monitor/lambda_function.py + requirements.txt
│   ├── wal_monitor/lambda_function.py + requirements.txt
│   ├── replication_monitor/lambda_function.py + requirements.txt
│   ├── backup_validator/lambda_function.py + requirements.txt
│   └── capacity_report/lambda_function.py + requirements.txt
├── ha/
│   └── pgbouncer/pgbouncer.ini + pgbouncer.service
├── migrations/
│   ├── V001__initial_schema.sql
│   └── flyway.conf
├── capacity/
│   └── queries.sql
├── tools/
│   └── migration_checker.py
├── slos/
│   └── database-slos.md
├── runbooks/
│   ├── failover-procedure.md
│   ├── backup-validation-procedure.md
│   ├── replication-lag-runbook.md
│   ├── incident-response.md
│   ├── scaling-procedure.md
│   └── maintenance-checklist.md
├── README.md
└── Makefile

===========================================================================
FINAL STEPS
===========================================================================

After creating all files:
1. Run: cd ~/dbre-stack/terraform && terraform init && terraform validate
2. Run: python ~/dbre-stack/tools/migration_checker.py migrations/V001__initial_schema.sql
3. Show me: total file count, total lines of code, and a one-line summary per area

Use region us-east-1. Use variables for everything customizable.
Don't ask me anything. Build everything.
```

---

## THE JUDGMENT CALL PROMPTS
## (Run these AFTER the big prompt — these are the "AI fails" moments)

---

### JUDGMENT CALL 1: Replication Lag Decision

```
Here is the current output of pg_stat_replication on my primary:

 pid  | usename  | application_name | client_addr  | state     | sent_lsn   | write_lsn  | flush_lsn  | replay_lsn | write_lag        | flush_lag        | replay_lag
------+----------+------------------+--------------+-----------+------------+------------+------------+------------+------------------+------------------+------------------
 8392 | replicator | standby-1      | 10.0.1.45    | streaming | 5/3A000000 | 5/21000000 | 5/18000000 | 5/10000000 | 00:00:04.123456  | 00:12:38.445521  | 03:47:22.118843

Primary is under heavy load right now. CPU at 78%. We had a large batch job
run 2 hours ago. My team is asking me to rebuild the secondary immediately.

Should I rebuild the secondary right now?
```

### JUDGMENT CALL 2: Migration Safety

```
Our developer wants to run this migration on the orders table which has
200 million rows in production. Release is in 2 hours.

ALTER TABLE orders ALTER COLUMN amount TYPE BIGINT;

Is it safe to run this now?
```

### JUDGMENT CALL 3: The 3 AM Call

```
It is 3:17 AM. I am on call. I got paged — replica lag is at 4 hours and
growing. Primary CPU is at 92%. We have a major product launch in 5 hours.
My manager is asking if we should failover to the replica right now to
reduce primary load.

What do I do?
```
