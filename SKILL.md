---
name: zread
description: Produce and consume a wiki-style knowledge base for a code repository via the `zread` CLI and its on-disk output under `./.zread/wiki/`. Use this skill whenever the user wants to understand, onboard onto, explore, summarize, map, or get an overview of an unfamiliar codebase; asks for architecture docs, a project wiki, a repo walkthrough, module/package explanations, or "what does this repo do"; wants to generate, regenerate, resume, browse, or serve code documentation locally; or mentions zread / zread.ai directly. Also use it proactively before diving into a large unknown repo — if `./.zread/wiki/current` exists, read the generated pages instead of crawling source file-by-file; if it doesn't, consider offering to run `zread generate`. The trigger is the intent (understand a codebase through generated docs), not the literal word "zread".
---

# zread skill

`zread` is a CLI that generates wiki documentation from code in the current
workspace using an LLM. Output lives under `./.zread/wiki/` in the workspace;
public repos can also be viewed at https://zread.ai.

This skill is intended for agent use. **ALWAYS check for and read existing zread
documentation first** before exploring source files or generating new docs.

## CRITICAL: Check for existing knowledge base FIRST

**Before doing ANY codebase exploration, ALWAYS run this check:**

```bash
# Check if zread knowledge base exists
if [ -f ./.zread/wiki/current ]; then
  echo "✅ zread knowledge base found"
  cat ./.zread/wiki/current
else
  echo "❌ No zread knowledge base"
fi
```

If the knowledge base exists, **you MUST use it** instead of reading source files
directly. This is the primary value of zread — avoiding redundant file crawling.

## Decision Tree: Local vs MCP

### For Public GitHub Repositories

**ALWAYS prefer MCP tools over local CLI for public repos:**

```bash
# Detect if it's a public GitHub repo
if [[ "$REPO_URL" =~ github.com/([^/]+)/([^/]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
  USE_MCP=true
fi
```

**MCP Tools (Recommended for public repos):**
- ✅ No local clone needed
- ✅ Always up-to-date (reads from zread.ai)
- ✅ Zero disk space
- ✅ Works from anywhere

**Use MCP tools in this order:**

1. **Get structure overview**
   ```
   Tool: mcp__zread__get_repo_structure
   Input: { "owner": "multica-ai", "repo": "multica" }
   Output: Complete page index with titles, slugs, sections
   ```

2. **Read specific pages**
   ```
   Tool: mcp__zread__read_file
   Input: { "owner": "multica-ai", "repo": "multica", "path": "overview" }
   Output: Full markdown content
   ```

3. **Search documentation**
   ```
   Tool: mcp__zread__search_doc
   Input: { "owner": "multica-ai", "repo": "multica", "query": "authentication" }
   Output: Relevant page excerpts with context
   ```

### For Private/Local Repositories

**Use local `.zread/wiki/` files:**
- Faster (no network latency)
- Works offline
- Access to unpublished docs

## How to utilize existing knowledge base (Local)

### Step 1: Read the version and index

```bash
# Get current version ID
VERSION=$(cat ./.zread/wiki/current)

# Read the table of contents
cat ./.zread/wiki/versions/$VERSION/wiki.json
```

The `wiki.json` contains:
- `id`: version identifier
- `generated_at`: timestamp
- `language`: documentation language
- `pages[]`: array of all documentation pages
  - `slug`: page identifier (e.g., "overview", "architecture")
  - `title`: human-readable title
  - `file`: markdown filename
  - `section`: category grouping
  - `group`: sub-grouping
  - `level`: hierarchy level

### Step 2: Smart page recommendation

**Analyze user's question and read only relevant pages:**

```bash
# Question analysis keywords
case "$USER_QUESTION" in
  *architecture*|*design*|*structure*)
    PAGES=("architecture" "system-design" "components")
    ;;
  *setup*|*install*|*start*)
    PAGES=("getting-started" "installation" "setup")
    ;;
  *api*|*endpoint*|*rest*)
    PAGES=("api" "endpoints" "rest-api")
    ;;
  *auth*|*login*|*security*)
    PAGES=("authentication" "authorization" "security")
    ;;
  *database*|*schema*|*model*)
    PAGES=("database" "schema" "models")
    ;;
  *)
    PAGES=("overview")
    ;;
esac

# Read recommended pages in parallel
VERSION=$(cat ./.zread/wiki/current)
for page in "${PAGES[@]}"; do
  FILE=$(jq -r ".pages[] | select(.slug == \"$page\") | .file" \
    ./.zread/wiki/versions/$VERSION/wiki.json)
  [ -n "$FILE" ] && cat ./.zread/wiki/versions/$VERSION/$FILE &
done
wait
```

### Step 3: Search for specific topics

