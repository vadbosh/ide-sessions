#!/usr/bin/env bash
# Install the ide-sessions tools — Linux / macOS.
#
#   ./install.sh                 install the five commands on PATH, and the
#                                history skill and /history command into
#                                every assistant found
#   ./install.sh --dry-run       print what would happen, change nothing
#   ./install.sh --bin-dir D     install the commands into D instead of ~/.local/bin
#   ./install.sh --uninstall     remove everything this script installed
#
# The three session commands are independent: each one reads only its own
# IDE's storage, so installing all of them on a machine that has one IDE is
# harmless — the others simply report that they found nothing. billing reads
# all three through ccusage and says how to install it when it is missing.
#
# agent-history reads the prompt history all three IDEs keep across sessions;
# the history skill (claude, codex, opencode) and the /history command (claude,
# opencode — codex has no user commands) are how an assistant runs it.
#
# Idempotent: re-running replaces only what changed. A file it overwrites is
# backed up ONLY when that content is not already in the source repository — a
# hand edit is the one thing git cannot give back. A command is backed up next
# to itself; a skill or command file of an assistant goes to
# ~/.local/state/ide-sessions/backups/, outside every directory an assistant
# reads, so a backup never loads as a second skill.
# Nothing outside $HOME is touched.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${IDE_SESSIONS_BIN_DIR:-$HOME/.local/bin}"
STAMP="$(date +%Y%m%d-%H%M%S)"
COMMANDS="claude-sessions codex-sessions opencode-sessions billing agent-history"
BACKUPS="${XDG_STATE_HOME:-$HOME/.local/state}/ide-sessions/backups"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

DRY_RUN=0
UNINSTALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)   DRY_RUN=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --bin-dir)   BIN_DIR="${2:-}"; shift ;;
        -h|--help)   sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# Colour only when stdout is a terminal — piping into a log must stay clean.
if [ -t 1 ]; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_BAD=$'\033[31m'; C_OFF=$'\033[0m'
else
    C_OK=''; C_WARN=''; C_BAD=''; C_OFF=''
fi

say()  { printf '%s\n' "$*"; }
ok()   { printf '%s%s%s\n' "$C_OK"   "$*" "$C_OFF"; }
warn() { printf '%s%s%s\n' "$C_WARN" "$*" "$C_OFF"; }
bad()  { printf '%s%s%s\n' "$C_BAD"  "$*" "$C_OFF"; }
tilde() { printf '%s' "${1/#$HOME/\~}"; }

# Is this exact content already in the source repository's object database?
# Then it is one `git checkout` away and a copy of it is worth nothing. Only a
# hand edit — content git has never seen — is worth a backup.
in_git_history() {
    local sha
    command -v git >/dev/null 2>&1 || return 1
    git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1 || return 1
    sha="$(git -C "$SRC" hash-object "$1" 2>/dev/null)" || return 1
    [ -n "$sha" ] && git -C "$SRC" cat-file -e "$sha" 2>/dev/null
}

install_file() {     # install_file SRC DST [MODE] [BACKUP_DIR]
    local src="$1" dst="$2" mode="${3:-755}" bdir="${4:-}"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        say "    = $(tilde "$dst")"
        return 0
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        say "    would write $(tilde "$dst")"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ]; then
        if in_git_history "$dst"; then
            say "    ~ $(tilde "$dst")"
        elif [ -n "$bdir" ]; then
            mkdir -p "$bdir"
            cp -p "$dst" "$bdir/$(basename "$(dirname "$dst")")-$(basename "$dst").bak.$STAMP"
            say "    ~ $(tilde "$dst")  (backup in $(tilde "$bdir") — not in git)"
        else
            cp -p "$dst" "$dst.bak.$STAMP"
            say "    ~ $(tilde "$dst")  (backup .bak.$STAMP — edited by hand, not in git)"
        fi
    else
        say "    + $(tilde "$dst")"
    fi
    cp "$src" "$dst"
    chmod "$mode" "$dst"
}

# Where each assistant found on this machine reads the history skill and the
# /history command. Codex has no user commands; it finds a skill in
# ~/.codex/skills by itself, config.toml only switches one off.
assistant_files() {  # prints: SRC DST, one pair per line
    [ -d "$CLAUDE_DIR" ] && printf '%s %s\n' \
        skills/history/SKILL.md "$CLAUDE_DIR/skills/history/SKILL.md" \
        commands/history.md     "$CLAUDE_DIR/commands/history.md"
    [ -d "$CODEX_DIR" ] && printf '%s %s\n' \
        skills/history/SKILL.md "$CODEX_DIR/skills/history/SKILL.md"
    [ -d "$OPENCODE_DIR" ] && printf '%s %s\n' \
        skills/history/SKILL.md "$OPENCODE_DIR/skills/history/SKILL.md" \
        commands/history.md     "$OPENCODE_DIR/commands/history.md"
    return 0
}

