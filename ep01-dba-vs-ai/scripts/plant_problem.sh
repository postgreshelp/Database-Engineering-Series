#!/bin/bash
###############################################################################
# create_pg_mess_v2.sh — Create 40 realistic PostgreSQL production problems
#
# Usage: ./create_pg_mess_v2.sh -h <host> -p <port> -U <user> -d <dbname>
# Example: ./create_pg_mess_v2.sh -h 192.168.1.50 -p 5432 -U postgres -d demohealth
#
# V2: 40 categories — enough to challenge a 15-year senior DBA
###############################################################################

set -uo pipefail
# NOTE: We intentionally do NOT use 'set -e' because background processes
# (lock holders, idle sessions, sleep queries) will run after script exits
# and may return non-zero.

# Disown all background jobs at exit so the script doesn't hang waiting for them.
# The bg psql sessions (locks, idle-in-txn, long queries) must stay alive as planted problems.
trap 'disown -a 2>/dev/null; exit 0' EXIT

HOST="localhost"; PORT="5432"; USER="postgres"; DB="demohealth"

while getopts "h:p:U:d:" opt; do
  case $opt in
    h) HOST="$OPTARG" ;; p) PORT="$OPTARG" ;; U) USER="$OPTARG" ;; d) DB="$OPTARG" ;;
    *) echo "Usage: $0 -h host -p port -U user -d dbname"; exit 1 ;;
  esac
done

PSQL="psql -h $HOST -p $PORT -U $USER"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  PostgreSQL Production Chaos Creator v2.0 — 40 Problems    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Target: $HOST:$PORT | User: $USER | DB: $DB"
echo "║  Time:   $(date)"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

###############################################################################
echo "=== STEP 0: CREATE DATABASE ==="
###############################################################################

echo "[0] Creating database '$DB' ..."
$PSQL -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB' AND pid != pg_backend_pid();" 2>/dev/null || true
$PSQL -d postgres -c "DROP DATABASE IF EXISTS $DB;" 2>/dev/null || true
$PSQL -d postgres -c "CREATE DATABASE $DB;"
PSQL_DB="$PSQL -d $DB"

###############################################################################
echo ""
echo "━━━ SECTION A: SCHEMA & SEED DATA ━━━"
###############################################################################

echo "[1] Creating tables and seeding data ..."
$PSQL_DB <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Core tables
CREATE TABLE customers (
    id SERIAL PRIMARY KEY, name VARCHAR(100) NOT NULL, email VARCHAR(150),
    phone VARCHAR(20), city VARCHAR(50), created_at TIMESTAMP DEFAULT now(),
    status VARCHAR(20) DEFAULT 'active'
);
CREATE TABLE products (
    id SERIAL PRIMARY KEY, name VARCHAR(100), category VARCHAR(50),
    price NUMERIC(10,2), stock INT DEFAULT 0, description TEXT, metadata JSONB DEFAULT '{}'
);
CREATE TABLE orders (
    id SERIAL PRIMARY KEY, customer_id INT REFERENCES customers(id),
    order_date TIMESTAMP DEFAULT now(), total_amount NUMERIC(12,2),
    status VARCHAR(20) DEFAULT 'pending', shipping_city VARCHAR(50), notes TEXT
);
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY, order_id INT REFERENCES orders(id),
    product_id INT REFERENCES products(id), quantity INT, unit_price NUMERIC(10,2)
);
CREATE TABLE payments (
    id SERIAL PRIMARY KEY, order_id INT REFERENCES orders(id),
    amount NUMERIC(12,2), method VARCHAR(30), status VARCHAR(20) DEFAULT 'pending',
    processed_at TIMESTAMP, gateway_response JSONB
);
CREATE TABLE audit_log (
    id SERIAL PRIMARY KEY, table_name VARCHAR(50), action VARCHAR(20),
    old_data JSONB, new_data JSONB, changed_at TIMESTAMP DEFAULT now(), changed_by VARCHAR(50)
);
CREATE TABLE notifications (
    id SERIAL PRIMARY KEY, customer_id INT REFERENCES customers(id),
    channel VARCHAR(20), message TEXT, sent_at TIMESTAMP DEFAULT now(),
    read_at TIMESTAMP, status VARCHAR(20) DEFAULT 'pending'
);

-- Seed data
INSERT INTO customers (name, email, phone, city)
SELECT 'Customer_'||i, 'cust'||i||'@example.com', '+91'||(9000000000+i)::TEXT,
       (ARRAY['Mumbai','Delhi','Bangalore','Hyderabad','Chennai','Pune','Kolkata','Jaipur'])[1+(i%8)]
FROM generate_series(1,50000) i;

INSERT INTO products (name, category, price, stock, description, metadata)
SELECT 'Product_'||i, (ARRAY['Electronics','Clothing','Books','Food','Sports','Home','Beauty'])[1+(i%7)],
       (random()*5000+100)::NUMERIC(10,2), (random()*1000)::INT,
       repeat('Product description for item '||i||'. ', 20),
       ('{"sku":"SKU'||i||'","weight":'||(random()*10)::NUMERIC(3,1)||'}')::JSONB
FROM generate_series(1,500) i;

INSERT INTO orders (customer_id, order_date, total_amount, status, shipping_city)
SELECT (random()*49999+1)::INT, now()-(random()*365||' days')::INTERVAL,
       (random()*50000+500)::NUMERIC(12,2),
       (ARRAY['pending','shipped','delivered','cancelled','returned'])[1+(i%5)],
       (ARRAY['Mumbai','Delhi','Bangalore','Hyderabad','Chennai'])[1+(i%5)]
FROM generate_series(1,200000) i;

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT (random()*199999+1)::INT, (random()*499+1)::INT, (random()*10+1)::INT, (random()*5000+50)::NUMERIC(10,2)
FROM generate_series(1,500000) i;

INSERT INTO payments (order_id, amount, method, status, processed_at, gateway_response)
SELECT (random()*199999+1)::INT, (random()*50000+100)::NUMERIC(12,2),
       (ARRAY['credit_card','debit_card','upi','net_banking','cod'])[1+(i%5)],
       (ARRAY['success','failed','pending','refunded'])[1+(i%4)],
       now()-(random()*365||' days')::INTERVAL,
       ('{"txn_id":"TXN'||i||'","code":"'||(ARRAY['00','01','05','14'])[1+(i%4)]||'"}')::JSONB
FROM generate_series(1,180000) i;