```bash
VERSION=$(cat ./.zread/wiki/current)

# Search with jq (structured search)
jq -r '.pages[] | select(.title | test("auth"; "i")) | "\(.slug): \(.title)"' \
  ./.zread/wiki/versions/$VERSION/wiki.json

# Full-text search (content search)
grep -rin "authentication" ./.zread/wiki/versions/$VERSION/*.md

# Search with context (3 lines before/after)
grep -rin -C 3 "authentication" ./.zread/wiki/versions/$VERSION/*.md
```

### Step 4: Parallel reading for performance

```bash
VERSION=$(cat ./.zread/wiki/current)

# Read multiple pages in parallel (3-5x faster)
{
  cat ./.zread/wiki/versions/$VERSION/overview.md &
  cat ./.zread/wiki/versions/$VERSION/architecture.md &
  cat ./.zread/wiki/versions/$VERSION/api.md &
  wait
}
```

## MCP Tools Usage Examples

### Example 1: Understanding a Public Repo

**Scenario**: User asks "Explain the Multica architecture"

```javascript
// Step 1: Get structure
const structure = await mcp__zread__get_repo_structure({
  owner: "multica-ai",
  repo: "multica"
});
// Returns: { pages: [{slug: "architecture", title: "System Architecture", ...}] }

// Step 2: Read architecture page
const content = await mcp__zread__read_file({
  owner: "multica-ai",
  repo: "multica",
  path: "architecture"
});

// Step 3: Answer user's question using the content
```

### Example 2: Searching Documentation

**Scenario**: User asks "How does authentication work?"

```javascript
// Use semantic search
const results = await mcp__zread__search_doc({
  owner: "multica-ai",
  repo: "multica",
  query: "how to authenticate users",  // Natural language
  limit: 5
});
// Returns ranked results with relevance scores and excerpts
```

### Example 3: Parallel MCP Calls

```javascript
// Read multiple pages in parallel
const [overview, architecture, api] = await Promise.all([
  mcp__zread__read_file({ owner, repo, path: "overview" }),
  mcp__zread__read_file({ owner, repo, path: "architecture" }),
  mcp__zread__read_file({ owner, repo, path: "api" })
]);
```

## Error Handling and Fallback

### Robust Error Handling

```bash
# Try MCP first for public repos
if ! mcp__zread__get_repo_structure 2>/dev/null; then
  echo "⚠️  MCP tool failed, trying local fallback..."
  
  # Fallback 1: Check local .zread/
  if [ -f ./.zread/wiki/current ]; then
    echo "✅ Using local zread docs"
    VERSION=$(cat ./.zread/wiki/current)
    cat ./.zread/wiki/versions/$VERSION/wiki.json
  else
    # Fallback 2: Offer alternatives
    echo "❌ No documentation available"
    echo "Options:"
    echo "1. Clone repo and run 'zread generate'"
    echo "2. Visit https://zread.ai/$OWNER/$REPO in browser"
    echo "3. Read source files directly (slower, more expensive)"
  fi
fi
```

## Documentation Quality Check

Before using zread docs, verify quality:

```bash
VERSION=$(cat ./.zread/wiki/current)

# Check 1: Minimum page count
PAGE_COUNT=$(jq '.pages | length' ./.zread/wiki/versions/$VERSION/wiki.json)
if [ "$PAGE_COUNT" -lt 3 ]; then
  echo "⚠️  Warning: Only $PAGE_COUNT pages. Documentation may be incomplete."
fi

# Check 2: Verify critical pages exist
CRITICAL_PAGES=("overview" "architecture" "getting-started")
for page in "${CRITICAL_PAGES[@]}"; do
  if ! jq -e ".pages[] | select(.slug == \"$page\")" \
    ./.zread/wiki/versions/$VERSION/wiki.json > /dev/null; then
    echo "⚠️  Warning: Missing critical page: $page"
  fi
done

# Check 3: Check for empty pages
for file in ./.zread/wiki/versions/$VERSION/*.md; do
  if [ $(wc -l < "$file") -lt 10 ]; then
    echo "⚠️  Warning: $(basename $file) is very short (< 10 lines)"
  fi
done
```

## Typical Usage Patterns

### Pattern 1: Quick project overview

```bash
VERSION=$(cat ./.zread/wiki/current)
cat ./.zread/wiki/versions/$VERSION/overview.md
```

### Pattern 2: Find and read specific module

```bash
VERSION=$(cat ./.zread/wiki/current)

# Search for module
FILE=$(jq -r '.pages[] | select(.title | test("UserService"; "i")) | .file' \
  ./.zread/wiki/versions/$VERSION/wiki.json)

# Read the module page
cat ./.zread/wiki/versions/$VERSION/$FILE
```

### Pattern 3: Understand architecture before changes

```bash
VERSION=$(cat ./.zread/wiki/current)

# Read architecture overview
cat ./.zread/wiki/versions/$VERSION/architecture.md

# Read related component docs in parallel
{
  cat ./.zread/wiki/versions/$VERSION/database-layer.md &
  cat ./.zread/wiki/versions/$VERSION/api-layer.md &
  wait
}
```

