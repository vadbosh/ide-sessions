# ide-sessions

**Three commands that list, summarize and prune the sessions of Claude Code,
Codex CLI and opencode — including the one you lost track of.**

[Русская версия](README.RU.md) · [Changelog](CHANGELOG.md)

```
$ claude-sessions -n 3
    SESSION ID (full)                    LAST       TURNS  DATE        DIR
*   bdc2f598-3b6a-4e6f-a648-10ba0f1d4360 14s ago    217    09-11 09:59 /srv/infra
    a7f9d1e9-59af-4c04-8aba-584f84474da4 2m ago     18     09-11 09:56 /tmp
    4bce8fb3-df02-4082-9a5e-14f7588c2a52 3m ago     34     09-11 09:56 /tmp

$ claude-sessions --sum bdc2f598-3b6a-4e6f-a648-10ba0f1d4360
### State recovery and backup pipeline
- Restored /srv/infra/backup state from knowledge base, not chat history.
- Git log shows 15+ refactoring commits from 2026-08-28 (cb66366 → 20b3fbf).

### Qdrant database cleanup
- Removed unnecessary directories from /srv/infra/qdrant/data.
- Confirmed memory collection health: 766 live points, green status.
```

The directories are stand-ins — the rest of that output is real.

The other two commands take the same flags and print the same shape, over their
own storage:

```
$ codex-sessions -n 2
SESSION ID (full)                      LAST       TURNS  DATE        DIR
01a08fe6-293e-72a1-b2cf-048950be1a8a   2m ago     17     09-11 09:57 /srv/infra
01a05994-7729-7e32-99c9-f6b53f98199e   10d ago    44     08-31 20:49 /tmp

$ opencode-sessions -n 2
SESSION ID (full)              LAST       MSGS   COST     DATE        DIR
ses_fa66c4184ffepvA00VLoagntRt 10d ago    3      $0.37    08-31 20:47 /srv/infra
ses_fa6766e0cffeSzBZQ2880QZWfK 10d ago    3      $0.30    08-31 20:36 /srv/infra
```

Everything below is written with `claude-sessions`; substitute
`codex-sessions` or `opencode-sessions` and it holds, except where a section
says otherwise.

---

## Why

Two problems, one per half of the tool.

**Where a session actually lives.** Each IDE files a session by its own rule,
and none of them is the directory you are standing in when you go looking.
Claude Code hashes the directory `claude` was launched from and never revisits
that — not even when you `cd` somewhere else inside the running session, so a
session started in one cluster directory can carry a whole day of work about
another, and `--resume` will not find it where you expect. Codex writes a
rollout under the date it started, which is a different date from the work when
a session is resumed. opencode keeps a `directory` column that is easy to
query, and impossible to see from the CLI. All three listings show the id, the
directory a session is really bound to, and how recent it is.

**What was in it.** Remembering means reading the whole transcript again.
`--sum` gives back 2-4 bullets per topic, five topics at most — and always in
English, whatever language the session was held in, so a summary can be skimmed
by someone who did not run the session.

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
claude-sessions --sum-orig <ID>            # in the session's own language
claude-sessions --sum <ID> --sum-gap 90    # 90 min of silence starts a new topic
claude-sessions --sum <ID> --sum-refresh   # ignore the cache, ask again
claude-sessions --sum <ID> --sum-model X   # summarize with a specific model
```

`--sum-orig <ID>` writes the summary in the language the session was held
in, taking the one the user typed most where several were used. The two are cached
separately, so a session can hold an English summary for a colleague and a
Russian one for whoever ran it, and neither overwrites the other.

The same session, summarized by each command over its own IDE's storage — this
one was held in Russian:

```
$ codex-sessions --sum 01a05994-7729-7e32-99c9-f6b53f98199e
### Environment Inspection and Secret Masking
- Replaced `env` with `safe-env` because project rules prohibited full dumps.
- Ran `safe-env` successfully with secrets masked; exit code was `0`.

$ opencode-sessions --sum-orig ses_fa66c4184ffepvA00VLoagntRt
### Отказ от `env` в пользу `safe-env`
- Запрос `env` отклонён: дамп окружения пишет ключи в транскрипт.
- Выполнен `safe-env`; токены вышли как `<REDACTED:N>`.
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

### Credentials

A session can contain one: pasted into a prompt, echoed back in a reply,
printed inside an error message. A summary would carry it three ways at once —
to whatever API does the summarizing, into a cache file, and onto the terminal
of the session that asked, which is itself being recorded. The API is worth
naming separately: the summary need not run on the vendor the session ran on,
so a key typed into one provider's session can reach another's.

So the digest masks before anything leaves the process, and `--sum-raw` shows
exactly what would have been sent:

