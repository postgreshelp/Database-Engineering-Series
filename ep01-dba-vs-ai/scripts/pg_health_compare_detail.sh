#!/bin/bash
###############################################################################
# pg_health_compare.sh v2 — Detailed Before vs After with DBA analysis
#
# Usage: ./pg_health_compare.sh <before_report.html> <after_report.html>
###############################################################################

set -uo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <before_report.html> <after_report.html>"
    exit 1
fi

BEFORE="$1"; AFTER="$2"
OUTPUT="pg_health_comparison_$(date +%Y%m%d_%H%M%S).html"

if [ ! -f "$BEFORE" ]; then echo "ERROR: $BEFORE not found"; exit 1; fi
if [ ! -f "$AFTER" ]; then echo "ERROR: $AFTER not found"; exit 1; fi

extract_count() { grep -oP "${2}: \K[0-9]+" "$1" 2>/dev/null | tail -1 || echo "0"; }
extract_rating() { grep -oP 'HEALTH RATING: \K[A-Z]+' "$1" 2>/dev/null | head -1 || echo "UNKNOWN"; }
rating_class() { case "$1" in CRITICAL) echo "rating-critical";; POOR) echo "rating-poor";; FAIR) echo "rating-fair";; GOOD) echo "rating-good";; *) echo "rating-unknown";; esac; }

B_ISSUES=$(extract_count "$BEFORE" "ISSUES"); B_WARNINGS=$(extract_count "$BEFORE" "WARNINGS")
B_PASSED=$(extract_count "$BEFORE" "PASSED"); B_TOTAL=$(extract_count "$BEFORE" "TOTAL CHECKS")
B_RATING=$(extract_rating "$BEFORE")
A_ISSUES=$(extract_count "$AFTER" "ISSUES"); A_WARNINGS=$(extract_count "$AFTER" "WARNINGS")
A_PASSED=$(extract_count "$AFTER" "PASSED"); A_TOTAL=$(extract_count "$AFTER" "TOTAL CHECKS")
A_RATING=$(extract_rating "$AFTER")
FIXED=$((B_ISSUES - A_ISSUES)); [ "$FIXED" -lt 0 ] && FIXED=0

echo "Generating detailed comparison..."

