---
description: Show persistent prompt history (survives /exit). Tool = claude|codex|opencode (default claude). Usage: /history [tool] sessions [project|all] [limit]  |  /history [tool] session=<id> [limit]  |  /history [tool] [project-substring|all] [limit]. No args -> defaults to "self" (current session, exact via CLAUDE_CODE_SESSION_ID for claude, heuristic for codex/opencode) instead of cwd. Default limit 40 (fits on screen); the command always also writes the unlimited result to a file in ~/.local/state/agent-history/ (kept 7 days) and prints its path so nothing is ever lost off-screen.
---
Run this exact shell command via the bash tool:

```
agent-history $ARGUMENTS
```

Then reply with its output, verbatim, inside one fenced code block — strip the ANSI colour codes, change nothing else, add nothing before or after. The tool output is collapsed in the user's terminal ("Ran 1 shell command") and they do not see it; a reply without the output shows them nothing. With `--file`, the output is a single path: reply with that line. If the command errored, state the error in one line instead.