# ── uninstall ───────────────────────────────────────────────────────────────
if [ "$UNINSTALL" -eq 1 ]; then
    say "── uninstall ──"
    for cmd in $COMMANDS; do
        dst="$BIN_DIR/$cmd"
        if [ ! -f "$dst" ]; then
            say "    - $(tilde "$dst") not there"
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            say "    would remove $(tilde "$dst")"
        else
            rm -f "$dst"
            say "    - $(tilde "$dst")"
        fi
    done
    while read -r _ dst; do
        [ -f "$dst" ] || continue
        if [ "$DRY_RUN" -eq 1 ]; then
            say "    would remove $(tilde "$dst")"
        else
            rm -f "$dst"
            rmdir "$(dirname "$dst")" 2>/dev/null || true   # an emptied skills/history/
            say "    - $(tilde "$dst")"
        fi
    done < <(assistant_files)
    say ""
    say "  Cached summaries and the trash dir are left alone:"
    say "    $(tilde "${IDE_SESSIONS_SUM_CACHE:-$HOME/.cache/ide-sessions-summaries}")"
    say "    $(tilde "${IDE_SESSIONS_TRASH:-$HOME/.cache/ide-sessions-trash}")"
    exit 0
fi

# ── prerequisites ───────────────────────────────────────────────────────────
# python3 does the parsing in all three scripts and reads opencode's sqlite
# database; without it only the bash skeleton would run.
if ! command -v python3 >/dev/null 2>&1; then
    bad "python3 is required and was not found."
    warn "  Debian/Ubuntu: sudo apt install python3"
    warn "  macOS:         brew install python@3.12"
    exit 1
fi
ok "python3 — $(python3 --version 2>&1)"

# ── install ─────────────────────────────────────────────────────────────────
say "── commands ──"
say "  $(tilde "$BIN_DIR")"
for cmd in $COMMANDS; do
    install_file "$SRC/bin/$cmd" "$BIN_DIR/$cmd"
done

say "── history skill and /history ──"
while read -r src dst; do
    install_file "$SRC/$src" "$dst" 644 "$BACKUPS"
done < <(assistant_files)

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "    $(tilde "$BIN_DIR") is not on PATH. Add it:"
       say  "        echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc" ;;
esac

# ── what is present on this machine ─────────────────────────────────────────
# Each command reads one IDE's storage. Saying up front which of them will find
# anything is cheaper than three empty listings.
say "── IDEs found ──"
[ -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" ] \
    && ok   "    claude-sessions   — transcripts found" \
    || warn "    claude-sessions   — no ~/.claude/projects, will list nothing"
[ -d "${CODEX_HOME:-$HOME/.codex}/sessions" ] \
    && ok   "    codex-sessions    — rollouts found" \
    || warn "    codex-sessions    — no ~/.codex/sessions, will list nothing"
[ -f "${OPENCODE_DATA_DIR:-$HOME/.local/share/opencode}/opencode.db" ] \
    && ok   "    opencode-sessions — database found" \
    || warn "    opencode-sessions — no opencode.db, will list nothing"

# billing prices the sessions through ccusage and lays the tables out with jq.
# Missing either, it installs anyway and says what to install when it runs.
say "── billing ──"
command -v "${CCUSAGE_BIN:-ccusage}" >/dev/null 2>&1 \
    && ok   "    ccusage — $("${CCUSAGE_BIN:-ccusage}" --version 2>/dev/null | head -1)" \
    || warn "    ccusage — not found: npm install -g ccusage"
command -v jq >/dev/null 2>&1 \
    && ok   "    jq      — $(jq --version 2>/dev/null)" \
    || warn "    jq      — not found: apt install jq (or brew install jq)"

# --sum spends one model call through that IDE's own CLI. Absent CLI, --sum-raw
# still prints the digest, and that is worth knowing before the first failure.
say "── CLIs for --sum ──"
for cli in claude codex opencode; do
    if command -v "$cli" >/dev/null 2>&1; then
        ok   "    $cli — $(command -v "$cli")"
    else
        warn "    $cli — not found; --sum will refuse, --sum-raw still works"
    fi
done

# ── verify ──────────────────────────────────────────────────────────────────
say "── verify ──"
if [ "$DRY_RUN" -eq 1 ]; then
    warn "  dry run — nothing was installed"
    exit 0
fi
failed=0
for cmd in $COMMANDS; do
    if "$BIN_DIR/$cmd" --help >/dev/null 2>&1; then
        ok "  ok — $(tilde "$BIN_DIR/$cmd")"
    else
        bad "  installed, but $(tilde "$BIN_DIR/$cmd") did not run"
        failed=1
    fi
done
[ "$failed" -eq 0 ] || exit 1

say ""
say "  History:   agent-history claude sessions all 10   ·   /history in Claude Code or Opencode"
say "  List:      claude-sessions"
say "  Summarize: claude-sessions --sum <SESSION ID>"
say "  Free look: claude-sessions --sum <SESSION ID> --sum-raw"
