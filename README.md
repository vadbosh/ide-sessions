# ide-sessions

**Three commands that list, summarize and prune the sessions of Claude Code,
Codex CLI and opencode — including the one you lost track of.**

[Русская версия](README.RU.md) · [Changelog](CHANGELOG.md)

```
$ claude-sessions -n 3
    SESSION ID (full)                    LAST       TURNS  DATE        DIR
*   bdc2f598-3b6a-4e6f-a648-10ba0f1d4360 14s ago    217    09-11 09:59 /44
    a7f9d1e9-59af-4c04-8aba-584f84474da4 2m ago     18     09-11 09:56 /tmp
    4bce8fb3-df02-4082-9a5e-14f7588c2a52 3m ago     34     09-11 09:56 /tmp

$ claude-sessions --sum bdc2f598-3b6a-4e6f-a648-10ba0f1d4360
### State recovery and backup pipeline
- Restored /mnt/2hdd/M_backup state from knowledge base, not chat history.
- Git log shows 15+ refactoring commits from 2026-08-28 (cb66366 → 20b3fbf).

### Qdrant database cleanup
- Removed unnecessary directories from /AI_P/Qdrant/data.
- Confirmed memory collection health: 766 live points, green status.
```

---

## Why

Two problems, one per half of the tool.

**Where a session actually lives.** Claude Code files a session under a hash of
the directory `claude` was launched from, and that never changes afterward —
not even when you `cd` somewhere else inside the running session. A session
started in one cluster directory can carry a whole day of work about another,
and `--resume` will not find it where you expect. The listing shows the id, the
directory a session is really bound to, and how recent it is.

**What was in it.** A transcript answers that only to someone willing to read
it again. `--sum` gives back four bullets per topic — and always in English,
whatever language the session was held in, so a summary can be skimmed by
someone who did not run the session.

## Install

```bash
git clone <this repo> ide-sessions
cd ide-sessions
./install.sh              # copies the three commands into ~/.local/bin
./install.sh --dry-run    # see what it would do first
```

The installer reports which IDEs it found and which CLIs are available for
`--sum`. Requires `python3`; nothing else. All three commands can be installed
on a machine with one IDE — the others just report that they found nothing.

Uninstall: `./install.sh --uninstall`.

## Usage

Listing, deleting and pruning are the same in all three commands:

```bash
claude-sessions                     # every session, newest first
claude-sessions -n 20               # limit rows
claude-sessions k8s                 # filter by directory substring
claude-sessions -p                  # only this project's sessions
claude-sessions -f                  # full paths instead of the last 3 parts

claude-sessions --rm <ID>           # confirms, then deletes
claude-sessions --older-than 30     # dry-run until you add --apply
claude-sessions --max-turns 2 --apply
```

Deleting moves files to `~/.cache/ide-sessions-trash/<ide>-<timestamp>/`, so a
mistake is recoverable. Naming an id is intent enough to delete after a
confirmation; bulk criteria can sweep up far more than expected, so they stay a
dry run until `--apply`. The live session is never deleted.

Summaries:

```bash
claude-sessions   --sum <ID>          # English summary, grouped by topic
codex-sessions    --sum <ID>
opencode-sessions --sum <ID>

claude-sessions --sum <ID> --sum-raw       # the digest only — no model, no cost
claude-sessions --sum <ID> --sum-gap 90    # 90 min of silence starts a new topic
claude-sessions --sum <ID> --sum-refresh   # ignore the cache, ask again
claude-sessions --sum <ID> --sum-model X   # summarize with a specific model
```

## How `--sum` works

Two passes.

**Locally**, the session is reduced to a digest: what was asked, short excerpts
of the replies, and a count per tool — split into parts wherever the work
actually stopped (a silence longer than `--sum-gap`, or a change of directory).
Everything a summary cannot use is dropped here: tool output, hook chatter,
slash-command plumbing, injected skill and AGENTS.md preambles, subagent
sidechains. `--sum-raw` prints exactly this and costs nothing.

