#!/bin/bash
###############################################################################
# pg_health_compare.sh — Compare two health check HTML reports (Before vs After)
#
# Usage: ./pg_health_compare.sh <before_report.html> <after_report.html>
#
# Generates a single comparison HTML with side-by-side scorecard and
# section-by-section diff showing what was fixed, what's new, what remains.
###############################################################################

set -uo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <before_report.html> <after_report.html>"
    echo "Example: $0 pg_health_before_20250225.html pg_health_after_20250225.html"
    exit 1
fi

BEFORE="$1"
AFTER="$2"
OUTPUT="pg_health_comparison_$(date +%Y%m%d_%H%M%S).html"

if [ ! -f "$BEFORE" ]; then echo "ERROR: $BEFORE not found"; exit 1; fi
if [ ! -f "$AFTER" ]; then echo "ERROR: $AFTER not found"; exit 1; fi

# Extract counts from reports using badge text
extract_count() {
    local file="$1" type="$2"
    grep -oP "${type}: \K[0-9]+" "$file" 2>/dev/null | tail -1 || echo "0"
}

extract_rating() {
    grep -oP 'HEALTH RATING: \K[A-Z]+' "$1" 2>/dev/null | head -1 || echo "UNKNOWN"
}

B_ISSUES=$(extract_count "$BEFORE" "ISSUES")
B_WARNINGS=$(extract_count "$BEFORE" "WARNINGS")
B_PASSED=$(extract_count "$BEFORE" "PASSED")
B_TOTAL=$(extract_count "$BEFORE" "TOTAL CHECKS")
B_RATING=$(extract_rating "$BEFORE")

A_ISSUES=$(extract_count "$AFTER" "ISSUES")
A_WARNINGS=$(extract_count "$AFTER" "WARNINGS")
A_PASSED=$(extract_count "$AFTER" "PASSED")
A_TOTAL=$(extract_count "$AFTER" "TOTAL CHECKS")
A_RATING=$(extract_rating "$AFTER")

FIXED=$((B_ISSUES - A_ISSUES))
if [ "$FIXED" -lt 0 ]; then FIXED=0; fi

# Extract all findings from both reports
extract_findings() {
    local file="$1"
    # Extract section number + badge type + text
    grep -oP "id='s\K[0-9]+|badge-issue'>ISSUE</span>\s*\K[^<]+|badge-warning'>WARNING</span>\s*\K[^<]+|badge-pass'>PASS</span>\s*\K[^<]+" "$file" 2>/dev/null
}

