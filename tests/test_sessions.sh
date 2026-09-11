#!/usr/bin/env bash
# Tests for the three session tools.
#
#   tests/test_sessions.sh
#
# Every test runs against a throwaway HOME built under a temp dir, so nothing
# here reads or writes the real transcripts. No test calls a model: --sum-raw
# stops at the digest, which is the part that can be wrong in a way nobody
# notices — a model will happily summarize a digest full of hook noise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

# contains <name> <haystack> <needle>
contains() {
    case "$2" in
        *"$3"*) ok "$1" ;;
        *) nope "$1" "expected to find: $3" ;;
    esac
}

# absent <name> <haystack> <needle>
absent() {
    case "$2" in
        *"$3"*) nope "$1" "should not contain: $3" ;;
        *) ok "$1" ;;
    esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

# ── claude ──────────────────────────────────────────────────────────────────
echo "claude-sessions"

CLAUDE_DIR="$TMP/claude"
export CLAUDE_CONFIG_DIR="$CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/projects/-work-repo"
SID="11111111-2222-3333-4444-555555555555"
T="$CLAUDE_DIR/projects/-work-repo/$SID.jsonl"

# A transcript with: a slash command (noise), a real ask, a tool use, a reply,
# and after a four-hour gap a second ask on another subject.
python3 - "$T" <<'PY'
import json
rows = [
    {"type": "user", "timestamp": "2026-03-02T10:00:00.000Z", "cwd": "/work/repo",
     "message": {"content": [{"type": "text",
                              "text": "<command-name>/model</command-name>"}]}},
    {"type": "user", "timestamp": "2026-03-02T10:01:00.000Z", "cwd": "/work/repo",
     "message": {"content": [{"type": "text",
                              "text": "почини парсер конфигов"}]}},
    {"type": "assistant", "timestamp": "2026-03-02T10:02:00.000Z", "cwd": "/work/repo",
     "message": {"content": [{"type": "tool_use", "name": "Edit", "input": {}},
                             {"type": "text", "text": "parser fixed in config.py"}]}},
    {"type": "user", "timestamp": "2026-03-02T10:03:00.000Z", "cwd": "/work/repo",
     "message": {"content": [{"type": "text",
                              "text": "ignore me <system-reminder>hidden note</system-reminder>"}]}},
    {"type": "user", "timestamp": "2026-03-02T16:00:00.000Z", "cwd": "/work/repo",
     "message": {"content": [{"type": "text", "text": "now the release notes"}]}},
    {"type": "assistant", "timestamp": "2026-03-02T16:01:00.000Z", "cwd": "/work/repo",
     "message": {"content": [{"type": "text", "text": "notes written"}]}},
    {"type": "user", "isSidechain": True, "timestamp": "2026-03-02T16:02:00.000Z",
     "cwd": "/work/repo",
     "message": {"content": [{"type": "text", "text": "subagent chatter"}]}},
]
with open(__import__('sys').argv[1], 'w') as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY

out="$("$ROOT/bin/claude-sessions" --sum "$SID" --sum-raw 2>&1)"
contains "reads the real ask"            "$out" "почини парсер конфигов"
absent   "drops slash-command plumbing"  "$out" "<command-name>"
absent   "strips system-reminder"        "$out" "hidden note"
absent   "skips sidechain turns"         "$out" "subagent chatter"
contains "counts tools"                  "$out" "TOOLS: Edit x1"
contains "six-hour gap splits the topic" "$out" "## part 2"

out="$("$ROOT/bin/claude-sessions" --sum "$SID" --sum-gap 600 --sum-raw 2>&1)"
absent "a wide gap keeps one part" "$out" "## part 2"

out="$("$ROOT/bin/claude-sessions" --sum no-such-session --sum-raw 2>&1)"
contains "unknown id is an error" "$out" "No transcript for session"

# ── codex ───────────────────────────────────────────────────────────────────
echo "codex-sessions"

export CODEX_HOME="$TMP/codex"
mkdir -p "$CODEX_HOME/sessions/2026/03/02"
CSID="01a00000-0000-7000-8000-000000000001"
CT="$CODEX_HOME/sessions/2026/03/02/rollout-2026-03-02T09-00-00-$CSID.jsonl"

