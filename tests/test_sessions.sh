#!/usr/bin/env bash
# Tests for the three session tools and billing.
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

# ── an empty result says so ─────────────────────────────────────────────────
# `-p` in a directory that never hosted a session used to print nothing at all
# and exit 1: the project directory does not exist, `find` failed, and
# `set -euo pipefail` killed the script before the header. The other two printed
# an empty table, which is only marginally better — an empty table is a shrug.
echo "empty results"

EMPTY="$TMP/never-used"
mkdir -p "$EMPTY"

out=$(cd "$EMPTY" && "$ROOT/bin/claude-sessions" -p 2>&1)
rc=$?
contains "claude: -p in a fresh directory explains itself" "$out" "No sessions bound to"
if [ "$rc" = 0 ]; then ok "claude: -p in a fresh directory exits 0"
else nope "claude: -p in a fresh directory exits 0" "exit $rc"; fi

# One state, one sentence: a missing project directory and a present one with
# no sessions in it are the same fact to the reader, and used to print two
# different messages of different lengths in the same tool.
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$lines" = 1 ]; then ok "claude: the empty result is one line, like the others"
else nope "claude: the empty result is one line, like the others" "$lines lines"; fi

# Codex and opencode have no store at all at this point in the run, which is its
# own case: a fresh machine, before the first session was ever written.
out=$(cd "$EMPTY" && "$ROOT/bin/codex-sessions" -p 2>&1)
rc=$?
contains "codex: no sessions tree at all is explained" "$out" "No sessions"
if [ "$rc" = 0 ]; then ok "codex: a missing sessions tree exits 0"
else nope "codex: a missing sessions tree exits 0" "exit $rc"; fi

out="$("$ROOT/bin/claude-sessions" zzzznope 2>&1)"
contains "a substring with no match names the substring" "$out" 'contains "zzzznope"'

# ── redaction ───────────────────────────────────────────────────────────────
# All values below are invented and match no real account. They are here
# because a secret in a session must not reach the model, the cache file or the
# terminal, and the digest is the only place that can stop it.
echo "redaction"

RSID="99999999-8888-7777-6666-555555555555"
RT="$CLAUDE_DIR/projects/-work-repo/$RSID.jsonl"
python3 - "$RT" <<'PY'
import json, sys
def turn(text, ts="2026-03-02T10:00:00.000Z"):
    return {"type": "user", "timestamp": ts, "cwd": "/work/repo",
            "message": {"content": [{"type": "text", "text": text}]}}
rows = [
    turn("deploy with ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA please"),
    turn("export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"),
    turn("DB_PASSWORD=hunter2-correct-horse in the values file"),
    turn("psql postgres://admin:s3cr3tpass@db.internal:5432/app"),
    turn("api token is 9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c and it expired"),
    turn("checked out 9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c from main"),
    turn("read /etc/passwd and config.yaml"),
]
with open(sys.argv[1], 'w') as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY

out="$("$ROOT/bin/claude-sessions" --sum "$RSID" --sum-raw 2>&1)"
absent   "GitHub token is masked"        "$out" "ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
absent   "AWS key id is masked"          "$out" "AKIAIOSFODNN7EXAMPLE"
absent   "password by variable name"     "$out" "hunter2-correct-horse"
absent   "password inside a URL"         "$out" "s3cr3tpass"
contains "the URL keeps scheme and host" "$out" "db.internal:5432/app"
contains "masking leaves a marker"       "$out" "<REDACTED:"
contains "the surrounding text survives" "$out" "in the values file"

# The marker carries the length of what was hidden, so a re-masked marker would
# report its own length instead of the secret's.
contains "the marker keeps the real length" "$out" "AWS_ACCESS_KEY_ID=<REDACTED:20>"

# The generic rules must not eat ordinary text: a git SHA is the same shape as
# an unprefixed token, and masking every one of them would make summaries
# useless.
contains "a SHA without credential words stays" "$out" "checked out 9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c"
contains "a path is not a secret"               "$out" "/etc/passwd"
n=$(printf '%s\n' "$out" | rg -c 'api token is <REDACTED:' || true)
if [ "$n" = 1 ]; then ok "a long run beside 'token' is masked"
else nope "a long run beside 'token' is masked" "matched $n times"; fi

