# Changelog

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
the flag. The patterns and the two-tier split come from
[env2hell](https://github.com/vadbosh/env2hell).

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
`--sum-raw` shows exactly what would have been sent. Two tiers, matching
`safe-env`: an unmistakable shape (`ghp_`, `AKIA`, `glpat-`, `xox…`, `sk-`,
`AIza`, `ATATT`, `hf_`, `dckr_pat_`, a JWT, a PEM header, a password inside a
URL) is masked anywhere; a merely plausible one (40 characters of base62, 32 of
hex) only on a line that also names a credential, in English or Russian.
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