cat > "$OUTPUT" <<'CSS'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PostgreSQL Health — Detailed Comparison</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:"Courier New",Courier,monospace;font-size:13px;color:#1a1a1a;background:#fff;padding:20px 30px;max-width:1400px;margin:0 auto}
.report-header{border:2px solid #333;padding:12px 16px;margin-bottom:20px;background:#f5f5f5;text-align:center}
.report-header h1{font-size:16px;letter-spacing:1px;margin-bottom:4px}
.report-header .sub{font-size:12px;color:#666}
.compare-grid{display:grid;grid-template-columns:1fr 80px 1fr;gap:0;margin-bottom:20px;border:2px solid #333}
.compare-col{padding:12px 16px}
.compare-col.before{background:#fff5f5;border-right:1px solid #ccc}
.compare-col.arrow{display:flex;align-items:center;justify-content:center;background:#f0f0f0;font-size:28px;font-weight:bold;color:#666;border-right:1px solid #ccc}
.compare-col.after{background:#f5fff5}
.compare-col h2{font-size:14px;margin-bottom:8px;text-align:center}
.metric-row{display:flex;justify-content:space-between;padding:3px 0;font-size:13px}
.metric-label{color:#666}.metric-value{font-weight:bold}
.rating-box{text-align:center;padding:6px;margin:6px 0;font-weight:bold;font-size:14px;border:1px solid}
.rating-critical{background:#ffcccc;border-color:#cc0000;color:#cc0000}
.rating-poor{background:#ffe0cc;border-color:#cc6600;color:#cc6600}
.rating-fair{background:#ffffcc;border-color:#999900;color:#999900}
.rating-good{background:#ccffcc;border-color:#006600;color:#006600}
.rating-unknown{background:#eee;border-color:#999;color:#999}
.summary-banner{border:2px solid #333;padding:12px 16px;margin-bottom:20px;text-align:center}
.summary-stats{display:flex;justify-content:center;gap:40px;margin-top:8px}
.summary-stat{text-align:center}
.summary-stat .num{font-size:24px;font-weight:bold}
.summary-stat .lbl{font-size:11px;color:#666}
.fixed-color{color:#006600}.remaining-color{color:#cc6600}
.section-card{border:1px solid #bbb;margin-bottom:10px}
.section-card-header{display:flex;justify-content:space-between;align-items:center;padding:6px 12px;cursor:pointer;user-select:none}
.section-card-header:hover{filter:brightness(0.95)}
.section-title{font-weight:bold;font-size:13px}
.card-fixed .section-card-header{background:#d4edda}
.card-improved .section-card-header{background:#e8f5e9}
.card-remains .section-card-header{background:#fff3cd}
.card-same .section-card-header{background:#f0f0f0}
.card-clean .section-card-header{background:#eaf7ec}
.card-new-issue .section-card-header{background:#ffcccc}
.section-detail{display:none;border-top:1px solid #ddd}
.section-detail.open{display:block}
.detail-grid{display:grid;grid-template-columns:1fr 1fr}
.detail-col{padding:10px 12px;font-size:12px}
.detail-col.before-col{background:#fffafa;border-right:1px solid #ddd}
.detail-col.after-col{background:#fafffa}
.detail-col h4{font-size:11px;color:#666;margin-bottom:6px;text-transform:uppercase;letter-spacing:1px}
.finding{margin:4px 0;padding:3px 6px;font-size:12px}
.finding-issue{background:#fff3cd;border-left:3px solid #cc9900}
.finding-warning{background:#fff5e6;border-left:3px solid #cc6600}
.finding-pass{background:#eaf7ec;border-left:3px solid #339933}
.dba-analysis{background:#f0f4ff;border:1px solid #99b3e6;border-left:4px solid #3366cc;padding:8px 12px;font-size:12px}
.dba-analysis .dba-title{font-weight:bold;color:#3366cc;font-size:11px;text-transform:uppercase;letter-spacing:.5px;margin-bottom:4px}
.dba-analysis ul{margin:4px 0 4px 16px}.dba-analysis li{margin:2px 0}
.badge{display:inline-block;padding:1px 6px;font-size:10px;font-weight:bold;font-family:"Courier New",monospace}
.badge-fixed{background:#d4edda;border:1px solid #339933;color:#1a4d1a}
.badge-improved{background:#e8f5e9;border:1px solid #66bb6a;color:#2e7d32}
.badge-remaining{background:#fff3cd;border:1px solid #cc9900;color:#664d00}
.badge-new{background:#ffcccc;border:1px solid #cc0000;color:#660000}
.badge-pass{background:#e8e8e8;border:1px solid #999;color:#666}
.badge-clean{background:#d4edda;border:1px solid #339933;color:#1a4d1a}
.toggle-arrow{font-size:14px;margin-right:6px;transition:transform .2s;display:inline-block}
.toggle-arrow.open{transform:rotate(90deg)}
.footer{margin-top:30px;padding-top:8px;border-top:2px solid #333;font-size:11px;color:#666;text-align:center}
.controls{margin-bottom:12px;text-align:right}
.controls button{font-family:"Courier New",monospace;font-size:11px;padding:3px 10px;cursor:pointer;border:1px solid #999;background:#f0f0f0;margin-left:4px}
.controls button:hover{background:#e0e0e0}
@media print{.section-detail{display:block!important}.toggle-arrow{display:none}body{font-size:11px}}
</style>
</head>
<body>
CSS

# Header + Scorecard
cat >> "$OUTPUT" <<EOF
<div class="report-header">
  <h1>POSTGRESQL HEALTH CHECK — DETAILED COMPARISON</h1>
  <div class="sub">Before: $(basename "$BEFORE") | After: $(basename "$AFTER") | $(date)</div>
</div>
<div class="compare-grid">
  <div class="compare-col before"><h2>BEFORE</h2>
    <div class="rating-box $(rating_class $B_RATING)">$B_RATING</div>
    <div class="metric-row"><span class="metric-label">Issues:</span><span class="metric-value" style="color:#cc0000">$B_ISSUES</span></div>
    <div class="metric-row"><span class="metric-label">Warnings:</span><span class="metric-value" style="color:#cc6600">$B_WARNINGS</span></div>
    <div class="metric-row"><span class="metric-label">Passed:</span><span class="metric-value" style="color:#006600">$B_PASSED</span></div>
    <div class="metric-row"><span class="metric-label">Total:</span><span class="metric-value">$B_TOTAL</span></div>
  </div>
  <div class="compare-col arrow">→</div>
  <div class="compare-col after"><h2>AFTER</h2>
    <div class="rating-box $(rating_class $A_RATING)">$A_RATING</div>
    <div class="metric-row"><span class="metric-label">Issues:</span><span class="metric-value" style="color:#cc0000">$A_ISSUES</span></div>
    <div class="metric-row"><span class="metric-label">Warnings:</span><span class="metric-value" style="color:#cc6600">$A_WARNINGS</span></div>
    <div class="metric-row"><span class="metric-label">Passed:</span><span class="metric-value" style="color:#006600">$A_PASSED</span></div>
    <div class="metric-row"><span class="metric-label">Total:</span><span class="metric-value">$A_TOTAL</span></div>
  </div>
</div>
<div class="summary-banner"><div class="summary-stats">
  <div class="summary-stat"><div class="num fixed-color">$FIXED</div><div class="lbl">ISSUES FIXED</div></div>
  <div class="summary-stat"><div class="num remaining-color">$A_ISSUES</div><div class="lbl">REMAINING</div></div>
  <div class="summary-stat"><div class="num">${B_ISSUES} → ${A_ISSUES}</div><div class="lbl">ISSUES</div></div>
  <div class="summary-stat"><div class="num">${B_WARNINGS} → ${A_WARNINGS}</div><div class="lbl">WARNINGS</div></div>
</div></div>
<div class="controls">
  <button onclick="toggleAll(true)">▼ Expand All</button>
  <button onclick="toggleAll(false)">▲ Collapse All</button>
  <button onclick="showOnly('card-remains');showOnly('card-improved');">▼ Unresolved Only</button>
</div>
EOF

###############################################################################
# DBA ANALYSIS NOTES
###############################################################################
declare -A DBA_NOTES

DBA_NOTES[1]='<ul>
<li><b>Autovacuum re-enable:</b> AI may fear overriding intentional per-table tuning. autovacuum should almost always be enabled.</li>
<li><b>Dead tuples:</b> VACUUM removes dead tuples but physical disk space is only reclaimed by VACUUM FULL (requires exclusive lock).</li>
</ul>'

DBA_NOTES[4]='<ul>
<li><b>Why AI is cautious:</b> An index with idx_scan=0 might be used by a monthly batch job that hasnt run since the last stats reset. AI sees zero usage and hesitates.</li>
<li><b>Production practice:</b> A DBA would monitor idx_scan for 30+ days before dropping. For a test database, all zero-scan non-unique indexes are safe to drop.</li>
</ul>'

DBA_NOTES[6]='<ul>
<li><b>Small tables:</b> AI may skip FK indexes on small lookup tables where a seq scan is faster than an index scan. However, the index is still needed for efficient DELETE cascades on the parent.</li>
</ul>'

DBA_NOTES[12]='<ul>
<li><b>Why AI wont drop slots:</b> Dropping a replication slot is irreversible. If the standby is temporarily down (maintenance, network issue), dropping its slot forces a full pg_basebackup rebuild — hours of downtime.</li>
<li><b>The risk of NOT dropping:</b> Each inactive slot prevents WAL cleanup. This is the #1 cause of "disk full" production emergencies. WAL files grow until pg_wal fills the disk and PostgreSQL shuts down.</li>
<li><b>What a DBA does:</b> Verify the standby is truly decommissioned (check pg_stat_replication, ask the team), THEN drop. AI cant make that call without context.</li>
</ul>'

DBA_NOTES[14]='<ul>
<li><b>Design decision, not mechanical fix:</b> Adding a PK requires choosing the right column. Should event_log use a new SERIAL, or is (event_type, created_at) a natural key? AI cant know the data model intent.</li>
<li><b>Lock impact:</b> Adding a PK acquires ACCESS EXCLUSIVE lock and scans the entire table for uniqueness. On a large table this blocks all queries.</li>
</ul>'

DBA_NOTES[15]='<ul>
<li><b>ALTER TABLE SET LOGGED:</b> This rewrites the entire table to generate WAL for all existing rows. For a 10GB table, this means 10GB+ of WAL generation and an exclusive lock for the duration.</li>
<li><b>Why AI hesitates:</b> If the table was made UNLOGGED deliberately for performance (bulk loading, temp staging), converting it to LOGGED could slow down the workload it was designed for.</li>
</ul>'

DBA_NOTES[16]='<ul>
<li><b>Restart-only parameters:</b> Settings like shared_buffers, max_connections, wal_level, max_worker_processes require a PostgreSQL restart. AI typically doesnt have systemctl/pg_ctl access.</li>
<li><b>ALTER SYSTEM vs reality:</b> ALTER SYSTEM writes to postgresql.auto.conf, but the change only takes effect after reload (for runtime params) or restart (for postmaster params). AI may "fix" a setting that doesnt actually apply until restart.</li>
<li><b>Session-level settings:</b> statement_timeout and idle_in_transaction_session_timeout only apply to NEW connections. Existing sessions keep the old value.</li>
</ul>'

DBA_NOTES[17]='<ul>
<li><b>REVOKE from PUBLIC:</b> This can instantly break every application that connects without explicit grants. AI needs to know the app connection role to grant back specific permissions.</li>
<li><b>SECURITY DEFINER functions:</b> Dropping a function used by triggers, views, or application code causes immediate cascading failures. AI flags it but wont drop without dependency analysis.</li>
<li><b>Weak passwords:</b> PostgreSQL stores password hashes (scram-sha-256), not plaintext. AI literally cannot check password strength — it can only flag suspicious role names like "app_admin" or "readonly_user".</li>
</ul>'

DBA_NOTES[19]='<ul>
<li><b>NOT VALID constraints:</b> VALIDATE CONSTRAINT does a full table scan and fails if ANY row violates the constraint. AI must first identify and fix ALL bad data, then validate. Multi-step process it may not complete.</li>
<li><b>Orphaned rows:</b> Should orphaned order_items be deleted, reassigned to a "deleted_orders" parent, or archived? This is a business decision AI cant make.</li>
<li><b>NULL in financial columns:</b> Setting NULL total_amount to 0 changes business meaning (free order vs unknown amount). A DBA would escalate this to the application team.</li>
</ul>'

DBA_NOTES[20]='<ul>
<li><b>Missing partitions:</b> AI needs to know the partitioning granularity (monthly? weekly? daily?) and how far ahead to create. Creating wrong-sized partitions causes uneven data distribution.</li>
<li><b>Moving data from DEFAULT:</b> Requires: (1) CREATE the correct partition, (2) detach DEFAULT, (3) INSERT rows that belong in the new partition, (4) DELETE from DEFAULT, (5) re-attach DEFAULT. Complex, error-prone, and requires careful locking.</li>
</ul>'

DBA_NOTES[21]='<ul>
<li><b>Disabled triggers:</b> Someone disabled it for a reason — bulk data load, debugging, performance issue. Re-enabling without knowing why can cause cascade failures or massive audit log growth.</li>
<li><b>Silent-fail triggers:</b> The EXCEPTION WHEN OTHERS THEN NULL pattern exists because the trigger was crashing on certain rows. Removing it makes the trigger fail loudly on every affected row.</li>
</ul>'

DBA_NOTES[22]='<ul>
<li><b>Role inheritance chains:</b> Revoking role memberships mid-day locks out users immediately. In production, a DBA schedules this during a maintenance window after confirming with team leads.</li>
<li><b>CREATEROLE privilege:</b> Some service accounts need CREATEROLE for provisioning (CI/CD, test automation). Revoking breaks the pipeline.</li>
<li><b>search_path:</b> Changing database-level search_path affects ALL sessions instantly. Apps relying on public schema resolution break with "relation not found" errors.</li>
</ul>'

DBA_NOTES[23]='<ul>
<li><b>FDW hardcoded passwords:</b> Removing the user mapping breaks all foreign table queries. AI needs to know if the foreign tables are actively used before dropping credentials.</li>
<li><b>Dead remote server:</b> The server might be temporarily unreachable (maintenance window, network blip). Dropping the FDW config means reconfiguring from scratch including credentials.</li>
</ul>'

DBA_NOTES[24]='<ul>
<li><b>pg_stat_statements_reset():</b> Clears ALL historical query performance data — not just the polluted entries. AI avoids it to preserve legitimate slow query analysis.</li>
<li><b>Materialized views:</b> REFRESH takes a lock and can be slow. CONCURRENTLY avoids the lock but requires a UNIQUE index on the materialized view.</li>
</ul>'

DBA_NOTES[26]='<ul>
<li><b>Reserved word table names:</b> Renaming requires updating every query, view, function, trigger, and application reference. This is a full application migration, not a DBA fix.</li>
<li><b>Wide tables / circular FKs:</b> These are architecture decisions requiring developer input and potentially weeks of refactoring. AI rightly flags them as warnings, not auto-fixable issues.</li>
</ul>'

###############################################################################
# SECTION CARDS
###############################################################################
SECTIONS=(
    "1|Table Bloat & Autovacuum"      "2|Index Bloat"
    "3|Invalid Indexes"                "4|Unused Indexes"
    "5|Duplicate / Overlapping Indexes" "6|Missing FK Indexes"
    "7|Wraparound Risk"                "8|Stale Statistics"
    "9|Long-Running Queries"           "10|Idle-in-Transaction Sessions"
    "11|Orphaned Prepared Transactions" "12|Replication Slots"
    "13|Sequence Exhaustion"           "14|Tables Without Primary Keys"
    "15|Unlogged Tables"               "16|Configuration Settings"
    "17|Security & Grants"             "18|Lock Contention & Advisory Locks"
    "19|Data Integrity"                "20|Partitioning Health"
    "21|Trigger Issues"                "22|Role Escalation & Privileges"
    "23|Foreign Data Wrappers"         "24|Materialized Views & pg_stat_statements"
    "25|Connection Pressure & WAL Archiving" "26|Schema Smells"
)

for entry in "${SECTIONS[@]}"; do
    NUM="${entry%%|*}"; NAME="${entry##*|}"

    # Extract section content
    if [ "$NUM" -eq 26 ]; then
        B_SEC=$(sed -n "/id='s${NUM}'/,/<div class='footer'>/p" "$BEFORE" 2>/dev/null)
        A_SEC=$(sed -n "/id='s${NUM}'/,/<div class='footer'>/p" "$AFTER" 2>/dev/null)
    else
        B_SEC=$(sed -n "/id='s${NUM}'/,/id='s$((NUM+1))'/p" "$BEFORE" 2>/dev/null)
        A_SEC=$(sed -n "/id='s${NUM}'/,/id='s$((NUM+1))'/p" "$AFTER" 2>/dev/null)
    fi

    B_IC=$(echo "$B_SEC" | grep -c "badge-issue" 2>/dev/null || echo 0)
    A_IC=$(echo "$A_SEC" | grep -c "badge-issue" 2>/dev/null || echo 0)
    B_WC=$(echo "$B_SEC" | grep -c "badge-warning" 2>/dev/null || echo 0)
    A_WC=$(echo "$A_SEC" | grep -c "badge-warning" 2>/dev/null || echo 0)

    # Finding text extraction
    B_IT=$(echo "$B_SEC" | grep -oP "badge-issue'>ISSUE</span>\s*\K[^<]+" 2>/dev/null || true)
    B_WT=$(echo "$B_SEC" | grep -oP "badge-warning'>WARNING</span>\s*\K[^<]+" 2>/dev/null || true)
    B_PT=$(echo "$B_SEC" | grep -oP "badge-pass'>PASS</span>\s*\K[^<]+" 2>/dev/null || true)
    A_IT=$(echo "$A_SEC" | grep -oP "badge-issue'>ISSUE</span>\s*\K[^<]+" 2>/dev/null || true)
    A_WT=$(echo "$A_SEC" | grep -oP "badge-warning'>WARNING</span>\s*\K[^<]+" 2>/dev/null || true)
    A_PT=$(echo "$A_SEC" | grep -oP "badge-pass'>PASS</span>\s*\K[^<]+" 2>/dev/null || true)

    # Determine verdict
    SHOW_DBA=0
    if [ "$B_IC" -gt 0 ] && [ "$A_IC" -eq 0 ] && [ "$A_WC" -eq 0 ]; then
        CC="card-fixed"; V="<span class='badge badge-fixed'>✓ FIXED</span>"
    elif [ "$B_IC" -gt 0 ] && [ "$A_IC" -eq 0 ] && [ "$A_WC" -gt 0 ]; then
        CC="card-improved"; V="<span class='badge badge-improved'>↓ IMPROVED</span>"; SHOW_DBA=1
    elif [ "$B_IC" -eq 0 ] && [ "$A_IC" -gt 0 ]; then
        CC="card-new-issue"; V="<span class='badge badge-new'>✗ NEW</span>"
    elif [ "$B_IC" -gt 0 ] && [ "$A_IC" -gt 0 ] && [ "$A_IC" -lt "$B_IC" ]; then
        CC="card-improved"; V="<span class='badge badge-improved'>↓ IMPROVED</span>"; SHOW_DBA=1
    elif [ "$B_IC" -gt 0 ] && [ "$A_IC" -gt 0 ]; then
        CC="card-remains"; V="<span class='badge badge-remaining'>— REMAINS</span>"; SHOW_DBA=1
    elif [ "$B_WC" -gt 0 ] && [ "$A_WC" -eq 0 ]; then
        CC="card-fixed"; V="<span class='badge badge-fixed'>✓ FIXED</span>"
    elif [ "$B_WC" -gt 0 ] && [ "$A_WC" -gt 0 ]; then
        CC="card-same"; V="<span class='badge badge-pass'>— SAME</span>"; SHOW_DBA=1
    else
        CC="card-clean"; V="<span class='badge badge-clean'>✓ CLEAN</span>"
    fi

    # Status labels
    [ "$B_IC" -gt 0 ] && BL="ISSUE ($B_IC)" || { [ "$B_WC" -gt 0 ] && BL="WARN ($B_WC)" || BL="PASS"; }
    [ "$A_IC" -gt 0 ] && AL="ISSUE ($A_IC)" || { [ "$A_WC" -gt 0 ] && AL="WARN ($A_WC)" || AL="PASS"; }

    # Build before findings HTML
    BF=""
    while IFS= read -r l; do [ -n "$l" ] && BF+="<div class='finding finding-issue'>❌ $l</div>"; done <<< "$B_IT"
    while IFS= read -r l; do [ -n "$l" ] && BF+="<div class='finding finding-warning'>⚠️ $l</div>"; done <<< "$B_WT"
    while IFS= read -r l; do [ -n "$l" ] && BF+="<div class='finding finding-pass'>✅ $l</div>"; done <<< "$B_PT"
    [ -z "$BF" ] && BF="<div class='finding finding-pass'>No findings</div>"

    # Build after findings HTML
    AF=""
    while IFS= read -r l; do [ -n "$l" ] && AF+="<div class='finding finding-issue'>❌ $l</div>"; done <<< "$A_IT"
    while IFS= read -r l; do [ -n "$l" ] && AF+="<div class='finding finding-warning'>⚠️ $l</div>"; done <<< "$A_WT"
    while IFS= read -r l; do [ -n "$l" ] && AF+="<div class='finding finding-pass'>✅ $l</div>"; done <<< "$A_PT"
    [ -z "$AF" ] && AF="<div class='finding finding-pass'>No findings</div>"

    # DBA analysis
    DBA=""
    if [ "$SHOW_DBA" -eq 1 ] && [ -n "${DBA_NOTES[$NUM]:-}" ]; then
        DBA="<div class='dba-analysis'><div class='dba-title'>🔍 DBA Analysis — Why AI May Not Resolve This</div>${DBA_NOTES[$NUM]}</div>"
    fi

    cat >> "$OUTPUT" <<EOF
<div class="section-card $CC">
  <div class="section-card-header" onclick="toggleDetail(this)">
    <span><span class="toggle-arrow">▶</span><span class="section-title">$NUM. $NAME</span> &nbsp;<small style="color:#888">$BL → $AL</small></span>
    <span>$V</span>
  </div>
  <div class="section-detail">
    <div class="detail-grid">
      <div class="detail-col before-col"><h4>Before</h4>$BF</div>
      <div class="detail-col after-col"><h4>After</h4>$AF</div>
    </div>
    $DBA
  </div>
</div>
EOF
done

# Footer + JS
cat >> "$OUTPUT" <<'END'
<div class="footer">
  Click any section to expand. Blue boxes explain why AI may not auto-fix certain issues.<br>
  "Show Unresolved Only" highlights items that still need DBA attention.
</div>
<script>
function toggleDetail(h){const d=h.nextElementSibling,a=h.querySelector('.toggle-arrow');d.classList.toggle('open');a.classList.toggle('open')}
function toggleAll(o){document.querySelectorAll('.section-detail').forEach(d=>{o?d.classList.add('open'):d.classList.remove('open')});document.querySelectorAll('.toggle-arrow').forEach(a=>{o?a.classList.add('open'):a.classList.remove('open')})}
function showOnly(c){toggleAll(false);document.querySelectorAll('.'+c).forEach(card=>{const d=card.querySelector('.section-detail'),a=card.querySelector('.toggle-arrow');if(d){d.classList.add('open');a.classList.add('open')}})}
</script>
</body></html>
END

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "  ✅ Detailed Comparison: $OUTPUT"
echo ""
echo "  Before: $B_RATING ($B_ISSUES issues, $B_WARNINGS warnings)"
echo "  After:  $A_RATING ($A_ISSUES issues, $A_WARNINGS warnings)"
echo "  Fixed:  $FIXED issue(s)"
echo ""
echo "  ➤ Click sections to see Before vs After details"
echo "  ➤ Blue DBA Analysis box explains unresolved items"
echo "╚══════════════════════════════════════════════════════════╝"

command -v xdg-open &>/dev/null && xdg-open "$OUTPUT" 2>/dev/null &
command -v open &>/dev/null && open "$OUTPUT" 2>/dev/null &
true