# Huawei, OpenStack and Jira: the access key is 20 upper-case characters and
# the secret 40 of base62, shapes no pattern can claim without taking every git
# SHA with them. The name beside the value is the only signal there is.
HSID="99999999-8888-7777-6666-555555555544"
HT="$CLAUDE_DIR/projects/-work-repo/$HSID.jsonl"
python3 - "$HT" <<'PY'
import json, sys
def turn(text):
    return {"type": "user", "timestamp": "2026-03-02T10:00:00.000Z",
            "cwd": "/work/repo",
            "message": {"content": [{"type": "text", "text": text}]}}
rows = [
    turn("export HW_ACCESS_KEY=ABCDEFGHIJKLMNOPQRST"),
    turn("HW_SECRET_KEY=aB3dEfGh1jKlMn0pQrStUvWxYz012345678AbCdE"),
    turn("OS_SECRET_KEY: qWeRtYuIoP1234567890asdfghjklzxcvbnm0987"),
    turn("HUAWEICLOUD_SDK_AK=QWERTYUIOPASDFGHJKLZ"),
    turn("jira --token ATATT3xFfGF0abcdefghijklmnop1234567890 issue list"),
    turn("curl -u me@corp.com:at-abcdefghijklmnopqrstuvwxyz012345 https://jira/rest"),
    turn("merged 1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d after review"),
]
with open(sys.argv[1], 'w') as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY

out="$("$ROOT/bin/claude-sessions" --sum "$HSID" --sum-raw 2>&1)"
absent   "Huawei access key"             "$out" "ABCDEFGHIJKLMNOPQRST"
absent   "Huawei secret key"             "$out" "aB3dEfGh1jKlMn0pQrStUvWxYz012345678AbCdE"
absent   "OpenStack secret key"          "$out" "qWeRtYuIoP1234567890asdfghjklzxcvbnm0987"
absent   "Huawei SDK key named _AK"      "$out" "QWERTYUIOPASDFGHJKLZ"
absent   "Jira token behind --token"     "$out" "ATATT3xFfGF0abcdefghijklmnop1234567890"
absent   "Jira legacy at- token"         "$out" "at-abcdefghijklmnopqrstuvwxyz012345"
contains "the label stays readable"      "$out" "HW_ACCESS_KEY=<REDACTED:20>"
contains "a 40-hex SHA with no label stays" "$out" "1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d"

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

out=$(cd "$EMPTY" && "$ROOT/bin/codex-sessions" -p 2>&1)
contains "codex: -p in a foreign directory names the scope" "$out" "No sessions bound to"

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
            (sid, 'prj', None, '/opt/site', 'a session', 0.17838120000000002,
             base, base + 9000))
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
# opencode stores cost as a REAL, and the raw float once went straight into the
# COST column — $0.17838120000000002 — pushing every column after it out of line.
contains "cost is rounded to cents"      "$out" '$0.18 '
absent   "cost is not the raw float"     "$out" '0.1783812'

out=$(cd "$EMPTY" && "$ROOT/bin/opencode-sessions" -p 2>&1)
contains "opencode: -p in a foreign directory names the scope" "$out" "No sessions bound to"

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

# ── summarizing leaves no session of its own ───────────────────────────────
# `claude -p` and `codex exec` are sessions like any other, so every --sum used
# to add a row to the listing this tool exists to keep readable. Stubs stand in
# for the CLIs: they write the transcript a real run would write, and the test
# is that it is gone afterwards.
echo "no scratch sessions"

# A rollout of its own, so the cleanup test does not depend on one the delete
# tests have already removed.
CSID2="01a00000-0000-7000-8000-000000000009"
CT2="$CODEX_HOME/sessions/2026/03/02/rollout-2026-03-02T13-00-00-$CSID2.jsonl"
python3 - "$CT2" <<'PY2'
import json, sys
rows = [
    {"timestamp": "2026-03-02T13:00:00.000Z", "type": "session_meta",
     "payload": {"session_id": "01a00000-0000-7000-8000-000000000009",
                 "cwd": "/srv/app"}},
    {"timestamp": "2026-03-02T13:00:01.000Z", "type": "event_msg",
     "payload": {"type": "user_message", "message": "tag the release"}},
    {"timestamp": "2026-03-02T13:00:02.000Z", "type": "event_msg",
     "payload": {"type": "agent_message", "message": "tagged v1.2.0"}},
]
with open(sys.argv[1], 'w') as fh:
    for r in rows:
        fh.write(json.dumps(r) + "\n")
