# Changelog

## 0.8.0

**`billing` says what each table is.** A table of dates under `DAY` read as a
data dump, and `billing week` read as "one week". Every table now opens with a
line naming the period, the IDEs and that periods with no usage are not listed,
then which rows it holds — "last 20 of 71 days with usage, 2026-08-29 …
2026-09-25". The verbs are plural, `days`, `weeks`, `months` (the singular
still works), a week row names both its Monday and its Sunday, `today` is one
row, and the sum is `TOTAL (rows above)`.

**`billing block` covers all three IDEs.** It was ccusage's own Claude Code
screen under the name `live`, with nothing saying what it belonged to. Now:
Claude Code's open 5-hour window — spent, rate, where the rate leads by its
end; Codex's used share of each window and when it resets, read from the
`rate_limits` its server logs beside every response, with a reading whose reset
has already passed flagged as out of date; and opencode, which keeps no limit
data in its SQLite store, said in so many words. `live` still works.

**One form of `--id` for every IDE.** The help showed `--ide codex` on the
Codex example alone, as if Codex needed it. It never did: the IDE is found from
the id, and `--ide` only narrows a prefix two IDEs share. The examples are now
one line per IDE in the same form, and the session card opens with the IDE.

## 0.7.0

**A fourth command, `billing`: what the sessions cost.** It answers two
questions — how much per day, week or month across Claude Code, Codex and
opencode, with a cost column per IDE and a TOTAL row, and what one session
cost, given the id the session commands show. ccusage does the pricing;
`billing` picks the view and lays out the table.

It lived outside this repository as a wrapper that had grown one view per
question and none of them fit: tables with a header only at the top, a Codex
session named by a twelve-character slice of its transcript path, and every
filter reachable only after `--`. The views are two now, the filters are its
own, and a Codex session is found by the uuid `codex-sessions` shows — ccusage
names it by the path, and the uuid is the path's tail.

Missing ccusage, `billing` says how to install it and exits 127; `--help` works
without it. `install.sh` installs `billing` with the other three and reports
whether ccusage and `jq` are present. Tested against a ccusage stub.

## 0.6.6

**`opencode-sessions` printed the cost as a raw float.** opencode stores it as
a REAL, and the value went straight into the COST column —
`$0.17838120000000002` — pushing every column after it out of line. It is
rounded to cents in the query now, `$0.18`, in the listing and in the `--rm`
preview alike. A test pins it with that very value.

## 0.6.5

**`claude-sessions -p` printed nothing at all in a directory that never hosted
a session.** No header, no message, exit 1. Claude Code files a session under a
directory derived from the cwd, that directory did not exist, `find` over a
missing path failed, and `set -euo pipefail` ended the script before its first
line of output. `codex-sessions` had the same hole for a machine with no
`~/.codex/sessions` yet.

Both now say what happened, and in the same sentence: a missing project
directory and a present one holding no sessions are one fact to whoever is
reading, so they no longer print two different messages of two different
lengths in the same tool.

An empty result is no longer an empty table in any of the three either: the
message names the scope that came up empty — this directory, that substring, or
nothing recorded at all — because a bare header row is indistinguishable from a
tool that failed quietly.

## 0.6.4

**Every example that deletes now says DELETES.** The help listed
`--older-than 30 --apply` against the words "this project, older than 30 days"
— a description of the selection, with no verb anywhere near it. Read quickly,
it looks like a filter. Each line in the examples block now leads with what
happens: lists, or DELETES, and the tests fail if a form carrying `--apply`
appears without the verb.

## 0.6.3

**`--help` ends with the combinations.** A flag list answers what `--rm-all`
means, not how to clear one project — and the scope lived in a different flag
on a different line. All three commands now print the working forms together:
the listing and the delete of that same selection, the substring form, the bare
`--rm-all` shown as refused, and `--everywhere` as the way to ask for the sweep.

## 0.6.2

**A bare `--rm-all` refuses instead of selecting the whole machine.** Unscoped
it means every session of every project, and that is exactly the form someone
types first — before finding the `-p` that narrows it. It now prints the three
scoped forms and exits 1. The machine-wide sweep still exists, asked for by
name: `--rm-all --everywhere`, dry-running like everything else.

## 0.6.1

