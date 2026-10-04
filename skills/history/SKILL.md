---
name: history
description: Handle phrases "history", "/history", "prompt history", "история команд", "покажи историю ввода", "история сессии", "что я спрашивал" by showing the prompts and conversations of past and current sessions across Claude Code, Codex and Opencode — they survive session exit/resume.
version: "2.0.0"
---

# history

Runs `ide-history`, which reads the prompt history each IDE keeps across
sessions (`~/.claude/history.jsonl`, `~/.codex/history.jsonl`, opencode's
database) and the session transcripts for whole conversations.

## Usage

Run via the bash tool, then put its output in the reply (see the end of
this file):

```bash
ide-history                        # this session's prompts
ide-history --id <ID>              # one session's prompts; a unique id prefix is enough
ide-history --id <ID> --full       # the conversation: prompts + replies; the file it names
                                   # holds everything, tool calls and output included
ide-history --grep <TEXT>          # every prompt containing TEXT, with its session id
ide-history sessions               # sessions with prompt counts — find an id here
ide-history -p                     # every prompt typed in this directory
```

Filters for all of them: `--ide claude|codex|opencode`, `--since`/`--until
YYYY-MM-DD`, `-n N` (rows on screen, default 40, `0` = all), `--json`.

- The IDE is found from the id; `--ide` is only needed when a prefix is
  shared by sessions of two IDEs. An ambiguous prefix lists the candidates.
- "This session" is exact in Claude Code (`CLAUDE_CODE_SESSION_ID`) and Codex
  (`CODEX_THREAD_ID`); in opencode it is the most recently active session.
- Every listing writes its uncapped result to `~/.local/state/ide-history/`
  and names the file on its last line, so nothing cut off the screen is lost.
- The user does not know the id → run `ide-history sessions` (or
  `--grep` with a word from that session) first.

Reply with the command output, verbatim, inside one fenced code block —
strip the ANSI colour codes, do not summarize or reformat it. The tool
output is collapsed in the user's terminal ("Ran 1 shell command"), so a
reply without the output shows them nothing.