# The 0.154 layout: response_item/message with a role, plus a developer message
# that is Codex talking to itself.
python3 - "$CT" <<'PY'
import json, sys
rows = [
    {"timestamp": "2026-03-02T09:00:00.000Z", "type": "session_meta",
     "payload": {"session_id": "01a00000-0000-7000-8000-000000000001",
                 "cwd": "/srv/app"}},
    {"timestamp": "2026-03-02T09:00:01.000Z", "type": "response_item",
     "payload": {"type": "message", "role": "developer",
                 "content": [{"type": "input_text",
                              "text": "<skills_instructions>list of skills</skills_instructions>"}]}},
    {"timestamp": "2026-03-02T09:00:02.000Z", "type": "response_item",
     "payload": {"type": "message", "role": "user",
                 "content": [{"type": "input_text",
                              "text": "# AGENTS.md instructions\n<INSTRUCTIONS>rules</INSTRUCTIONS>\nprüfe den Cache"}]}},
    {"timestamp": "2026-03-02T09:00:03.000Z", "type": "response_item",
     "payload": {"type": "custom_tool_call", "name": "exec"}},
    {"timestamp": "2026-03-02T09:00:04.000Z", "type": "response_item",
     "payload": {"type": "message", "role": "assistant",
                 "content": [{"type": "output_text", "text": "cache cleared"}]}},
]
with open(sys.argv[1], 'w') as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY

out="$("$ROOT/bin/codex-sessions" --sum "$CSID" --sum-raw 2>&1)"
contains "reads the 0.154 layout"      "$out" "prüfe den Cache"
absent   "drops the AGENTS.md preamble" "$out" "<INSTRUCTIONS>"
absent   "drops developer messages"     "$out" "list of skills"
contains "counts custom tool calls"     "$out" "TOOLS: exec x1"

# The pre-0.154 layout: event_msg/user_message and agent_message.
OSID="019e0000-0000-7000-8000-000000000002"
OT="$CODEX_HOME/sessions/2026/03/02/rollout-2026-03-02T11-00-00-$OSID.jsonl"
python3 - "$OT" <<'PY'
import json, sys
rows = [
    {"timestamp": "2026-03-02T11:00:00.000Z", "type": "session_meta",
     "payload": {"id": "019e0000-0000-7000-8000-000000000002", "cwd": "/srv/old"}},
    {"timestamp": "2026-03-02T11:00:01.000Z", "type": "event_msg",
     "payload": {"type": "user_message", "message": "rotate the logs"}},
    {"timestamp": "2026-03-02T11:00:02.000Z", "type": "event_msg",
     "payload": {"type": "agent_message", "message": "logrotate configured"}},
]
with open(sys.argv[1], 'w') as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY

out="$("$ROOT/bin/codex-sessions" --sum "$OSID" --sum-raw 2>&1)"
contains "reads the pre-0.154 layout" "$out" "rotate the logs"

# A file written across an upgrade carries both forms of the same turn.
BSID="01a00000-0000-7000-8000-000000000003"
BT="$CODEX_HOME/sessions/2026/03/02/rollout-2026-03-02T12-00-00-$BSID.jsonl"
python3 - "$BT" <<'PY'
import json, sys
rows = [
    {"timestamp": "2026-03-02T12:00:00.000Z", "type": "session_meta",
     "payload": {"session_id": "01a00000-0000-7000-8000-000000000003",
                 "cwd": "/srv/both"}},
    {"timestamp": "2026-03-02T12:00:01.000Z", "type": "event_msg",
     "payload": {"type": "user_message", "message": "bump the version"}},
    {"timestamp": "2026-03-02T12:00:01.000Z", "type": "response_item",
     "payload": {"type": "message", "role": "user",
                 "content": [{"type": "input_text", "text": "bump the version"}]}},
]
with open(sys.argv[1], 'w') as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY

out="$("$ROOT/bin/codex-sessions" --sum "$BSID" --sum-raw 2>&1)"
n=$(printf '%s\n' "$out" | grep -c 'ASKED: bump the version')
if [ "$n" = 1 ]; then ok "both layouts in one file count the turn once"
else nope "both layouts in one file count the turn once" "counted $n times"; fi

# ── opencode ────────────────────────────────────────────────────────────────
echo "opencode-sessions"

export OPENCODE_DATA_DIR="$TMP/opencode"
mkdir -p "$OPENCODE_DATA_DIR"
OCSID="ses_test0000000000000000000001"

python3 - "$OPENCODE_DATA_DIR/opencode.db" "$OCSID" <<'PY'
import sqlite3, json, sys
db, sid = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
con.executescript("""
CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT, parent_id TEXT,
    directory TEXT, title TEXT, cost REAL DEFAULT 0,
    time_created INTEGER, time_updated INTEGER);
CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT,
    time_created INTEGER, time_updated INTEGER, data TEXT);
CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT,
    time_created INTEGER, time_updated INTEGER, data TEXT);
""")
base = 1772445600000
con.execute("INSERT INTO session VALUES (?,?,?,?,?,?,?,?)",
            (sid, 'prj', None, '/opt/site', 'a session', 0.5, base, base + 9000))