**`--rm-all` deletes everything the filters select.** Clearing one project meant
`--older-than 0` — "older than no days", which is true of every session and
appears in no help text. The flag now says what it does, narrows with `-p` or a
directory substring like the listing does, dry-runs until `--apply`, and leaves
the live session alone.

## 0.6.0

**Summarizing no longer breeds sessions.**

`claude -p` and `codex exec` open a session like anything else, so every `--sum`
added a row to the listing this tool exists to keep readable — two summaries in
a row looked like the tool multiplying sessions by itself. opencode was already
cleaned up after; the other two were not.

Each is removed by something that cannot match a session belonging to someone
else. Claude Code takes a `--session-id` chosen here, so exactly one UUID is
deleted, and the cleanup runs from a trap as well, for a summary interrupted
half way. Codex chooses its own id, so the rollout is identified by having
appeared during the call *and* containing the prompt this script sends —
deleting the newest file instead would have taken the rollout of a Codex
running in another terminal, which appends to it continuously.

Three tests stand on it now, including one that a rollout which is not ours
survives.

## 0.5.2

**Both READMEs say why an old session is missing from the listing.** It looks
like a bug in the tool and is not one: Claude Code prunes transcripts older
than `cleanupPeriodDays` and takes only the `.jsonl`, so the project directory
survives with its notes and no sessions. Codex and opencode delete nothing —
their `[history]` and storage options are about the prompt history, not the
rollouts — so their oldest session is just the day the IDE was first used.

## 0.5.1

**Deleting a session deletes its summaries.** They outlived it: a 1.5 kB file
named after an id that no longer resolves to anything. For Claude Code and
Codex they join the footprint that already moves to the trash; for opencode,
where the session itself is rows in a database, the two files are moved into
the same trash directory beside the row dump. Restoring is the same `cp -a` it
was before.

## 0.5.0

**A summary of a long session no longer looks like a hang.**

Measured on a 9 MB, 4577-line transcript: the local digest takes 0.6 s and the
model call 79 s, because one model is writing a summary of ten separate
stretches of work. Nothing said so, and a terminal silent for over a minute
reads as a stuck command. There is now a counter on stderr — `summarizing 10
part(s) with claude-haiku-4-5-20251001… 37s` — printed only when stderr is a
terminal, so a pipe or a script still sees the summary alone.

**A cache hit does no work.** The transcript was parsed first and the cache
consulted afterwards, so a hit paid the full 0.6 s of parsing to throw the
result away. The key needs only the mtime and the model, so it is checked
first: 1.1 s to 0.3 s on that same session.

**Both READMEs say where summaries live**, since "cached" was doing a lot of
unexplained work: one Markdown file per session and language under
`~/.cache/ide-sessions-summaries/`, `0600` in a `0700` directory, the key on
the first line. The only SQLite anywhere is opencode's own session store, which
is read, never written with a summary.

## 0.4.2

**`--sum-orig <ID>` needs no second flag.**

Naming the session through one flag and the language through another —
`--sum <ID> --sum-orig` — is ceremony for what is one request. The id can now
follow `--sum-orig` directly; a word after it that starts with `-` is still
read as a flag, so `--sum-orig --sum <ID>` keeps working. Both READMEs and
`--help` show the short form.

## 0.4.1

**Huawei Cloud, OpenStack and Jira credentials are masked too.**

Their keys have no distinctive prefix: a Huawei access key is 20 characters of
upper case and digits, the secret 40 of base62 — indistinguishable from a git
SHA or a build id, so tier 1 cannot claim them. The label beside the value can,
and now does: `HW_ACCESS_KEY=`, `HUAWEICLOUD_SDK_AK=`, `OS_SECRET_KEY:`, plus
the flag forms `--token`, `--pass` and `Authorization: Bearer`. Jira arrives in
both tiers — `ATATT` and the legacy `at-` prefix by shape, `jira --token …` by
the flag.

**The documentation stopped being about Claude Code only.**

Every example was a `claude-sessions` one, which read as if the other two were
afterthoughts. Both READMEs now show all three listings side by side, the same
session summarized through Codex and opencode, and say once that the flags are
identical rather than repeating each command three times.

**The model auto-selection is written down, per IDE.** The order was in the
scripts and nowhere else: the catalogue lookup for Claude Code with its two
fallbacks, the configured model plus lowered reasoning for Codex, and for
opencode the deliberate decision not to choose — 385 models whose availability
differs per machine is not a list to pick from silently.

## 0.4.0