**Then one model call** turns the digest into headings and bullets. This is the
step that cannot be done locally: the sessions are in Russian, English, German
or a mix inside one sentence, and the summary has to come back in English.

Each command calls **its own IDE's CLI** — `claude -p`, `codex exec`,
`opencode run`. A machine with Codex may have no Claude Code installed, so
binding one tool's feature to another tool's binary would make it unavailable
exactly where it is needed.

The result is cached in `~/.cache/ide-sessions-summaries/`, keyed by the
transcript's modification time. Asking twice about an unchanged session costs
nothing; a session that has since been resumed re-summarizes itself.

### Cost

Measured, not estimated. A headless `claude -p` run inherits your `CLAUDE.md`,
skills and MCP servers unless told otherwise — a one-line prompt billed
**40 179** input tokens that way, and **4 591** with `--setting-sources ''` and
an empty MCP config. Both are passed. Codex likewise runs with skills, MCP and
hooks switched off for this one call.

A typical summary is one call over a 2-4 kB digest, and the cache makes the
second look free.

### Which model

No model name or version is pinned in these scripts — a pinned name is wrong
by the next release.

- `claude-sessions` picks the cheapest **priced** Anthropic model it can find in
  a [models.dev](https://models.dev) catalogue already on disk (opencode keeps
  one at `~/.cache/opencode/models.json`), and otherwise falls back to the
  CLI's own alias for its small model. A model the account cannot call falls
  back again to whatever the CLI would have chosen itself.
- `codex-sessions` and `opencode-sessions` use the model their IDE is already
  set to — both resolve one themselves, and overriding it here would undo a
  choice the user made for that machine. Reasoning effort is turned down for
  Codex, because a digest needs none.
- `--sum-model` or `IDE_SESSIONS_SUM_MODEL` overrides all of this.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `IDE_SESSIONS_SUM_MODEL` | unset | model for `--sum` |
| `IDE_SESSIONS_SUM_CACHE` | `~/.cache/ide-sessions-summaries` | cached summaries |
| `IDE_SESSIONS_TRASH` | `~/.cache/ide-sessions-trash` | where deletes go |
| `IDE_SESSIONS_MODELS_JSON` | unset | a models.dev catalogue to price against |
| `IDE_SESSIONS_BIN_DIR` | `~/.local/bin` | where `install.sh` writes |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude Code storage |
| `CODEX_HOME` | `~/.codex` | Codex storage |
| `OPENCODE_DATA_DIR` | `~/.local/share/opencode` | opencode storage |

## Notes per IDE

**Claude Code** — one `.jsonl` per session under `~/.claude/projects/<hash>/`.
A session is more than its transcript: subagent logs, file history, session
env, usage data and security state are all keyed by the same id, and `--rm`
moves the whole footprint to the trash.

**Codex** — one `rollout-*.jsonl` per session. Two layouts are in circulation:
up to codex-cli 0.135 the turns are `event_msg/user_message`, from 0.154 they
are `response_item/message` with a role. Both are read, and a file written
across an upgrade does not count its turns twice.

**opencode** — a sqlite database. A session is rows across eight tables; the
schema declares `ON DELETE CASCADE` but `PRAGMA foreign_keys` defaults to off,
so every table is deleted explicitly inside one transaction, and child
(subagent) sessions are pulled in with their parent. Rows are dumped as INSERT
statements into the trash dir before deletion. The queries go through Python's
bundled `sqlite3` module rather than the `sqlite3` CLI, which is a separate
package and often missing — where it was, this script printed `sqlite3 not
found` and listed nothing at all.

Running `opencode run` creates a session of its own, so `--sum` deletes that
scratch session afterward by the title it gave it.

## Tests

```bash
tests/test_sessions.sh
```

Each test builds a throwaway storage tree under a temp dir — no test touches
real transcripts, and none calls a model. What they check is the digest, which
is the part that can be wrong without anyone noticing: a model will happily
summarize a digest full of hook noise.

## License

MIT.
