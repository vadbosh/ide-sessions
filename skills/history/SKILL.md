---
name: history
description: Handle phrases "history", "/history", "prompt history", "история команд", "покажи историю ввода" by showing persistent prompt history that survives session exit/resume, across Claude Code, Codex, and Opencode.
version: "1.0.0"
---

# history

Codex's own arrow-key history is per-session only and disappears after the
session ends. The real persistent log survives at `~/.codex/history.jsonl`
(one JSON object per line: `session_id`, `ts`, `text`) with no bundled cwd —
cwd is recovered by cross-referencing `~/.codex/sessions/**/*.jsonl`
`session_meta` events.

## Usage

Run via the bash tool, then put its output in the reply (see the end of
this file):

```bash
agent-history codex [project-substring|all] [limit]
agent-history codex sessions [project-substring|all] [limit]
agent-history codex session=<id-substring> [limit]
```

- Last 40 entries by default (fits one screen).
- `all` as second arg → no project filter, all cwd's mixed.
- Third arg → limit (default 40).
- Without `--file`, every run also writes the *unlimited* result to a
  side file in `~/.local/state/agent-history/` (kept 7 days) and prints a trailing `[FULL history: N entries -> path]`
  line, so nothing shown on screen is ever actually clipped/lost.
- `sessions` → list sessions instead of entries: first/last time, session
  id, entry count, cwd. Use this first when the user wants a specific
  past session but doesn't know the id.
- `session=<id-substring>` → show every entry for one session (id match
  is substring, so a short fragment is enough); ignores the project
  filter since the session already pins it to one cwd.
- No args after `codex` (and no `all`) now defaults to "self": since
  Codex injects no session-id env var into bash-tool subprocesses, this
  is resolved heuristically as the session_id of the very last line in
  `~/.codex/history.jsonl` — running this skill just appended that line,
  so it's a reliable proxy for "the session I'm in right now". If you
  need a *different* session (not the current one), use `session=<id>`
  explicitly instead.

The same script also supports `claude` and `opencode` as the first
argument, reading `~/.claude/history.jsonl` and the Opencode
`opencode.db` (`message`/`part`/`session` tables) respectively — useful
when the user asks to compare history across tools.

Reply with the command output, verbatim, inside one fenced code block —
strip the ANSI colour codes, do not summarize or reformat it. The tool
output is collapsed in the user's terminal ("Ran 1 shell command"), so a
reply without the output shows them nothing.
The script also supports a trailing `--file` flag (writes to a unique
`~/.local/state/agent-history/agent-history-<tool>-<pid>-<random>.txt` and prints only the path)
for cases where the direct dump is too large or noisy — use only if the
user explicitly asks for it.