### Pattern 4: Onboarding workflow

```bash
VERSION=$(cat ./.zread/wiki/current)

# Read in sequence for onboarding
cat ./.zread/wiki/versions/$VERSION/overview.md
cat ./.zread/wiki/versions/$VERSION/getting-started.md
cat ./.zread/wiki/versions/$VERSION/architecture.md
cat ./.zread/wiki/versions/$VERSION/development.md
```

## Commands

| Command | Purpose | Key flags |
|---|---|---|
| `zread generate` | Generate wiki for cwd | `-y/--yes`, `--draft resume\|clear\|cancel`, `--skip-failed`, `--stdio` |
| `zread browse` | Serve docs at http://localhost:9681+ and open browser | `--generate`, `--version <id>`, `--host`, `--port`, `--stdio` |
| `zread login` | OAuth into BigModel/Z.AI to obtain an API key | `--custom`, `--model`, `--stdio` |
| `zread config` | Edit `~/.zread/config.yaml` | `--stdio` |
| `zread update` | Self-update CLI | `--stdio` |
| `zread version` | Print version | `--stdio` |

`--stdio` is supported on every command and turns the process into a JSON-line
machine protocol on stdin/stdout. See
[references/stdio-protocol.md](./references/stdio-protocol.md) for the wire
format (events, `waiting_for`, `done`, `quit`). Load it whenever zread is
invoked from another program/agent.

## When to Generate Documentation

### User wants to (re)generate docs?

- Confirm with the user first — `generate` is long-running, calls an LLM,
  and writes files. Get explicit consent in unfamiliar directories.
- Verify `~/.zread/login.json` exists or `~/.zread/config.yaml` has an
  `llm.api_key`. If neither, run `zread login` first.
- If `./.zread/wiki/drafts/` exists, decide:
  - resume previous run → `zread generate --draft resume -y --stdio`
  - throw away and start fresh → `zread generate --draft clear -y --stdio`
- Otherwise: `zread generate -y --stdio`.
- To not block on a few failing pages: add `--skip-failed`.

### User wants to view docs in a browser?

- `zread browse` (add `--generate` to bootstrap if no wiki exists yet).

## Non-interactive invocation rules

- Always pass `-y` to `generate` when running unattended; otherwise it stops
  at a catalog confirmation gate.
- Always set `--draft` explicitly when a draft may exist, so the command does
  not prompt.
- For any command run from another agent/script, use `--stdio` so output is
  parseable JSON instead of ANSI TUI frames.
- `zread` writes logs to `~/.zread/log/zread.log` — read this if a run fails
  silently.

## Safety / blast radius

- `generate` consumes LLM tokens (real cost) and can run for many minutes on
  large repos. Confirm before launching.
- `generate` writes only under `./.zread/` and does not commit anything to
  git. It is safe to delete `./.zread/wiki/drafts/` to recover from a stuck
  state.
- `update` replaces the zread binary in place and is hard to reverse — only
  run it when the user explicitly asks.
- `login` opens a browser for OAuth; do not run it in a non-interactive
  context unless the user has asked for it.

## When documentation might be stale

If the codebase has changed significantly since the last generation:

```bash
# Check when docs were generated
VERSION=$(cat ./.zread/wiki/current)
GENERATED_AT=$(jq -r '.generated_at' ./.zread/wiki/versions/$VERSION/wiki.json)

# Compare with recent git activity
COMMIT_COUNT=$(git log --since="$GENERATED_AT" --oneline 2>/dev/null | wc -l | tr -d ' ')

if [ "$COMMIT_COUNT" -gt 50 ]; then
  echo "⚠️  Warning: $COMMIT_COUNT commits since documentation was generated"
  echo "   Consider regenerating: zread generate -y"
fi
```

## Performance Tips

### 1. Use MCP for public repos
- No clone needed
- Always up-to-date
- Zero disk space

### 2. Read pages in parallel
- 3-5x faster than sequential
- Use `&` and `wait` in bash
- Use `Promise.all()` for MCP calls

### 3. Smart page selection
- Analyze user's question
- Read only relevant pages
- Avoid reading all 50+ pages

### 4. Cache MCP results (optional)
```bash
# Cache for 1 hour
mkdir -p .zread-cache/
CACHE_FILE=".zread-cache/$OWNER-$REPO-structure.json"

if [ -f "$CACHE_FILE" ] && [ $(find "$CACHE_FILE" -mmin -60 2>/dev/null) ]; then
  cat "$CACHE_FILE"
else
  mcp__zread__get_repo_structure | tee "$CACHE_FILE"
fi
```

## Reference files

- [references/stdio-protocol.md](./references/stdio-protocol.md) — JSON-line
  wire protocol shared by every command's `--stdio` mode. Load when
  programmatically driving zread.
