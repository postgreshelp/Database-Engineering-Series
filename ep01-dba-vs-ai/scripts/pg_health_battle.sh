#!/bin/bash
###############################################################################
# pg_health_battle.sh — Multi-AI Comparison Report Generator
#
# Compares 2 to 5 health check HTML reports side-by-side.
# First report is always treated as BEFORE (baseline).
# Remaining reports are AI contestants.
#
# Usage:
#   ./pg_health_battle.sh <before.html> <ai1.html> [ai2.html] [ai3.html] [ai4.html]
#
# Examples:
#   # Two AIs:
#   ./pg_health_battle.sh before.html gemini.html claude.html
#
#   # Four rounds:
#   ./pg_health_battle.sh before.html gemini.html claude_basic.html claude_detailed.html
#
# Labels: By default, filenames are used as labels. Override with -l flag:
#   ./pg_health_battle.sh -l "Planted|Gemini CLI|Claude Basic|Claude Detailed" \
#       before.html gemini.html claude1.html claude2.html
###############################################################################

set -uo pipefail

LABELS=""
while getopts "l:" opt; do
    case $opt in l) LABELS="$OPTARG" ;; *) ;; esac
done
shift $((OPTIND-1))

if [ $# -lt 2 ]; then
    echo "Usage: $0 [-l 'Label1|Label2|...'] <before.html> <ai1.html> [ai2.html] ..."
    echo ""
    echo "Examples:"
    echo "  $0 before.html gemini.html claude.html"
    echo "  $0 -l 'Planted|Gemini|Claude Basic|Claude Detailed' before.html g.html c1.html c2.html"
    exit 1
fi

# Validate files
FILES=()
for f in "$@"; do
    if [ ! -f "$f" ]; then echo "ERROR: $f not found"; exit 1; fi
    FILES+=("$f")
done

FILE_COUNT=${#FILES[@]}
if [ "$FILE_COUNT" -gt 5 ]; then echo "ERROR: Max 5 reports supported"; exit 1; fi

# Parse labels
IFS='|' read -ra LABEL_ARR <<< "$LABELS"
for i in $(seq 0 $((FILE_COUNT-1))); do
    if [ -z "${LABEL_ARR[$i]:-}" ]; then
        # Default: derive from filename
        LABEL_ARR[$i]=$(basename "${FILES[$i]}" .html | sed 's/pg_health_//' | sed 's/_/ /g' | sed 's/\b\(.\)/\u\1/g')
    fi
done

OUTPUT="pg_health_battle_$(date +%Y%m%d_%H%M%S).html"

# Colors for each contestant
COLORS=("#cc3333" "#4285f4" "#d97706" "#7c3aed" "#059669")
BG_COLORS=("#fff5f5" "#f0f0ff" "#fff8f0" "#f8f0ff" "#f0fff8")
ICONS=("🔴" "🔵" "🟠" "🟣" "🟢")

###############################################################################
# EXTRACTION FUNCTIONS
###############################################################################
extract_count() { grep -oP "${2}: \K[0-9]+" "$1" 2>/dev/null | tail -1 || echo "0"; }
extract_rating() { grep -oP 'HEALTH RATING: \K[A-Z]+' "$1" 2>/dev/null | head -1 || echo "UNKNOWN"; }
rating_class() { case "$1" in CRITICAL) echo "rating-critical";; POOR) echo "rating-poor";; FAIR) echo "rating-fair";; GOOD) echo "rating-good";; *) echo "rating-unknown";; esac; }

# Extract section data: issues count, warning count, issue texts, warning texts, pass texts
extract_section() {
    local file="$1" num="$2"
    local next=$((num+1))
    local content
    if [ "$num" -eq 26 ]; then
        content=$(sed -n "/id='s${num}'/,/<div class='footer'>/p" "$file" 2>/dev/null)
    else
        content=$(sed -n "/id='s${num}'/,/id='s${next}'/p" "$file" 2>/dev/null)
    fi
    echo "$content"
}

count_badges() {
    local content="$1" type="$2"
    local c
    c=$(echo "$content" | grep -c "badge-${type}" 2>/dev/null || true)
    echo "${c:-0}" | tr -d '[:space:]'
}