PY2

mkdir -p "$TMP/stub"
cat > "$TMP/stub/claude" <<'STUB'
#!/usr/bin/env bash
sid=""
prev=""
for a in "$@"; do
    [ "$prev" = "--session-id" ] && sid="$a"
    prev="$a"
done
cat > /dev/null
[ -n "$sid" ] && printf '{}\n' > "$CLAUDE_CONFIG_DIR/projects/-work-repo/$sid.jsonl"
printf '### stub summary\n'
STUB
chmod 755 "$TMP/stub/claude"
export PATH="$TMP/stub:$PATH"

export IDE_SESSIONS_SUM_CACHE="$TMP/cache2"
before=$(ls "$CLAUDE_DIR/projects/-work-repo" | wc -l)
out="$("$ROOT/bin/claude-sessions" --sum "$SID" --sum-model stub 2>&1)"
after=$(ls "$CLAUDE_DIR/projects/-work-repo" | wc -l)
contains "the summary is returned" "$out" "### stub summary"
if [ "$before" = "$after" ]; then ok "claude: --sum leaves no new transcript"
else nope "claude: --sum leaves no new transcript" "$before before, $after after"; fi

cat > "$TMP/stub/codex" <<'STUB'
#!/usr/bin/env bash
out=""
prev=""
for a in "$@"; do
    [ "$prev" = "-o" ] && out="$a"
    prev="$a"
done
prompt="$(cat)"
day="$CODEX_HOME/sessions/2026/03/09"
mkdir -p "$day"
printf '%s\n' "$prompt" > "$day/rollout-2026-03-09T10-00-00-$(date +%s%N).jsonl"
[ -n "$out" ] && printf '### stub codex summary\n' > "$out"
STUB
chmod 755 "$TMP/stub/codex"

before=$(find "$CODEX_HOME/sessions" -name 'rollout-*.jsonl' | wc -l)
out="$("$ROOT/bin/codex-sessions" --sum "$CSID2" 2>&1)"
after=$(find "$CODEX_HOME/sessions" -name 'rollout-*.jsonl' | wc -l)
contains "the summary is returned" "$out" "### stub codex summary"
if [ "$before" = "$after" ]; then ok "codex: --sum leaves no new rollout"
else nope "codex: --sum leaves no new rollout" "$before before, $after after"; fi

# A rollout that was already there, and one written by something else during the
# call, must both survive.
printf 'someone else at work\n' > "$CODEX_HOME/sessions/2026/03/09/rollout-2026-03-09T11-00-00-other.jsonl"
"$ROOT/bin/codex-sessions" --sum "$CSID2" --sum-refresh >/dev/null 2>&1
if [ -f "$CODEX_HOME/sessions/2026/03/09/rollout-2026-03-09T11-00-00-other.jsonl" ]; then
    ok "codex: a rollout that is not ours is left alone"
else
    nope "codex: a rollout that is not ours is left alone" "it was deleted"
fi

# ── deleting takes the cached summary with it ───────────────────────────────
echo "delete clears the cache"

export IDE_SESSIONS_SUM_CACHE="$TMP/cache"
export IDE_SESSIONS_TRASH="$TMP/trash"
mkdir -p "$IDE_SESSIONS_SUM_CACHE"

for suffix in "" ".orig"; do
    printf '<!-- stale -->\n### old summary\n' \
        > "$IDE_SESSIONS_SUM_CACHE/claude-$RSID$suffix.md"
done
"$ROOT/bin/claude-sessions" --rm "$RSID" --yes >/dev/null 2>&1
left=$(ls "$IDE_SESSIONS_SUM_CACHE" | grep -c "$RSID" || true)
if [ "$left" = 0 ]; then ok "claude: --rm removes the cached summaries"
else nope "claude: --rm removes the cached summaries" "$left file(s) left"; fi

for suffix in "" ".orig"; do
    printf '<!-- stale -->\n### old summary\n' \
        > "$IDE_SESSIONS_SUM_CACHE/codex-$CSID$suffix.md"
