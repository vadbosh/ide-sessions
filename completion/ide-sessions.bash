# Bash completion for the ide-sessions commands: Tab offers the options, the
# subcommands, and the ids of the sessions of the CURRENT directory — only
# those, never the sessions of other projects.
#
#   claude-sessions codex-sessions opencode-sessions   options; --rm, --sum,
#                                                      --sum-orig: session ids
#   ide-history billing                                options, subcommands;
#                                                      --id: session ids
#   claude-procs codex-procs opencode-procs            subcommands, options;
#                                                      fg, resume: window pids
#   dev-soft-clean.sh                                  options
#
# ./install.sh puts this file into ~/.local/share/bash-completion/completions/
# once under the name of each command, because bash-completion loads a file by
# the name of the command Tab is pressed after. Without the bash-completion
# package, source it from ~/.bashrc instead.
#
# The ids come straight from each IDE's own storage, read-only, in well under a
# tenth of a second; running the commands themselves would take seconds per
# Tab. "This directory" is what -p means in each command:
#   Claude Code  the *.jsonl in the project dir named after $PWD
#   Codex        the rollouts whose session_meta cwd is $PWD; subagent
#                rollouts are folded into their session, as codex-sessions does
#   opencode     the sessions whose directory is $PWD (opencode 2.x and 1.x)
#
# The tests compare every option list below with the command's --help, so a
# new option fails them until it is added here.

_ides_sessions_opts="-n -f -p --about-min --search --min-hits --all --sum --sum-model
--list-models --sum-gap --sum-refresh --sum-raw --sum-orig --rm --rm-all --everywhere
--older-than --max-turns --apply --yes --dry-run --trash --help"
_ides_history_opts="--id --full --grep --ide --since --until -p -n --json --help"
_ides_history_subs="sessions"
_ides_billing_opts="--id --ide --since --until -n --json --help"
_ides_billing_subs="days weeks months today block"
_ides_procs_subs="list fg resume clean"
_ides_clean_opts="--dry-run --apply --uv-clean --help"
_ides_ides="claude codex opencode"

# ── session ids of $PWD, newest first ───────────────────────────────────────
_ides_ids_claude() {
    local dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/${PWD//[^a-zA-Z0-9]/-}" f
    [ -d "$dir" ] || return 0
    # ls -t: newest first; the names are uuids, nothing to quote
    for f in $(cd "$dir" && ls -t -- *.jsonl 2>/dev/null); do
        printf '%s\n' "${f%.jsonl}"
    done
}

_ides_ids_codex() {
    local dir="${CODEX_HOME:-$HOME/.codex}/sessions"
    [ -d "$dir" ] && command -v python3 >/dev/null 2>&1 || return 0
    python3 -I -c '
import json, os, sys
root, want = sys.argv[1], sys.argv[2]
found = []
for dirpath, _, names in os.walk(root):
    for name in names:
        if not (name.startswith("rollout-") and name.endswith(".jsonl")):
            continue
        f = os.path.join(dirpath, name)
        try:
            with open(f, "rb") as fh:
                p = json.loads(fh.readline()).get("payload") or {}
            mtime = os.stat(f).st_mtime
        except (OSError, ValueError, AttributeError):
            continue
        if not isinstance(p, dict):
            continue
        sid = p.get("id") or p.get("session_id") or ""
        if not sid:
            continue
        src, spawn = p.get("source"), {}
        if isinstance(src, dict) and isinstance(src.get("subagent"), dict):
            spawn = src["subagent"].get("thread_spawn") or {}
        parent = p.get("parent_thread_id") or spawn.get("parent_thread_id") or ""
        if not parent and p.get("thread_source") == "subagent":
            parent = p.get("session_id") or ""
        if parent == sid:
            parent = ""
        found.append((mtime, sid, p.get("cwd") or "", parent))
parent_of = {r[1]: r[3] for r in found}
top = {r[1] for r in found if not r[3]}
def root_of(sid):
    seen = set()
    while parent_of.get(sid) and sid not in seen:
        seen.add(sid)
        sid = parent_of[sid]
    return sid
for mtime, sid, cwd, parent in sorted(found, reverse=True):
    if cwd == want and not (parent and root_of(sid) in top):
        print(sid)
' "$dir" "$PWD" 2>/dev/null
}

_ides_ids_opencode() {
    local db="${OPENCODE_DATA_DIR:-$HOME/.local/share/opencode}/opencode.db"
    [ -f "$db" ] && command -v python3 >/dev/null 2>&1 || return 0
    python3 -I -c '
import sqlite3, sys
con = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True, timeout=2)
v2 = con.execute("SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?",
                 ("table", "session_v2")).fetchone()
table = "session_v2" if v2 else "session"
for (sid,) in con.execute("SELECT id FROM %s WHERE directory = ? "
                          "ORDER BY time_updated DESC" % table, (sys.argv[2],)):
    print(sid)
' "$db" "$PWD" 2>/dev/null
}

# ── helpers ─────────────────────────────────────────────────────────────────
# _ides_reply WORDS — the words that start with the current word, in the order
# given (newest session first), not sorted by bash.
_ides_reply() {
    mapfile -t COMPREPLY < <(compgen -W "$1" -- "$cur")
    compopt -o nosort 2>/dev/null
}

