# DBRE Mini Demo — Deploy + Test + Destroy
# Real AWS deployment to prove AI-generated code actually works
# Estimated cost: < $0.10 total
# Estimated time: 15-20 minutes end to end
# Prerequisites: AWS CLI configured, Terraform installed, Python 3, psycopg2

---

## STEP 1: DEPLOY PROMPT
## Paste this into Claude Code first

```
I have AWS CLI configured. Build me a minimal but real PostgreSQL setup on AWS
to prove AI-generated DBRE code actually works in production.

Keep it cheap (db.t3.micro, no NAT Gateway, no KMS).
This is a demo — it will be destroyed after testing.
Do it all. Don't ask me anything.

Create everything in ~/dbre-mini/

## Infrastructure (Terraform)

1. VPC & Networking
   - VPC: 10.0.0.0/16
   - 1 public subnet: 10.0.1.0/24 (us-east-1a)
   - 1 private subnet: 10.0.2.0/24 (us-east-1b)
   - Internet Gateway (no NAT Gateway — not needed for this demo)
   - Security group: allow 5432 from 0.0.0.0/0 (demo only)
   - All in vpc.tf

2. RDS PostgreSQL 15
   - Instance: db.t3.micro
   - Single AZ (no Multi-AZ — demo only)
   - Storage: 20GB gp2
   - No KMS (default encryption)
   - Parameter group with production settings:
     - shared_preload_libraries = 'pg_stat_statements'
     - log_min_duration_statement = 1000
     - idle_in_transaction_session_timeout = 300000
     - statement_timeout = 60000
     - log_connections = on
     - track_io_timing = on
   - Backup retention: 1 day
   - Skip final snapshot: true (demo)
   - Publicly accessible: true (demo — needed for Lambda testing)
   - Master username: dbretest
   - Master password: stored in terraform.tfvars (variable)
   - All in rds.tf

3. CloudWatch Alarm
   - CPU > 80% for 5 min
   - DatabaseConnections > 10 for 2 min
   - All in monitoring.tf

4. SNS Topic
   - Name: dbre-mini-alerts
   - Email subscription: variable
   - In monitoring.tf

5. Lambda: Bloat Monitor (Python)
   - Trigger: manual invocation (for demo)
   - Connect to RDS using master credentials from SSM Parameter Store
   - Query pg_stat_user_tables for dead_tuple_ratio
   - Log results to CloudWatch
   - Return JSON summary of all tables checked
   - In lambdas/bloat_monitor/

6. SSM Parameter Store
   - Store DB host, username, password as SecureString parameters
   - Lambda reads from SSM (no hardcoded credentials)
   - In ssm.tf

## Project Structure

~/dbre-mini/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── vpc.tf
│   ├── rds.tf
│   ├── monitoring.tf
│   └── ssm.tf
├── lambdas/
│   └── bloat_monitor/
│       ├── lambda_function.py
│       └── requirements.txt
├── migrations/
│   ├── V001__initial_schema.sql
│   └── V002__bad_migration.sql  ← intentionally bad, for migration_checker demo
├── tools/
│   └── migration_checker.py
├── tests/
│   ├── test_connection.py
│   ├── test_parameter_group.py
│   ├── test_bloat_monitor.py
│   ├── test_migration_checker.py
│   └── run_all_tests.sh
├── README.md
└── Makefile

## V002__bad_migration.sql content:
   Include ALL of these intentionally problematic statements:
   - CREATE INDEX ON orders(customer_id);  ← missing CONCURRENTLY
   - ALTER TABLE orders ALTER COLUMN amount TYPE BIGINT;  ← full table rewrite
   - ALTER TABLE orders ADD COLUMN status VARCHAR(50) NOT NULL DEFAULT 'pending';  ← NOT NULL without NOT VALID
   - DELETE FROM audit_log;  ← missing WHERE clause

## Test scripts (in tests/):

### test_connection.py
   - Connect to RDS endpoint
   - Run: SELECT version()
   - Run: SELECT current_database()
   - Run: SHOW shared_preload_libraries  ← verify pg_stat_statements loaded
   - Run: SHOW log_min_duration_statement  ← verify parameter group applied
   - Run: SHOW idle_in_transaction_session_timeout
   - Print PASS/FAIL for each check

### test_parameter_group.py
   - Connect to RDS
   - Check ALL production parameters are applied:
     shared_preload_libraries, log_min_duration_statement,
     idle_in_transaction_session_timeout, statement_timeout,
     log_connections, track_io_timing
   - Print parameter name, expected value, actual value, PASS/FAIL

### test_bloat_monitor.py
   - Create test table with intentional bloat:
     CREATE TABLE bloat_test AS SELECT i FROM generate_series(1,100000) i;
     DELETE FROM bloat_test WHERE i % 2 = 0;  ← 50% dead tuples
     (do NOT run VACUUM so dead tuples remain)
   - Invoke bloat_monitor Lambda
   - Verify Lambda response contains bloat_test table
   - Verify dead_tuple_ratio > 40% detected
   - Print PASS/FAIL

### test_migration_checker.py
   - Run migration_checker.py against V001__initial_schema.sql
   - Verify result is PASS
   - Run migration_checker.py against V002__bad_migration.sql
   - Verify it catches ALL 4 problems:
     - Missing CONCURRENTLY → WARN
     - ALTER COLUMN TYPE → WARN
     - NOT NULL without NOT VALID → WARN
     - DELETE without WHERE → BLOCK
   - Print each check: found/missed, PASS/FAIL

### run_all_tests.sh
   - Runs all 4 test scripts in order
   - Prints summary: X/4 tests passed
   - Exits with code 0 if all pass, 1 if any fail

## Makefile targets:
   - make deploy    → terraform init + apply
   - make test      → cd tests && bash run_all_tests.sh
   - make destroy   → terraform destroy -auto-approve
   - make all       → deploy + test (destroy manually after demo)

After creating all files:
1. Run terraform init + terraform validate
2. Show file count and summary
3. Show exact commands to deploy, test, and destroy
```