done
"$ROOT/bin/codex-sessions" --rm "$CSID" --yes >/dev/null 2>&1
left=$(ls "$IDE_SESSIONS_SUM_CACHE" | grep -c "$CSID" || true)
if [ "$left" = 0 ]; then ok "codex: --rm removes the cached summaries"
else nope "codex: --rm removes the cached summaries" "$left file(s) left"; fi

# A removed summary must be recoverable like everything else --rm touches.
if find "$IDE_SESSIONS_TRASH" -name "codex-$CSID.md" | grep -q .; then
    ok "the removed summary is in the trash"
else
    nope "the removed summary is in the trash" "not found under $IDE_SESSIONS_TRASH"
fi

# ── --rm-all ────────────────────────────────────────────────────────────────
# Deleting everything in one project used to mean --older-than 0, which reads
# as "older than nothing" and appears in no help text.
echo "--rm-all"

# The help has to answer "how do I clear this project" without a reading of the
# source: the combination, not the flags one by one.
for cmd in claude-sessions codex-sessions opencode-sessions; do
    out="$("$ROOT/bin/$cmd" --help 2>&1)"
    contains "$cmd --help shows the scoped form" "$out" "$cmd -p --rm-all --apply"
    contains "$cmd --help shows the refusal"     "$out" "refused: nothing narrows it"
    contains "$cmd --help shows --everywhere"    "$out" "--rm-all --everywhere"
    # Every line that deletes has to say so. An example that only names the
    # selection — "this project, older than 30 days" — is how someone runs a
    # delete believing it is a filter.
    for form in "--rm-all --apply" "--older-than 30 --apply" "--max-turns 20 --apply"; do
        # The usage header at the top names the same forms without explaining
        # them, so the test asks whether ANY line carrying this form says
        # DELETES — that line is the one in the examples.
        if printf '%s\n' "$out" | grep -F -- "$form" | grep -q DELETES; then
            ok "$cmd --help: '$form' says DELETES"
        else
            nope "$cmd --help: '$form' says DELETES" "no line pairs it with the verb"
        fi
    done
done


mkdir -p "$CLAUDE_DIR/projects/-bulk" "$CLAUDE_DIR/projects/-keep"
for i in 1 2 3; do
    python3 - "$CLAUDE_DIR/projects/-bulk/2222222$i-2222-3333-4444-555555555555.jsonl" <<'PY2'
import json, sys
with open(sys.argv[1], 'w') as fh:
    fh.write(json.dumps({"type": "user", "cwd": "/bulk",
                         "timestamp": "2026-03-02T10:00:00.000Z",
                         "message": {"content": [{"type": "text", "text": "x"}]}}) + "\n")
PY2
done
python3 - "$CLAUDE_DIR/projects/-keep/33333333-2222-3333-4444-555555555555.jsonl" <<'PY2'
import json, sys
with open(sys.argv[1], 'w') as fh:
    fh.write(json.dumps({"type": "user", "cwd": "/keep",
                         "timestamp": "2026-03-02T10:00:00.000Z",
                         "message": {"content": [{"type": "text", "text": "y"}]}}) + "\n")
PY2

# The first thing anyone types is the bare flag. On its own it would mean every
# session of every project, so it has to refuse before it is ever run twice.
out="$("$ROOT/bin/claude-sessions" --rm-all 2>&1)"
rc=$?
contains "a bare --rm-all refuses" "$out" "needs something to narrow it"
if [ "$rc" != 0 ]; then ok "a bare --rm-all exits non-zero"
else nope "a bare --rm-all exits non-zero" "exit $rc"; fi
still=$(find "$CLAUDE_DIR/projects" -name '*.jsonl' | wc -l)

out="$("$ROOT/bin/claude-sessions" --rm-all --apply --yes 2>&1)"
now=$(find "$CLAUDE_DIR/projects" -name '*.jsonl' | wc -l)
if [ "$still" = "$now" ]; then ok "a bare --rm-all --apply still deletes nothing"
else nope "a bare --rm-all --apply still deletes nothing" "$still then, $now now"; fi

out="$("$ROOT/bin/claude-sessions" --rm-all --everywhere 2>&1)"
contains "--everywhere names the sweep explicitly" "$out" "Dry run. Nothing deleted"