```
ASKED: deploy with <REDACTED:42> please
ASKED: export AWS_ACCESS_KEY_ID=<REDACTED:20>
ASKED: DB_PASSWORD=<REDACTED:21> in the values file
ASKED: psql postgres://<REDACTED:10>@db.internal:5432/app
ASKED: HW_ACCESS_KEY=<REDACTED:20>
ASKED: jira --token <REDACTED:38> issue list
ASKED: api token is <REDACTED:40> and it expired
ASKED: checked out 9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c from main
```

Two tiers, ported from [env2hell](https://github.com/vadbosh/env2hell), whose
`safe-env` and `secrets-redact` solve the same problem for shell output.

**Tier 1, the shape decides.** `ghp_`, `github_pat_`, `AKIA`, `glpat-`,
`xox…`, `sk-` (including `sk-ant-`, `sk-proj-`, `sk-or-v1-`), `AIza`,
`sk_live_`, `tvly-`, `hf_`, `dckr_pat_`, Atlassian `ATATT` and `at-`, a JWT, a
`BEGIN … PRIVATE KEY` line, a password inside a URL. Masked wherever it
appears.

**Tier 2, the name decides.** Huawei Cloud and OpenStack are the reason this
tier has to exist: their access key is 20 characters of upper case and digits
and the secret 40 of base62 — the same shapes as a git SHA, a build id, half
the identifiers in ordinary output. No pattern can claim them without taking
everything else too. So a long value is masked when the thing beside it is
named like a credential — `HW_ACCESS_KEY=`, `HUAWEICLOUD_SDK_AK=`,
`OS_SECRET_KEY:`, `--token`, `--pass`, `Authorization: Bearer`, anything whose
name contains password, secret, token, credential — and, more loosely, when a
credential word appears anywhere on the line (English or Russian).

The last line of the example above is what that condition buys: a 40-character
SHA with no credential word beside it stays readable. A summary that hides its
own commits answers nothing.

Jira lands in both tiers: an API token carries `ATATT`, while `jira --token …`
is caught by the flag.

The prompt also forbids writing a credential out, cached summaries are `0600`
and their directory `0700`. None of this recovers a key that was already in the
transcript — rotate that one. It stops the summary from copying it somewhere
new.

### Cost

Measured, not estimated. A headless `claude -p` run inherits your `CLAUDE.md`,
skills and MCP servers unless told otherwise — a one-line prompt billed
**40 179** input tokens that way, and **4 591** with `--setting-sources ''` and
an empty MCP config. Both are passed. Codex likewise runs with skills, MCP and
hooks switched off for this one call.

A typical summary is one call over a 2-4 kB digest, and the cache makes the
second look free.

### Which model

No model name or version is pinned in these scripts — a pinned name is wrong by
the next release. `--sum` and `--sum-orig` resolve it identically; the language
of the answer has no bearing on which model writes it.

**`claude-sessions`**, in order, first hit wins:

1. `--sum-model M`, else `IDE_SESSIONS_SUM_MODEL`.
2. The cheapest **priced** Anthropic model in a [models.dev](https://models.dev)
   catalogue found on disk: `IDE_SESSIONS_MODELS_JSON`,
   `~/.cache/ide-sessions/models.dev.json`, `~/.cache/opencode/models.json`.
   Cheapest by input price per million, skipping models priced at zero — that
   means "not priced here" far more often than "free" — and those with a
   context window under 100k. No network call; the catalogue is used only if it
   is already there.
3. `haiku` — the CLI's own alias, which follows whatever the current small
   model is.
4. Whatever the CLI picks itself, if the call above failed because the account
   cannot reach that model. The summary then says `(CLI default)`.

**`codex-sessions`**:

1. `--sum-model M`, else `IDE_SESSIONS_SUM_MODEL`, passed as `codex exec -m`.
2. Otherwise the model Codex is configured with — `model` in
   `~/.codex/config.toml`, or its own default. Codex offers one model family
   per account and ships no price list on disk, so there is nothing to choose
   between; what is chosen instead is depth, `model_reasoning_effort="low"`,
   because a digest needs no reasoning.

**`opencode-sessions`**:

1. `--sum-model M`, else `IDE_SESSIONS_SUM_MODEL`, passed as
   `opencode run --model provider/model`.
2. Otherwise no `--model` flag at all, which leaves opencode's own resolution
   order in place: the `model` field in its config, then the last model used.
   Picking a cheaper one from the catalogue here is possible and deliberately
   not done — opencode reaches ~385 models across providers whose availability
   differs per machine and per login, and a summary that silently ran on
   something the user never configured is worse than one that cost more.

Which model actually wrote a summary is printed on stderr, so `--sum | …` stays
pure summary:

```
$ claude-sessions --sum <ID> > /tmp/s.md
summarized with claude-haiku-4-5-20251001
```

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