INSERT INTO audit_log (table_name, action, old_data, new_data, changed_by)
SELECT (ARRAY['customers','orders','products','payments'])[1+(i%4)],
       (ARRAY['INSERT','UPDATE','DELETE'])[1+(i%3)],
       ('{"id":'||i||'}')::JSONB,
       ('{"id":'||i||',"modified":true,"data":"'||repeat('x',200)||'"}')::JSONB,
       (ARRAY['system','admin','api','batch_job','cron'])[1+(i%5)]
FROM generate_series(1,100000) i;

INSERT INTO notifications (customer_id, channel, message, status)
SELECT (random()*49999+1)::INT, (ARRAY['email','sms','push','whatsapp'])[1+(i%4)],
       'Notification #'||i||' - '||repeat('content ',15),
       (ARRAY['pending','sent','delivered','failed','read'])[1+(i%5)]
FROM generate_series(1,150000) i;
SQL
echo "    ✓ 7 tables, ~1.2M+ rows seeded"

###############################################################################
echo ""
echo "━━━ SECTION B: STORAGE & BLOAT (Problems 2-4) ━━━"
###############################################################################

echo "[2] Creating table bloat (disable autovacuum + heavy updates) ..."
$PSQL_DB <<'SQL'
ALTER TABLE customers SET (autovacuum_enabled = false);
ALTER TABLE orders SET (autovacuum_enabled = false);
ALTER TABLE audit_log SET (autovacuum_enabled = false);
ALTER TABLE notifications SET (autovacuum_enabled = false);

UPDATE customers SET status='inactive' WHERE id%3=0;
UPDATE customers SET status='active'   WHERE id%3=0;
UPDATE customers SET city='Unknown'    WHERE id%5=0;
UPDATE customers SET city='Mumbai'     WHERE id%5=0;
UPDATE orders SET status='processing'  WHERE id%4=0;
UPDATE orders SET status='shipped'     WHERE id%4=0;
UPDATE orders SET total_amount=total_amount+1 WHERE id%2=0;
UPDATE orders SET total_amount=total_amount-1 WHERE id%2=0;
UPDATE notifications SET status='sent'      WHERE id%3=0;
UPDATE notifications SET status='delivered' WHERE id%3=0;
SQL
echo "    ✓ ~600K dead tuples, autovacuum disabled on 4 tables"

echo "[3] Creating index bloat ..."
$PSQL_DB <<'SQL'
CREATE INDEX idx_audit_changed_at ON audit_log(changed_at);
CREATE INDEX idx_notif_sent_at ON notifications(sent_at);
DELETE FROM audit_log WHERE id%2=0;
INSERT INTO audit_log (table_name, action, old_data, new_data, changed_by)
SELECT 'orders','UPDATE', ('{"id":'||i||'}')::JSONB, ('{"id":'||i||',"refilled":true}')::JSONB, 'batch_job'
FROM generate_series(1,50000) i;
SQL
echo "    ✓ B-tree indexes fragmented"

echo "[4] Creating TOAST bloat ..."
$PSQL_DB <<'SQL'
UPDATE products SET metadata = metadata || ('{"u'||gs||'":"'||repeat('bloat',100)||'"}')::JSONB
FROM generate_series(1,5) gs WHERE id <= 200;
UPDATE products SET metadata = '{"reset":true}'::JSONB WHERE id <= 200;
SQL
echo "    ✓ TOAST bloat on products.metadata"

###############################################################################
echo ""
echo "━━━ SECTION C: INDEX ISSUES (Problems 5-8) ━━━"
###############################################################################

echo "[5] Missing FK indexes (intentional — 5 FKs unindexed)"

echo "[6] Creating unused indexes ..."
$PSQL_DB <<'SQL'
CREATE INDEX idx_cust_phone ON customers(phone);
CREATE INDEX idx_cust_created ON customers(created_at);
CREATE INDEX idx_ord_shipcity ON orders(shipping_city);
CREATE INDEX idx_prod_stock ON products(stock);
CREATE INDEX idx_audit_changedby ON audit_log(changed_by);
CREATE INDEX idx_pay_processed ON payments(processed_at);
CREATE INDEX idx_notif_readat ON notifications(read_at);
SELECT pg_stat_reset();
SQL
echo "    ✓ 7 unused indexes (stats reset so scan count = 0)"

echo "[7] Creating duplicate / overlapping indexes ..."
$PSQL_DB <<'SQL'
CREATE INDEX idx_cust_id_dup ON customers(id);
CREATE INDEX idx_ord_status ON orders(status);
CREATE INDEX idx_ord_status_date ON orders(status, order_date);
CREATE INDEX idx_cust_email_1 ON customers(email);
CREATE INDEX idx_cust_email_2 ON customers(email);
CREATE INDEX idx_pay_status ON payments(status);
CREATE INDEX idx_pay_status_method ON payments(status, method);
SQL
echo "    ✓ 7 duplicate/overlapping indexes"

echo "[8] Creating invalid index ..."
$PSQL_DB -c "CREATE INDEX CONCURRENTLY idx_ord_notes_invalid ON orders(notes);"
$PSQL_DB -c "UPDATE pg_index SET indisvalid = false WHERE indexrelid = 'idx_ord_notes_invalid'::regclass;" 2>/dev/null || echo "    ⚠ Could not mark invalid (need superuser)"
echo "    ✓ 1 invalid index"

###############################################################################
echo ""
echo "━━━ SECTION D: VACUUM & WRAPAROUND (Problems 9-10) ━━━"
###############################################################################

echo "[9] Creating wraparound risk ..."
$PSQL_DB <<'SQL'
DO $$ BEGIN FOR i IN 1..500 LOOP
    INSERT INTO audit_log (table_name, action, changed_by) VALUES ('xid_burn','INSERT','wraparound_test');
END LOOP; END $$;
ALTER TABLE audit_log SET (autovacuum_freeze_max_age = 10000);
SQL
echo "    ✓ Tables aging without vacuum, aggressive freeze threshold"

echo "[10] Creating stale statistics ..."
$PSQL_DB <<'SQL'
ANALYZE customers; ANALYZE orders; ANALYZE payments;

-- Delete orders that have no children (safe delete for stale stats)
DELETE FROM orders WHERE id > 180000
  AND id NOT IN (SELECT DISTINCT order_id FROM order_items WHERE order_id > 180000)
  AND id NOT IN (SELECT DISTINCT order_id FROM payments WHERE order_id > 180000);

-- Delete customers that have no children (safe delete for stale stats)
DELETE FROM customers WHERE id > 40000
  AND id NOT IN (SELECT DISTINCT customer_id FROM orders WHERE customer_id > 40000)
  AND id NOT IN (SELECT DISTINCT customer_id FROM notifications WHERE customer_id > 40000);