out="$("$ROOT/bin/claude-sessions" bulk --rm-all 2>&1)"
contains "--rm-all selects the filtered set" "$out" "3 session(s)"
contains "--rm-all dry-runs first"           "$out" "Dry run. Nothing deleted"
left=$(find "$CLAUDE_DIR/projects/-bulk" -name '*.jsonl' | wc -l)
if [ "$left" = 3 ]; then ok "--rm-all without --apply deletes nothing"
else nope "--rm-all without --apply deletes nothing" "$left left"; fi

"$ROOT/bin/claude-sessions" bulk --rm-all --apply --yes >/dev/null 2>&1
gone=$(find "$CLAUDE_DIR/projects/-bulk" -name '*.jsonl' | wc -l)
kept=$(find "$CLAUDE_DIR/projects/-keep" -name '*.jsonl' | wc -l)
if [ "$gone" = 0 ]; then ok "--rm-all --apply deletes the selection"
else nope "--rm-all --apply deletes the selection" "$gone left"; fi
if [ "$kept" = 1 ]; then ok "a project outside the filter is untouched"
else nope "a project outside the filter is untouched" "$kept left"; fi

# ── summary cache ───────────────────────────────────────────────────────────
echo "cache"

export IDE_SESSIONS_SUM_CACHE="$TMP/cache"
mkdir -p "$IDE_SESSIONS_SUM_CACHE"
src_mtime=$(stat -c %Y "$T" 2>/dev/null || stat -f %m "$T")
key="ide-sessions-sum v1 src=$src_mtime model=pinned gap=45 lang=en"
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

# --sum and --sum-orig must not share a cache entry: one file would mean asking
# for the other language silently returns the one already stored.
src_mtime=$(stat -c %Y "$T" 2>/dev/null || stat -f %m "$T")
for lang in en orig; do
    key="ide-sessions-sum v1 src=$src_mtime model=pinned gap=45 lang=$lang"
    suffix=""
    [ "$lang" = orig ] && suffix=".orig"
    { printf '<!-- %s -->\n' "$key"; printf '### %s heading\n' "$lang"; } \
        > "$IDE_SESSIONS_SUM_CACHE/claude-$SID$suffix.md"
done

out="$("$ROOT/bin/claude-sessions" --sum "$SID" --sum-model pinned 2>&1)"
contains "--sum reads the English entry" "$out" "### en heading"

out="$("$ROOT/bin/claude-sessions" --sum "$SID" --sum-orig --sum-model pinned 2>&1)"
contains "--sum-orig reads its own entry"    "$out" "### orig heading"
absent   "--sum-orig does not read English"  "$out" "### en heading"

# --sum-orig <ID> means the same as --sum <ID> --sum-orig; nobody should have to
# name the session through one flag and the language through another.
out="$("$ROOT/bin/claude-sessions" --sum-orig "$SID" --sum-model pinned 2>&1)"
contains "--sum-orig takes the id itself" "$out" "### orig heading"

# …and it must not eat the next flag as an id.
out="$("$ROOT/bin/claude-sessions" --sum-orig --sum "$SID" --sum-model pinned 2>&1)"
contains "a flag after --sum-orig stays a flag" "$out" "### orig heading"

# ── billing ─────────────────────────────────────────────────────────────────
# billing only lays out what ccusage reports, so ccusage is replaced by a stub
# that prints canned JSON in the shape ccusage 20 writes. What is checked is
# the layout and the lookup — the numbers are ccusage's business.
echo "billing"

STUB="$TMP/ccusage-stub"
mkdir -p "$STUB"
cat > "$STUB/ccusage" <<'SH'
#!/usr/bin/env bash
case "$1" in
  daily|weekly|monthly|session|blocks) cat "$(dirname "$0")/$1.json" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$STUB/ccusage"