**Credentials in a session no longer reach the summary.**

The digest copied reply text verbatim, so a key pasted into a prompt or echoed
back in an answer would have gone to the summarizing API — possibly a different
vendor than the session itself ran on — into a cache file, and onto the
terminal of the session asking, which is recorded in turn.

Masking now happens in the digest, before anything leaves the process, and
`--sum-raw` shows exactly what would have been sent. Two tiers: an unmistakable
shape (`ghp_`, `AKIA`, `glpat-`, `xox…`, `sk-`, `AIza`, `ATATT`, `hf_`,
`dckr_pat_`, a JWT, a PEM header, a password inside a URL) is masked anywhere; a
merely plausible one (40 characters of base62, 32 of hex) only on a line that
also names a credential, in English or Russian.
Without that condition every git SHA would come back as `<REDACTED>`.

The marker keeps the length of what it replaced. URLs keep their scheme and
host, so `postgres://<REDACTED:10>@db.internal:5432/app` still says which
database was involved.

Alongside: the prompt forbids writing a credential out, summary files are
created `0600` inside a `0700` directory. A key already in a transcript still
has to be rotated — this stops the summary from copying it somewhere new.

## 0.3.0

**`--sum-orig` — the same summary in the language the session was held in.**

`--sum` exists so a colleague can read a session they did not run, which is why
it always answers in English. Reading back your own session is the other half
of the same need, and there the translation is a loss: the words you typed come
back as someone else's. `--sum-orig` takes the language the user typed most and
writes in that one.

- The two are cached side by side (`<id>.md` and `<id>.orig.md`), so a session
  can hold an English summary and a native one at once.
- One prompt with one variable rule, not two prompts — everything else about
  what a summary should contain stays in a single place.

## 0.2.0

**`--sum ID` — an English summary of one session, grouped by topic.**

A local pass reduces the session to a digest (asks, short excerpts of replies,
tool counts, split where the work stopped), then one model call turns that into
headings and bullets. `--sum-raw` stops after the local pass and costs nothing.

- English regardless of the session's language, including a session that mixes
  Russian, German and English inside one sentence. Code, paths, commands and
  error strings stay verbatim.
- Each script calls its own IDE's CLI (`claude -p`, `codex exec`,
  `opencode run`), so no machine needs an IDE it does not use.
- Summaries are cached in `~/.cache/ide-sessions-summaries/`, keyed by the
  transcript's mtime: asking twice about an unchanged session costs once.
- Model choice is data-driven, never a pinned name. `claude-sessions` reads the
  cheapest priced Anthropic model from a models.dev catalogue already on disk
  and falls back to the CLI's small-model alias; the other two use the model
  their IDE already resolves. `--sum-model` / `IDE_SESSIONS_SUM_MODEL` override.
- Context is trimmed for the call: a one-line headless `claude -p` prompt
  measured 40 179 input tokens with the user's CLAUDE.md, skills and MCP
  servers loaded, and 4 591 with `--setting-sources ''` and an empty MCP
  config. Codex switches off skills, MCP and hooks the same way.
- New flags: `--sum-model`, `--sum-gap`, `--sum-refresh`, `--sum-raw`.

**`opencode-sessions` no longer needs the `sqlite3` CLI.**

That CLI is a separate package and was absent on the machine this was written
on — the command printed `sqlite3 not found` and listed nothing. Every query,
the row dump that used `.mode insert`, and the delete transaction now go
through Python's bundled `sqlite3` module. Seed ids are passed as bound
parameters instead of being interpolated into SQL.

**Codex rollouts from codex-cli 0.154 are read.**

The turn events changed from `event_msg/user_message` to
`response_item/message` with a role. Both layouts are supported, and a file
written across an upgrade — which carries both forms of the same turn — does
not count it twice.

**Repository, installer and tests.**

The three commands, until now hand-copied into `~/.local/bin`, live in a repo
with `install.sh` (idempotent, `--dry-run`, `--uninstall`, backs up only files
git has never seen) and a test suite that builds throwaway storage for each IDE
and calls no model.

## 0.1.0

The three session listers as they were used before this repository existed:
`claude-sessions`, `codex-sessions`, `opencode-sessions`. Listing with the
directory a session is really bound to, `--rm` by id, `--older-than` and
`--max-turns` pruning with a dry run until `--apply`, and deletes that move the
whole footprint to a trash directory instead of unlinking it.
