#!/bin/bash
###############################################################################
# pg_health_report_html.sh — AWR-style HTML PostgreSQL Health Check Report
#
# Usage: ./pg_health_report_html.sh -h <host> -p <port> -U <user> -d <dbname> [-t before|after]
#
# Examples:
#   ./pg_health_report_html.sh -h 192.168.1.50 -U postgres -d demohealth -t before
#   ./pg_health_report_html.sh -h 192.168.1.50 -U postgres -d demohealth -t after
#
# Opens the report in your default browser automatically.
###############################################################################

set -uo pipefail

HOST="localhost"; PORT="5432"; USER="postgres"; DB="demohealth"; TAG=""

while getopts "h:p:U:d:t:" opt; do
  case $opt in
    h) HOST="$OPTARG" ;; p) PORT="$OPTARG" ;; U) USER="$OPTARG" ;;
    d) DB="$OPTARG" ;; t) TAG="$OPTARG" ;;
    *) echo "Usage: $0 -h host -p port -U user -d dbname [-t before|after]"; exit 1 ;;
  esac
done

PSQL="psql -h $HOST -p $PORT -U $USER -d $DB --no-psqlrc -q"
TS=$(date +%Y%m%d_%H%M%S)
REPORT="pg_health_${TAG:+${TAG}_}${TS}.html"
ISSUES=0; WARNINGS=0; PASSED=0

sql()      { $PSQL -t -A -c "$1" 2>/dev/null; }
sql_count(){ local c; c=$($PSQL -t -A -c "$1" 2>/dev/null); echo "${c:-0}"; }
# sql_html: runs query, outputs <table> rows from psql HTML output
sql_html() {
    $PSQL --html -c "$1" 2>/dev/null | sed -n '/<table/,/<\/table>/p'
}

echo "Scanning $DB on $HOST:$PORT ..."

###############################################################################
# Gather header info
###############################################################################
PG_VER=$(sql "SELECT version();" | head -1)
PG_SHORT=$(sql "SELECT current_setting('server_version');")
DB_SIZE=$(sql "SELECT pg_size_pretty(pg_database_size(current_database()));")
TABLE_COUNT=$(sql_count "SELECT count(*) FROM pg_stat_user_tables WHERE schemaname='public';")
INDEX_COUNT=$(sql_count "SELECT count(*) FROM pg_indexes WHERE schemaname='public';")
CONN_TOTAL=$(sql_count "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database();")
MAX_CONN=$(sql "SHOW max_connections;")
UPTIME=$(sql "SELECT now() - pg_postmaster_start_time();")
START_TIME=$(sql "SELECT pg_postmaster_start_time()::TEXT;")

###############################################################################
# Start HTML
###############################################################################
cat > "$REPORT" <<'HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PostgreSQL Health Check Report</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    font-family: "Courier New", Courier, monospace;
    font-size: 13px;
    color: #1a1a1a;
    background: #fff;
    padding: 20px 30px;
    max-width: 1200px;
    margin: 0 auto;
}

/* AWR-style header */
.report-header {
    border: 2px solid #333;
    padding: 12px 16px;
    margin-bottom: 20px;
    background: #f5f5f5;
}
.report-header h1 {
    font-size: 16px;
    font-weight: bold;
    text-align: center;
    margin-bottom: 8px;
    letter-spacing: 1px;
}
.report-header table {
    width: 100%;
    border-collapse: collapse;
}
.report-header td {
    padding: 2px 8px;
    font-size: 12px;
}
.report-header td.label {
    font-weight: bold;
    width: 160px;
    color: #444;
}

