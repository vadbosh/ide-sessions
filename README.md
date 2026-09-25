# ide-sessions

**Three commands that list, summarize and prune the sessions of Claude Code,
Codex CLI and opencode — including the one you lost track of.** A fourth,
`billing`, shows what they cost: per day, week or month across all three, or
for one session by its id.

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

## Why ide-sessions exists

Two problems, one per half of the tool.

**Where a session actually lives.** Each IDE files a session by its own rule,
and none of them is the directory you are standing in when you go looking.
Claude Code hashes the directory `claude` was launched from and never revisits
that — not even when you `cd` somewhere else inside the running session. A
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
./install.sh              # copies the four commands into ~/.local/bin
./install.sh --dry-run    # see what it would do first
```

The installer reports which IDEs it found and which CLIs are available for
`--sum`. The three session commands need `python3` and nothing else, and all
three can be installed on a machine with one IDE — the others just report that
they found nothing. `billing` also needs [ccusage](https://ccusage.com)
(`npm install -g ccusage`) and `jq`; the installer says whether they are there,
and `billing` says how to install them when they are not.

Uninstall: `./install.sh --uninstall`.

## Usage

Listing, deleting and pruning are the same in all three commands:

```bash
claude-sessions                     # every session, newest first
claude-sessions -n 20               # limit rows
claude-sessions k8s                 # filter by directory substring
claude-sessions -p                  # only this project's sessions
claude-sessions -f                  # full paths instead of the last 3 parts

claude-sessions --rm <ID>                    # confirms, then deletes
claude-sessions --older-than 30              # lists; deletes nothing yet
claude-sessions --older-than 30 --apply      # DELETES everything untouched for 30+ days
claude-sessions -p --max-turns 20 --apply    # DELETES this project's short sessions
claude-sessions -p --rm-all --apply          # DELETES every session of this project
claude-sessions k8s --rm-all                 # lists what that would take, in every dir matching k8s
```

Every bulk form lists first and deletes only with `--apply`. The examples in
`--help` spell out which is which, because "older than 30 days" describes a
selection and says nothing about what happens to it.

`--rm-all` refuses to run with nothing narrowing it. On its own it would mean
every session of every project, and that is the form a person types first —
before reading the flag that scopes it. Name a scope with `-p` or a substring,
or ask for the machine-wide sweep by its name:

```bash
claude-sessions --rm-all                   # refuses, explains, exits 1
claude-sessions --rm-all --everywhere      # every project — still a dry run
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
claude-sessions --list-models              # the names --sum-model accepts, and the default
```

`--sum-orig <ID>` writes the summary in the language the session was held
in, taking the one the user typed most where several were used. The two are cached
separately, so a session can hold an English summary for a colleague and a
Russian one for whoever ran it, and neither overwrites the other.

The same session, summarized by each command over its own IDE's storage — this
one was held in Russian:

```
$ codex-sessions --sum 01a05994-7729-7e32-99c9-f6b53f98199e
### File listing tool replacement
- Diagnosed `--group-directories-first` sorting bug in uutils coreutils 0.8.0.
- Replaced the `ll` alias with an eza-based one, fixed the time format.

$ opencode-sessions --sum-orig ses_fa66c4184ffepvA00VLoagntRt
### Исправление сортировки в alias ll
- Выявлен дефект в uutils coreutils 0.8.0: `--group-directories-first`
  отменяет сортировку по имени.
- Удалён мёртвый alias `lld`, вызывавший отсутствующую команду `lsd`.
```

## Cost: `billing`

`billing` answers three questions: how much per day, week or month; what one
session cost; and where each IDE stands against its usage limits. It does not
price anything itself — [ccusage](https://ccusage.com) reads the same local
logs the other three commands read and prices them; `billing` picks the view
and lays out the table.

```bash
billing days                      # last 20 days with usage, all IDEs, cost per IDE
billing days --ide claude         # the same, Claude Code only
billing weeks --ide codex         # Codex per week, Monday to Sunday
billing months --ide opencode     # opencode per calendar month
billing weeks --since 2026-09-01  # all IDEs, weeks from a date
billing today                     # one row: today
billing days -n 0                 # every day with usage, not just the last 20
billing --id <ID>                 # one session, any IDE: tokens, cache, cost, per model
billing block                     # usage limits, each IDE
billing --json                    # ccusage's own JSON instead of the table
```

Every table opens with a line that says what it is — the period, the IDEs, and
that periods with no usage are not listed — and which rows it holds:

```
$ billing weeks -n 2
Cost per week (Monday to Sunday) · all IDEs · weeks with no usage are not listed
last 2 of 18 weeks with usage, 2026-09-14 … 2026-09-21  (-n 0 for all, --since to start earlier)