---

## STEP 2: DEPLOY

```bash
cd ~/dbre-mini/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — add your email and db password
nano terraform.tfvars

terraform init
terraform apply -auto-approve
```

Expected output:
- VPC created
- RDS instance created (takes ~5 min)
- Lambda deployed
- SSM parameters stored
- CloudWatch alarms active

---

## STEP 3: RUN TESTS

```bash
cd ~/dbre-mini

# Install Python dependencies
pip install psycopg2-binary boto3 --break-system-packages

# Get RDS endpoint from Terraform output
terraform -chdir=terraform output rds_endpoint

# Run all tests
make test
```

**What each test proves on camera:**

| Test | What it proves |
|------|---------------|
| test_connection.py | RDS is running, AI-generated config works |
| test_parameter_group.py | Production parameters actually applied — not just in code |
| test_bloat_monitor.py | Lambda connects, queries pg_stat, returns real data |
| test_migration_checker.py | Safety tool catches bad migrations before they hit production |

---

## STEP 4: THE JUDGMENT CALL PROMPTS
## Run these after tests pass — these are the "AI fails" moments

### JUDGMENT CALL 1: Replication Lag Decision

```
Here is the current output of pg_stat_replication on my primary:

 pid  | usename    | application_name | client_addr  | state     | sent_lsn   | replay_lsn | replay_lag
------+------------+------------------+--------------+-----------+------------+------------+------------------
 8392 | replicator | standby-1        | 10.0.1.45    | streaming | 5/3A000000 | 5/10000000 | 03:47:22.118843

Primary CPU is at 78%. Large batch job ran 2 hours ago.
My team is asking me to rebuild the secondary immediately.

Should I rebuild the secondary right now?
```

**What AI will miss:**
- Is the batch job still running or finished?
- Is lag growing or stable?
- What happens to the primary if we start a resync now — extra I/O load
- Do we have any other replica? If not, rebuilding leaves us with zero HA
- GitLab 2017: they rebuilt — and deleted the wrong server

---

### JUDGMENT CALL 2: Migration Safety

```
Our developer wants to run this migration on the orders table
which has 200 million rows. Release is in 2 hours.

ALTER TABLE orders ALTER COLUMN amount TYPE BIGINT;

Is it safe to run this now?
```

**What AI will miss:**
- How long will this actually take on 200M rows? (estimate: 2-4 hours)
- Will it block all reads and writes during rewrite?
- Is there a safer pattern? (new column + backfill + rename)
- 2 hour release window is not enough — this will blow the deadline

---

### JUDGMENT CALL 3: The 3 AM Call

```
3:17 AM. I am on call. Replica lag is 4 hours and growing.
Primary CPU at 92%. Major product launch in 5 hours.
Manager is asking: failover to replica right now to reduce primary load?

What do I do?
```

**What AI will miss:**
- Failing over to a replica that is 4 hours behind means 4 hours of data loss
- Primary CPU at 92% — what is causing it? Failover won't fix the root cause
- Is the replica even healthy enough to become primary?
- 5 hours to launch — failover adds risk, not removes it
- GitLab 2017: they acted fast under pressure — and made it worse

---

## STEP 5: DESTROY

```bash
cd ~/dbre-mini/terraform
terraform destroy -auto-approve
```

Show on camera:
- All resources being destroyed
- Final output: "Destroy complete! Resources: 0"

Estimated cost of entire demo: < $0.10
```

---

## ON-CAMERA FLOW SUMMARY

| Step | Time | What audience sees |
|------|------|--------------------|
| Run big prompt | 10-14 min | AI builds full DBRE stack |
| terraform validate | 1 min | Code is real |
| Run mini deploy prompt | 2 min | Stripped down version |
| terraform apply | 5 min | Actually deploys to AWS |
| make test | 3 min | All tests pass — code works |
| Judgment call 1 | 3 min | AI hedges on replication lag |
| Judgment call 2 | 3 min | AI misses migration timeline |
| Judgment call 3 | 3 min | AI can't make the 3 AM call |
| terraform destroy | 1 min | Clean teardown, ~$0.05 spent |
| Conclusion slides | 3 min | Audience decides |

**Total: ~35 minutes raw footage → edit to 25 minutes**