/* Scorecard */
.scorecard {
    border: 2px solid #333;
    padding: 10px 16px;
    margin-bottom: 20px;
    text-align: center;
}
.scorecard .rating { font-size: 18px; font-weight: bold; margin: 6px 0; }
.scorecard .counts { font-size: 13px; margin-top: 4px; }
.scorecard .counts span { margin: 0 12px; }
.rating-critical { color: #cc0000; }
.rating-poor { color: #cc6600; }
.rating-fair { color: #999900; }
.rating-good { color: #006600; }

/* TOC */
.toc {
    border: 1px solid #999;
    padding: 10px 16px;
    margin-bottom: 20px;
    background: #fafafa;
}
.toc h2 { font-size: 13px; font-weight: bold; margin-bottom: 6px; }
.toc a { color: #0000cc; text-decoration: none; font-size: 12px; }
.toc a:hover { text-decoration: underline; }
.toc-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2px 20px;
}

/* Sections */
.section {
    margin-bottom: 16px;
    page-break-inside: avoid;
}
.section-header {
    background: #e8e8e8;
    border: 1px solid #999;
    border-bottom: none;
    padding: 5px 10px;
    font-weight: bold;
    font-size: 13px;
}
.section-body {
    border: 1px solid #999;
    padding: 8px 10px;
}

/* Status badges */
.badge {
    display: inline-block;
    padding: 1px 8px;
    font-size: 11px;
    font-weight: bold;
    font-family: "Courier New", monospace;
}
.badge-issue {
    background: #fff3cd;
    border: 1px solid #cc9900;
    color: #664d00;
}
.badge-warning {
    background: #ffe8cc;
    border: 1px solid #cc6600;
    color: #663300;
}
.badge-pass {
    background: #d4edda;
    border: 1px solid #339933;
    color: #1a4d1a;
}

/* Finding rows */
.finding {
    margin: 6px 0;
    padding: 4px 8px;
}
.finding-issue {
    background: #fff3cd;
    border-left: 4px solid #cc9900;
}
.finding-warning {
    background: #fff5e6;
    border-left: 4px solid #cc6600;
}
.finding-pass {
    background: #eaf7ec;
    border-left: 4px solid #339933;
}

/* Data tables — AWR style */
table.data {
    width: 100%;
    border-collapse: collapse;
    margin: 6px 0;
    font-size: 12px;
}
table.data th {
    background: #d0d0d0;
    border: 1px solid #999;
    padding: 3px 6px;
    text-align: left;
    font-weight: bold;
    white-space: nowrap;
}
table.data td {
    border: 1px solid #bbb;
    padding: 3px 6px;
    vertical-align: top;
}
table.data tr:nth-child(even) { background: #f5f5f5; }
table.data tr:hover { background: #ffffcc; }

/* Highlight rows */
tr.row-issue { background: #fff3cd !important; }
tr.row-warning { background: #fff5e6 !important; }

/* Misc */
.note { font-size: 11px; color: #666; margin-top: 4px; }
.footer {
    margin-top: 30px;
    padding-top: 8px;
    border-top: 2px solid #333;
    font-size: 11px;
    color: #666;
    text-align: center;
}
hr.separator { border: none; border-top: 1px solid #ccc; margin: 4px 0; }

@media print {
    body { font-size: 11px; padding: 10px; }
    .section { page-break-inside: avoid; }
}
</style>
</head>
<body>
HEADER

###############################################################################
# Header section
###############################################################################
cat >> "$REPORT" <<EOF
<div class="report-header">
  <h1>POSTGRESQL HEALTH CHECK REPORT</h1>
  <table>
    <tr><td class="label">Database:</td><td>$DB</td><td class="label">DB Size:</td><td>$DB_SIZE</td></tr>
    <tr><td class="label">Host:</td><td>$HOST:$PORT</td><td class="label">Tables:</td><td>$TABLE_COUNT</td></tr>
    <tr><td class="label">User:</td><td>$USER</td><td class="label">Indexes:</td><td>$INDEX_COUNT</td></tr>
    <tr><td class="label">PG Version:</td><td>$PG_SHORT</td><td class="label">Connections:</td><td>$CONN_TOTAL / $MAX_CONN</td></tr>
    <tr><td class="label">Started:</td><td>$START_TIME</td><td class="label">Uptime:</td><td>$UPTIME</td></tr>
    <tr><td class="label">Report Tag:</td><td><b>${TAG:-none}</b></td><td class="label">Generated:</td><td>$(date)</td></tr>
  </table>
</div>
EOF

###############################################################################
# Helper: write section to report
###############################################################################
section_start() {
    echo "<div class='section' id='s$1'>" >> "$REPORT"
    echo "<div class='section-header'>$1. $2</div>" >> "$REPORT"
    echo "<div class='section-body'>" >> "$REPORT"
}
section_end() {
    echo "</div></div>" >> "$REPORT"
}
finding_issue() {
    ISSUES=$((ISSUES+1))
    echo "<div class='finding finding-issue'><span class='badge badge-issue'>ISSUE</span> $1</div>" >> "$REPORT"
}
finding_warn() {
    WARNINGS=$((WARNINGS+1))
    echo "<div class='finding finding-warning'><span class='badge badge-warning'>WARNING</span> $1</div>" >> "$REPORT"
}
finding_pass() {
    PASSED=$((PASSED+1))
    echo "<div class='finding finding-pass'><span class='badge badge-pass'>PASS</span> $1</div>" >> "$REPORT"
}
write_table() {
    sql_html "$1" >> "$REPORT"
}
note() {
    echo "<div class='note'>$1</div>" >> "$REPORT"
}

###############################################################################
# PLACEHOLDER for scorecard (will be filled at the end)
###############################################################################
echo "<!-- SCORECARD_PLACEHOLDER -->" >> "$REPORT"

###############################################################################
# TOC
###############################################################################
cat >> "$REPORT" <<'TOC'
<div class="toc">
<h2>Table of Contents</h2>
<div class="toc-grid">
<div>
<a href="#s1">1. Table Bloat &amp; Autovacuum</a><br>
<a href="#s2">2. Index Bloat</a><br>
<a href="#s3">3. Invalid Indexes</a><br>
<a href="#s4">4. Unused Indexes</a><br>
<a href="#s5">5. Duplicate / Overlapping Indexes</a><br>
<a href="#s6">6. Missing Foreign Key Indexes</a><br>
<a href="#s7">7. Wraparound Risk (XID Age)</a><br>
<a href="#s8">8. Stale Statistics</a><br>
<a href="#s9">9. Long-Running Queries</a><br>
<a href="#s10">10. Idle-in-Transaction Sessions</a><br>
<a href="#s11">11. Orphaned Prepared Transactions</a><br>
<a href="#s12">12. Replication Slots</a><br>
<a href="#s13">13. Sequence Exhaustion</a><br>
</div>
<div>
<a href="#s14">14. Tables Without Primary Keys</a><br>
<a href="#s15">15. Unlogged Tables</a><br>
<a href="#s16">16. Configuration Settings</a><br>
<a href="#s17">17. Security &amp; Grants</a><br>
<a href="#s18">18. Lock Contention &amp; Advisory Locks</a><br>
<a href="#s19">19. Data Integrity (Orphans, Dupes, NULLs)</a><br>
<a href="#s20">20. Partitioning Health</a><br>
<a href="#s21">21. Trigger Issues</a><br>
<a href="#s22">22. Role Escalation &amp; Privileges</a><br>
<a href="#s23">23. Foreign Data Wrappers</a><br>
<a href="#s24">24. Materialized Views &amp; pg_stat_statements</a><br>
<a href="#s25">25. Connection Pressure &amp; WAL Archiving</a><br>
<a href="#s26">26. Schema Smells</a><br>
</div>
</div>
</div>
TOC

echo "Running 26 checks..."

###############################################################################
# 1. TABLE BLOAT
###############################################################################
section_start 1 "Table Bloat &amp; Autovacuum"

DEAD_TOTAL=$(sql_count "SELECT COALESCE(SUM(n_dead_tup),0) FROM pg_stat_user_tables WHERE schemaname='public';")
if [ "$DEAD_TOTAL" -gt 10000 ] 2>/dev/null; then
    finding_issue "Dead tuple accumulation: <b>$(echo $DEAD_TOTAL | sed ':a;s/\B[0-9]\{3\}\>/.&/;ta')</b> dead rows across tables"
else
    finding_pass "Dead tuple count acceptable ($DEAD_TOTAL)"
fi

AV_DISABLED=$(sql_count "SELECT count(*) FROM pg_class c JOIN pg_stat_user_tables s ON c.oid=s.relid WHERE s.schemaname='public' AND c.reloptions @> '{autovacuum_enabled=false}';")
if [ "$AV_DISABLED" -gt 0 ] 2>/dev/null; then
    finding_issue "Autovacuum <b>DISABLED</b> on $AV_DISABLED table(s)"
    write_table "SELECT c.relname AS table_name, s.n_dead_tup AS dead_tuples, pg_size_pretty(pg_total_relation_size(c.oid)) AS size FROM pg_class c JOIN pg_stat_user_tables s ON c.oid=s.relid WHERE s.schemaname='public' AND c.reloptions @> '{autovacuum_enabled=false}' ORDER BY s.n_dead_tup DESC;"
else
    finding_pass "Autovacuum enabled on all tables"
fi

write_table "SELECT relname AS table_name, pg_size_pretty(pg_total_relation_size(relid)) AS total_size, n_dead_tup AS dead_tuples, n_live_tup AS live_tuples, CASE WHEN n_live_tup>0 THEN round(100.0*n_dead_tup/n_live_tup,1)||'%' ELSE '0%' END AS dead_pct, COALESCE(last_autovacuum::TEXT,'never') AS last_autovacuum FROM pg_stat_user_tables WHERE schemaname='public' ORDER BY n_dead_tup DESC LIMIT 10;"
section_end

###############################################################################
# 2. INDEX BLOAT
###############################################################################
section_start 2 "Index Bloat"
note "Top indexes by size (large indexes on bloated tables indicate index bloat):"
write_table "SELECT schemaname, tablename, indexname, pg_size_pretty(pg_relation_size(indexrelid)) AS index_size, idx_scan AS times_used FROM pg_stat_user_indexes WHERE schemaname='public' ORDER BY pg_relation_size(indexrelid) DESC LIMIT 10;"
section_end

###############################################################################
# 3. INVALID INDEXES
###############################################################################
section_start 3 "Invalid Indexes"
INVALID=$(sql_count "SELECT count(*) FROM pg_index WHERE NOT indisvalid;")
if [ "$INVALID" -gt 0 ] 2>/dev/null; then
    finding_issue "$INVALID invalid index(es) found — not used by queries"
    write_table "SELECT c.relname AS index_name, t.relname AS table_name, pg_size_pretty(pg_relation_size(c.oid)) AS size FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid WHERE NOT i.indisvalid;"
else
    finding_pass "No invalid indexes"
fi
section_end

###############################################################################
# 4. UNUSED INDEXES
###############################################################################
section_start 4 "Unused Indexes (scan count = 0)"
UNUSED=$(sql_count "SELECT count(*) FROM pg_stat_user_indexes WHERE idx_scan=0 AND schemaname='public' AND indexrelid NOT IN (SELECT indexrelid FROM pg_index WHERE indisprimary OR indisunique);")
if [ "$UNUSED" -gt 3 ] 2>/dev/null; then
    finding_issue "$UNUSED unused non-unique indexes — wasting disk &amp; slowing writes"
    write_table "SELECT tablename, indexname, pg_size_pretty(pg_relation_size(indexrelid)) AS size FROM pg_stat_user_indexes WHERE idx_scan=0 AND schemaname='public' AND indexrelid NOT IN (SELECT indexrelid FROM pg_index WHERE indisprimary OR indisunique) ORDER BY pg_relation_size(indexrelid) DESC;"
else
    finding_pass "Unused index count acceptable ($UNUSED)"
fi
section_end

###############################################################################
# 5. DUPLICATE INDEXES
###############################################################################
section_start 5 "Duplicate / Overlapping Indexes"
DUP=$(sql_count "SELECT count(*) FROM pg_index a JOIN pg_index b ON a.indrelid=b.indrelid AND a.indkey::TEXT=b.indkey::TEXT AND a.indexrelid<b.indexrelid WHERE a.indrelid::regclass::TEXT NOT LIKE 'pg_%';")
if [ "$DUP" -gt 0 ] 2>/dev/null; then
    finding_issue "$DUP exact duplicate index pair(s)"
    write_table "SELECT a.indrelid::regclass AS table_name, a.indexrelid::regclass AS index_1, b.indexrelid::regclass AS index_2, pg_size_pretty(pg_relation_size(b.indexrelid)) AS wasted_size FROM pg_index a JOIN pg_index b ON a.indrelid=b.indrelid AND a.indkey::TEXT=b.indkey::TEXT AND a.indexrelid<b.indexrelid WHERE a.indrelid::regclass::TEXT NOT LIKE 'pg_%';"
else
    finding_pass "No duplicate indexes"
fi

OVERLAP=$(sql_count "SELECT count(*) FROM pg_index a JOIN pg_index b ON a.indrelid=b.indrelid AND a.indexrelid!=b.indexrelid AND a.indkey::TEXT LIKE b.indkey::TEXT||' %' WHERE a.indrelid::regclass::TEXT NOT LIKE 'pg_%';")
if [ "$OVERLAP" -gt 0 ] 2>/dev/null; then
    finding_warn "$OVERLAP overlapping index pair(s)"
    write_table "SELECT a.indrelid::regclass AS table_name, a.indexrelid::regclass AS broader_index, b.indexrelid::regclass AS narrower_index FROM pg_index a JOIN pg_index b ON a.indrelid=b.indrelid AND a.indexrelid!=b.indexrelid AND a.indkey::TEXT LIKE b.indkey::TEXT||' %' WHERE a.indrelid::regclass::TEXT NOT LIKE 'pg_%';"
else
    finding_pass "No overlapping indexes"
fi
section_end

###############################################################################
# 6. MISSING FK INDEXES
###############################################################################
section_start 6 "Missing Foreign Key Indexes"
FK_NOINDEX=$(sql_count "SELECT count(*) FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON tc.constraint_name=kcu.constraint_name WHERE tc.constraint_type='FOREIGN KEY' AND tc.table_schema='public' AND NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid=(tc.table_schema||'.'||tc.table_name)::regclass AND a.attname=kcu.column_name AND i.indkey[0]=a.attnum);")
if [ "$FK_NOINDEX" -gt 0 ] 2>/dev/null; then
    finding_issue "$FK_NOINDEX foreign key(s) without indexes"
    write_table "SELECT tc.table_name AS child_table, kcu.column_name AS fk_column, ccu.table_name AS parent_table FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON tc.constraint_name=kcu.constraint_name JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name=ccu.constraint_name WHERE tc.constraint_type='FOREIGN KEY' AND tc.table_schema='public' AND NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid=(tc.table_schema||'.'||tc.table_name)::regclass AND a.attname=kcu.column_name AND i.indkey[0]=a.attnum);"
else
    finding_pass "All foreign keys have indexes"
fi
section_end

###############################################################################
# 7. WRAPAROUND RISK
###############################################################################
section_start 7 "Wraparound Risk (Transaction ID Age)"
MAX_AGE=$(sql_count "SELECT COALESCE(max(age(relfrozenxid)),0) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND n.nspname='public';")
if [ "$MAX_AGE" -gt 500000000 ] 2>/dev/null; then
    finding_issue "Wraparound risk! Max XID age: <b>$MAX_AGE</b>"
elif [ "$MAX_AGE" -gt 200000000 ] 2>/dev/null; then
    finding_warn "XID age getting high: $MAX_AGE"
else
    finding_pass "XID age acceptable ($MAX_AGE)"
fi

CUSTOM_FREEZE=$(sql_count "SELECT count(*) FROM pg_class WHERE reloptions::TEXT LIKE '%autovacuum_freeze_max_age%' AND relnamespace='public'::regnamespace;")
if [ "$CUSTOM_FREEZE" -gt 0 ] 2>/dev/null; then
    finding_warn "$CUSTOM_FREEZE table(s) with custom freeze thresholds"
fi

write_table "SELECT c.relname AS table_name, age(c.relfrozenxid) AS xid_age, pg_size_pretty(pg_total_relation_size(c.oid)) AS size FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND n.nspname='public' ORDER BY age(c.relfrozenxid) DESC LIMIT 8;"
section_end

###############################################################################
# 8. STALE STATISTICS
###############################################################################
section_start 8 "Stale Statistics"
STALE=$(sql_count "SELECT count(*) FROM pg_stat_user_tables WHERE schemaname='public' AND n_mod_since_analyze > 5000;")
if [ "$STALE" -gt 0 ] 2>/dev/null; then
    finding_issue "$STALE table(s) with stale statistics (&gt;5000 modifications since ANALYZE)"
    write_table "SELECT relname AS table_name, n_live_tup AS live_rows, n_mod_since_analyze AS mods_since_analyze, COALESCE(last_analyze::TEXT,'never') AS last_analyze, COALESCE(last_autoanalyze::TEXT,'never') AS last_autoanalyze FROM pg_stat_user_tables WHERE schemaname='public' AND n_mod_since_analyze>5000 ORDER BY n_mod_since_analyze DESC;"
else
    finding_pass "Statistics up to date"
fi
section_end

###############################################################################
# 9. LONG-RUNNING QUERIES
###############################################################################
section_start 9 "Long-Running Queries (&gt;5 min)"
LONG_Q=$(sql_count "SELECT count(*) FROM pg_stat_activity WHERE state!='idle' AND datname=current_database() AND pid!=pg_backend_pid() AND now()-query_start>interval '5 minutes';")
if [ "$LONG_Q" -gt 0 ] 2>/dev/null; then
    finding_issue "$LONG_Q queries running &gt; 5 minutes"
    write_table "SELECT pid, state, (now()-query_start)::TEXT AS duration, usename, left(query,100) AS query_preview FROM pg_stat_activity WHERE state!='idle' AND datname=current_database() AND pid!=pg_backend_pid() AND now()-query_start>interval '5 minutes' ORDER BY query_start;"
else
    finding_pass "No long-running queries"
fi
section_end

###############################################################################
# 10. IDLE-IN-TRANSACTION
###############################################################################
section_start 10 "Idle-in-Transaction Sessions"
IDLE_TXN=$(sql_count "SELECT count(*) FROM pg_stat_activity WHERE state='idle in transaction' AND datname=current_database();")
if [ "$IDLE_TXN" -gt 0 ] 2>/dev/null; then
    finding_issue "$IDLE_TXN idle-in-transaction session(s)"
    write_table "SELECT pid, usename, (now()-state_change)::TEXT AS idle_duration, left(query,100) AS last_query FROM pg_stat_activity WHERE state='idle in transaction' AND datname=current_database() ORDER BY state_change;"
else
    finding_pass "No idle-in-transaction sessions"
fi
section_end

###############################################################################
# 11. ORPHANED 2PC
###############################################################################
section_start 11 "Orphaned Prepared Transactions (2PC)"
ORPHAN=$(sql_count "SELECT count(*) FROM pg_prepared_xacts;")
if [ "$ORPHAN" -gt 0 ] 2>/dev/null; then
    finding_issue "$ORPHAN orphaned prepared transaction(s)"
    write_table "SELECT gid, prepared::TEXT, owner, database FROM pg_prepared_xacts;"
else
    finding_pass "No orphaned prepared transactions"
fi
section_end

###############################################################################
# 12. REPLICATION SLOTS
###############################################################################
section_start 12 "Replication Slots"
SLOTS=$(sql_count "SELECT count(*) FROM pg_replication_slots WHERE NOT active;")
if [ "$SLOTS" -gt 0 ] 2>/dev/null; then
    finding_issue "$SLOTS inactive replication slot(s) — WAL accumulating!"
    write_table "SELECT slot_name, slot_type, active::TEXT, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained FROM pg_replication_slots ORDER BY active, slot_type;"
else
    finding_pass "No stale replication slots"
fi
section_end

###############################################################################
# 13. SEQUENCES
###############################################################################
section_start 13 "Sequence Exhaustion"
SEQ_RISK=$(sql_count "SELECT count(*) FROM pg_sequences WHERE last_value IS NOT NULL AND max_value>0 AND last_value::FLOAT/max_value::FLOAT > 0.75;")
if [ "$SEQ_RISK" -gt 0 ] 2>/dev/null; then
    finding_issue "$SEQ_RISK sequence(s) at &gt;75% capacity"
    write_table "SELECT schemaname, sequencename, last_value, max_value, round(100.0*last_value/max_value,1) AS pct_used, max_value-last_value AS remaining, CASE WHEN cycle THEN 'YES' ELSE 'NO' END AS can_cycle FROM pg_sequences WHERE last_value IS NOT NULL AND max_value>0 AND last_value::FLOAT/max_value::FLOAT>0.75 ORDER BY last_value::FLOAT/max_value::FLOAT DESC;"
else
    finding_pass "All sequences have sufficient headroom"
fi
section_end

###############################################################################
# 14. NO PRIMARY KEY
###############################################################################
section_start 14 "Tables Without Primary Keys"
NO_PK=$(sql_count "SELECT count(*) FROM information_schema.tables t WHERE t.table_schema='public' AND t.table_type='BASE TABLE' AND NOT EXISTS (SELECT 1 FROM information_schema.table_constraints tc WHERE tc.table_schema=t.table_schema AND tc.table_name=t.table_name AND tc.constraint_type='PRIMARY KEY');")
if [ "$NO_PK" -gt 0 ] 2>/dev/null; then
    finding_issue "$NO_PK table(s) without primary key"
    write_table "SELECT t.table_name, pg_size_pretty(pg_total_relation_size((t.table_schema||'.'||t.table_name)::regclass)) AS size FROM information_schema.tables t WHERE t.table_schema='public' AND t.table_type='BASE TABLE' AND NOT EXISTS (SELECT 1 FROM information_schema.table_constraints tc WHERE tc.table_schema=t.table_schema AND tc.table_name=t.table_name AND tc.constraint_type='PRIMARY KEY') ORDER BY 1;"
else
    finding_pass "All tables have primary keys"
fi
section_end

###############################################################################
# 15. UNLOGGED TABLES
###############################################################################
section_start 15 "Unlogged Tables"
UNLOGGED=$(sql_count "SELECT count(*) FROM pg_class WHERE relpersistence='u' AND relkind='r';")
if [ "$UNLOGGED" -gt 0 ] 2>/dev/null; then
    finding_issue "$UNLOGGED UNLOGGED table(s) — <b>data lost on crash</b>"
    write_table "SELECT c.relname AS table_name, pg_size_pretty(pg_total_relation_size(c.oid)) AS size, s.n_live_tup AS rows FROM pg_class c JOIN pg_stat_user_tables s ON c.oid=s.relid WHERE c.relpersistence='u' AND c.relkind='r' ORDER BY pg_total_relation_size(c.oid) DESC;"
else
    finding_pass "No unlogged tables"
fi
section_end

###############################################################################
# 16. CONFIGURATION
###############################################################################
section_start 16 "Configuration Settings"
BAD_SETTINGS=$(sql_count "SELECT count(*) FROM pg_settings WHERE (name='work_mem' AND setting::INT<=1024) OR (name='maintenance_work_mem' AND setting::INT<=16384) OR (name='random_page_cost' AND setting::FLOAT>=4.0) OR (name='effective_cache_size' AND setting::BIGINT<=131072) OR (name='checkpoint_completion_target' AND setting::FLOAT<0.9) OR (name='default_statistics_target' AND setting::INT<100) OR (name='statement_timeout' AND setting='0') OR (name='idle_in_transaction_session_timeout' AND setting='0') OR (name='log_min_duration_statement' AND setting='-1') OR (name='log_checkpoints' AND setting='off') OR (name='log_connections' AND setting='off') OR (name='log_disconnections' AND setting='off') OR (name='log_lock_waits' AND setting='off') OR (name='log_temp_files' AND setting='-1') OR (name='track_io_timing' AND setting='off');")
if [ "$BAD_SETTINGS" -gt 0 ] 2>/dev/null; then
    finding_issue "$BAD_SETTINGS suboptimal setting(s)"
else
    finding_pass "Configuration looks good"
fi

write_table "SELECT name, setting, unit, CASE WHEN name='work_mem' AND setting::INT<=1024 THEN 'TOO LOW' WHEN name='maintenance_work_mem' AND setting::INT<=16384 THEN 'TOO LOW' WHEN name='random_page_cost' AND setting::FLOAT>=4.0 THEN 'TOO HIGH FOR SSD' WHEN name='effective_cache_size' AND setting::BIGINT<=131072 THEN 'TOO LOW' WHEN name='checkpoint_completion_target' AND setting::FLOAT<0.9 THEN 'SHOULD BE 0.9' WHEN name='default_statistics_target' AND setting::INT<100 THEN 'TOO LOW' WHEN name='statement_timeout' AND setting='0' THEN 'NO TIMEOUT' WHEN name='idle_in_transaction_session_timeout' AND setting='0' THEN 'NO TIMEOUT' WHEN name='log_min_duration_statement' AND setting='-1' THEN 'DISABLED' WHEN name='log_checkpoints' AND setting='off' THEN 'SHOULD BE ON' WHEN name='log_connections' AND setting='off' THEN 'SHOULD BE ON' WHEN name='log_disconnections' AND setting='off' THEN 'SHOULD BE ON' WHEN name='log_lock_waits' AND setting='off' THEN 'SHOULD BE ON' WHEN name='log_temp_files' AND setting='-1' THEN 'SHOULD BE 0' WHEN name='track_io_timing' AND setting='off' THEN 'SHOULD BE ON' ELSE 'OK' END AS status FROM pg_settings WHERE name IN ('work_mem','maintenance_work_mem','random_page_cost','effective_cache_size','checkpoint_completion_target','default_statistics_target','statement_timeout','idle_in_transaction_session_timeout','log_min_duration_statement','log_checkpoints','log_connections','log_disconnections','log_lock_waits','log_temp_files','track_io_timing') ORDER BY name;"
section_end

###############################################################################
# 17. SECURITY
###############################################################################
section_start 17 "Security &amp; Grants"
PUB_GRANTS=$(sql_count "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee='PUBLIC' AND table_schema='public';")
if [ "$PUB_GRANTS" -gt 0 ] 2>/dev/null; then
    finding_issue "$PUB_GRANTS table grant(s) to PUBLIC"
else
    finding_pass "No PUBLIC grants on tables"
fi

SEC_DEF=$(sql_count "SELECT count(*) FROM pg_proc WHERE prosecdef AND pronamespace='public'::regnamespace;")
if [ "$SEC_DEF" -gt 0 ] 2>/dev/null; then
    finding_issue "$SEC_DEF SECURITY DEFINER function(s) in public schema"
    write_table "SELECT proname AS function_name FROM pg_proc WHERE prosecdef AND pronamespace='public'::regnamespace;"
else
    finding_pass "No SECURITY DEFINER functions in public"
fi

note "Login roles:"
write_table "SELECT rolname, rolsuper::TEXT, rolcreaterole::TEXT, rolcreatedb::TEXT, rolcanlogin::TEXT FROM pg_roles WHERE rolcanlogin AND rolname NOT LIKE 'pg_%' ORDER BY rolname;"
section_end

###############################################################################
# 18. LOCKS
###############################################################################
section_start 18 "Lock Contention &amp; Advisory Locks"
BLOCKED=$(sql_count "SELECT count(*) FROM pg_locks WHERE NOT granted;")
if [ "$BLOCKED" -gt 0 ] 2>/dev/null; then
    finding_issue "$BLOCKED blocked lock request(s)"
    write_table "SELECT bl.pid AS blocked_pid, left(ba.query,80) AS blocked_query, bk.pid AS blocking_pid, left(bka.query,80) AS blocking_query FROM pg_locks bl JOIN pg_stat_activity ba ON ba.pid=bl.pid JOIN pg_locks bk ON bk.relation=bl.relation AND bk.granted AND bl.pid!=bk.pid JOIN pg_stat_activity bka ON bka.pid=bk.pid WHERE NOT bl.granted LIMIT 10;"
else
    finding_pass "No lock contention"
fi

ADV=$(sql_count "SELECT count(*) FROM pg_locks WHERE locktype='advisory';")
if [ "$ADV" -gt 0 ] 2>/dev/null; then
    finding_warn "$ADV advisory lock(s) held"
    write_table "SELECT l.pid, l.objid AS lock_id, a.state, left(a.query,80) AS query FROM pg_locks l JOIN pg_stat_activity a ON a.pid=l.pid WHERE l.locktype='advisory';"
else
    finding_pass "No advisory locks"
fi
section_end

###############################################################################
# 19. DATA INTEGRITY
###############################################################################
section_start 19 "Data Integrity"
NOTVALID=$(sql_count "SELECT count(*) FROM pg_constraint WHERE NOT convalidated AND connamespace='public'::regnamespace;")
if [ "$NOTVALID" -gt 0 ] 2>/dev/null; then
    finding_issue "$NOTVALID NOT VALID constraint(s) — existing bad data not checked"
    write_table "SELECT conname AS constraint_name, conrelid::regclass AS table_name, pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE NOT convalidated AND connamespace='public'::regnamespace;"
else
    finding_pass "All constraints validated"
fi

DUP_EMAIL=$(sql_count "SELECT count(*) FROM (SELECT email FROM customers WHERE email IS NOT NULL GROUP BY email HAVING count(*)>1) x;")
if [ "$DUP_EMAIL" -gt 0 ] 2>/dev/null; then
    finding_issue "$DUP_EMAIL duplicate email(s) in customers"
else
    finding_pass "No duplicate emails"
fi

NULL_ORD=$(sql_count "SELECT count(*) FROM orders WHERE total_amount IS NULL OR customer_id IS NULL;")
if [ "$NULL_ORD" -gt 0 ] 2>/dev/null; then
    finding_issue "$NULL_ORD order(s) with NULL customer_id or total_amount"
fi

NULL_PAY=$(sql_count "SELECT count(*) FROM payments WHERE amount IS NULL OR amount<0;")
if [ "$NULL_PAY" -gt 0 ] 2>/dev/null; then
    finding_issue "$NULL_PAY payment(s) with NULL or negative amount"
fi

NEG_RATE=$(sql_count "SELECT count(*) FROM user_feedback WHERE rating<0;" 2>/dev/null)
if [ "${NEG_RATE:-0}" -gt 0 ] 2>/dev/null; then
    finding_warn "$NEG_RATE feedback row(s) with negative ratings"
fi
section_end

###############################################################################
# 20. PARTITIONING
###############################################################################
section_start 20 "Partitioning Health"
PART_EXISTS=$(sql_count "SELECT count(*) FROM pg_partitioned_table;" 2>/dev/null)
if [ "${PART_EXISTS:-0}" -gt 0 ] 2>/dev/null; then
    DEFAULT_ROWS=$(sql_count "SELECT count(*) FROM sales_log_default;" 2>/dev/null)
    if [ "${DEFAULT_ROWS:-0}" -gt 0 ] 2>/dev/null; then
        finding_issue "$DEFAULT_ROWS rows in DEFAULT partition — missing partition definitions"
    else
        finding_pass "Partitioning healthy"
    fi
    EMPTY_P=$(sql_count "SELECT count(*) FROM pg_inherits i JOIN pg_stat_user_tables s ON s.relid=i.inhrelid WHERE i.inhparent='sales_log'::regclass AND s.n_live_tup=0;" 2>/dev/null)
    if [ "${EMPTY_P:-0}" -gt 0 ] 2>/dev/null; then
        finding_warn "$EMPTY_P empty partition(s)"
    fi
    write_table "SELECT inhrelid::regclass AS partition, pg_size_pretty(pg_total_relation_size(inhrelid)) AS size, (SELECT n_live_tup FROM pg_stat_user_tables WHERE relid=inhrelid) AS rows FROM pg_inherits WHERE inhparent='sales_log'::regclass ORDER BY inhrelid::regclass::TEXT;" 2>/dev/null
else
    note "No partitioned tables found."
fi
section_end

###############################################################################
# 21. TRIGGERS
###############################################################################
section_start 21 "Trigger Issues"
DIS_TRG=$(sql_count "SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE NOT t.tgenabled='O' AND c.relnamespace='public'::regnamespace AND NOT t.tgisinternal;")
if [ "$DIS_TRG" -gt 0 ] 2>/dev/null; then
    finding_issue "$DIS_TRG disabled trigger(s)"
    write_table "SELECT c.relname AS table_name, t.tgname AS trigger_name, CASE t.tgenabled WHEN 'D' THEN 'DISABLED' WHEN 'R' THEN 'REPLICA' WHEN 'A' THEN 'ALWAYS' ELSE t.tgenabled::TEXT END AS status FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE NOT t.tgenabled='O' AND c.relnamespace='public'::regnamespace AND NOT t.tgisinternal;"
else
    finding_pass "All triggers enabled"
fi

SILENT=$(sql_count "SELECT count(*) FROM pg_proc WHERE prosrc LIKE '%EXCEPTION WHEN OTHERS THEN%' AND prosrc LIKE '%NULL;%' AND pronamespace='public'::regnamespace;")
if [ "${SILENT:-0}" -gt 0 ] 2>/dev/null; then
    finding_warn "$SILENT function(s) silently swallowing errors"
fi
section_end

###############################################################################
# 22. ROLE ESCALATION
###############################################################################
section_start 22 "Role Escalation &amp; Privileges"
POWERFUL=$(sql_count "SELECT count(*) FROM pg_roles WHERE (rolcreaterole OR rolcreatedb) AND rolcanlogin AND NOT rolsuper AND rolname NOT LIKE 'pg_%';")
if [ "$POWERFUL" -gt 0 ] 2>/dev/null; then
    finding_issue "$POWERFUL non-superuser role(s) with CREATEROLE/CREATEDB"
    write_table "SELECT rolname, rolcreaterole::TEXT, rolcreatedb::TEXT FROM pg_roles WHERE (rolcreaterole OR rolcreatedb) AND rolcanlogin AND NOT rolsuper AND rolname NOT LIKE 'pg_%';"
fi

MEMBERSHIPS=$(sql_count "SELECT count(*) FROM pg_auth_members;")
if [ "$MEMBERSHIPS" -gt 3 ] 2>/dev/null; then
    finding_warn "Complex role membership ($MEMBERSHIPS grants) — check for escalation chains"
    write_table "SELECT m.rolname AS member, r.rolname AS member_of FROM pg_auth_members am JOIN pg_roles r ON r.oid=am.roleid JOIN pg_roles m ON m.oid=am.member ORDER BY m.rolname;"
else
    finding_pass "Role memberships look simple"
fi

DB_SP=$(sql "SELECT setconfig FROM pg_db_role_setting WHERE setdatabase=(SELECT oid FROM pg_database WHERE datname=current_database()) AND setrole=0;" 2>/dev/null)
if echo "$DB_SP" | grep -q 'public.*pg_catalog' 2>/dev/null; then
    finding_issue "search_path: public before pg_catalog — function shadowing risk"
else
    finding_pass "search_path safe"
fi
section_end

###############################################################################
# 23. FDW
###############################################################################
section_start 23 "Foreign Data Wrappers"
FDW_C=$(sql_count "SELECT count(*) FROM pg_foreign_server;")
if [ "$FDW_C" -gt 0 ] 2>/dev/null; then
    finding_warn "$FDW_C foreign server(s) configured"
    write_table "SELECT srvname, fdwname, srvoptions::TEXT FROM pg_foreign_server fs JOIN pg_foreign_data_wrapper fdw ON fdw.oid=fs.srvfdw;"

    HC=$(sql_count "SELECT count(*) FROM pg_user_mappings WHERE umoptions::TEXT LIKE '%password%';")
    if [ "$HC" -gt 0 ] 2>/dev/null; then
        finding_issue "$HC FDW user mapping(s) with hardcoded passwords!"
    fi
else
    finding_pass "No foreign data wrappers"
fi
section_end

###############################################################################
# 24. MAT VIEWS & PGSS
###############################################################################
section_start 24 "Materialized Views &amp; pg_stat_statements"
MV_C=$(sql_count "SELECT count(*) FROM pg_matviews WHERE schemaname='public';")
if [ "$MV_C" -gt 0 ] 2>/dev/null; then
    finding_warn "$MV_C materialized view(s) — verify refresh schedule"
    write_table "SELECT matviewname, pg_size_pretty(pg_total_relation_size(('public.'||matviewname)::regclass)) AS size FROM pg_matviews WHERE schemaname='public';"
else
    finding_pass "No materialized views"
fi

PGSS=$(sql_count "SELECT count(*) FROM pg_stat_statements;" 2>/dev/null)
if [ "${PGSS:-0}" -gt 2000 ] 2>/dev/null; then
    finding_warn "pg_stat_statements: $PGSS entries (possibly polluted)"
else
    finding_pass "pg_stat_statements: ${PGSS:-N/A} entries"
fi
section_end

###############################################################################
# 25. CONNECTIONS & WAL
###############################################################################
section_start 25 "Connection Pressure &amp; WAL Archiving"
CONN_PCT=$((CONN_TOTAL * 100 / MAX_CONN))
if [ "$CONN_PCT" -gt 80 ] 2>/dev/null; then
    finding_issue "Connections at ${CONN_PCT}% ($CONN_TOTAL/$MAX_CONN)"
elif [ "$CONN_PCT" -gt 50 ] 2>/dev/null; then
    finding_warn "Connections at ${CONN_PCT}% ($CONN_TOTAL/$MAX_CONN)"
else
    finding_pass "Connections at ${CONN_PCT}% ($CONN_TOTAL/$MAX_CONN)"
fi

ARCH=$(sql "SHOW archive_command;")
if echo "$ARCH" | grep -q 'nonexistent\|/dev/null\|false' 2>/dev/null; then
    finding_issue "archive_command broken: $ARCH"
else
    finding_pass "archive_command: ${ARCH:-(disabled)}"
fi
section_end

###############################################################################
# 26. SCHEMA SMELLS
###############################################################################
section_start 26 "Schema Smells"
RESERVED=$(sql_count "SELECT count(*) FROM pg_class WHERE relkind='r' AND relnamespace='public'::regnamespace AND relname IN ('order','user','select','table','group','date','column','index','constraint','check','primary','foreign','key','grant','revoke');")
if [ "$RESERVED" -gt 0 ] 2>/dev/null; then
    finding_warn "$RESERVED table(s) using SQL reserved words"
    write_table "SELECT relname AS table_name FROM pg_class WHERE relkind='r' AND relnamespace='public'::regnamespace AND relname IN ('order','user','select','table','group','date','column','index','constraint','check','primary','foreign','key','grant','revoke');"
else
    finding_pass "No reserved-word table names"
fi

WIDE=$(sql_count "SELECT count(*) FROM (SELECT relname FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped GROUP BY relname HAVING count(*)>20) x;")
if [ "$WIDE" -gt 0 ] 2>/dev/null; then
    finding_warn "$WIDE table(s) with &gt;20 columns"
    write_table "SELECT c.relname, count(*) AS column_count FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped GROUP BY c.relname HAVING count(*)>20 ORDER BY count(*) DESC;"
fi

CIRC=$(sql_count "SELECT count(*) FROM pg_constraint c1 JOIN pg_constraint c2 ON c1.confrelid=c2.conrelid AND c2.confrelid=c1.conrelid WHERE c1.contype='f' AND c2.contype='f' AND c1.oid<c2.oid AND c1.connamespace='public'::regnamespace;")
if [ "$CIRC" -gt 0 ] 2>/dev/null; then
    finding_warn "$CIRC circular FK dependency pair(s)"
else
    finding_pass "No circular FKs"
fi
section_end

###############################################################################
# SCORECARD — inject at placeholder
###############################################################################
TOTAL=$((ISSUES + WARNINGS + PASSED))
if [ "$TOTAL" -gt 0 ]; then
    HEALTH_PCT=$(( (PASSED * 100) / TOTAL ))
else
    HEALTH_PCT=100
fi

if [ "$ISSUES" -ge 15 ]; then
    RATING="CRITICAL"; RATING_CLASS="rating-critical"
elif [ "$ISSUES" -ge 8 ]; then
    RATING="POOR"; RATING_CLASS="rating-poor"
elif [ "$ISSUES" -ge 3 ]; then
    RATING="FAIR"; RATING_CLASS="rating-fair"
else
    RATING="GOOD"; RATING_CLASS="rating-good"
fi

SCORECARD_HTML="<div class='scorecard'><div class='rating $RATING_CLASS'>HEALTH RATING: $RATING ($HEALTH_PCT% checks passed)</div><div class='counts'><span class='badge badge-issue'>ISSUES: $ISSUES</span> <span class='badge badge-warning'>WARNINGS: $WARNINGS</span> <span class='badge badge-pass'>PASSED: $PASSED</span> <span>TOTAL CHECKS: $TOTAL</span></div></div>"

# Replace placeholder
sed -i "s|<!-- SCORECARD_PLACEHOLDER -->|$SCORECARD_HTML|" "$REPORT"

###############################################################################
# FOOTER
###############################################################################
cat >> "$REPORT" <<EOF
<div class="footer">
PostgreSQL Health Check Report &mdash; Generated $(date) &mdash; $DB @ $HOST:$PORT &mdash; Tag: ${TAG:-none}<br>
Issues: $ISSUES | Warnings: $WARNINGS | Passed: $PASSED | Total: $TOTAL | Rating: $RATING
</div>
</body>
</html>
EOF

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "  ✅ HTML Report: $REPORT"
echo "  ❌ Issues: $ISSUES  |  ⚠️  Warnings: $WARNINGS  |  ✅ Passed: $PASSED"
echo "  Rating: $RATING ($HEALTH_PCT%)"
echo ""
echo "  Open:  xdg-open $REPORT  (Linux)"
echo "         open $REPORT       (Mac)"
echo "╚══════════════════════════════════════════════════════════╝"

# Auto-open if possible
if command -v xdg-open &>/dev/null; then
    xdg-open "$REPORT" 2>/dev/null &
elif command -v open &>/dev/null; then
    open "$REPORT" 2>/dev/null &
fi