-- Now bulk insert new data to make statistics stale
INSERT INTO customers (name, email, city, status)
SELECT 'NewBulk_'||i, 'bulk'||i||'@test.com', 'Pune', 'premium' FROM generate_series(1,20000) i;
INSERT INTO orders (customer_id, total_amount, status, shipping_city)
SELECT (random()*30000+1)::INT, (random()*10000)::NUMERIC(12,2), 'new', 'Pune' FROM generate_series(1,30000) i;
SQL
echo "    ✓ Statistics stale on customers, orders"

###############################################################################
echo ""
echo "━━━ SECTION E: CONNECTIONS & SESSIONS (Problems 11-13) ━━━"
###############################################################################

echo "[11] Creating long-running queries ..."
$PSQL_DB -c "SELECT pg_sleep(600), 'long_running_demo_query_1';" &>/dev/null &
PID1=$!
$PSQL_DB -c "SELECT pg_sleep(600), 'long_running_demo_query_2';" &>/dev/null &
PID2=$!
sleep 1
echo "    ✓ 2 long-running queries (10 min, PIDs: $PID1, $PID2)"

echo "[12] Creating idle-in-transaction sessions ..."
$PSQL_DB -c "BEGIN; SELECT * FROM customers LIMIT 1; SELECT pg_sleep(600);" &>/dev/null &
$PSQL_DB -c "BEGIN; UPDATE products SET stock=stock WHERE id=1; SELECT pg_sleep(600);" &>/dev/null &
$PSQL_DB -c "BEGIN; DELETE FROM notifications WHERE id=-1; SELECT pg_sleep(600);" &>/dev/null &
sleep 2
echo "    ✓ 3 idle-in-transaction sessions"

echo "[13] Creating orphaned prepared transactions ..."
$PSQL_DB <<'SQL'
DO $$ BEGIN
    IF current_setting('max_prepared_transactions')::INT > 0 THEN
        BEGIN
            EXECUTE 'BEGIN'; EXECUTE 'INSERT INTO audit_log (table_name,action,changed_by) VALUES ($$test$$,$$2PC$$,$$orphan1$$)';
            EXECUTE 'PREPARE TRANSACTION ''orphan_txn_001''';
        EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Prepared txn 1 skipped: %', SQLERRM; END;
        BEGIN
            EXECUTE 'BEGIN'; EXECUTE 'INSERT INTO audit_log (table_name,action,changed_by) VALUES ($$test$$,$$2PC$$,$$orphan2$$)';
            EXECUTE 'PREPARE TRANSACTION ''orphan_txn_002''';
        EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Prepared txn 2 skipped: %', SQLERRM; END;
    ELSE RAISE NOTICE 'max_prepared_transactions=0, skipping 2PC'; END IF;
END $$;
SQL
echo "    ✓ Orphaned 2PC transactions (if enabled)"

###############################################################################
echo ""
echo "━━━ SECTION F: REPLICATION SLOTS (Problems 14-15) ━━━"
###############################################################################

echo "[14] Creating stale physical replication slots ..."
$PSQL_DB <<'SQL'
SELECT pg_create_physical_replication_slot('stale_replica_slot_1')
WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='stale_replica_slot_1');
SELECT pg_create_physical_replication_slot('stale_replica_slot_2')
WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='stale_replica_slot_2');
SELECT pg_create_physical_replication_slot('abandoned_standby_slot')
WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='abandoned_standby_slot');
SQL
echo "    ✓ 3 stale physical replication slots (WAL will accumulate)"

echo "[15] Creating inactive logical replication slots ..."
WAL_LEVEL=$($PSQL_DB -t -A -c "SHOW wal_level;")
if [ "$WAL_LEVEL" = "logical" ]; then
    $PSQL_DB <<'SQL'
    SELECT pg_create_logical_replication_slot('stale_logical_sub_1', 'pgoutput')
    WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='stale_logical_sub_1');
    SELECT pg_create_logical_replication_slot('dead_cdc_slot', 'test_decoding')
    WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='dead_cdc_slot');
SQL
    echo "    ✓ 2 inactive logical replication slots"
else
    echo "    ⚠ wal_level=$WAL_LEVEL (not 'logical') — skipping logical slots"
fi

###############################################################################
echo ""
echo "━━━ SECTION G: SEQUENCES (Problem 16) ━━━"
###############################################################################

echo "[16] Creating sequence exhaustion ..."
$PSQL_DB <<'SQL'
CREATE SEQUENCE demo_low_seq MAXVALUE 1000 NO CYCLE; SELECT setval('demo_low_seq', 990);
CREATE SEQUENCE report_seq MAXVALUE 5000 NO CYCLE;   SELECT setval('report_seq', 4800);
CREATE TABLE ticket_queue (id SMALLSERIAL PRIMARY KEY, description TEXT);
SELECT setval('ticket_queue_id_seq', 32700);
CREATE TABLE session_tokens (id SMALLSERIAL PRIMARY KEY, token TEXT);
SELECT setval('session_tokens_id_seq', 32000);
SQL
echo "    ✓ 4 sequences at 90-99% capacity"

###############################################################################
echo ""
echo "━━━ SECTION H: SCHEMA ISSUES (Problems 17-19) ━━━"
###############################################################################

echo "[17] Creating tables without primary keys ..."
$PSQL_DB <<'SQL'
CREATE TABLE event_log (event_type VARCHAR(50), payload JSONB, created_at TIMESTAMP DEFAULT now(), source VARCHAR(30));
INSERT INTO event_log (event_type, payload, source)
SELECT 'click', ('{"page":"page_'||i||'"}')::JSONB, 'web' FROM generate_series(1,50000) i;

CREATE TABLE staging_imports (raw_data TEXT, imported_at TIMESTAMP DEFAULT now(), batch_id INT);
INSERT INTO staging_imports (raw_data, batch_id)
SELECT repeat('raw data line '||i||' ',10), i/1000 FROM generate_series(1,20000) i;

CREATE TABLE temp_calculations (calc_type VARCHAR(30), input_val NUMERIC, result_val NUMERIC, computed_at TIMESTAMP DEFAULT now());
SQL
echo "    ✓ 3 tables without primary keys"