cat > "$STUB/daily.json" <<'JSON'
{"daily": [
  {"period": "2026-03-02", "inputTokens": 300, "outputTokens": 3000,
   "cacheCreationTokens": 30000, "cacheReadTokens": 966700, "totalTokens": 1000000,
   "totalCost": 3.0,
   "agents": [{"agent": "claude", "totalCost": 2.0, "inputTokens": 100, "outputTokens": 2000,
               "cacheCreationTokens": 30000, "cacheReadTokens": 467900, "totalTokens": 500000},
              {"agent": "codex", "totalCost": 1.0, "inputTokens": 200, "outputTokens": 1000,
               "cacheCreationTokens": 0, "cacheReadTokens": 498800, "totalTokens": 500000}]},
  {"period": "2026-03-01", "inputTokens": 10, "outputTokens": 90,
   "cacheCreationTokens": 0, "cacheReadTokens": 0, "totalTokens": 100,
   "totalCost": 0.5,
   "agents": [{"agent": "opencode", "totalCost": 0.5, "inputTokens": 10, "outputTokens": 90,
               "cacheCreationTokens": 0, "cacheReadTokens": 0, "totalTokens": 100}]}
]}
JSON

cat > "$STUB/monthly.json" <<'JSON'
{"monthly": [
  {"period": "2026-03", "inputTokens": 310, "outputTokens": 3090,
   "cacheCreationTokens": 30000, "cacheReadTokens": 966700, "totalTokens": 1000100,
   "totalCost": 3.5, "agents": []}
]}
JSON

cat > "$STUB/weekly.json" <<'JSON'
{"weekly": [
  {"period": "2026-03-02", "inputTokens": 310, "outputTokens": 3090,
   "cacheCreationTokens": 30000, "cacheReadTokens": 966700, "totalTokens": 1000100,
   "totalCost": 3.5, "agents": []}
]}
JSON

cat > "$STUB/blocks.json" <<'JSON'
{"blocks": [
  {"isActive": true, "startTime": "2026-03-02T10:00:00.000Z", "endTime": "2026-03-02T15:00:00.000Z",
   "models": ["claude-opus-5-5"], "costUSD": 4.5, "totalTokens": 2000000,
   "tokenCounts": {"inputTokens": 10, "outputTokens": 20000,
                   "cacheCreationInputTokens": 30000, "cacheReadInputTokens": 1949990},
   "burnRate": {"costPerHour": 1.5}, "projection": {"totalCost": 7.25, "totalTokens": 3500000}}
]}
JSON

# Codex logs the limits its server reported beside every token count. The reset
# time is in the past, so the reading must say it is out of date.
CXR="$CODEX_HOME/sessions/2026/03/03/rollout-2026-03-03T09-00-00-01a00000-0000-7000-8000-000000000011.jsonl"
mkdir -p "$(dirname "$CXR")"
printf '%s\n' '{"timestamp":"2026-03-03T09:05:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":37.0,"window_minutes":10080,"resets_at":1772500000},"secondary":null}}}' > "$CXR"

cat > "$STUB/session.json" <<'JSON'
{"session": [
  {"agent": "claude", "period": "aa000000-0000-4000-8000-000000000001",
   "inputTokens": 1234, "outputTokens": 5678, "cacheCreationTokens": 9000,
   "cacheReadTokens": 1000000, "totalTokens": 1015912, "totalCost": 12.345,
   "modelsUsed": ["claude-opus-5-5"], "metadata": {"lastActivity": "2026-03-02T10:00:00Z"},
   "modelBreakdowns": [{"modelName": "claude-opus-5-5", "inputTokens": 1234,
     "outputTokens": 5678, "cacheCreationTokens": 9000, "cacheReadTokens": 1000000,
     "cost": 12.345}]},
  {"agent": "claude", "period": "aa000000-0000-4000-8000-000000000002",
   "inputTokens": 1, "outputTokens": 1, "cacheCreationTokens": 0, "cacheReadTokens": 0,
   "totalTokens": 2, "totalCost": 0.01, "modelsUsed": [], "metadata": {},
   "modelBreakdowns": []},
  {"agent": "codex",
   "period": "2026/03/02/rollout-2026-03-02T13-00-00-01a00000-0000-7000-8000-000000000007",
   "inputTokens": 500, "outputTokens": 50, "cacheCreationTokens": 0, "cacheReadTokens": 450,
   "totalTokens": 1000, "totalCost": 0.25, "modelsUsed": ["gpt-5.6-sol"],
   "metadata": {"lastActivity": "2026-03-02T13:05:00Z", "reasoningOutputTokens": 20},
   "modelBreakdowns": [{"modelName": "gpt-5.6-sol", "inputTokens": 500, "outputTokens": 50,
     "cacheCreationTokens": 0, "cacheReadTokens": 450, "cost": 0.25}]}
]}
JSON

