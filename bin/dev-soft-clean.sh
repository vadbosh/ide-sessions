#!/usr/bin/env bash
set -euo pipefail

# Soft cleanup for dev caches.
# Default: dry-run (no changes).
# Safe for OpenCode/Claude Code runtime files; for Codex and Claude Code,
# removes only stale binary releases and keeps the live one.

MODE="dry-run"
NPX_DAYS=7
LOG_DAYS=14
TOTAL_STEPS=12
STEP=0
UV_PRUNE_TIMEOUT_SEC=20

# Dedicated uv cache for the Qdrant MCP server (uvx mcp-server-qdrant), set via
# UV_CACHE_DIR in its MCP env. The default `uv cache prune` does NOT cover it.
#
# Read the path out of mcp.json instead of hardcoding it. The hardcoded
# /AI_P/Qdrant-MCP/uv-cache went stale when the cache moved, and for months this
# script dutifully pruned 679MB of nothing while the live cache grew to 10GB —
# 41 archived copies of the same onnxruntime/numpy environment. A wrong path
# here fails silently, so it has to follow the config that actually runs.
QDRANT_UV_CACHE_FALLBACK="$HOME/.cache/mcp-server-qdrant/uv-cache"
QDRANT_UV_CACHE=$(
  jq -r '.mcpServers.qdrant.env.UV_CACHE_DIR // empty' "$HOME/.claude/mcp.json" 2>/dev/null || true
)
[[ -n "$QDRANT_UV_CACHE" ]] || QDRANT_UV_CACHE="$QDRANT_UV_CACHE_FALLBACK"
QDRANT_UV_CACHE="${QDRANT_UV_CACHE/#\~/$HOME}"

# Codex app-server daemon keeps every auto-updated release (~400MB each) and
# never removes the old ones. The live one is what `current` points at;
# `auto-update-version` names the same release after an update.
CODEX_DAEMON_DIR="$HOME/.codex/packages/app-server-daemon"

# Claude Code native installer leaves one ~270MB binary per version in
# versions/; the live one is what the `claude` launcher symlink points at.
CLAUDE_VERSIONS_DIR="$HOME/.local/share/claude/versions"
CLAUDE_LAUNCHER="$HOME/.local/bin/claude"

# Opencode plugin cache. Up to ~Oct 2026 plugins lived in packages/, with
# superseded installs moved aside to packages/.stale/<pkg>.<epoch>. Opencode
# 2.x installs into npm/<pkg>/<epoch>/ instead and loads only the newest
# <epoch> (numeric sort, last one); its binary has no path to packages/ at all.
# So once npm/ exists, packages/ is a dead layout and goes whole; without npm/
# only packages/.stale goes. models.json.<pid>.<ms>.tmp are interrupted writes
# of models.json.
OPENCODE_CACHE_DIR="$HOME/.cache/opencode"

# Claude Code marks a superseded plugin version with .orphaned_at but leaves
# it in the cache: claude-hud 0.10.0 still sat there 10 days after its mark
# (~45MB per claude-hud version). installed_plugins.json names the live ones.
CLAUDE_PLUGIN_CACHE="$HOME/.claude/plugins/cache"
CLAUDE_PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"

CACHE_LOCK_PATHS=(
  "$HOME/.cache/uv"
  "$HOME/.npm"
  "$HOME/.bun/install"
  "$HOME/.cache/pip"
  "$HOME/.cache/opencode"
  "$QDRANT_UV_CACHE"
)

if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_GREEN='\033[0;32m'
  C_YELLOW='\033[0;33m'
  C_CYAN='\033[0;36m'
  C_RED='\033[0;31m'
  C_BOLD='\033[1m'
else
  C_RESET=''
  C_GREEN=''
  C_YELLOW=''
  C_CYAN=''
  C_RED=''
  C_BOLD=''
fi

# `uv cache prune` only drops UNREACHABLE objects. Measured 2026-08-17: on the
# qdrant cache that was nearly everything (11G -> 289M, its ephemeral uvx
# environments lose their references), but on ~/.cache/uv it freed 39.6MB out of
# 6.3GB — those are unpacked wheels (polars alone is 196MB per version), all of
# them still "reachable", so prune will never touch them no matter how often it
# runs. `uv cache clean` wipes the cache outright and is the only thing that
# reclaims that space. Opt-in, never the default: the next install or upgrade of
# any package re-downloads and re-unpacks. Installed uv tools survive it —
# ~/.local/share/uv/tools holds its own venvs, hardlinked to the cache, and a
# file lives as long as any link to it does.
UV_CLEAN=0