echo "[18] Creating unlogged tables with important data ..."
$PSQL_DB <<'SQL'
CREATE UNLOGGED TABLE daily_revenue (
    report_date DATE NOT NULL, total_revenue NUMERIC(15,2), order_count INT, avg_order_value NUMERIC(10,2)
);
INSERT INTO daily_revenue SELECT d::DATE, (random()*1000000)::NUMERIC(15,2), (random()*5000)::INT, (random()*2000)::NUMERIC(10,2)
FROM generate_series(now()-interval '365 days', now(), interval '1 day') d;

CREATE UNLOGGED TABLE customer_scores (
    customer_id INT, credit_score NUMERIC(5,2), risk_level VARCHAR(20), last_updated TIMESTAMP DEFAULT now()
);
INSERT INTO customer_scores SELECT i, (random()*100)::NUMERIC(5,2), (ARRAY['low','medium','high','critical'])[1+(i%4)], now()
FROM generate_series(1,50000) i;
SQL
echo "    ✓ 2 UNLOGGED tables with business-critical data (lost on crash!)"

echo "[19] Creating unconstrained columns ..."
$PSQL_DB <<'SQL'
CREATE TABLE user_feedback (
    id SERIAL PRIMARY KEY, user_id INT, feedback TEXT, internal_notes TEXT,
    rating INT, created_at TIMESTAMP DEFAULT now()
);
INSERT INTO user_feedback (user_id, feedback, internal_notes, rating)
SELECT (random()*50000)::INT, repeat('feedback text ',500), repeat('internal notes ',300),
       (random()*100-50)::INT
FROM generate_series(1,5000) i;
SQL
echo "    ✓ Oversized TEXT columns, no CHECK constraints, negative ratings"

###############################################################################
echo ""
echo "━━━ SECTION I: CONFIGURATION (Problem 20) ━━━"
###############################################################################

echo "[20] Applying suboptimal settings ..."
$PSQL_DB <<'SQL'
ALTER SYSTEM SET work_mem = '1MB';
ALTER SYSTEM SET maintenance_work_mem = '16MB';
ALTER SYSTEM SET random_page_cost = 4.0;
ALTER SYSTEM SET effective_cache_size = '128MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.5;
ALTER SYSTEM SET log_min_duration_statement = -1;
ALTER SYSTEM SET default_statistics_target = 50;
ALTER SYSTEM SET statement_timeout = '0';
ALTER SYSTEM SET idle_in_transaction_session_timeout = '0';
ALTER SYSTEM SET log_checkpoints = 'off';
ALTER SYSTEM SET log_connections = 'off';
ALTER SYSTEM SET log_disconnections = 'off';
ALTER SYSTEM SET log_lock_waits = 'off';
ALTER SYSTEM SET log_temp_files = '-1';
ALTER SYSTEM SET track_io_timing = 'off';
SELECT pg_reload_conf();
SQL
echo "    ✓ 15 suboptimal/dangerous settings applied"

###############################################################################
echo ""
echo "━━━ SECTION J: SECURITY / HYGIENE (Problem 21) ━━━"
###############################################################################

echo "[21] Creating security issues ..."
$PSQL_DB <<'SQL'
GRANT ALL ON ALL TABLES IN SCHEMA public TO PUBLIC;

CREATE OR REPLACE FUNCTION public.debug_info()
RETURNS TABLE(setting_name TEXT, setting_value TEXT) AS $$
    SELECT name::TEXT, setting::TEXT FROM pg_settings WHERE name LIKE '%password%' OR name LIKE '%auth%';
$$ LANGUAGE SQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.debug_info() TO PUBLIC;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_admin') THEN
        CREATE ROLE app_admin LOGIN PASSWORD 'admin123';
        GRANT ALL PRIVILEGES ON DATABASE demohealth TO app_admin;
    END IF;
END $$;
SQL
echo "    ✓ Excessive grants, SECURITY DEFINER leak, weak password role"

###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  NEW IN V2: ADVANCED PROBLEMS (22-40)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
###############################################################################

###############################################################################
echo "━━━ SECTION K: LOCK CONTENTION & DEADLOCKS (Problems 22-23) ━━━"
###############################################################################

echo "[22] Creating lock contention (blocking sessions) ..."
# Session A: holds lock on row 1, sleeps 10 min (holds the lock open)
$PSQL_DB -c "BEGIN; UPDATE products SET stock = stock + 1 WHERE id = 1; SELECT pg_sleep(600); COMMIT;" &>/dev/null &
LOCK_PID_A=$!
sleep 2

# Session B: holds lock on row 2, then tries row 1 — BLOCKED by A
# Uses statement_timeout so it won't hang forever, but will stay blocked for a while
$PSQL_DB -c "SET statement_timeout='590s'; BEGIN; UPDATE products SET stock = stock + 1 WHERE id = 2; UPDATE products SET stock = stock + 1 WHERE id = 1; COMMIT;" &>/dev/null &
LOCK_PID_B=$!
sleep 1

# Session C: tries row 2 — BLOCKED by B (which is blocked by A) = lock chain!
$PSQL_DB -c "SET statement_timeout='590s'; BEGIN; UPDATE products SET stock = stock + 1 WHERE id = 2; COMMIT;" &>/dev/null &
LOCK_PID_C=$!
sleep 1
echo "    ✓ Lock chain: C blocked by B blocked by A (PIDs: $LOCK_PID_A → $LOCK_PID_B → $LOCK_PID_C)"

echo "[23] Creating advisory lock leak ..."
$PSQL_DB -c "BEGIN; SELECT pg_advisory_lock(12345); SELECT pg_advisory_lock(67890); SELECT pg_sleep(600);" &>/dev/null &
$PSQL_DB -c "BEGIN; SELECT pg_advisory_lock(11111); SELECT pg_sleep(600);" &>/dev/null &
sleep 1
echo "    ✓ 3 advisory locks held indefinitely (leaked)"

###############################################################################
echo ""
echo "━━━ SECTION L: DATA INTEGRITY DISASTERS (Problems 24-27) ━━━"
###############################################################################

echo "[24] Creating orphaned child rows (FK violations) ..."
$PSQL_DB <<'SQL'
-- Must drop ALL FKs referencing orders (order_items + payments) before deleting
ALTER TABLE order_items DROP CONSTRAINT IF EXISTS order_items_order_id_fkey;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_order_id_fkey;

-- Now delete parent rows — children become orphans
DELETE FROM orders WHERE id BETWEEN 1 AND 500;

-- Re-add FKs as NOT VALID — existing orphans won't be checked!
ALTER TABLE order_items ADD CONSTRAINT order_items_order_id_fkey
    FOREIGN KEY (order_id) REFERENCES orders(id) NOT VALID;