rows = [
    ('msg1', 'user', base, [{'type': 'text', 'text': 'разбери падение тестов'}]),
    ('msg2', 'assistant', base + 1000,
     [{'type': 'tool', 'tool': 'bash'},
      {'type': 'text', 'text': 'flaky fixture removed'}]),
]
for mid, role, t, parts in rows:
    con.execute("INSERT INTO message VALUES (?,?,?,?,?)",
                (mid, sid, t, t, json.dumps({'role': role})))
    for i, p in enumerate(parts):
        con.execute("INSERT INTO part VALUES (?,?,?,?,?,?)",
                    ('%s_p%d' % (mid, i), mid, sid, t + i, t + i, json.dumps(p)))
con.commit()
PY

out="$("$ROOT/bin/opencode-sessions" --sum "$OCSID" --sum-raw 2>&1)"
contains "reads text parts"     "$out" "разбери падение тестов"
contains "counts tool parts"    "$out" "TOOLS: bash x1"
contains "names the directory"  "$out" "/opt/site"

out="$("$ROOT/bin/opencode-sessions" -n 5 2>&1)"
contains "lists without the sqlite3 CLI" "$out" "$OCSID"

out="$("$ROOT/bin/opencode-sessions" --sum ses_nope --sum-raw 2>&1)"
contains "unknown id is an error" "$out" "No session ses_nope"

# --rm on a real id must actually select it. It once did not: the seed list was
# piped to a python heredoc, which uses stdin for the program, so zero sessions
# were selected and the delete reported success having done nothing.
out="$("$ROOT/bin/opencode-sessions" --rm "$OCSID" --dry-run 2>&1)"
contains "--rm selects the named session" "$out" "$OCSID"
contains "--rm counts its rows"           "$out" "1 session(s)."
contains "--dry-run deletes nothing"      "$out" "Nothing deleted"

left=$(python3 -c "
import sqlite3, sys
print(sqlite3.connect(sys.argv[1]).execute('SELECT COUNT(*) FROM session').fetchone()[0])
" "$OPENCODE_DATA_DIR/opencode.db")
if [ "$left" = 1 ]; then ok "--dry-run left the row in place"
else nope "--dry-run left the row in place" "sessions now: $left"; fi

out="$("$ROOT/bin/opencode-sessions" --rm ses_nope --yes 2>&1)"
contains "--rm of an absent id deletes nothing" "$out" "No sessions match"

out="$("$ROOT/bin/opencode-sessions" --rm "$OCSID" --yes 2>&1)"
contains "--rm deletes for real" "$out" "Deleted 1 session(s)"
left=$(python3 -c "
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
print(sum(db.execute('SELECT COUNT(*) FROM ' + t).fetchone()[0]
          for t in ('session', 'message', 'part')))
" "$OPENCODE_DATA_DIR/opencode.db")
if [ "$left" = 0 ]; then ok "child tables go with the session"
else nope "child tables go with the session" "rows left: $left"; fi

# ── summary cache ───────────────────────────────────────────────────────────
echo "cache"

export IDE_SESSIONS_SUM_CACHE="$TMP/cache"
mkdir -p "$IDE_SESSIONS_SUM_CACHE"
src_mtime=$(stat -c %Y "$T" 2>/dev/null || stat -f %m "$T")
key="ide-sessions-sum v1 src=$src_mtime model=pinned gap=45"
{ printf '<!-- %s -->\n' "$key"; printf '### cached heading\n'; } \
    > "$IDE_SESSIONS_SUM_CACHE/claude-$SID.md"

# A cache hit must not reach for a model. A stub `claude` earlier on PATH makes
# that observable: it fails and says so, so a miss cannot be mistaken for a hit.
# (Emptying PATH instead would take `stat`, `find` and python3 with it.)
mkdir -p "$TMP/stub"
printf '#!/bin/sh\necho STUB-CALLED >&2\nexit 1\n' > "$TMP/stub/claude"
chmod 755 "$TMP/stub/claude"
export PATH="$TMP/stub:$PATH"

out="$("$ROOT/bin/claude-sessions" --sum "$SID" --sum-model pinned 2>&1)"
contains "a hit returns the cached summary" "$out" "### cached heading"
absent   "a hit does not print the key"     "$out" "ide-sessions-sum v1"
absent   "a hit does not call a model"      "$out" "STUB-CALLED"

sleep 1
touch "$T"
out="$("$ROOT/bin/claude-sessions" --sum "$SID" --sum-model pinned 2>&1)"
absent   "a newer transcript invalidates the cache" "$out" "### cached heading"
contains "a failed model call is reported"          "$out" "returned nothing"

# ── report ──────────────────────────────────────────────────────────────────
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