cat > "$OUTPUT" <<'HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PostgreSQL Health Check — Before vs After Comparison</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    font-family: "Courier New", Courier, monospace;
    font-size: 13px;
    color: #1a1a1a;
    background: #fff;
    padding: 20px 30px;
    max-width: 1400px;
    margin: 0 auto;
}
.report-header {
    border: 2px solid #333;
    padding: 12px 16px;
    margin-bottom: 20px;
    background: #f5f5f5;
    text-align: center;
}
.report-header h1 { font-size: 16px; letter-spacing: 1px; margin-bottom: 4px; }
.report-header .sub { font-size: 12px; color: #666; }

/* Comparison grid */
.compare-grid {
    display: grid;
    grid-template-columns: 1fr 80px 1fr;
    gap: 0;
    margin-bottom: 20px;
    border: 2px solid #333;
}
.compare-col {
    padding: 12px 16px;
}
.compare-col.before {
    background: #fff5f5;
    border-right: 1px solid #ccc;
}
.compare-col.arrow {
    display: flex;
    align-items: center;
    justify-content: center;
    background: #f0f0f0;
    font-size: 28px;
    font-weight: bold;
    color: #666;
    border-right: 1px solid #ccc;
}
.compare-col.after {
    background: #f5fff5;
}
.compare-col h2 {
    font-size: 14px;
    margin-bottom: 8px;
    text-align: center;
}
.metric-row {
    display: flex;
    justify-content: space-between;
    padding: 3px 0;
    font-size: 13px;
}
.metric-label { color: #666; }
.metric-value { font-weight: bold; }

/* Rating display */
.rating-box {
    text-align: center;
    padding: 6px;
    margin: 6px 0;
    font-weight: bold;
    font-size: 14px;
    border: 1px solid;
}
.rating-critical { background: #ffcccc; border-color: #cc0000; color: #cc0000; }
.rating-poor { background: #ffe0cc; border-color: #cc6600; color: #cc6600; }
.rating-fair { background: #ffffcc; border-color: #999900; color: #999900; }
.rating-good { background: #ccffcc; border-color: #006600; color: #006600; }
.rating-unknown { background: #eee; border-color: #999; color: #999; }

/* Summary banner */
.summary-banner {
    border: 2px solid #333;
    padding: 12px 16px;
    margin-bottom: 20px;
    text-align: center;
}
.summary-banner .big-number {
    font-size: 36px;
    font-weight: bold;
    margin: 4px 0;
}
.fixed-color { color: #006600; }
.remaining-color { color: #cc6600; }
.new-color { color: #cc0000; }

.summary-stats {
    display: flex;
    justify-content: center;
    gap: 40px;
    margin-top: 8px;
}
.summary-stat { text-align: center; }
.summary-stat .num { font-size: 24px; font-weight: bold; }
.summary-stat .lbl { font-size: 11px; color: #666; }

/* Section comparison table */
table.compare {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 20px;
    font-size: 12px;
}
table.compare th {
    background: #d0d0d0;
    border: 1px solid #999;
    padding: 4px 8px;
    text-align: left;
    font-weight: bold;
}
table.compare td {
    border: 1px solid #bbb;
    padding: 4px 8px;
    vertical-align: top;
}
table.compare tr:nth-child(even) { background: #f8f8f8; }

/* Row highlights */
.row-fixed { background: #d4edda !important; }
.row-fixed td:last-child { color: #006600; font-weight: bold; }
.row-remaining { background: #fff3cd !important; }
.row-remaining td:last-child { color: #996600; font-weight: bold; }
.row-new-issue { background: #ffcccc !important; }
.row-new-issue td:last-child { color: #cc0000; font-weight: bold; }
.row-pass { background: #f0f0f0; }
.row-pass td:last-child { color: #339933; }

.badge {
    display: inline-block;
    padding: 1px 6px;
    font-size: 10px;
    font-weight: bold;
    font-family: "Courier New", monospace;
}
.badge-fixed { background: #d4edda; border: 1px solid #339933; color: #1a4d1a; }
.badge-remaining { background: #fff3cd; border: 1px solid #cc9900; color: #664d00; }
.badge-new { background: #ffcccc; border: 1px solid #cc0000; color: #660000; }
.badge-pass { background: #e8e8e8; border: 1px solid #999; color: #666; }

.footer {
    margin-top: 30px;
    padding-top: 8px;
    border-top: 2px solid #333;
    font-size: 11px;
    color: #666;
    text-align: center;
}

/* Iframe side-by-side */
.iframe-section {
    margin-top: 20px;
    border: 2px solid #333;
}
.iframe-section h2 {
    background: #e8e8e8;
    padding: 5px 10px;
    font-size: 13px;
    border-bottom: 1px solid #999;
}
.iframe-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
}
.iframe-grid iframe {
    width: 100%;
    height: 600px;
    border: none;
    border-right: 1px solid #ccc;
}
</style>
</head>
<body>
HEADER

# Header
cat >> "$OUTPUT" <<EOF
<div class="report-header">
  <h1>POSTGRESQL HEALTH CHECK — BEFORE vs AFTER</h1>
  <div class="sub">Generated: $(date)</div>
</div>
EOF

# Rating class helper
rating_class() {
    case "$1" in
        CRITICAL) echo "rating-critical" ;;
        POOR)     echo "rating-poor" ;;
        FAIR)     echo "rating-fair" ;;
        GOOD)     echo "rating-good" ;;
        *)        echo "rating-unknown" ;;
    esac
}

# Side-by-side scorecard
cat >> "$OUTPUT" <<EOF
<div class="compare-grid">
  <div class="compare-col before">
    <h2>BEFORE</h2>
    <div class="rating-box $(rating_class $B_RATING)">$B_RATING</div>
    <div class="metric-row"><span class="metric-label">Issues:</span><span class="metric-value" style="color:#cc0000">$B_ISSUES</span></div>
    <div class="metric-row"><span class="metric-label">Warnings:</span><span class="metric-value" style="color:#cc6600">$B_WARNINGS</span></div>
    <div class="metric-row"><span class="metric-label">Passed:</span><span class="metric-value" style="color:#006600">$B_PASSED</span></div>
    <div class="metric-row"><span class="metric-label">Total Checks:</span><span class="metric-value">$B_TOTAL</span></div>
  </div>
  <div class="compare-col arrow">→</div>
  <div class="compare-col after">
    <h2>AFTER</h2>
    <div class="rating-box $(rating_class $A_RATING)">$A_RATING</div>
    <div class="metric-row"><span class="metric-label">Issues:</span><span class="metric-value" style="color:#cc0000">$A_ISSUES</span></div>
    <div class="metric-row"><span class="metric-label">Warnings:</span><span class="metric-value" style="color:#cc6600">$A_WARNINGS</span></div>
    <div class="metric-row"><span class="metric-label">Passed:</span><span class="metric-value" style="color:#006600">$A_PASSED</span></div>
    <div class="metric-row"><span class="metric-label">Total Checks:</span><span class="metric-value">$A_TOTAL</span></div>
  </div>
</div>
EOF

# Summary banner
REMAINING=$A_ISSUES
NEW_ISSUES=0
if [ "$A_ISSUES" -gt "$B_ISSUES" ]; then
    NEW_ISSUES=$((A_ISSUES - B_ISSUES))
fi

cat >> "$OUTPUT" <<EOF
<div class="summary-banner">
  <div class="summary-stats">
    <div class="summary-stat">
      <div class="num fixed-color">$FIXED</div>
      <div class="lbl">ISSUES FIXED</div>
    </div>
    <div class="summary-stat">
      <div class="num remaining-color">$REMAINING</div>
      <div class="lbl">REMAINING</div>
    </div>
    <div class="summary-stat">
      <div class="num">${B_ISSUES} → ${A_ISSUES}</div>
      <div class="lbl">ISSUES BEFORE → AFTER</div>
    </div>
    <div class="summary-stat">
      <div class="num">${B_WARNINGS} → ${A_WARNINGS}</div>
      <div class="lbl">WARNINGS BEFORE → AFTER</div>
    </div>
  </div>
</div>
EOF

# Section-by-section comparison
# Parse each section from both reports and compare findings

SECTIONS=(
    "1|Table Bloat & Autovacuum"
    "2|Index Bloat"
    "3|Invalid Indexes"
    "4|Unused Indexes"
    "5|Duplicate / Overlapping Indexes"
    "6|Missing FK Indexes"
    "7|Wraparound Risk"
    "8|Stale Statistics"
    "9|Long-Running Queries"
    "10|Idle-in-Transaction Sessions"
    "11|Orphaned Prepared Transactions"
    "12|Replication Slots"
    "13|Sequence Exhaustion"
    "14|Tables Without Primary Keys"
    "15|Unlogged Tables"
    "16|Configuration Settings"
    "17|Security & Grants"
    "18|Lock Contention & Advisory Locks"
    "19|Data Integrity"
    "20|Partitioning Health"
    "21|Trigger Issues"
    "22|Role Escalation & Privileges"
    "23|Foreign Data Wrappers"
    "24|Materialized Views & pg_stat_statements"
    "25|Connection Pressure & WAL Archiving"
    "26|Schema Smells"
)

cat >> "$OUTPUT" <<'TABLE_START'
<table class="compare">
<tr>
  <th style="width:30px">#</th>
  <th style="width:280px">Check</th>
  <th style="width:200px">Before</th>
  <th style="width:200px">After</th>
  <th style="width:100px">Status</th>
</tr>
TABLE_START

# For each section, extract findings from both files
for entry in "${SECTIONS[@]}"; do
    NUM="${entry%%|*}"
    NAME="${entry##*|}"

    # Extract findings for this section from before report
    # Look between section start and next section
    B_FINDINGS=$(sed -n "/id='s${NUM}'/,/id='s$((NUM+1))'/p" "$BEFORE" 2>/dev/null | grep -oP "badge-issue'>ISSUE</span>\s*\K[^<]+|badge-warning'>WARNING</span>\s*\K[^<]+|badge-pass'>PASS</span>\s*\K[^<]+" 2>/dev/null || true)
    A_FINDINGS=$(sed -n "/id='s${NUM}'/,/id='s$((NUM+1))'/p" "$AFTER" 2>/dev/null | grep -oP "badge-issue'>ISSUE</span>\s*\K[^<]+|badge-warning'>WARNING</span>\s*\K[^<]+|badge-pass'>PASS</span>\s*\K[^<]+" 2>/dev/null || true)

    B_HAS_ISSUE=$(sed -n "/id='s${NUM}'/,/id='s$((NUM+1))'/p" "$BEFORE" 2>/dev/null | grep -c "badge-issue" 2>/dev/null || echo "0")
    A_HAS_ISSUE=$(sed -n "/id='s${NUM}'/,/id='s$((NUM+1))'/p" "$AFTER" 2>/dev/null | grep -c "badge-issue" 2>/dev/null || echo "0")
    B_HAS_WARN=$(sed -n "/id='s${NUM}'/,/id='s$((NUM+1))'/p" "$BEFORE" 2>/dev/null | grep -c "badge-warning" 2>/dev/null || echo "0")
    A_HAS_WARN=$(sed -n "/id='s${NUM}'/,/id='s$((NUM+1))'/p" "$AFTER" 2>/dev/null | grep -c "badge-warning" 2>/dev/null || echo "0")

    # Determine before status
    if [ "$B_HAS_ISSUE" -gt 0 ]; then
        B_STATUS="ISSUE ($B_HAS_ISSUE)"
        B_STYLE="color:#cc0000;font-weight:bold"
    elif [ "$B_HAS_WARN" -gt 0 ]; then
        B_STATUS="WARNING ($B_HAS_WARN)"
        B_STYLE="color:#cc6600"
    else
        B_STATUS="PASS"
        B_STYLE="color:#339933"
    fi

    # Determine after status
    if [ "$A_HAS_ISSUE" -gt 0 ]; then
        A_STATUS="ISSUE ($A_HAS_ISSUE)"
        A_STYLE="color:#cc0000;font-weight:bold"
    elif [ "$A_HAS_WARN" -gt 0 ]; then
        A_STATUS="WARNING ($A_HAS_WARN)"
        A_STYLE="color:#cc6600"
    else
        A_STATUS="PASS"
        A_STYLE="color:#339933"
    fi

    # Determine comparison result
    if [ "$B_HAS_ISSUE" -gt 0 ] && [ "$A_HAS_ISSUE" -eq 0 ]; then
        ROW_CLASS="row-fixed"
        VERDICT="<span class='badge badge-fixed'>✓ FIXED</span>"
    elif [ "$B_HAS_ISSUE" -eq 0 ] && [ "$A_HAS_ISSUE" -gt 0 ]; then
        ROW_CLASS="row-new-issue"
        VERDICT="<span class='badge badge-new'>✗ NEW ISSUE</span>"
    elif [ "$B_HAS_ISSUE" -gt 0 ] && [ "$A_HAS_ISSUE" -gt 0 ]; then
        if [ "$A_HAS_ISSUE" -lt "$B_HAS_ISSUE" ]; then
            ROW_CLASS="row-remaining"
            VERDICT="<span class='badge badge-remaining'>↓ IMPROVED</span>"
        else
            ROW_CLASS="row-remaining"
            VERDICT="<span class='badge badge-remaining'>— REMAINS</span>"
        fi
    elif [ "$B_HAS_WARN" -gt 0 ] && [ "$A_HAS_WARN" -eq 0 ]; then
        ROW_CLASS="row-fixed"
        VERDICT="<span class='badge badge-fixed'>✓ FIXED</span>"
    elif [ "$B_HAS_WARN" -gt 0 ] && [ "$A_HAS_WARN" -gt 0 ]; then
        ROW_CLASS="row-pass"
        VERDICT="<span class='badge badge-pass'>— SAME</span>"
    else
        ROW_CLASS="row-pass"
        VERDICT="<span class='badge badge-pass'>✓ CLEAN</span>"
    fi

    cat >> "$OUTPUT" <<EOF
<tr class="$ROW_CLASS">
  <td>$NUM</td>
  <td>$NAME</td>
  <td style="$B_STYLE">$B_STATUS</td>
  <td style="$A_STYLE">$A_STATUS</td>
  <td>$VERDICT</td>
</tr>
EOF
done

echo "</table>" >> "$OUTPUT"

# Side-by-side iframe view
cat >> "$OUTPUT" <<EOF
<div class="iframe-section">
  <h2>Full Reports (Side-by-Side)</h2>
  <div class="iframe-grid">
    <iframe src="$(basename "$BEFORE")" title="Before"></iframe>
    <iframe src="$(basename "$AFTER")" title="After"></iframe>
  </div>
</div>
EOF

# Footer
cat >> "$OUTPUT" <<EOF
<div class="footer">
Before: $(basename "$BEFORE") | After: $(basename "$AFTER")<br>
Comparison generated: $(date)
</div>
</body>
</html>
EOF

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "  ✅ Comparison: $OUTPUT"
echo ""
echo "  Before: $B_RATING ($B_ISSUES issues, $B_WARNINGS warnings)"
echo "  After:  $A_RATING ($A_ISSUES issues, $A_WARNINGS warnings)"
echo "  Fixed:  $FIXED issue(s)"
echo ""
echo "  Open:  xdg-open $OUTPUT  (Linux)"
echo "         open $OUTPUT       (Mac)"
echo "╚══════════════════════════════════════════════════════════╝"

# Auto-open
if command -v xdg-open &>/dev/null; then
    xdg-open "$OUTPUT" 2>/dev/null &
elif command -v open &>/dev/null; then
    open "$OUTPUT" 2>/dev/null &
fi