# _ides_reply_ids WORDS — as _ides_reply, for --rm ID,ID,...: after a comma the
# ids are matched against what follows it, and the part before stays.
_ides_reply_ids() {
    local pre="" part="$cur" i
    case "$cur" in *,*) pre="${cur%,*},"; part="${cur##*,}" ;; esac
    mapfile -t COMPREPLY < <(compgen -W "$1" -- "$part")
    for i in "${!COMPREPLY[@]}"; do COMPREPLY[i]="$pre${COMPREPLY[i]}"; done
    compopt -o nosort 2>/dev/null
}

# _ides_unused OPTIONS — the options not yet on the line; _ides_opts offers them.
# The word under the cursor does not count: `-p<Tab>` completes -p itself.
_ides_unused() {
    local o i out=""
    for o in $1; do
        for ((i = 1; i < ${#COMP_WORDS[@]}; i++)); do
            [ "$i" -ne "$COMP_CWORD" ] && [ "${COMP_WORDS[i]}" = "$o" ] && continue 2
        done
        out+=" $o"
    done
    printf '%s' "$out"
}
_ides_opts() { _ides_reply "$(_ides_unused "$1")"; }

# _ides_ide_of — the --ide value already on the line, if any.
_ides_ide_of() {
    local i
    for ((i = 1; i < COMP_CWORD; i++)); do
        [ "${COMP_WORDS[i]}" = --ide ] && { printf '%s' "${COMP_WORDS[i+1]:-}"; return; }
    done
}

# ── the commands ────────────────────────────────────────────────────────────
_ides_sessions() {
    local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
    local ide="${1%-sessions}"
    ide="${ide##*/}"
    COMPREPLY=()
    case "$prev" in
        --rm|--sum|--sum-orig) _ides_reply_ids "$("_ides_ids_$ide")"; return 0 ;;
        --trash) compopt -o dirnames 2>/dev/null; return 0 ;;
        # a number, a pattern or a model name: nothing to offer
        -n|--about-min|--search|--min-hits|--sum-model|--sum-gap|--older-than|--max-turns)
            return 0 ;;
    esac
    # A word that is not an option is a directory substring: nothing to offer
    # for it, so an empty word gets the options.
    case "$cur" in
        -*|'') _ides_opts "$_ides_sessions_opts" ;;
    esac
    return 0
}

_ides_history() {
    local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
    local subs opts ide i ids=""
    COMPREPLY=()
    case "${1##*/}" in
        billing) subs="$_ides_billing_subs" opts="$_ides_billing_opts" ;;
        *)       subs="$_ides_history_subs" opts="$_ides_history_opts" ;;
    esac
    case "$prev" in
        --ide) _ides_reply "$_ides_ides"; return 0 ;;
        --id)
            ide="$(_ides_ide_of)"
            for i in $_ides_ides; do
                [ -z "$ide" ] || [ "$ide" = "$i" ] || continue
                ids+=" $("_ides_ids_$i")"
            done
            _ides_reply "$ids"; return 0 ;;
        --since|--until|--grep|-n) return 0 ;;
    esac
    case "$cur" in
        -*) _ides_opts "$opts" ;;
        # an empty word: the subcommand, if none is on the line yet, then the
        # options
        *)  for ((i = 1; i < COMP_CWORD; i++)); do
                case " $subs " in *" ${COMP_WORDS[i]} "*) subs="" ;; esac
            done
            [ -z "$cur" ] && subs+=" $(_ides_unused "$opts")"
            _ides_reply "$subs" ;;
    esac
    return 0
}

_ides_procs() {
    local cur="${COMP_WORDS[COMP_CWORD]}" sub="${COMP_WORDS[1]:-}"
    local comm="${1%-procs}"
    comm="${comm##*/}"
    COMPREPLY=()
    if [ "$COMP_CWORD" -eq 1 ]; then _ides_reply "$_ides_procs_subs --help"; return 0; fi
    case "$sub" in
        fg|resume)
            case "$cur" in
                -*) if [ "$sub" = fg ]; then _ides_opts "--no-mark"
                    else _ides_opts "-n --dry-run"; fi ;;
                # the windows: processes of that name on a terminal; a
                # background service (codex app-server, opencode serve) has none
                *)  _ides_reply "$(ps -C "$comm" -o pid=,tty= 2>/dev/null |
                                   awk '$2 != "?" { print $1 }')" ;;
            esac ;;
        clean) _ides_opts "--apply" ;;
    esac
    return 0
}

_ides_clean() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()
    _ides_opts "$_ides_clean_opts"
    return 0
}

# ── your own resume function ────────────────────────────────────────────────
# For a shell function or alias that takes a session id as its first argument,
# such as  ccr() { claude --resume "$1"; }  — not registered here, the name is
# yours. Two lines in ~/.bashrc, after the function:
#   . ~/.local/share/bash-completion/completions/claude-sessions
#   complete -F _ides_resume_claude ccr
# The first line is needed because bash-completion loads this file only on the
# first Tab after one of the commands above, and it does not know ccr.
# `claude --resume` finds only the sessions of the current directory's project,
# so those are the ids offered.
_ides_resume() {   # _ides_resume IDE
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()
    [ "$COMP_CWORD" -eq 1 ] && _ides_reply "$("_ides_ids_$1")"
    return 0
}
_ides_resume_claude()   { _ides_resume claude; }
_ides_resume_codex()    { _ides_resume codex; }
_ides_resume_opencode() { _ides_resume opencode; }

complete -F _ides_sessions claude-sessions codex-sessions opencode-sessions
complete -F _ides_history ide-history billing
complete -F _ides_procs claude-procs codex-procs opencode-procs
complete -F _ides_clean dev-soft-clean.sh