extract_texts() {
    local content="$1" type="$2"
    echo "$content" | grep -oP "badge-${type}'>${type^^}</span>\s*\K[^<]+" 2>/dev/null || true
}

echo "Analyzing ${FILE_COUNT} reports..."

# Gather stats for each file
declare -a R_ISSUES R_WARNINGS R_PASSED R_TOTAL R_RATING
for i in $(seq 0 $((FILE_COUNT-1))); do
    R_ISSUES[$i]=$(extract_count "${FILES[$i]}" "ISSUES")
    R_WARNINGS[$i]=$(extract_count "${FILES[$i]}" "WARNINGS")
    R_PASSED[$i]=$(extract_count "${FILES[$i]}" "PASSED")
    R_TOTAL[$i]=$(extract_count "${FILES[$i]}" "TOTAL CHECKS")
    R_RATING[$i]=$(extract_rating "${FILES[$i]}")
done

BASELINE_ISSUES=${R_ISSUES[0]}

###############################################################################
# DBA ANALYSIS NOTES
###############################################################################
declare -A DBA_NOTES
DBA_NOTES[1]='Autovacuum re-enable requires per-table ALTER. AI may fear overriding intentional tuning. Dead tuples need VACUUM; physical space needs VACUUM FULL.'
DBA_NOTES[4]='Unused indexes: AI hesitates because idx_scan=0 might mean a monthly job hasnt run. Production practice: monitor 30+ days before dropping.'
DBA_NOTES[6]='FK indexes: Some AIs skip small tables where seq scan is faster. But index is needed for DELETE cascades on parent.'
DBA_NOTES[12]='Replication slots: Irreversible drop. If standby is temporarily down, dropping forces full pg_basebackup rebuild. AI wont drop without explicit confirmation.'
DBA_NOTES[13]='Sequences: Need ALTER SEQUENCE MAXVALUE or convert to BIGINT. Some AIs dont touch sequences because changing MAXVALUE can affect application assumptions.'
DBA_NOTES[14]='Adding PK requires choosing the right column (design decision). Also needs ACCESS EXCLUSIVE lock and uniqueness scan on full table.'
DBA_NOTES[15]='ALTER TABLE SET LOGGED rewrites entire table + generates WAL for all rows. Blocking DDL, risky on large tables.'
DBA_NOTES[16]='Many settings need PostgreSQL restart (shared_buffers, max_connections). AI only has ALTER SYSTEM + pg_reload_conf, which doesnt apply restart-only params.'
DBA_NOTES[17]='REVOKE from PUBLIC can break every application. SECURITY DEFINER drop can cascade. AI needs app context to fix safely.'
DBA_NOTES[19]='VALIDATE CONSTRAINT fails if ANY bad row exists. Must clean data first. NULL fixes need business context (is NULL=0 or NULL=unknown?).'
DBA_NOTES[20]='Partition management: Multi-step (create partition, detach default, move rows, reattach). Complex and error-prone. Needs partitioning scheme knowledge.'
DBA_NOTES[21]='Disabled triggers exist for a reason (bulk load, debugging). Re-enabling without context can cause cascade failures.'
DBA_NOTES[22]='Revoking roles locks out users immediately. search_path change affects all sessions. Needs coordination.'
DBA_NOTES[23]='Dropping FDW user mapping breaks foreign table queries. Remote server might be temporarily down.'