bill() { CCUSAGE_BIN="$STUB/ccusage" "$ROOT/bin/billing" "$@" 2>&1; }

out="$(bill)"
contains "billing: a column per IDE when no IDE is named" "$out" "claude     codex  opencode"
# A bare table of dates read as a data dump: the first line says what it is.
contains "billing: the table says what it is"  "$(printf '%s\n' "$out" | head -1)" "Cost per day · all IDEs · days with no usage are not listed"
contains "billing: and which rows it holds"    "$out" "all 2 days with usage, 2026-03-01 … 2026-03-02"
contains "billing: periods run oldest first"   "$(printf '%s\n' "$out" | awk '/^DAY /{getline; print; exit}')" "2026-03-01"
# TOTAL is also a column header, so the row is looked for where it belongs.
last="$(printf '%s\n' "$out" | tail -1)"
contains "billing: the last row is TOTAL"      "$last" 'TOTAL '
contains "billing: TOTAL adds the costs up"    "$last" '$3.50'
contains "billing: cache share of the total"   "$out" '97%'

out="$(bill --ide codex)"
absent   "billing --ide: no per-IDE columns"   "$out" "opencode"
contains "billing --ide: that IDE's share"     "$out" '$1.00'
absent   "billing --ide: other IDEs' days go"  "$out" "2026-03-01"

out="$(bill -n 1)"
contains "billing -n: says what it cut"        "$out" "last 1 of 2 days with usage"

out="$(bill months)"
contains "billing months: monthly rows"        "$out" "2026-03 "
contains "billing months: says so"             "$out" "Cost per calendar month"
contains "billing month still works"           "$(bill month)" "Cost per calendar month"

# `billing week` read as "one week". The verb is plural and the row names
# both ends of the week.
out="$(bill weeks)"
contains "billing weeks: Monday to Sunday"     "$out" "Cost per week (Monday to Sunday)"
contains "billing weeks: a row names its Sunday" "$out" "2026-03-02 … 03-08"

contains "billing today: one day, named"       "$(bill today)" "Cost today ("

out="$(bill block)"
contains "billing block: every IDE, one heading" "$out" "Usage limits · where each IDE stands now"
contains "billing block: the Claude window"    "$out" "Claude Code · the current 5-hour window"
contains "billing block: its projection"       "$out" '$7.25'
contains "billing block: Codex limits from its log" "$out" "weekly window (7 days):    37% used, 63% left"
contains "billing block: a past reset says the reading is old" "$out" "this reading is out of date"
contains "billing block: opencode, honestly"   "$out" "opencode · keeps no usage-limit data locally"
out="$(bill block --ide codex)"
absent   "billing block --ide: one IDE only"   "$out" "Claude Code ·"
contains "billing live still works"            "$(bill live)" "Usage limits"

out="$(CCUSAGE_BIN="$TMP/no-such-ccusage" "$ROOT/bin/billing" --help 2>&1)"
contains "billing --help: one --id form for every IDE" "$out" "billing --id ses_f4ba6fcd         an opencode session"

out="$(bill --id aa000000-0000-4000-8000-000000000001)"
contains "billing --id: the session"           "$out" "Session:       aa000000-0000-4000-8000-000000000001"
contains "billing --id: a row per model"       "$out" "claude-opus-5-5"
contains "billing --id: exact counts"          "$out" "1,015,912"
contains "billing --id: cost to the cent"      "$out" '$12.35'

out="$(bill --id 01a00000-0000-7000)"
contains "billing --id: a codex uuid finds its transcript path" "$out" "Transcript:    2026/03/02/rollout"
contains "billing --id: codex reasoning tokens" "$out" "Reasoning:     20 output tokens"

out="$(bill --id aa000000; echo "EXIT=$?")"
contains "billing --id: an ambiguous prefix lists the candidates" "$out" "matches 2 sessions"
contains "billing --id: ambiguous is exit 1"   "$out" "EXIT=1"

