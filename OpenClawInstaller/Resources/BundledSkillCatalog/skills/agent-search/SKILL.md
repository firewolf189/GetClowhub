---
name: agent-search
description: Internet research and search routing for web pages, social platforms, GitHub, videos, jobs, finance, and OpenCLI-backed site adapters. Use when the user asks to search, research, look up, inspect a URL, find discussions, compare sources, or choose an OpenCLI/API/CLI source. Routes across AgentSearch backends, gh, Exa/Jina, platform CLIs, and OpenCLI without duplicating search logic.
metadata:
  openclaw:
    display_name: AgentSearch
    homepage: https://github.com/Panniantong/Agent-Reach
---

# AgentSearch

Use this as the single search and internet-research router. It replaces the separate `agent-reach`, `opencli-usage`, and `smart-search` entries: keep one routing decision tree, then load only the reference that matches the task.

## Core Rules

1. Start with routing, not browsing. Pick the best backend for the requested source, freshness, login needs, and evidence quality.
2. Say which route you are using, for example: "Using AgentSearch via GitHub CLI" or "Using AgentSearch via OpenCLI/xiaohongshu".
3. Prefer source-native or structured tools before raw browser automation.
4. Use browser automation only when the page requires rendering, authenticated UI interaction, or no structured backend exists.
5. Keep a short source ledger for multi-source research: source, query, attempt count, status.
6. Do not invent command syntax. For OpenCLI, inspect the live registry/help before using a site adapter.

## Primary Route Map

| User asks for | Preferred route | Reference |
| --- | --- | --- |
| General web search or broad research | Exa/search, then direct source reading | `references/search.md` |
| Web page, article, RSS, URL reading | Jina Reader, direct page, or browser fallback | `references/web.md` |
| GitHub repo, issue, PR, code search | `gh` CLI or GitHub search | `references/dev.md` |
| Twitter/X, Reddit, 小红书, B站, V2EX | Platform CLI or OpenCLI backend selected by doctor/help | `references/social.md` |
| LinkedIn/jobs/career | Career source routing | `references/career.md` |
| YouTube, B站, podcast subtitles | Video and transcript route | `references/video.md` |
| OpenCLI-backed search across sites | `opencli list -f json`, site help, then adapter command | OpenCLI sections below |

For open-ended research, combine one broad source with one or two source-specific checks. Do not fan out to many sources unless the user explicitly asks for a wide survey.

## AgentSearch Backend Check

For multi-backend AgentSearch platforms, run:

```bash
agent-reach doctor --json
```

Use the reported active backend for the target platform. The command name remains `agent-reach` because it is the upstream CLI; the skill display name is AgentSearch.

## OpenCLI Route

Use OpenCLI when a site adapter exists, when login state is needed through the user's browser, or when a site-specific adapter is more reliable than raw scraping.

Always start with live discovery:

```bash
opencli list -f json
opencli <site> --help
opencli <site> <command> --help
```

Read the `strategy` before deciding whether browser setup is needed:

| Strategy | Meaning |
| --- | --- |
| `PUBLIC` | No browser or login required. |
| `LOCAL` | Talks to local/dev endpoints. |
| `COOKIE` | Needs Chrome login and OpenCLI extension. |
| `INTERCEPT` | Needs Chrome login plus captured signed request. |
| `UI` | Needs browser DOM interaction. |

Use `-f json` for agent consumption unless the command help says another format is better. Use `-v` only for debugging.

## OpenCLI Search Budget

For one user question:

- Use at most one AI-style source by default (`grok`, `doubao`, or `gemini`) when no exact source is specified.
- Use source-specific adapters when the user names a platform or when broad AI output lacks primary evidence.
- Limit each AI source to one real query per question.
- Limit each non-AI site to two real queries unless the user asks for deeper searching.
- Help/list commands do not count as search attempts.

When the task is complete, include a concise search summary for multi-source work:

```md
Search summary
- Source: <site> | Query: <term> | Attempts: <n>
- Skipped: <site>, reason: unavailable or rate limit
```

## OpenCLI Capabilities To Preserve

- Adapter commands: `opencli <site> <command> ...`
- Browser driving fallback: `opencli browser <session> ...`
- Current-tab binding: `opencli browser <session> bind`
- External CLI passthrough: `opencli gh ...`, `opencli docker ...`, etc.
- Plugin management: `opencli plugin install/list/update/uninstall`
- Adapter repair: rerun failing adapter commands with `--trace retain-on-failure`, then patch only the adapter source path reported by the trace.

Do not hard-code adapter lists. The registry changes; `opencli list -f json` is the source of truth.

## OpenCLI Source References

Use these only when the query needs OpenCLI source selection beyond the primary route map:

- `references/opencli-sources-ai.md` — AI default sources
- `references/opencli-sources-tech.md` — technology, code, academic sources
- `references/opencli-sources-social.md` — social platforms
- `references/opencli-sources-media.md` — media and entertainment
- `references/opencli-sources-info.md` — knowledge and news sources
- `references/opencli-sources-shopping.md` — shopping sources
- `references/opencli-sources-travel.md` — travel sources
- `references/opencli-sources-other.md` — other vertical sources

## Avoid

- Do not load all references for every task.
- Do not use OpenCLI when a simpler source-native route is better, such as `gh` for GitHub.
- Do not silently switch from a failing adapter to hand-written scraping before collecting trace/help output.
- Do not repeat the same search source with small keyword changes after hitting the per-question budget.