###############################################################################
# GENERATE HTML
###############################################################################
cat > "$OUTPUT" <<'CSS'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PostgreSQL Health — AI Battle Report</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:"Courier New",Courier,monospace;font-size:13px;color:#1a1a1a;background:#fff;padding:20px 30px;max-width:1600px;margin:0 auto}
.header{border:2px solid #333;padding:14px 20px;margin-bottom:20px;background:#f5f5f5;text-align:center}
.header h1{font-size:16px;letter-spacing:1px;margin-bottom:4px}
.header .sub{font-size:12px;color:#666}
.score-grid{display:flex;gap:0;margin-bottom:20px;border:2px solid #333}
.score-col{padding:14px 16px;flex:1}
.score-col h2{font-size:13px;margin-bottom:8px;text-align:center}
.score-col.arrow{flex:0 0 40px;display:flex;align-items:center;justify-content:center;background:#f0f0f0;font-size:18px;color:#888}
.metric{display:flex;justify-content:space-between;padding:2px 0;font-size:12px}
.metric .lbl{color:#666}.metric .val{font-weight:bold}
.rating-box{text-align:center;padding:5px;margin:5px 0;font-weight:bold;font-size:13px;border:1px solid}
.rating-critical{background:#ffcccc;border-color:#cc0000;color:#cc0000}
.rating-poor{background:#ffe0cc;border-color:#cc6600;color:#cc6600}
.rating-fair{background:#ffffcc;border-color:#999900;color:#999900}
.rating-good{background:#ccffcc;border-color:#006600;color:#006600}
.rating-unknown{background:#eee;border-color:#999;color:#999}
.banner{border:2px solid #333;padding:12px 20px;margin-bottom:20px}
.banner h2{font-size:14px;text-align:center;margin-bottom:10px}
.banner-row{display:flex;justify-content:center;gap:20px;flex-wrap:wrap}
.banner-stat{text-align:center;padding:8px 16px;border:1px solid #ddd;min-width:140px}
.banner-stat .num{font-size:24px;font-weight:bold}
.banner-stat .lbl{font-size:10px;color:#666}
table.main{width:100%;border-collapse:collapse;margin-bottom:8px;font-size:11px}
table.main th{background:#333;color:#fff;padding:4px 6px;text-align:left;font-weight:bold;border:1px solid #333;white-space:nowrap}
table.main td{border:1px solid #bbb;padding:3px 6px;vertical-align:top}
table.main tr:nth-child(even){background:#f8f8f8}
table.main tr:hover{background:#ffffee}
.cell-issue{background:#fff3cd;color:#664d00}
.cell-warn{background:#fff8ee;color:#663300}
.cell-pass{background:#d4edda;color:#1a4d1a}
.badge{display:inline-block;padding:1px 5px;font-size:9px;font-weight:bold;font-family:"Courier New",monospace}
.b-win{background:#006600;border:1px solid #004400;color:#fff}
.b-tie{background:#fff3cd;border:1px solid #cc9900;color:#664d00}
.b-worse{background:#ffcccc;border:1px solid #cc0000;color:#660000}
.b-best{background:#006600;border:1px solid #004400;color:#fff;font-size:11px;padding:2px 8px}
.section-card{border:1px solid #bbb;margin-bottom:8px}
.section-card-hdr{padding:5px 10px;cursor:pointer;user-select:none;display:flex;justify-content:space-between;align-items:center;background:#e8e8e8}
.section-card-hdr:hover{background:#ddd}
.section-detail{display:none;border-top:1px solid #ccc}
.section-detail.open{display:block}
.detail-grid{display:flex}
.detail-col{flex:1;padding:8px 10px;font-size:11px;border-right:1px solid #eee}
.detail-col:last-child{border-right:none}
.detail-col h4{font-size:10px;color:#666;margin-bottom:4px;text-transform:uppercase;letter-spacing:.5px}
.finding{margin:3px 0;padding:2px 5px;font-size:11px}
.f-issue{background:#fff3cd;border-left:3px solid #cc9900}
.f-warn{background:#fff8ee;border-left:3px solid #cc6600}
.f-pass{background:#eaf7ec;border-left:3px solid #339933}
.dba-note{background:#f0f4ff;border-left:4px solid #3366cc;padding:6px 10px;font-size:11px;margin:0}
.dba-note b{color:#3366cc}
.toggle-arrow{font-size:12px;margin-right:5px;transition:transform .2s;display:inline-block}
.toggle-arrow.open{transform:rotate(90deg)}
.verdict{border:2px solid #333;padding:16px 20px;margin:20px 0}
.verdict h2{font-size:14px;margin-bottom:10px}
.verdict h3{font-size:13px;margin:10px 0 5px 0;border-bottom:1px solid #ddd;padding-bottom:3px}
.verdict p,.verdict li{font-size:12px;line-height:1.5;margin:3px 0}
.verdict ul{margin-left:16px}
.controls{margin-bottom:10px;text-align:right}
.controls button{font-family:"Courier New",monospace;font-size:11px;padding:3px 10px;cursor:pointer;border:1px solid #999;background:#f0f0f0;margin-left:4px}
.controls button:hover{background:#e0e0e0}
.footer{margin-top:30px;padding-top:8px;border-top:2px solid #333;font-size:11px;color:#666;text-align:center}
@media print{.section-detail{display:block!important}.toggle-arrow{display:none}body{font-size:10px;padding:10px}}
</style>
</head>
<body>
CSS

# Title
CONTESTANT_NAMES=""
for i in $(seq 1 $((FILE_COUNT-1))); do
    [ -n "$CONTESTANT_NAMES" ] && CONTESTANT_NAMES+=" vs "
    CONTESTANT_NAMES+="${LABEL_ARR[$i]}"
done

cat >> "$OUTPUT" <<EOF
<div class="header">
  <h1>POSTGRESQL HEALTH CHECK — AI BATTLE REPORT</h1>
  <div class="sub">${CONTESTANT_NAMES} | $(date)</div>
</div>
EOF

# Scorecard
echo '<div class="score-grid">' >> "$OUTPUT"
for i in $(seq 0 $((FILE_COUNT-1))); do
    [ "$i" -gt 0 ] && echo '<div class="score-col arrow">→</div>' >> "$OUTPUT"
    cat >> "$OUTPUT" <<EOF
<div class="score-col" style="background:${BG_COLORS[$i]}">
  <h2>${ICONS[$i]} ${LABEL_ARR[$i]}</h2>
  <div class="rating-box $(rating_class ${R_RATING[$i]})">${R_RATING[$i]}</div>
  <div class="metric"><span class="lbl">Issues:</span><span class="val" style="color:#cc0000">${R_ISSUES[$i]}</span></div>
  <div class="metric"><span class="lbl">Warnings:</span><span class="val" style="color:#cc6600">${R_WARNINGS[$i]}</span></div>
  <div class="metric"><span class="lbl">Passed:</span><span class="val" style="color:#006600">${R_PASSED[$i]}</span></div>
</div>
EOF
done
echo '</div>' >> "$OUTPUT"

# Summary banner
echo '<div class="banner"><h2>ISSUES FIXED</h2><div class="banner-row">' >> "$OUTPUT"
for i in $(seq 1 $((FILE_COUNT-1))); do
    FIXED=$((BASELINE_ISSUES - R_ISSUES[$i]))
    [ "$FIXED" -lt 0 ] && FIXED=0
    PCT=0
    [ "$BASELINE_ISSUES" -gt 0 ] && PCT=$((FIXED * 100 / BASELINE_ISSUES))
    cat >> "$OUTPUT" <<EOF
<div class="banner-stat">
  <div class="num" style="color:${COLORS[$i]}">${FIXED} fixed</div>
  <div class="lbl">${LABEL_ARR[$i]}: ${BASELINE_ISSUES} → ${R_ISSUES[$i]} (${PCT}% reduction)</div>
</div>
EOF
done
echo '</div></div>' >> "$OUTPUT"

# Controls
cat >> "$OUTPUT" <<'CTRL'
<div class="controls">
  <button onclick="toggleAll(true)">▼ Expand All</button>
  <button onclick="toggleAll(false)">▲ Collapse All</button>
</div>
CTRL

###############################################################################
# SECTION-BY-SECTION CARDS
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

# Track wins for final scoreboard
declare -A WINS
for i in $(seq 0 $((FILE_COUNT-1))); do WINS[$i]=0; done
TIES=0

for entry in "${SECTIONS[@]}"; do
    NUM="${entry%%|*}"; NAME="${entry##*|}"

    # Extract data per file
    declare -a S_IC S_WC S_IT S_WT S_PT
    for i in $(seq 0 $((FILE_COUNT-1))); do
        SEC_CONTENT=$(extract_section "${FILES[$i]}" "$NUM")
        S_IC[$i]=$(count_badges "$SEC_CONTENT" "issue")
        S_WC[$i]=$(count_badges "$SEC_CONTENT" "warning")
        S_IT[$i]=$(extract_texts "$SEC_CONTENT" "issue")
        S_WT[$i]=$(extract_texts "$SEC_CONTENT" "warning")
        S_PT[$i]=$(extract_texts "$SEC_CONTENT" "pass")
    done

    # Determine winner among contestants (index 1+)
    # Score: lower issues = better, then lower warnings = better
    BEST_SCORE=999999
    BEST_IDX=-1
    ALL_SAME=1
    for i in $(seq 1 $((FILE_COUNT-1))); do
        _ic=$(echo "${S_IC[$i]}" | tr -d '[:space:]'); [ -z "$_ic" ] && _ic=0
        _wc=$(echo "${S_WC[$i]}" | tr -d '[:space:]'); [ -z "$_wc" ] && _wc=0
        SCORE=$(( _ic * 1000 + _wc ))
        if [ "$SCORE" -lt "$BEST_SCORE" ]; then
            BEST_SCORE=$SCORE; BEST_IDX=$i; ALL_SAME=0
        elif [ "$SCORE" -eq "$BEST_SCORE" ] && [ "$BEST_IDX" -ne "$i" ]; then
            if [ "$_ic" -eq "$(echo "${S_IC[$BEST_IDX]}" | tr -d '[:space:]')" ] && [ "$_wc" -eq "$(echo "${S_WC[$BEST_IDX]}" | tr -d '[:space:]')" ]; then
                ALL_SAME=1
            fi
        fi
    done

    # Check if all contestants have same score
    _f_ic=$(echo "${S_IC[1]}" | tr -d '[:space:]'); [ -z "$_f_ic" ] && _f_ic=0
    _f_wc=$(echo "${S_WC[1]}" | tr -d '[:space:]'); [ -z "$_f_wc" ] && _f_wc=0
    FIRST_SCORE=$(( _f_ic * 1000 + _f_wc ))
    IS_TIE=1
    for i in $(seq 2 $((FILE_COUNT-1))); do
        _ic=$(echo "${S_IC[$i]}" | tr -d '[:space:]'); [ -z "$_ic" ] && _ic=0
        _wc=$(echo "${S_WC[$i]}" | tr -d '[:space:]'); [ -z "$_wc" ] && _wc=0
        THIS_SCORE=$(( _ic * 1000 + _wc ))
        [ "$THIS_SCORE" -ne "$FIRST_SCORE" ] && IS_TIE=0
    done

    if [ "$IS_TIE" -eq 1 ]; then
        WINNER_HTML="<span class='badge b-tie'>TIE</span>"
        TIES=$((TIES+1))
    else
        WINNER_HTML="<span class='badge b-win'>${ICONS[$BEST_IDX]} ${LABEL_ARR[$BEST_IDX]}</span>"
        WINS[$BEST_IDX]=$((${WINS[$BEST_IDX]} + 1))
    fi

    # Card background
    BASELINE_IC=$(echo "${S_IC[0]}" | tr -d '[:space:]'); [ -z "$BASELINE_IC" ] && BASELINE_IC=0
    _tic=$(echo "${S_IC[1]}" | tr -d '[:space:]'); [ -z "$_tic" ] && _tic=0
    if [ "$IS_TIE" -eq 1 ] && [ "$_tic" -eq 0 ] && [ "$BASELINE_IC" -eq 0 ]; then
        CARD_BG="#eaf7ec"  # all clean
    elif [ "$IS_TIE" -eq 1 ] && [ "$_tic" -gt 0 ]; then
        CARD_BG="#fff3cd"  # all failed
    else
        CARD_BG="#f8f8f8"
    fi

    # Status labels per file
    STATUS_PARTS=""
    for i in $(seq 0 $((FILE_COUNT-1))); do
        _sic=$(echo "${S_IC[$i]}" | tr -d '[:space:]'); [ -z "$_sic" ] && _sic=0
        _swc=$(echo "${S_WC[$i]}" | tr -d '[:space:]'); [ -z "$_swc" ] && _swc=0
        if [ "$_sic" -gt 0 ]; then
            STATUS_PARTS+="<span style='color:${COLORS[$i]}'>❌${_sic}</span> "
        elif [ "$_swc" -gt 0 ]; then
            STATUS_PARTS+="<span style='color:${COLORS[$i]}'>⚠️${_swc}</span> "
        else
            STATUS_PARTS+="<span style='color:${COLORS[$i]}'>✅</span> "
        fi
    done

    # Build detail columns
    DETAIL_COLS=""
    for i in $(seq 0 $((FILE_COUNT-1))); do
        FINDINGS=""
        while IFS= read -r l; do [ -n "$l" ] && FINDINGS+="<div class='finding f-issue'>❌ $l</div>"; done <<< "${S_IT[$i]}"
        while IFS= read -r l; do [ -n "$l" ] && FINDINGS+="<div class='finding f-warn'>⚠️ $l</div>"; done <<< "${S_WT[$i]}"
        while IFS= read -r l; do [ -n "$l" ] && FINDINGS+="<div class='finding f-pass'>✅ $l</div>"; done <<< "${S_PT[$i]}"
        [ -z "$FINDINGS" ] && FINDINGS="<div class='finding f-pass'>No findings</div>"
        DETAIL_COLS+="<div class='detail-col' style='background:${BG_COLORS[$i]}'><h4>${ICONS[$i]} ${LABEL_ARR[$i]}</h4>$FINDINGS</div>"
    done

    # DBA note (show if any contestant still has issues)
    DBA_HTML=""
    HAS_REMAINING=0
    for i in $(seq 1 $((FILE_COUNT-1))); do
        _hic=$(echo "${S_IC[$i]}" | tr -d '[:space:]'); [ -z "$_hic" ] && _hic=0
        [ "$_hic" -gt 0 ] && HAS_REMAINING=1
    done
    if [ "$HAS_REMAINING" -eq 1 ] && [ -n "${DBA_NOTES[$NUM]:-}" ]; then
        DBA_HTML="<div class='dba-note'><b>🔍 DBA Analysis:</b> ${DBA_NOTES[$NUM]}</div>"
    fi

    cat >> "$OUTPUT" <<EOF
<div class="section-card">
  <div class="section-card-hdr" style="background:${CARD_BG}" onclick="toggleDetail(this)">
    <span><span class="toggle-arrow">▶</span><b>$NUM. $NAME</b> &nbsp; $STATUS_PARTS</span>
    <span>$WINNER_HTML</span>
  </div>
  <div class="section-detail">
    <div class="detail-grid">$DETAIL_COLS</div>
    $DBA_HTML
  </div>
</div>
EOF

    unset S_IC S_WC S_IT S_WT S_PT
done

###############################################################################
# FINAL SCOREBOARD
###############################################################################
cat >> "$OUTPUT" <<'VERDICT_START'
<div class="verdict">
<h2>📊 FINAL SCOREBOARD</h2>
VERDICT_START

echo '<table class="main" style="width:600px;margin-bottom:16px">' >> "$OUTPUT"
echo '<tr><th>Metric</th>' >> "$OUTPUT"
for i in $(seq 1 $((FILE_COUNT-1))); do
    echo "<th style='background:${COLORS[$i]}'>${LABEL_ARR[$i]}</th>" >> "$OUTPUT"
done
echo '</tr>' >> "$OUTPUT"

# Issues fixed
echo '<tr><td>Issues fixed (of '"$BASELINE_ISSUES"')</td>' >> "$OUTPUT"
BEST_FIXED=0
for i in $(seq 1 $((FILE_COUNT-1))); do
    F=$((BASELINE_ISSUES - R_ISSUES[$i])); [ "$F" -lt 0 ] && F=0
    [ "$F" -gt "$BEST_FIXED" ] && BEST_FIXED=$F
done
for i in $(seq 1 $((FILE_COUNT-1))); do
    F=$((BASELINE_ISSUES - R_ISSUES[$i])); [ "$F" -lt 0 ] && F=0
    BOLD=""; [ "$F" -eq "$BEST_FIXED" ] && BOLD="font-weight:bold;color:#006600"
    echo "<td style='$BOLD'>$F</td>" >> "$OUTPUT"
done
echo '</tr>' >> "$OUTPUT"

# Final issues
echo '<tr><td>Final issue count</td>' >> "$OUTPUT"
BEST_FINAL=999
for i in $(seq 1 $((FILE_COUNT-1))); do
    [ "${R_ISSUES[$i]}" -lt "$BEST_FINAL" ] && BEST_FINAL=${R_ISSUES[$i]}
done
for i in $(seq 1 $((FILE_COUNT-1))); do
    BOLD=""; [ "${R_ISSUES[$i]}" -eq "$BEST_FINAL" ] && BOLD="font-weight:bold;color:#006600"
    echo "<td style='$BOLD'>${R_ISSUES[$i]}</td>" >> "$OUTPUT"
done
echo '</tr>' >> "$OUTPUT"

# Sections won
echo '<tr><td>Sections won</td>' >> "$OUTPUT"
BEST_WINS=0
for i in $(seq 1 $((FILE_COUNT-1))); do
    [ "${WINS[$i]}" -gt "$BEST_WINS" ] && BEST_WINS=${WINS[$i]}
done
for i in $(seq 1 $((FILE_COUNT-1))); do
    BOLD=""; [ "${WINS[$i]}" -eq "$BEST_WINS" ] && BOLD="font-weight:bold;color:#006600"
    echo "<td style='$BOLD'>${WINS[$i]}</td>" >> "$OUTPUT"
done
echo '</tr>' >> "$OUTPUT"

# Ties
echo "<tr><td>Sections tied</td><td colspan='$((FILE_COUNT-1))' style='text-align:center'>$TIES</td></tr>" >> "$OUTPUT"

# Final rating
echo '<tr><td>Final rating</td>' >> "$OUTPUT"
for i in $(seq 1 $((FILE_COUNT-1))); do
    echo "<td>${R_RATING[$i]}</td>" >> "$OUTPUT"
done
echo '</tr></table>' >> "$OUTPUT"

# Determine overall winner
OVERALL_BEST_IDX=1
OVERALL_BEST_ISSUES=${R_ISSUES[1]}
for i in $(seq 2 $((FILE_COUNT-1))); do
    if [ "${R_ISSUES[$i]}" -lt "$OVERALL_BEST_ISSUES" ]; then
        OVERALL_BEST_IDX=$i; OVERALL_BEST_ISSUES=${R_ISSUES[$i]}
    fi
done

cat >> "$OUTPUT" <<EOF
<h3>🏆 Overall Winner: ${ICONS[$OVERALL_BEST_IDX]} ${LABEL_ARR[$OVERALL_BEST_IDX]}</h3>
<p>${LABEL_ARR[$OVERALL_BEST_IDX]} resolved the most issues, bringing the database from <b>$BASELINE_ISSUES issues</b> down to <b>$OVERALL_BEST_ISSUES issues</b>.</p>

<h3>⚠️ What a Senior DBA Would Also Fix</h3>
<ul>
<li>Drop inactive replication slots (after verifying no active standby)</li>
<li>ALTER TABLE SET LOGGED on unlogged tables (during maintenance window)</li>
<li>ALTER SYSTEM for all config settings + schedule restart</li>
<li>REVOKE from PUBLIC + grant to specific app roles</li>
<li>Create missing partitions + migrate DEFAULT rows</li>
<li>Fix search_path, validate constraints, clean bad data</li>
</ul>
<p>A senior DBA would resolve <b>21-23 out of $BASELINE_ISSUES</b> issues in ~2-3 hours. The remaining 1-2 need business approval.</p>
</div>
EOF

# Footer
cat >> "$OUTPUT" <<EOF
<div class="footer">
  PostgreSQL Health — AI Battle Report | $(date) | postgreshelp.com
</div>
<script>
function toggleDetail(h){const d=h.nextElementSibling,a=h.querySelector('.toggle-arrow');d.classList.toggle('open');a.classList.toggle('open')}
function toggleAll(o){document.querySelectorAll('.section-detail').forEach(d=>{o?d.classList.add('open'):d.classList.remove('open')});document.querySelectorAll('.toggle-arrow').forEach(a=>{o?a.classList.add('open'):a.classList.remove('open')})}
</script>
</body></html>
EOF

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "  ✅ Battle Report: $OUTPUT"
echo ""
for i in $(seq 0 $((FILE_COUNT-1))); do
    F=$((BASELINE_ISSUES - R_ISSUES[$i])); [ "$F" -lt 0 ] && F=0
    echo "  ${ICONS[$i]} ${LABEL_ARR[$i]}: ${R_RATING[$i]} (${R_ISSUES[$i]} issues, fixed $F)"
done
echo ""
echo "  🏆 Winner: ${LABEL_ARR[$OVERALL_BEST_IDX]}"
echo "╚══════════════════════════════════════════════════════════╝"

command -v xdg-open &>/dev/null && xdg-open "$OUTPUT" 2>/dev/null &
command -v open &>/dev/null && open "$OUTPUT" 2>/dev/null &
true

