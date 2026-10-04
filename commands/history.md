---
description: Prompts and conversations of Claude Code, Codex and opencode sessions (survives /exit). Usage: /history (this session) | /history --id <ID> [--full] | /history --grep <TEXT> | /history sessions | /history -p. Filters: --ide claude|codex|opencode, --since/--until YYYY-MM-DD, -n N (default 40, 0 = all). Every listing also writes the uncapped result to ~/.local/state/ide-history/ and names the file, so nothing is lost off-screen.
---
Run this exact shell command via the bash tool:

```
ide-history $ARGUMENTS
```

Then reply with its output, verbatim, inside one fenced code block — strip the ANSI colour codes, change nothing else, add nothing before or after. The tool output is collapsed in the user's terminal ("Ran 1 shell command") and they do not see it; a reply without the output shows them nothing. If the command errored, state the error in one line instead.