for arg in "$@"; do
  case "$arg" in
    --apply)     MODE="apply" ;;
    --dry-run)   MODE="dry-run" ;;
    --uv-clean)  UV_CLEAN=1 ;;
    *)
      echo "Usage: $(basename "$0") [--dry-run|--apply] [--uv-clean]" >&2
      echo "  --uv-clean  wipe uv caches entirely (uv cache clean) instead of" >&2
      echo "              pruning them — reclaims reachable wheels, forces re-download" >&2
      exit 1
      ;;
  esac
done

for cmd in du python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
done

# A uv cache is blocked by whoever holds its .lock, so ask lsof about that one
# file. Walking the tree with +D took 8.5s on the qdrant cache (207k files),
# `timeout 8` killed lsof before it printed anything, and the live holders —
# the uvx of every running Claude Code / Opencode session — went unreported:
# apply was not blocked, and the prune step then sat on the lock until its own
# timeout and ended in a bare "warn". +D stays for caches without a .lock.
# `|| true` because lsof exits 1 when nothing holds the path, and under
# `set -e -o pipefail` that ended the whole loop at the first idle cache
# (~/.npm): every path after it, qdrant included, was never checked at all.
collect_cache_holders() {
  local p
  for p in "${CACHE_LOCK_PATHS[@]}"; do
    [[ -d "$p" ]] || continue
    if [[ -e "$p/.lock" ]]; then
      timeout 8 lsof -w -n -P "$p/.lock" 2>/dev/null
    else
      timeout 8 lsof -w -n -P +D "$p" 2>/dev/null
    fi | awk -v path="$p" 'NR>1{print $2"\t"$1"\t"path}' || true
  done | awk -v self="$$" '$1!=self && $2!="lsof" && $2!="timeout" {print}' | sort -u
}

# Command name of the parent: a lock held by `uv` means little until it says
# which claude/opencode session started that uvx.
parent_cmd() {
  local ppid
  ppid=$(ps -o ppid= -p "$1" 2>/dev/null | tr -d ' ')
  [[ -n "$ppid" ]] && ps -o comm= -p "$ppid" 2>/dev/null || echo "?"
}

size_h() {
  local p="$1"
  [[ -e "$p" ]] || {
    echo "0B"
    return
  }
  # -L dereferences: ~/.cache and ~/.npm are symlinks onto /mnt/2hdd, and plain
  # `du -sh` measures the link itself, so the preview reported "0" for a 19GB
  # cache and there was no way to tell cleaning mattered.
  du -shL "$p" 2>/dev/null | awk '{print $1}'
}

npx_old_stats() {
  python3 - "$HOME/.npm/_npx" "$NPX_DAYS" <<'PY'
import os, sys, time
root = sys.argv[1]
days = int(sys.argv[2])
cutoff = time.time() - days * 86400
count = 0
total = 0
if os.path.isdir(root):
    for name in os.listdir(root):
        path = os.path.join(root, name)
        try:
            st = os.stat(path)
        except FileNotFoundError:
            continue
        if st.st_mtime >= cutoff:
            continue
        count += 1
        for dp, _, files in os.walk(path):
            for f in files:
                fp = os.path.join(dp, f)
                try:
                    total += os.path.getsize(fp)
                except FileNotFoundError:
                    pass
print(count)
print(total)
PY
}

delete_npx_old() {
  python3 - "$HOME/.npm/_npx" "$NPX_DAYS" <<'PY'
import os, sys, time, shutil
root = sys.argv[1]
days = int(sys.argv[2])
cutoff = time.time() - days * 86400
if os.path.isdir(root):
    for name in os.listdir(root):
        path = os.path.join(root, name)
        try:
            st = os.stat(path)
        except FileNotFoundError:
            continue
        if st.st_mtime < cutoff:
            shutil.rmtree(path, ignore_errors=True)
PY
}