WEEK (Mon–Sun)       INPUT  OUTPUT CACHE_WR CACHE_RD    TOTAL CACHE%      COST     claude     codex  opencode
2026-09-14 … 09-20    163K    3.1M    16.4M     1.5B     1.5B    99%   $971.05    $970.05     $0.70     $0.31
2026-09-21 … 09-27      5K    2.0M    13.6M   776.8M   792.4M    98%   $431.78    $431.78     $0.00     $0.00
TOTAL (rows above)    168K    5.1M    30.0M     2.3B     2.3B    99%  $1402.83   $1401.83     $0.70     $0.31
```

`billing block` reads each IDE where it keeps its limits. **Claude Code**: the
open 5-hour window — it opens with the first message — with what is spent, the
rate, and where the rate leads by the window's end, from ccusage. **Codex**:
the used share of each window (weekly, 5-hour) and when it resets, as the Codex
server reported it beside the last response, from the newest rollout under
`~/.codex/sessions`; a reset already past is flagged as an out-of-date reading.
**opencode** keeps no limit data in its SQLite store, and `billing` says so.

`<ID>` is the id the session commands show — `claude-sessions`,
`codex-sessions`, `opencode-sessions` — and a unique prefix is enough. ccusage
names a Codex session by its transcript path; `billing` matches the uuid at its
end, so the id from `codex-sessions` works as is. The form is the same for every
IDE: the IDE is found from the id. A prefix that fits several sessions lists
them instead of guessing; `--ide` narrows it.

```
$ billing --id bdc2f598
Cost of one session · Claude Code

  IDE:           Claude Code
  Session:       bdc2f598-3b6a-4e6f-a648-10ba0f1d4360
  Models:        claude-opus-5-5
  Started:       2026-09-11T09:40:02Z
  Last activity: 2026-09-11T09:59:41.210Z

  MODEL                           INPUT      OUTPUT     CACHE_WR        CACHE_RD           TOTAL CACHE%       COST
  claude-opus-5-5                   412      96,318      288,051      24,110,907      24,495,688    98%      $9.12
  TOTAL                             412      96,318      288,051      24,110,907      24,495,688    98%      $9.12
```

- **CACHE_WR / CACHE_RD** — tokens written to and read from the prompt cache.
- **TOTAL** — input + output + cache write + cache read.
- **CACHE%** — cache read as a share of the total: how much of the context was
  reused rather than paid for again.
- **COST** — an estimate, tokens times the model's price. On a subscription it
  is what the same work would cost through the API, not money charged.
- **The model** is what the API reported for each response, not what the
  session was started with: a `/model` switch mid-session shows up as a second
  row.

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

That call is itself a session, and each IDE records it. Summarizing therefore
removes what it created, by a means that cannot reach anything else:

- `claude-sessions` passes a `--session-id` it generated, so the cleanup names
  one UUID;
- `opencode-sessions` gives its scratch session a title and deletes by that
  title;
- `codex-sessions`, where the id is the CLI's to choose, takes only a rollout
  that both appeared during the call and contains the prompt this script sends.

Deleting by "newest file" would have been the obvious shortcut and is wrong: a
Codex running in another terminal appends to its rollout the whole time.

### How long a summary takes, and what it stores

The model call is the whole wait. Measured on a 9 MB, 4577-line transcript:

| Step | Time |
|---|---|
| Local digest (`--sum-raw`) | 0.6 s |
| Model call, 15 kB digest, 10 parts merged into 5 topics | 79 s |
| Second run, from cache | 0.3 s |

So a minute or more on a long session is normal, and it is neither the parsing
nor the writing — it is one model generating a summary of ten separate stretches
of work. `--sum-raw` tells the two apart: if that returns instantly and `--sum`
does not, the time is being spent at the API.

While the call is out, a counter says so — on stderr, and only when stderr is a
terminal, so a pipe or a script sees nothing of it:

```
  summarizing 10 part(s) with claude-haiku-4-5-20251001… 37s