ALTER TABLE payments ADD CONSTRAINT payments_order_id_fkey
    FOREIGN KEY (order_id) REFERENCES orders(id) NOT VALID;


echo "[25] Creating duplicate data that should be unique ..."
$PSQL_DB <<'SQL'
-- Insert duplicate emails (should be unique but no constraint!)
INSERT INTO customers (name, email, phone, city, status)
VALUES
    ('Duplicate_User_1', 'cust1@example.com', '+910000000001', 'Mumbai', 'active'),
    ('Duplicate_User_2', 'cust1@example.com', '+910000000002', 'Delhi', 'active'),
    ('Duplicate_User_3', 'cust2@example.com', '+910000000003', 'Pune', 'active'),
    ('Duplicate_User_4', 'cust2@example.com', '+910000000004', 'Chennai', 'active'),
    ('Duplicate_User_5', 'cust3@example.com', '+910000000005', 'Hyderabad', 'active');
SQL
echo "    ✓ Duplicate emails in customers table (data integrity violation)"

echo "[26] Creating NULL values in critical columns ..."
$PSQL_DB <<'SQL'
-- Orders with NULL amounts, NULL customer_ids
INSERT INTO orders (customer_id, total_amount, status, shipping_city)
VALUES (NULL, NULL, 'pending', NULL),
       (NULL, 0, 'shipped', NULL),
       (NULL, -500, 'delivered', 'Mumbai');

-- Payments with NULL amounts
INSERT INTO payments (order_id, amount, method, status)
VALUES (1, NULL, NULL, 'success'),
       (2, -1000, 'upi', 'success'),
       (3, 0, NULL, NULL);
SQL
echo "    ✓ NULL and negative values in critical financial columns"

echo "[27] Creating data type abuse (everything stored as TEXT) ..."
$PSQL_DB <<'SQL'
CREATE TABLE app_settings (
    id SERIAL PRIMARY KEY,
    setting_key VARCHAR(100),
    setting_value TEXT,  -- stores ints, bools, dates, JSON all as TEXT!
    updated_at TIMESTAMP DEFAULT now()
);
INSERT INTO app_settings (setting_key, setting_value) VALUES
    ('max_retries', '3'),            -- should be INT
    ('feature_flag_beta', 'true'),   -- should be BOOLEAN
    ('launch_date', '2025-01-15'),   -- should be DATE
    ('rate_limit', '1000.50'),       -- should be NUMERIC
    ('api_config', '{"timeout":30,"retries":3}'),  -- should be JSONB
    ('is_maintenance', 'yes'),       -- inconsistent boolean representation
    ('max_connections', 'one hundred'), -- non-parseable "number"
    ('backup_time', 'midnight'),     -- non-parseable "time"
    ('threshold', 'N/A'),            -- placeholder instead of NULL
    ('price_multiplier', '1,5');     -- comma instead of decimal point
SQL
echo "    ✓ TEXT column abuse — mixed types stored as strings"

###############################################################################
echo ""
echo "━━━ SECTION M: PARTITIONING GONE WRONG (Problem 28) ━━━"
###############################################################################

echo "[28] Creating broken partitioning (missing future partitions) ..."
$PSQL_DB <<'SQL'
-- Partitioned table by month
CREATE TABLE sales_log (
    id BIGSERIAL,
    sale_date DATE NOT NULL,
    amount NUMERIC(12,2),
    region VARCHAR(30)
) PARTITION BY RANGE (sale_date);

-- Only create partitions for past months — future data goes to default!
CREATE TABLE sales_log_2025_01 PARTITION OF sales_log
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE sales_log_2025_02 PARTITION OF sales_log
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE sales_log_2025_03 PARTITION OF sales_log
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
-- Missing: April onwards!

-- Create a default partition (catch-all — bad practice when unmonitored)
CREATE TABLE sales_log_default PARTITION OF sales_log DEFAULT;

-- Insert data spanning past and future — future data lands in default
INSERT INTO sales_log (sale_date, amount, region)
SELECT d::DATE, (random()*10000)::NUMERIC(12,2),
       (ARRAY['North','South','East','West'])[1+(gs%4)]
FROM generate_series('2025-01-01'::DATE, '2025-08-31'::DATE, '1 hour') d,
     generate_series(1,1) gs;

-- Also: create an empty partition that's wasting space
CREATE TABLE sales_log_2024_12 PARTITION OF sales_log
    FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');
SQL
echo "    ✓ Partitions missing for future months, data piling in DEFAULT partition"
echo "    ✓ Empty stale partition (2024_12) wasting catalog space"

###############################################################################
echo ""
echo "━━━ SECTION N: TRIGGER CHAOS (Problems 29-30) ━━━"
###############################################################################

echo "[29] Creating broken / expensive triggers ..."
$PSQL_DB <<'SQL'
-- Trigger that silently swallows errors (data silently lost)
CREATE OR REPLACE FUNCTION trg_silent_fail() RETURNS TRIGGER AS $$
BEGIN
    BEGIN
        INSERT INTO audit_log (table_name, action, new_data, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(NEW)::JSONB, 'trigger');
    EXCEPTION WHEN OTHERS THEN
        -- Silently swallow ALL errors — data loss!
        NULL;
    END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_customers_audit
    AFTER INSERT OR UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION trg_silent_fail();

-- Expensive trigger: does a full table scan on every insert
CREATE OR REPLACE FUNCTION trg_expensive_check() RETURNS TRIGGER AS $$
DECLARE
    total_count INT;
BEGIN
    -- Full count on every single INSERT — O(n) per row!
    SELECT count(*) INTO total_count FROM orders;
    IF total_count > 10000000 THEN
        RAISE NOTICE 'Order threshold exceeded: %', total_count;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_expensive
    BEFORE INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION trg_expensive_check();
SQL
echo "    ✓ Silent-fail trigger (swallows errors), expensive per-row trigger"

echo "[30] Creating disabled trigger that should be active ..."
$PSQL_DB <<'SQL'
-- Critical audit trigger that someone disabled "temporarily"
CREATE OR REPLACE FUNCTION trg_payment_audit() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, action, new_data, changed_by)
    VALUES ('payments', TG_OP, row_to_json(NEW)::JSONB, 'payment_trigger');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payments_audit
    AFTER INSERT OR UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION trg_payment_audit();

-- "Temporarily" disable it — and forget
ALTER TABLE payments DISABLE TRIGGER trg_payments_audit;
SQL
echo "    ✓ Critical audit trigger DISABLED on payments table"