# Print stale Codex daemon release dirs, one per line. Kept: the target of
# `current`, the release named in `auto-update-version`, and any release a
# running process executes from. Prints nothing (deletes nothing) when
# `current` does not resolve into releases/ — then the live one is unknown —
# or while an update holds install.lock.
codex_stale_releases() {
  local rel cur pinned e t d name
  rel=$(readlink -f "$CODEX_DAEMON_DIR/releases" 2>/dev/null) || return 0
  [[ -d "$rel" ]] || return 0
  cur=$(readlink -f "$CODEX_DAEMON_DIR/current" 2>/dev/null) || return 0
  [[ -d "$cur" && "$(dirname "$cur")" == "$rel" ]] || return 0
  if [[ -e "$CODEX_DAEMON_DIR/install.lock" ]] &&
     [[ -n "$(timeout 5 lsof -w -n -P "$CODEX_DAEMON_DIR/install.lock" 2>/dev/null || true)" ]]; then
    return 0
  fi

  local -A keep=(["$(basename "$cur")"]=1)
  pinned=$(tr -d '[:space:]' < "$CODEX_DAEMON_DIR/auto-update-version" 2>/dev/null || true)
  [[ -n "$pinned" ]] && keep["$pinned"]=1
  for e in /proc/[0-9]*/exe; do
    t=$(readlink "$e" 2>/dev/null) || continue
    [[ "$t" == "$rel"/* ]] || continue
    t=${t#"$rel"/}
    keep["${t%%/*}"]=1
  done

  for d in "$rel"/*/; do
    d=${d%/}
    name=$(basename "$d")
    # Only real release dirs: never a symlink, never something without the
    # package manifest the daemon writes into each release.
    [[ -L "$d" || ! -f "$d/codex-package.json" ]] && continue
    [[ -n "${keep[$name]:-}" ]] || echo "$d"
  done
}

# Print stale Claude Code version binaries, one per line. Kept: the target of
# the launcher symlink and any version a running process executes. Prints
# nothing when the launcher does not resolve into versions/ — then the live
# one is unknown.
claude_stale_versions() {
  local dir cur e t f name
  dir=$(readlink -f "$CLAUDE_VERSIONS_DIR" 2>/dev/null) || return 0
  [[ -d "$dir" ]] || return 0
  cur=$(readlink -f "$CLAUDE_LAUNCHER" 2>/dev/null) || return 0
  [[ -f "$cur" && "$(dirname "$cur")" == "$dir" ]] || return 0

  local -A keep=(["$(basename "$cur")"]=1)
  for e in /proc/[0-9]*/exe; do
    t=$(readlink "$e" 2>/dev/null) || continue
    [[ "$t" == "$dir"/* ]] || continue
    t=${t#"$dir"/}
    keep["${t%% *}"]=1
  done

  for f in "$dir"/*; do
    name=$(basename "$f")
    # Only version-named regular files, never a symlink or anything else.
    [[ -L "$f" || ! -f "$f" ]] && continue
    [[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    [[ -n "${keep[$name]:-}" ]] || echo "$f"
  done
}

# Print orphaned Claude Code plugin version dirs, one per line: those that
# carry .orphaned_at and are no installPath in installed_plugins.json. Prints
# nothing when that file is missing or unreadable — then the live set is
# unknown.
claude_orphan_plugins() {
  [[ -d "$CLAUDE_PLUGIN_CACHE" && -f "$CLAUDE_PLUGINS_JSON" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local live m d
  live=$(jq -r '.plugins[][].installPath // empty' "$CLAUDE_PLUGINS_JSON" 2>/dev/null) || return 0
  [[ -n "$live" ]] || return 0
  local -A keep=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && keep["$(readlink -f "$d" 2>/dev/null || echo "$d")"]=1
  done <<< "$live"
  for m in "$CLAUDE_PLUGIN_CACHE"/*/*/*/.orphaned_at; do
    [[ -f "$m" ]] || continue
    d=$(dirname "$m")
    [[ -L "$d" ]] && continue
    [[ -n "${keep[$(readlink -f "$d")]:-}" ]] || echo "$d"
  done
}

progress_prefix() {
  local pct=$(( STEP * 100 / TOTAL_STEPS ))
  printf '[%d/%d | %3d%%]' "$STEP" "$TOTAL_STEPS" "$pct"
}

run_step() {
  local label="$1"
  shift
  STEP=$((STEP + 1))
  local start end elapsed
  start=$(date +%s)
  printf '%b %s ... ' "${C_CYAN}$(progress_prefix)${C_RESET}" "$label"
  if "$@"; then
    end=$(date +%s)
    elapsed=$((end - start))
    printf '%bdone%b (%ss)\n' "$C_GREEN" "$C_RESET" "$elapsed"
  else
    end=$(date +%s)
    elapsed=$((end - start))
    printf '%bwarn%b (%ss)\n' "$C_YELLOW" "$C_RESET" "$elapsed"
  fi
}

step_npm_cache() {
  if command -v npm >/dev/null 2>&1; then
    npm cache clean --force >/dev/null 2>&1 || return 1
  fi
  return 0
}

step_npx_old() {
  delete_npx_old
  return 0
}

step_uv_cache() {
  if command -v uv >/dev/null 2>&1; then
    local rc=0
    local errf="/tmp/dev-soft-clean-uv.err"
    local verb="prune"
    [[ "$UV_CLEAN" -eq 1 ]] && verb="clean"
    : > "$errf"
    timeout "${UV_PRUNE_TIMEOUT_SEC}s" uv cache "$verb" >/dev/null 2>"$errf" || rc=$?
    if [[ $rc -eq 124 ]]; then
      printf '  note: uv cache %s timed out after %ss (likely cache lock); skipping\n' "$verb" "$UV_PRUNE_TIMEOUT_SEC" >&2
      return 1
    fi
    if [[ $rc -ne 0 ]]; then
      if grep -q "Cache is currently in-use" "$errf" 2>/dev/null; then
        printf '  note: uv cache in-use by another process; skipping\n' >&2
      fi
      return 1
    fi
  fi
  return 0
}

step_qdrant_uv_cache() {
  [[ -d "$QDRANT_UV_CACHE" ]] || return 0
  if command -v uv >/dev/null 2>&1; then
    local rc=0
    local errf="/tmp/dev-soft-clean-qdrant-uv.err"
    local verb="prune"
    [[ "$UV_CLEAN" -eq 1 ]] && verb="clean"
    : > "$errf"
    timeout "${UV_PRUNE_TIMEOUT_SEC}s" env UV_CACHE_DIR="$QDRANT_UV_CACHE" uv cache "$verb" >/dev/null 2>"$errf" || rc=$?
    if [[ $rc -eq 124 ]]; then
      printf '  note: qdrant uv cache %s timed out after %ss (likely cache lock); skipping\n' "$verb" "$UV_PRUNE_TIMEOUT_SEC" >&2
      return 1
    fi
    if [[ $rc -ne 0 ]]; then
      if grep -q "Cache is currently in-use" "$errf" 2>/dev/null; then
        printf '  note: qdrant uv cache in-use by another process; skipping\n' >&2
      fi
      return 1
    fi
  fi
  return 0
}

step_pip_cache() {
  if command -v pip >/dev/null 2>&1; then
    pip cache purge >/dev/null 2>&1 || return 1
  fi
  return 0
}

step_go_cache() {
  if command -v go >/dev/null 2>&1; then
    go clean -cache >/dev/null 2>&1 || return 1
  fi
  return 0
}

step_bun_cache() {
  if command -v bun >/dev/null 2>&1; then
    bun pm cache rm >/dev/null 2>&1 || return 1
  fi
  return 0
}

step_opencode_logs() {
  if [[ -d "$HOME/.local/share/opencode/log" ]]; then
    python3 - "$HOME/.local/share/opencode/log" "$LOG_DAYS" <<'PY'
import os, sys, time
root = sys.argv[1]
days = int(sys.argv[2])
cutoff = time.time() - days * 86400
for name in os.listdir(root):
    path = os.path.join(root, name)
    try:
        st = os.stat(path)
    except FileNotFoundError:
        continue
    if st.st_mtime < cutoff and os.path.isfile(path):
        try:
            os.remove(path)
        except OSError:
            pass
PY
  fi
  return 0
}

step_codex_releases() {
  local d rc=0
  # Re-detect at apply time: an update may have landed since the preview.
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    rm -rf -- "$d" || rc=1
  done < <(codex_stale_releases)
  return "$rc"
}

step_claude_versions() {
  local f rc=0
  # Re-detect at apply time: an auto-update may have landed since the preview.
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    rm -f -- "$f" || rc=1
  done < <(claude_stale_versions)
  return "$rc"
}

# Print opencode cache leftovers, one path per line (see OPENCODE_CACHE_DIR).
opencode_cache_leftovers() {
  local c="$OPENCODE_CACHE_DIR" pkg
  [[ -d "$c" ]] || return 0
  if [[ -d "$c/npm" && -d "$c/packages" ]]; then
    echo "$c/packages"
  elif [[ -d "$c/packages/.stale" ]]; then
    find "$c/packages/.stale" -mindepth 1 -maxdepth 1
  fi
  if [[ -d "$c/npm" ]]; then
    # npm/<pkg> and npm/@scope/<pkg>: every numeric dir but the newest.
    while IFS= read -r pkg; do
      find "$pkg" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended \
        -regex '.*/[0-9]+' -printf '%f\n' | sort -n | head -n -1 |
        sed "s|^|$pkg/|"
    done < <(find "$c/npm" -mindepth 1 -maxdepth 2 -type d \
               -not -name '@*' -not -regex '.*/[0-9]+')
  fi
  find "$c" -maxdepth 1 -type f -name 'models.json.*.tmp' -mmin +1440
}

step_opencode_cache() {
  local p rc=0
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    rm -rf -- "$p" || rc=1
  done < <(opencode_cache_leftovers)
  return "$rc"
}

step_claude_orphan_plugins() {
  local d rc=0
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    rm -rf -- "$d" || rc=1
  done < <(claude_orphan_plugins)
  return "$rc"
}

echo "== Soft cleanup preview =="
echo "Mode: $MODE"
echo

echo "Will NOT touch critical runtime data:"
echo "- $HOME/.local/share/opencode/opencode.db"
echo "- $HOME/.local/share/opencode/bin"
echo "- $HOME/.local/share/claude (except stale versions/, see step 10)"
echo "- $HOME/.nvm/versions"
echo

echo "Current sizes:"
echo "- codex daemon      : $(size_h "$CODEX_DAEMON_DIR/releases")"
echo "- claude versions   : $(size_h "$CLAUDE_VERSIONS_DIR")"
echo "- ~/.npm            : $(size_h "$HOME/.npm")"
echo "- ~/.cache          : $(size_h "$HOME/.cache")"
echo "- ~/go/pkg/mod      : $(size_h "$HOME/go/pkg/mod")"
echo "- ~/.bun/install    : $(size_h "$HOME/.bun/install")"
echo "- qdrant uv-cache   : $(size_h "$QDRANT_UV_CACHE")"

# Unpacked wheels are what stays behind after a prune, so show that number and
# name the flag that reclaims it — otherwise the run reports "done" while GBs
# sit untouched and nothing hints at why. ~/.cache/uv only: in the qdrant cache
# archive-v0 holds ephemeral uvx environments, and prune does free them — all
# but the one a running session uses.
if [[ "$UV_CLEAN" -eq 0 ]]; then
  _a="$HOME/.cache/uv/archive-v0"
  [[ -d "$_a" ]] && \
    echo "  note: unpacked wheels prune will NOT free: $(size_h "$_a") in ${_a/#$HOME/\~} — use --uv-clean"
fi

mapfile -t _npx_stats < <(npx_old_stats)
NPX_OLD_COUNT="${_npx_stats[0]:-0}"
NPX_OLD_BYTES="${_npx_stats[1]:-0}"
echo "- ~/.npm/_npx old>${NPX_DAYS}d dirs: ${NPX_OLD_COUNT} ($(numfmt --to=iec "$NPX_OLD_BYTES"))"

mapfile -t _codex_stale < <(codex_stale_releases)
_codex_cur=$(readlink -f "$CODEX_DAEMON_DIR/current" 2>/dev/null || true)
if [[ ${#_codex_stale[@]} -gt 0 ]]; then
  echo "- codex daemon stale releases: ${#_codex_stale[@]} ($(du -scL "${_codex_stale[@]}" 2>/dev/null | tail -1 | awk '{print $1}' | numfmt --from-unit=1024 --to=iec)), keep: ${_codex_cur##*/}"
  for d in "${_codex_stale[@]}"; do echo "    ${d##*/}"; done
elif [[ -d "$CODEX_DAEMON_DIR/releases" ]]; then
  echo "- codex daemon stale releases: 0 (keep: ${_codex_cur##*/}; skipped if current is unresolved or an update is running)"
fi

mapfile -t _claude_stale < <(claude_stale_versions)
_claude_cur=$(readlink -f "$CLAUDE_LAUNCHER" 2>/dev/null || true)
if [[ ${#_claude_stale[@]} -gt 0 ]]; then
  echo "- claude stale versions: ${#_claude_stale[@]} ($(du -scL "${_claude_stale[@]}" 2>/dev/null | tail -1 | awk '{print $1}' | numfmt --from-unit=1024 --to=iec)), keep: ${_claude_cur##*/}"
  for f in "${_claude_stale[@]}"; do echo "    ${f##*/}"; done
elif [[ -d "$CLAUDE_VERSIONS_DIR" ]]; then
  echo "- claude stale versions: 0 (keep: ${_claude_cur##*/}; skipped if the launcher is unresolved)"
fi

mapfile -t _oc_left < <(opencode_cache_leftovers)
if [[ ${#_oc_left[@]} -gt 0 ]]; then
  echo "- opencode cache leftovers: ${#_oc_left[@]} ($(du -sc "${_oc_left[@]}" 2>/dev/null | tail -1 | awk '{print $1}' | numfmt --from-unit=1024 --to=iec))"
  for p in "${_oc_left[@]}"; do echo "    ${p#"$OPENCODE_CACHE_DIR"/}"; done
fi

mapfile -t _cc_orphans < <(claude_orphan_plugins)
if [[ ${#_cc_orphans[@]} -gt 0 ]]; then
  echo "- claude orphaned plugin versions: ${#_cc_orphans[@]} ($(du -sc "${_cc_orphans[@]}" 2>/dev/null | tail -1 | awk '{print $1}' | numfmt --from-unit=1024 --to=iec))"
  for d in "${_cc_orphans[@]}"; do echo "    ${d#"$CLAUDE_PLUGIN_CACHE"/}"; done
fi

# A running AI IDE blocks apply by itself, not only through the cache locks of
# its MCP servers: an IDE whose uvx servers are not up, or that has none, holds
# no lock, and the holder check below would wave the cleanup through while the
# IDE still has its caches open. Process names, not paths: claude and opencode
# are native binaries, and codex.js spawns a native `codex`.
#
# Two kinds of match are not an open IDE. A zombie (state Z/X) has exited and
# holds nothing; `codex app-server` stopped by hand stays one until its parent
# reaps it. And the background services of Codex and opencode 2.x —
# `codex app-server …` and `opencode serve` — run all the time with PPID 1, so
# blocking on them blocked apply for good. They are listed, and what of theirs
# matters is checked on its own: their MCP servers' cache locks by the holder
# check below, the live Codex release by step 9, which keeps the release any
# process runs from.
_running_ides=() _services=()
while read -r _pid _args; do
  [[ -n "$_pid" ]] || continue
  _state=$(awk '{ sub(/.*\) /, ""); print $1 }' "/proc/$_pid/stat" 2>/dev/null) || continue
  [[ "$_state" == Z || "$_state" == X ]] && continue
  case " $_args " in
    *" app-server "*|*" serve "*) _services+=("$_pid $_args"); continue ;;
  esac
  _running_ides+=("$_pid $_args")
done < <(pgrep -a -x 'claude|codex|opencode' || true)
if [[ ${#_services[@]} -gt 0 ]]; then
  echo
  echo "Background IDE services (do not block, see the checks below):"
  for line in "${_services[@]}"; do
    echo "- pid=${line%% *} cmd=$(ps -o comm= -p "${line%% *}" 2>/dev/null || echo "?") $(cut -c1-60 <<< "${line#* }")"
  done
fi
if [[ ${#_running_ides[@]} -gt 0 ]]; then
  echo
  echo "Running AI IDEs detected:"
  for line in "${_running_ides[@]}"; do
    echo "- pid=${line%% *} cmd=$(ps -o comm= -p "${line%% *}" 2>/dev/null || echo "?")"
  done
  echo
  if [[ "$MODE" == "apply" ]]; then
    printf '%bBlocked:%b cleanup will not run while an AI IDE is running.\n' "${C_BOLD}${C_RED}" "$C_RESET"
    printf '%bClose Claude Code / Codex / Opencode%b, then run %bdclean-apply%b again from a plain terminal.\n' "$C_RED" "$C_RESET" "${C_BOLD}${C_CYAN}" "$C_RESET"
    exit 2
  else
    echo "Dry-run note: apply mode would be blocked until these IDEs exit."
  fi
fi

mapfile -t _cache_holders < <(collect_cache_holders)
if [[ ${#_cache_holders[@]} -gt 0 ]]; then
  echo
  echo "Cache lock holders detected:"
  for line in "${_cache_holders[@]}"; do
    IFS=$'\t' read -r pid cmd path <<< "$line"
    echo "- pid=${pid} cmd=${cmd} parent=$(parent_cmd "$pid") path=${path}"
  done
  echo
  if [[ "$MODE" == "apply" ]]; then
    printf '%bBlocked:%b cleanup will not run while cache paths are in use.\n' "${C_BOLD}${C_RED}" "$C_RESET"
    printf '%bClose lock holders%b (not only AI IDEs), then run %bdclean-apply%b again.\n' "$C_RED" "$C_RESET" "${C_BOLD}${C_CYAN}" "$C_RESET"
    exit 2
  else
    echo "Dry-run note: apply mode would be blocked until these processes stop."
  fi
fi

echo
echo "Planned soft cleanup actions:"
echo "1) npm cache clean --force"
echo "2) delete ~/.npm/_npx dirs older than ${NPX_DAYS} days"
if [[ "$UV_CLEAN" -eq 1 ]]; then
  echo "3) uv cache CLEAN — wipes ~/.cache/uv entirely (if uv exists)"
  echo "4) qdrant MCP uv cache CLEAN (${QDRANT_UV_CACHE})"
else
  echo "3) uv cache prune (if uv exists)"
  echo "4) qdrant MCP uv cache prune (${QDRANT_UV_CACHE})"
fi
echo "5) pip cache purge (if pip exists)"
echo "6) go clean -cache (if go exists)"
echo "7) bun pm cache rm (if bun exists)"
echo "8) delete OpenCode logs older than ${LOG_DAYS} days"
echo "9) delete stale Codex app-server-daemon releases (keep current)"
echo "10) delete stale Claude Code versions (keep the one claude points at)"
echo "11) delete opencode cache leftovers (legacy packages/, old npm/<pkg>/<epoch>, stale models.json tmp)"
echo "12) delete orphaned Claude Code plugin versions (keep installed ones)"
echo

if [[ "$MODE" == "dry-run" ]]; then
  echo "Dry-run only. No files changed."
  exit 0
fi

echo "Applying soft cleanup..."

run_step "npm cache clean" step_npm_cache
run_step "delete old npx dirs" step_npx_old
run_step "uv cache prune" step_uv_cache
run_step "qdrant uv cache prune" step_qdrant_uv_cache
run_step "pip cache purge" step_pip_cache
run_step "go clean -cache" step_go_cache
run_step "bun pm cache rm" step_bun_cache
run_step "delete old OpenCode logs" step_opencode_logs
run_step "delete stale Codex daemon releases" step_codex_releases
run_step "delete stale Claude Code versions" step_claude_versions
run_step "delete opencode cache leftovers" step_opencode_cache
run_step "delete orphaned Claude plugin versions" step_claude_orphan_plugins

echo
echo "Cleanup done. Updated sizes:"
echo "- codex daemon      : $(size_h "$CODEX_DAEMON_DIR/releases")"
echo "- claude versions   : $(size_h "$CLAUDE_VERSIONS_DIR")"
echo "- ~/.npm            : $(size_h "$HOME/.npm")"
echo "- ~/.cache          : $(size_h "$HOME/.cache")"
echo "- ~/go/pkg/mod      : $(size_h "$HOME/go/pkg/mod")"
echo "- ~/.bun/install    : $(size_h "$HOME/.bun/install")"
echo "- qdrant uv-cache   : $(size_h "$QDRANT_UV_CACHE")"
echo
echo "Tip: if you need deeper cleanup later, run manually and separately:"
echo "- go clean -modcache   (re-downloads Go modules)"
echo "- remove old Node versions via nvm uninstall <version>"