```

**The cache is plain files, not a database.** One Markdown file per session and
language in `~/.cache/ide-sessions-summaries/`:

```
claude-<ID>.md          English summary
claude-<ID>.orig.md     the --sum-orig one
codex-<ID>.md
opencode-<ses_…>.md
```

The first line is a comment holding the key — transcript mtime, model, gap,
language — and the rest is the summary as printed. Files are `0600` in a `0700`
directory; deleting one costs a re-run and nothing else. The key is checked
before the transcript is parsed, so a hit does no work at all, and a session
resumed since then re-summarizes itself because its mtime moved.

Nothing is ever appended. A re-run replaces that one file wholesale, because
the new summary is made from the whole transcript, not from the part added
since. A summary of the last hour with the first hour missing would be worse
than none. Deleting a file, or the whole directory, costs exactly one re-run;
there is no other state. `--rm` removes a session's summaries along with the
session, into the same recoverable trash directory.

The only SQLite involved anywhere is opencode's own session store, which
`opencode-sessions` reads to list and to delete. No summary is ever written to
it.

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

Two tiers, because shape alone cannot decide.

**Tier 1, the shape decides.** `ghp_`, `github_pat_`, `AKIA`, `glpat-`,
`xox…`, `sk-` (including `sk-ant-`, `sk-proj-`, `sk-or-v1-`), `AIza`,
`sk_live_`, `tvly-`, `hf_`, `dckr_pat_`, Atlassian `ATATT` and `at-`, a JWT, a
`BEGIN … PRIVATE KEY` line, a password inside a URL. Masked wherever it
appears.

**Tier 2, the name decides.** Huawei Cloud and OpenStack are the reason this
tier has to exist. Their access key is 20 characters of upper case and digits,
the secret 40 of base62 — the same shapes as a git SHA, a build id, half the
identifiers in ordinary output. No pattern can claim them without taking
everything else too. So a long value is masked when the thing beside it is
named like a credential:

- `HW_ACCESS_KEY=`, `HUAWEICLOUD_SDK_AK=`, `OS_SECRET_KEY:`;
- `--token`, `--pass`, `Authorization: Bearer`;
- anything whose name contains password, secret, token, credential.

More loosely, a value is masked when a credential word appears anywhere on the
line, in English or in Russian.

The last line of the example above is what that condition buys: a 40-character
SHA with no credential word beside it stays readable. A summary that hides its
own commits answers nothing.

Jira lands in both tiers: an API token carries `ATATT`, while `jira --token …`
is caught by the flag.

The prompt also forbids writing a credential out, cached summaries are `0600`
and their directory `0700`. None of this recovers a key that was already in the
transcript — rotate that one. It stops the summary from copying it somewhere
new.

### What a summary costs

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

`--list-models` prints the names `--sum-model` accepts, each from where its IDE
keeps them, and which model `--sum` would use without the flag:

- `claude-sessions` — Claude Code has no command that lists models, so: the
  aliases it documents (`haiku`, `sonnet`, `opus`, `fable`, `best`, `opus[1m]`,
  `sonnet[1m]`), and the full names this account has actually run, read from
  its transcripts, newest first.
- `codex-sessions` — the catalogue Codex keeps in `~/.codex/models_cache.json`:
  each slug with its name, the ones offered in Codex's model picker first, and
  the one `config.toml` sets marked.
- `opencode-sessions` — `opencode models`, grouped by provider, with how each
  provider is connected. Only providers connected through `opencode auth login`
  and opencode's built-in one are listed: a provider reachable only because an
  API key sits in the environment is named in one line and left out, since the
  variable proves nothing about the key. `--list-models <provider>` shows one
  provider, that kind included.

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
   not done. opencode reaches ~385 models across providers whose availability
   differs per machine and per login. A summary that silently ran on something
   the user never configured is worse than one that cost more.

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
| `CCUSAGE_BIN` | `ccusage` | the ccusage binary `billing` runs |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude Code storage |
| `CODEX_HOME` | `~/.codex` | Codex storage |
| `OPENCODE_DATA_DIR` | `~/.local/share/opencode` | opencode storage |

## Notes per IDE

An empty result always says which scope came up empty. `-p` in a directory that
never hosted a session is the common case, and it is not an error. Claude Code
derives the project directory from the cwd, so a directory it was never launched
from has none.

**Claude Code** — one `.jsonl` per session under `~/.claude/projects/<hash>/`.
A session is more than its transcript: subagent logs, file history, session
env, usage data and security state are all keyed by the same id, and `--rm`
moves the whole footprint to the trash.

### Why an old session is missing

Only Claude Code deletes anything. It prunes transcripts older than
`cleanupPeriodDays` from `settings.json` — 30 days by default. The pruning
takes the `.jsonl` and leaves the project directory with whatever else lives in
it. A directory full of notes and no sessions is the normal look of a session
that aged out. Raising the setting does not bring back what a previous
run already removed.

Codex and opencode keep everything: no time limit, no size limit, nothing to
configure. Codex's `[history]` settings in `config.toml` govern
`~/.codex/history.jsonl`, the prompt history — not the rollouts. Their oldest
session is simply the day the IDE was first used, and the only thing that
removes one is `--rm`.

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

`billing` is tested against a stub in place of ccusage that prints canned JSON
in the shape ccusage writes: the layout and the session lookup are what can go
wrong here, and the prices are ccusage's own business.

## Sending a change

Commit messages are written in English, body included. The history is the only
place the reason for a change survives, and whoever can read the code can read
the message. A message that quotes Russian — a heading being renamed, a word
being replaced — keeps the quotation: there the Russian is the subject.

The documentation itself is bilingual and stays that way: `README.md` and
`README.RU.md` are edited as a pair.

## License

MIT.