###############################################################################
echo ""
echo "━━━ SECTION O: ROLE & PRIVILEGE ESCALATION (Problems 31-32) ━━━"
###############################################################################

echo "[31] Creating role inheritance mess ..."
$PSQL_DB <<'SQL'
DO $$ BEGIN
    -- Create a chain of roles with dangerous inheritance
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='junior_dev') THEN
        CREATE ROLE junior_dev LOGIN PASSWORD 'junior123';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='senior_dev') THEN
        CREATE ROLE senior_dev LOGIN PASSWORD 'senior123';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='team_lead') THEN
        CREATE ROLE team_lead LOGIN PASSWORD 'lead123';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='dba_role') THEN
        CREATE ROLE dba_role LOGIN PASSWORD 'dba123' CREATEDB CREATEROLE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='readonly_user') THEN
        CREATE ROLE readonly_user LOGIN PASSWORD 'readonly123';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='etl_service') THEN
        CREATE ROLE etl_service LOGIN PASSWORD 'etl_service';
    END IF;

    -- Dangerous inheritance chain: junior -> senior -> lead -> dba
    GRANT senior_dev TO junior_dev;
    GRANT team_lead TO senior_dev;
    GRANT dba_role TO team_lead;

    -- readonly_user that isn't actually read-only
    GRANT ALL ON ALL TABLES IN SCHEMA public TO readonly_user;

    -- Service account with too many privileges
    GRANT ALL ON DATABASE demohealth TO etl_service;
    ALTER ROLE etl_service CREATEDB;
END $$;
SQL
echo "    ✓ Role chain: junior_dev → senior_dev → team_lead → dba_role (escalation!)"
echo "    ✓ 'readonly_user' with WRITE privileges, overprivileged service account"

echo "[32] Creating search_path hijack vulnerability ..."
$PSQL_DB <<'SQL'
-- Set a dangerous search_path that allows function shadowing
ALTER DATABASE demohealth SET search_path TO public, pg_catalog;

-- Create a function in public that shadows a common pattern
-- An attacker could replace this with malicious code
CREATE OR REPLACE FUNCTION public.current_user_id() RETURNS INT AS $$
    SELECT 1;  -- This could be anything malicious
$$ LANGUAGE SQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.current_user_id() TO PUBLIC;
SQL
echo "    ✓ search_path hijack: public before pg_catalog, shadowing function"

###############################################################################
echo ""
echo "━━━ SECTION P: CONSTRAINT VIOLATIONS (Problems 33-34) ━━━"
###############################################################################

echo "[33] Creating NOT VALID constraints (never validated) ..."
$PSQL_DB <<'SQL'
-- Add constraints as NOT VALID — existing bad data remains!
ALTER TABLE orders ADD CONSTRAINT chk_positive_amount
    CHECK (total_amount >= 0) NOT VALID;

ALTER TABLE payments ADD CONSTRAINT chk_positive_payment
    CHECK (amount >= 0) NOT VALID;

-- Insert some violating data BEFORE the constraint (already done in step 26)
-- The NOT VALID means existing rows are NOT checked
SQL
echo "    ✓ NOT VALID constraints on orders.total_amount and payments.amount"
echo "    ✓ Existing negative values not caught"

echo "[34] Creating CHECK constraint that's too permissive ..."
$PSQL_DB <<'SQL'
ALTER TABLE user_feedback ADD CONSTRAINT chk_rating_range
    CHECK (rating BETWEEN -999 AND 999) NOT VALID;
-- Rating should be 1-5 but constraint allows -999 to 999!
SQL
echo "    ✓ Overly permissive CHECK constraint (allows -999 to 999 for ratings)"

###############################################################################
echo ""
echo "━━━ SECTION Q: TEMP FILES & MEMORY SPILLS (Problem 35) ━━━"
###############################################################################

echo "[35] Creating queries that spill to disk ..."
$PSQL_DB <<'SQL'
-- Create a view that forces massive sorts with tiny work_mem (1MB)
CREATE VIEW v_expensive_report AS
SELECT o.id, o.customer_id, o.total_amount, o.order_date, o.status,
       c.name, c.email, c.city,
       p.amount AS payment_amount, p.method, p.status AS payment_status,
       rank() OVER (PARTITION BY o.customer_id ORDER BY o.total_amount DESC) AS customer_rank,
       sum(o.total_amount) OVER (PARTITION BY c.city ORDER BY o.order_date) AS city_running_total
FROM orders o
JOIN customers c ON c.id = o.customer_id
LEFT JOIN payments p ON p.order_id = o.id;

-- Create a materialized view that's never refreshed
CREATE MATERIALIZED VIEW mv_stale_summary AS
SELECT c.city, count(*) AS order_count,
       sum(o.total_amount) AS total_revenue,
       avg(o.total_amount) AS avg_order
FROM orders o JOIN customers c ON c.id = o.customer_id
GROUP BY c.city;
-- It's now stale since we've modified data after this point
SQL
echo "    ✓ Expensive view with window functions (will spill with 1MB work_mem)"
echo "    ✓ Stale materialized view (never refreshed after data changes)"

###############################################################################
echo ""
echo "━━━ SECTION R: EXTENSION ISSUES (Problem 36) ━━━"
###############################################################################

echo "[36] Creating extension issues ..."
$PSQL_DB <<'SQL'
-- Install extensions but don't update them
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create a function that depends on an extension in a fragile way
CREATE OR REPLACE FUNCTION generate_secure_token() RETURNS TEXT AS $$
    SELECT encode(gen_random_bytes(32), 'hex');
$$ LANGUAGE SQL;
SQL

# Check if any extensions need updating
echo "    Checking for outdated extensions..."
$PSQL_DB -c "SELECT name, installed_version, default_version, CASE WHEN installed_version != default_version THEN '❌ NEEDS UPDATE' ELSE '✅ current' END AS status FROM pg_available_extensions WHERE installed_version IS NOT NULL;" 2>/dev/null
echo "    ✓ Extensions installed (may need version updates)"

###############################################################################
echo ""
echo "━━━ SECTION S: WAL & ARCHIVING (Problem 37) ━━━"
###############################################################################