out="$(bill --id aa000000 --ide codex; echo "EXIT=$?")"
contains "billing --id --ide: narrows to that IDE" "$out" 'no session matches "aa000000" in codex'

out="$(CCUSAGE_BIN="$TMP/no-such-ccusage" "$ROOT/bin/billing" 2>&1; echo "EXIT=$?")"
contains "billing without ccusage says how to install it" "$out" "npm install -g ccusage"
contains "billing without ccusage is exit 127" "$out" "EXIT=127"

out="$(CCUSAGE_BIN="$TMP/no-such-ccusage" "$ROOT/bin/billing" --help 2>&1)"
contains "billing --help needs no ccusage"     "$out" "ONE SESSION"

out="$(bill dates; echo "EXIT=$?")"
contains "billing: a removed view names its replacement" "$out" "billing --id ID"

# ── --list-models ───────────────────────────────────────────────────────────
# What --sum-model accepts, from where each IDE keeps it. Built last, so no
# session added here changes a count an earlier test depends on.
echo "--list-models"

mkdir -p "$CLAUDE_DIR/projects/-models-probe"
printf '%s\n' '{"type":"assistant","timestamp":"2026-03-04T10:00:00.000Z","message":{"model":"claude-probe-9","content":[]}}' \
    > "$CLAUDE_DIR/projects/-models-probe/99999999-0000-4000-8000-000000000099.jsonl"
out="$("$ROOT/bin/claude-sessions" --list-models 2>&1)"
contains "claude --list-models: the aliases"            "$out" "haiku        fast and efficient"
contains "claude --list-models: names the account ran"  "$out" "claude-probe-9"
contains "claude --list-models: the default, no catalogue" "$out" "Model for --sum by default: haiku"
contains "claude --list-model is the same flag"         "$("$ROOT/bin/claude-sessions" --list-model 2>&1)" "Aliases"

cat > "$CODEX_HOME/models_cache.json" <<'JSON'
{"fetched_at": "2026-03-04T10:00:00Z", "models": [
  {"slug": "gpt-probe-sol", "display_name": "GPT-Probe-Sol", "visibility": "list"},
  {"slug": "gpt-probe-hidden", "display_name": "GPT-Probe-Hidden", "visibility": "hide"}]}
JSON
printf 'model = "gpt-probe-sol"\n' > "$CODEX_HOME/config.toml"
out="$("$ROOT/bin/codex-sessions" --list-models 2>&1)"
contains "codex --list-models: the slug and its name"   "$out" "gpt-probe-sol            GPT-Probe-Sol  ← config.toml"
contains "codex --list-models: hidden ones apart"       "$out" "In the catalogue, hidden from the Codex picker"
contains "codex --list-models: the default"             "$out" "Model for --sum by default: gpt-probe-sol"

# opencode lists its own models; a stub stands in for it, with one provider
# connected through auth.json and one only through an environment variable.
mkdir -p "$TMP/stub-models"
cat > "$TMP/stub-models/opencode" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "models ") printf '%s\n' copilot-probe/model-a copilot-probe/model-b envonly/model-x opencode/free-1 ;;
  "models envonly") printf '%s\n' envonly/model-x ;;
  "auth list") printf '%s\n' '┌  Credentials' '●  Copilot Probe oauth' '└  1 credentials' \
                              '┌  Environment' '●  Envonly ENVONLY_API_KEY' '└  1 environment variable' ;;
esac
SH
chmod +x "$TMP/stub-models/opencode"
out="$(PATH="$TMP/stub-models:$PATH" "$ROOT/bin/opencode-sessions" --list-models 2>&1)"
contains "opencode --list-models: a connected provider" "$out" "copilot-probe — 2 model(s) · credential in auth.json (oauth)"
contains "opencode --list-models: the built-in one"     "$out" "opencode — 1 model(s) · built into opencode"
absent   "opencode --list-models: an env-only key is not a provider" "$out" "  envonly/model-x"
contains "opencode --list-models: but says it left one out" "$out" "not listed: envonly — 1 model(s)"
out="$(PATH="$TMP/stub-models:$PATH" "$ROOT/bin/opencode-sessions" --list-models envonly 2>&1)"
contains "opencode --list-models P: asked by name, shown" "$out" "  envonly/model-x"

# ── report ──────────────────────────────────────────────────────────────────
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
