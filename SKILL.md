---
name: zread
description: Use zread-generated repository knowledge bases to understand codebases quickly. Use when the user asks to understand, summarize, onboard onto, map, or explore a repository; asks for architecture, module, API, dependency, or workflow explanations; wants to generate, regenerate, browse, or validate zread docs; mentions zread or zread.ai; or when a large unfamiliar repo may already contain `./.zread/wiki/` docs. Prefer existing zread docs before crawling source files, and generate docs only with user consent because it can consume LLM tokens.
---

# zread

Use existing zread documentation as the first source of truth for repository
understanding. zread output lives under `./.zread/wiki/`; the active version is
selected by `./.zread/wiki/current`.

## First Check

When the task is about understanding a repo, run this from the repo root before
wide source exploration:

```bash
if [ -f ./.zread/wiki/current ]; then
  version="$(cat ./.zread/wiki/current)"
  printf 'zread wiki found: %s\n' "$version"
  test -f "./.zread/wiki/versions/$version/wiki.json"
else
  printf 'no zread wiki found\n'
fi
```

If a valid wiki exists, read `wiki.json` and the relevant page markdown before
reading source files. Do not run `zread generate` just because a wiki is absent.

## Read Local Wiki

Use `wiki.json` as the routing table. Do not assume page files live under a
`pages/` directory; always use `pages[].file`.

```bash
version="$(cat ./.zread/wiki/current)"
wiki="./.zread/wiki/versions/$version/wiki.json"

# List pages.
jq -r '.pages[] | [.slug, .title, .section, .file] | @tsv' "$wiki"

# Read a page by slug.
slug="overview"
file="$(jq -r --arg slug "$slug" '.pages[] | select(.slug == $slug) | .file // empty' "$wiki" | head -n 1)"
if [ -n "$file" ] && [ -f "./.zread/wiki/versions/$version/$file" ]; then
  cat "./.zread/wiki/versions/$version/$file"
fi
```

Pick pages by intent:

| Intent | Likely slugs or titles |
| --- | --- |
| Project overview | `overview`, `introduction`, `summary` |
| Architecture | `architecture`, `system-design`, `components` |
| Setup or onboarding | `getting-started`, `installation`, `development` |
| APIs | `api`, `api-reference`, `endpoints` |
| Data model | `database`, `schema`, `models` |
| Auth/security | `authentication`, `authorization`, `security` |

For topic search, prefer `rg` for content and `jq` for the index:

```bash
query="auth"
jq -r --arg q "$query" '
  .pages[]
  | select((.slug + " " + .title + " " + (.section // "")) | test($q; "i"))
  | [.slug, .title, .file] | @tsv
' "$wiki"

rg -n -i "$query" "./.zread/wiki/versions/$version"
```

## Public Repositories and MCP

If zread MCP tools are available in the current runtime, prefer them for public
GitHub repositories because they avoid cloning:

- `mcp__zread__get_repo_structure`
- `mcp__zread__read_file`
- `mcp__zread__search_doc`

Only call these tools after confirming they are actually available. If they are
not available, fall back to local files, a local clone, or normal source
inspection. Do not block the task waiting for MCP setup unless the user asked
for MCP configuration.

## Generate or Refresh Docs

Generate only after explicit user consent. `zread generate` can take minutes and
consume paid LLM tokens.

Before generating:

```bash
zread version --stdio
test -f ~/.zread/login.json || test -f ~/.zread/config.yaml
```

If drafts exist, choose the action deliberately:

```bash
# Resume interrupted work.
zread generate --draft resume -y --stdio

# Or discard drafts and start over, only if the user agreed.
zread generate --draft clear -y --stdio
```

Use `--skip-failed` only when partial docs are acceptable.

## Browse Docs

Use browser mode for human inspection, not for agent parsing:

```bash
zread browse --stdio
```

For agents, read markdown files directly.

## Validate Wiki Freshness

When accuracy matters, compare the wiki generation time with recent commits:

```bash
version="$(cat ./.zread/wiki/current)"
generated_at="$(jq -r '.generated_at // empty' "./.zread/wiki/versions/$version/wiki.json")"
if [ -n "$generated_at" ]; then
  git log --since="$generated_at" --oneline -- . | head
fi
```

If many relevant commits landed after `generated_at`, tell the user the docs may
be stale and ask before regenerating.

## Non-Interactive Rules

- Use `--stdio` for programmatic zread commands; parse JSON lines, not the TUI.
- Always pass `-y` to unattended `generate`.
- Always set `--draft resume|clear|cancel` when drafts may exist.
- Read `~/.zread/log/zread.log` when a stdio run reports an unclear error.
- Do not run `zread update` unless the user explicitly asks.

For the full JSON-line protocol, read
`references/stdio-protocol.md` when you need to drive zread from a program.