echo "[37] Creating WAL archiving issues ..."
$PSQL_DB <<'SQL'
-- Set archive_command to a failing path (will silently fail)
-- Only works if archive_mode is on
DO $$ BEGIN
    IF current_setting('archive_mode') = 'on' THEN
        EXECUTE 'ALTER SYSTEM SET archive_command = ''/nonexistent/path/archive.sh %p %f''';
        PERFORM pg_reload_conf();
        RAISE NOTICE 'Set bad archive_command';
    ELSE
        RAISE NOTICE 'archive_mode is off — setting bad archive_command anyway for detection';
        EXECUTE 'ALTER SYSTEM SET archive_command = ''/nonexistent/path/archive.sh %p %f''';
        PERFORM pg_reload_conf();
    END IF;
END $$;
SQL
echo "    ✓ archive_command pointing to non-existent path"

###############################################################################
echo ""
echo "━━━ SECTION T: FOREIGN DATA WRAPPER MESS (Problem 38) ━━━"
###############################################################################

echo "[38] Creating broken Foreign Data Wrapper ..."
$PSQL_DB <<'SQL'
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Create FDW server pointing to a dead host
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname='dead_remote_server') THEN
        CREATE SERVER dead_remote_server FOREIGN DATA WRAPPER postgres_fdw
            OPTIONS (host '10.255.255.1', port '5432', dbname 'production');
    END IF;
END $$;

-- Create user mapping with hardcoded credentials (security issue!)
DO $$ BEGIN
    BEGIN
        CREATE USER MAPPING IF NOT EXISTS FOR PUBLIC SERVER dead_remote_server
            OPTIONS (user 'remote_admin', password 'RemotePass123!');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'User mapping skipped: %', SQLERRM;
    END;
END $$;

-- Create foreign table (will fail on any query)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_table WHERE ftrelid = 'remote_inventory'::regclass) THEN
        CREATE FOREIGN TABLE remote_inventory (
            id INT, product_name TEXT, warehouse VARCHAR(50), quantity INT
        ) SERVER dead_remote_server OPTIONS (table_name 'inventory');
    END IF;
EXCEPTION WHEN OTHERS THEN
    CREATE FOREIGN TABLE remote_inventory (
        id INT, product_name TEXT, warehouse VARCHAR(50), quantity INT
    ) SERVER dead_remote_server OPTIONS (table_name 'inventory');
END $$;
SQL
echo "    ✓ FDW pointing to dead server (10.255.255.1), hardcoded credentials in user mapping"

###############################################################################
echo ""
echo "━━━ SECTION U: pg_stat_statements BLOAT (Problem 39) ━━━"
###############################################################################

echo "[39] Bloating pg_stat_statements with unique queries ..."
$PSQL_DB <<'SQL'
-- Generate thousands of unique query patterns (no parameterization)
-- This fills pg_stat_statements, making it useless for finding real slow queries
DO $$ BEGIN
    FOR i IN 1..2000 LOOP
        EXECUTE format('SELECT * FROM customers WHERE id = %s AND name = %L', i, 'user_' || i);
    END LOOP;
END $$;

DO $$ BEGIN
    FOR i IN 1..1000 LOOP
        EXECUTE format('SELECT count(*) FROM orders WHERE total_amount > %s AND status = %L',
                        i * 10, (ARRAY['pending','shipped','delivered'])[1+(i%3)]);
    END LOOP;
END $$;
SQL
echo "    ✓ 3000+ unique query patterns in pg_stat_statements (polluted)"

###############################################################################
echo ""
echo "━━━ SECTION V: CONNECTION EXHAUSTION SIMULATION (Problem 40) ━━━"
###############################################################################

echo "[40] Simulating connection pressure ..."
MAX_CONN=$($PSQL_DB -t -A -c "SHOW max_connections;")
echo "    max_connections = $MAX_CONN"

# Open many idle connections to eat up slots
CONN_COUNT=0
TARGET=$((MAX_CONN * 60 / 100))  # Try to use 60% of connections
if [ "$TARGET" -gt 50 ]; then TARGET=50; fi  # Cap at 50 for safety

for i in $(seq 1 $TARGET); do
    $PSQL_DB -c "SELECT pg_sleep(600);" &>/dev/null &
    CONN_COUNT=$((CONN_COUNT+1))
done
sleep 2
echo "    ✓ $CONN_COUNT idle connections opened (eating connection slots)"
echo "    ✓ Connection pool pressure: ~$CONN_COUNT / $MAX_CONN used"

###############################################################################
echo ""
echo "━━━ BONUS: MISCELLANEOUS TIME BOMBS ━━━"
###############################################################################

echo "[41] Creating miscellaneous issues ..."
$PSQL_DB <<'SQL'
-- Table with extremely wide rows (column sprawl)
CREATE TABLE wide_config_table (
    id SERIAL PRIMARY KEY,
    col_01 TEXT, col_02 TEXT, col_03 TEXT, col_04 TEXT, col_05 TEXT,
    col_06 TEXT, col_07 TEXT, col_08 TEXT, col_09 TEXT, col_10 TEXT,
    col_11 TEXT, col_12 TEXT, col_13 TEXT, col_14 TEXT, col_15 TEXT,
    col_16 TEXT, col_17 TEXT, col_18 TEXT, col_19 TEXT, col_20 TEXT,
    col_21 TEXT, col_22 TEXT, col_23 TEXT, col_24 TEXT, col_25 TEXT,
    col_26 TEXT, col_27 TEXT, col_28 TEXT, col_29 TEXT, col_30 TEXT,
    col_31 TEXT, col_32 TEXT, col_33 TEXT, col_34 TEXT, col_35 TEXT,
    col_36 TEXT, col_37 TEXT, col_38 TEXT, col_39 TEXT, col_40 TEXT,
    col_41 TEXT, col_42 TEXT, col_43 TEXT, col_44 TEXT, col_45 TEXT,
    col_46 TEXT, col_47 TEXT, col_48 TEXT, col_49 TEXT, col_50 TEXT,
    created_at TIMESTAMP DEFAULT now()
);
INSERT INTO wide_config_table (col_01, col_02, col_03)
SELECT repeat('data',50), repeat('more',50), repeat('stuff',50)
FROM generate_series(1,1000);

-- Table with reserved keyword names (will cause quoting nightmares)
CREATE TABLE "order" (
    "user" INT, "select" TEXT, "table" TEXT, "group" INT, "date" TIMESTAMP DEFAULT now()
);
INSERT INTO "order" ("user", "select", "table", "group")
SELECT i, 'val_'||i, 'tbl_'||i, i%10 FROM generate_series(1,1000) i;

-- Circular dependency via deferred constraints
CREATE TABLE dept (
    id SERIAL PRIMARY KEY, name TEXT, manager_id INT
);
CREATE TABLE emp (
    id SERIAL PRIMARY KEY, name TEXT, dept_id INT REFERENCES dept(id)
);
ALTER TABLE dept ADD CONSTRAINT fk_dept_manager
    FOREIGN KEY (manager_id) REFERENCES emp(id) DEFERRABLE INITIALLY DEFERRED;
INSERT INTO dept (name) VALUES ('Engineering'), ('Sales'), ('Support');
INSERT INTO emp (name, dept_id) VALUES ('Alice', 1), ('Bob', 2), ('Charlie', 3);
UPDATE dept SET manager_id = 1 WHERE id = 1;
UPDATE dept SET manager_id = 2 WHERE id = 2;

-- Functions with implicit casts that will break
CREATE OR REPLACE FUNCTION get_order_total(order_id TEXT) RETURNS NUMERIC AS $$
    SELECT total_amount FROM orders WHERE id = order_id::INT LIMIT 1;
$$ LANGUAGE SQL;
-- This function accepts TEXT for an INT column — implicit cast time bomb

-- Abandoned temporary table namespace pollution
DO $$ BEGIN
    CREATE TEMP TABLE IF NOT EXISTS _tmp_migration_2024 (id INT, data TEXT);
    INSERT INTO _tmp_migration_2024 SELECT i, repeat('migration',100) FROM generate_series(1,10000) i;
END $$;
SQL
echo "    ✓ 50-column wide table"
echo "    ✓ Table/column names using SQL reserved keywords"
echo "    ✓ Circular FK dependency (dept ↔ emp)"
echo "    ✓ Function with implicit type cast (TEXT → INT)"
echo "    ✓ Temp table pollution"

###############################################################################
echo ""
echo "=== FINAL SUMMARY ==="
###############################################################################

$PSQL_DB -x <<'SQL'
SELECT
    (SELECT to_char(SUM(n_dead_tup),'FM999,999,999') FROM pg_stat_user_tables WHERE schemaname='public') AS dead_tuples,
    (SELECT COUNT(*) FROM pg_indexes WHERE schemaname='public') AS total_indexes,
    (SELECT COUNT(*) FROM pg_index WHERE NOT indisvalid) AS invalid_indexes,
    (SELECT COUNT(*) FROM information_schema.tables t WHERE t.table_schema='public' AND t.table_type='BASE TABLE'
     AND NOT EXISTS (SELECT 1 FROM information_schema.table_constraints tc WHERE tc.table_schema=t.table_schema
     AND tc.table_name=t.table_name AND tc.constraint_type='PRIMARY KEY')) AS tables_without_pk,
    (SELECT COUNT(*) FROM pg_replication_slots) AS replication_slots,
    (SELECT COUNT(*) FROM pg_class WHERE relpersistence='u' AND relkind='r') AS unlogged_tables,
    (SELECT COUNT(*) FROM pg_sequences WHERE last_value::FLOAT/max_value::FLOAT > 0.75) AS sequences_near_limit,
    (SELECT COUNT(*) FROM pg_stat_activity WHERE datname=current_database() AND pid!=pg_backend_pid()) AS active_backends,
    (SELECT COUNT(*) FROM pg_prepared_xacts) AS orphaned_2pc,
    (SELECT COUNT(*) FROM pg_trigger WHERE NOT tgenabled = 'O' AND tgrelid IN (SELECT oid FROM pg_class WHERE relnamespace='public'::regnamespace)) AS disabled_triggers,
    (SELECT COUNT(*) FROM pg_foreign_server) AS foreign_servers,
    (SELECT COUNT(*) FROM pg_proc WHERE prosecdef AND pronamespace='public'::regnamespace) AS security_definer_funcs;
SQL

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅ ALL 40+ PROBLEMS PLANTED SUCCESSFULLY!                 ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
echo "║  ORIGINAL 21 PROBLEMS (v1):                                ║"
echo "║  ─────────────────────────────────────────────────────────  ║"
echo "║  STORAGE:     Table bloat, Index bloat, TOAST bloat        ║"
echo "║  INDEXES:     Missing FK, Unused(7), Duplicate(7), Invalid ║"
echo "║  VACUUM:      Autovacuum off(4), Wraparound, Stale stats   ║"
echo "║  SESSIONS:    Long queries(2), Idle-in-txn(3), Orphan 2PC  ║"
echo "║  REPLICATION: Stale physical(3), Logical slots(2)          ║"
echo "║  SEQUENCES:   4 near exhaustion (90-99%)                   ║"
echo "║  SCHEMA:      No PK(3), Unlogged(2), Unconstrained cols    ║"
echo "║  CONFIG:      15 bad settings                              ║"
echo "║  SECURITY:    Public grants, SECURITY DEFINER, weak pwd    ║"
echo "║                                                            ║"
echo "║  NEW IN V2 (Problems 22-41):                               ║"
echo "║  ─────────────────────────────────────────────────────────  ║"
echo "║  LOCKS:       Deadlock scenario, Advisory lock leaks       ║"
echo "║  DATA:        Orphaned FKs, Duplicate emails, NULLs in    ║"
echo "║               financials, TEXT column type abuse            ║"
echo "║  PARTITION:   Missing future partitions, DEFAULT overflow   ║"
echo "║  TRIGGERS:    Silent-fail, Expensive per-row, Disabled     ║"
echo "║  ROLES:       Escalation chain, Fake readonly, search_path ║"
echo "║  CONSTRAINTS: NOT VALID FKs, NOT VALID CHECKs, Permissive ║"
echo "║  PERFORMANCE: Disk-spilling views, Stale materialized view ║"
echo "║  EXTENSIONS:  Outdated versions, FDW to dead server        ║"
echo "║  STATEMENTS:  3000+ unique queries polluting pg_stat_stmts ║"
echo "║  CONNECTIONS: ~60% slots consumed by idle connections      ║"
echo "║  MISC:        50-col wide table, Reserved keyword names,   ║"
echo "║               Circular FK, Implicit cast funcs, Temp bloat ║"
echo "║               Bad archive_command                          ║"
echo "║                                                            ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
echo "║  Now open Claude Code and say:                             ║"
echo "║  ┌──────────────────────────────────────────────────────┐  ║"
echo "║  │ This database is sick.                               │  ║"
echo "║  │ Connect: psql -h <IP> -p 5432 -U postgres            │  ║"
echo "║  │          -d demohealth                               │  ║"
echo "║  │ Scan everything. Fix everything. Verify everything.  │  ║"
echo "║  │ Don't ask me anything. Just do it.                   │  ║"
echo "║  └──────────────────────────────────────────────────────┘  ║"
echo "║                                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
