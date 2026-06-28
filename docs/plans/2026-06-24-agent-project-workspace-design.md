# Agent Project Workspace Design

> Date: 2026-06-24 | Status: design draft

---

## Goal

Add a Codex-like local project workspace capability to GetClawHub while preserving the existing agent sidebar model.

Users should be able to open or create a local project under a specific agent, ask questions inside that project, and let the agent inspect or modify local files through tools. The app must not upload an entire project or inject large file contents into every chat request.

The core model is:

```
Agent persona      Long-lived agent identity, capability, style
Project repo map   Local semantic index generated from the project folder
Session history    Conversation and task history for one chat session
```

Project truth must always come from the current local filesystem and tool results, not from stale conversation memory.

---

## Product Shape

### Sidebar Hierarchy

The current agent sidebar remains the primary navigation. Projects are shown under each agent as collapsible folders. Sessions without a project are placed after project folders.

```
Agents
  Frontend Agent
    PersonalWebsite v
      Session A
      Session B
    GetClowHub >
    General Chat 1
    General Chat 2

  Reviewer Agent
    GetClowHub v
      Review Session
    General Chat
```

Levels:

| Level | Item | Description |
| --- | --- | --- |
| 1 | Agents | Section title |
| 2 | Specific agent | Existing agent row |
| 3 | Project folder | Collapsible local project under the agent |
| 4 | Project session | Chat session inside that agent-project pair |
| 3 | General session | Agent-level session with no project, shown after projects |

This makes agent and project a many-to-many relationship:

- One agent can operate on many projects.
- One project can appear under many agents.
- The same project index can be shared across agents, while UI state stays agent-scoped.
- Users can still chat with an agent outside any project.

### Project Entry Points

The feature should support two project entry paths:

1. Open an existing local folder.
2. Create a project entry from a known local folder or app-created folder.

The project becomes visible in the selected agent's sidebar after it is added. Selecting the project creates or opens project-scoped sessions.

No extra Codex-style controls are required for the initial design:

- No branch selector.
- No permission selector.
- No "Work locally" selector.

The selected project itself is enough visible context.

---

## Storage Model

### Do Not Store Project Sessions In The User Project

Project chat sessions should stay in GetClowHub's own session storage, not inside the user's project folder.

The app may read project files such as `AGENTS.md`, `.codex/config.toml`, package manifests, or source files, but it should not write chat history, repo-map cache, or GetClowHub metadata into the project unless the user explicitly asks for a project artifact.

### Why Application Support

Repo maps, project bindings, and cache databases belong to GetClowHub. They should live under the app's Application Support directory because:

- They are app-owned cache and metadata.
- They should not pollute user repositories.
- They survive app restart and computer shutdown.
- They can be deleted or rebuilt without changing project source files.
- They can be versioned independently from project content.

Example layout:

```
~/Library/Application Support/GetClowHub/
  ProjectRegistry/
    projects.sqlite
  ProjectIndexes/
    <projectId>/
      index.sqlite
      symbols.sqlite
      summaries.sqlite
      manifest.json
```

### Data Entities

#### ProjectRecord

```
projectId
displayName
rootPath
createdAt
lastOpenedAt
lastIndexedAt
indexVersion
indexStatus
```

#### AgentProjectBinding

```
agentId
projectId
isCollapsed
sortOrder
lastOpenedAt
```

This lets the same project appear under multiple agents while keeping sidebar state separate.

#### ChatSession

Extend the existing session metadata with:

```
sessionId
agentId
projectId?        // nil means agent-level general chat
projectRoot?
repoMapVersion?
lastKnownGitHead?
```

Sessions with `projectId == nil` appear as general chats under the agent. Sessions with `projectId != nil` appear under that project folder.

---

## Runtime Model

### Active Context

When the user clicks an agent, project, or session, GetClowHub should build an active local execution context:

```
activeAgentId
activeProjectId?
activeSessionId
projectRoot?
repoMapVersion?
```

This context is app state, not prompt text. The model should not receive a full project summary on every turn.

When sending a chat message, the app should pass this context to the local runtime or gateway as metadata. The runtime can then expose project tools scoped to the selected project.

### Minimal Model Instruction

The model should only receive a short orientation, such as:

```
You are working as <agent name>.
Current project: <project name>, rooted at <project path>.
Use project tools to inspect files and symbols.
Do not assume stale paths are correct; verify with tools.
```

Project understanding should come from tool calls, not from a giant prompt.

### Project Tools

The local runtime should expose tools like:

```
project.map.overview(projectId)
project.map.findSymbol(projectId, query)
project.map.findReferences(projectId, symbol)
project.search(projectId, query)
project.readRange(projectId, path, startLine, endLine)
project.git.status(projectId)
project.git.diff(projectId, paths?)
project.applyPatch(projectId, patch)
```

The model sees only the results of these tools. For large files, `readRange` returns bounded line ranges. For broad questions, `map.overview` returns a compact semantic overview.

---

## Semantic Repo Map

### What `SemanticRepoMapService` Is

`SemanticRepoMapService` is not an Apple-provided backend. It is a GetClowHub internal service implemented inside the app or bundled helper runtime.

It owns:

- Initial project indexing.
- Persistent repo-map cache.
- Symbol extraction.
- Dirty-path tracking.
- Incremental reindexing.
- Project search APIs used by the agent runtime.

It can be implemented in Swift with helper binaries/libraries where needed.

### What The Repo Map Stores

The repo map is a local semantic database. It does not store every file as prompt text.

Suggested fields:

```
fileIndex:
  path
  language
  size
  modifiedAt
  contentHash
  isGeneratedGuess
  isBinary

symbolIndex:
  symbolName
  symbolKind
  filePath
  startLine
  endLine
  signature
  parentSymbol?

dependencyGraph:
  filePath
  imports
  exportedSymbols
  referencedSymbols

fileSummaries:
  filePath
  compactSummary
  summaryVersion
  contentHash

gitSnapshot:
  gitRoot
  currentHead
  branchName
  statusFingerprint
  remoteUrls
```

Management fields such as `projectId`, `rootPath`, `indexVersion`, and `lastIndexedAt` do not help the AI understand a project by themselves. They are for cache management. The AI understands the project through semantic query results: symbols, references, summaries, diffs, and bounded file reads.

### Indexing Engines

Use a layered parser strategy:

| Layer | Purpose |
| --- | --- |
| SourceKit-LSP | Swift and Xcode-oriented projects |
| tree-sitter | JavaScript, TypeScript, Python, Go, Rust, Java, etc. |
| ctags fallback | Languages without a stronger parser |
| ripgrep fallback | Text search and broad discovery |
| Git metadata | Git root, status, diffs, tracked file hints |

This follows the same general direction as tools such as Aider's repo map: build a compact code-structure map and fetch exact file content only when needed.

### Shared Index, Separate Presentation

The underlying repo map should be keyed by canonical project root:

```
canonicalRootPath -> projectId -> RepoIndex
```

If two agents use the same local folder, they should share the same semantic index. Their sidebar bindings, collapsed state, sessions, and agent-specific history remain separate.

This saves disk and avoids duplicate indexing. If later we need agent-specific overlays, add them as separate lightweight metadata instead of duplicating the whole repo map.

---

## Index Lifecycle

### First Project Open

When a user opens a project under an agent:

1. Create or reuse `ProjectRecord` for the canonical root path.
2. Create `AgentProjectBinding(agentId, projectId)`.
3. Display the project immediately in the sidebar.
4. Start repo-map indexing in the background.
5. Let the user ask immediately.

The user should not have to wait for indexing to finish.

### While Index Is Cold

If the repo map is not ready:

- The runtime can use direct tools such as `rg`, `git status`, and bounded file reads.
- The app can quietly continue indexing in the background.
- The UI may show a subtle progress dot or spinner next to the project name, but it should not show a blocking `Indexing...` state.

The feature should feel available immediately.

### App Quit, Computer Shutdown, Restart

There is no permanent macOS daemon required.

When GetClowHub quits or the computer shuts down:

- In-memory index workers and file watchers stop.
- Persistent index files remain in Application Support.
- On next app launch or project click, GetClowHub reloads the saved index.
- If needed, it restarts watchers and schedules a lightweight freshness check.

This is stable because no user-facing thread depends on a long-lived OS background process.

---

## Change Detection

### FSEvents

FSEvents is Apple's macOS file-system event API for watching directory tree changes.

GetClowHub can create an FSEvent stream for the project root while the project is active or recently used. The callback should not reindex immediately. It should only enqueue changed paths:

```
FSEvents callback
  -> normalize changed paths
  -> add to dirtyPaths
  -> debounce
  -> batch incremental reindex when idle
```

This is similar in spirit to file watching in development tools such as VS Code and Watchman.

### Updates From Agent Edits

When the agent edits files through GetClowHub-controlled tools:

```
apply_patch/edit succeeds
  -> tool returns changedPaths
  -> RepoMapService.markDirty(changedPaths)
  -> schedule incremental reindex
```

Do not rebuild the whole map after every edit.

### External Edits

When users modify files in Xcode, VS Code, Terminal, or Finder:

```
FSEvents
  -> dirtyPaths
  -> debounce 3-10 seconds
  -> background incremental reindex
```

If many changes arrive quickly, the service should coalesce them and reindex in batches.

### Query-Time Freshness

The repo map is an index, not truth. Before returning symbol or file results, the service should check cheap freshness signals:

- file existence
- modified time
- size
- content hash for targeted reads

If a result points to a missing or changed file:

1. Mark the path dirty.
2. Reindex that file or search for moved symbols.
3. Return the refreshed location when possible.
4. Tell the runtime that the map was refreshed.

This handles file moves and renames without trusting stale paths.

### Git Freshness

On project activation and after agent-controlled edits, run cheap Git checks:

```
git rev-parse --show-toplevel
git status --porcelain=v1 -b
git diff --stat
git log -1 --oneline
```

These checks update `gitSnapshot` and help the agent understand current local changes. They do not replace file-system freshness checks.

### Avoiding Excessive Work

Indexing must be intentionally lazy:

- Initial indexing runs at utility priority.
- Reindexing is incremental by changed file.
- Dirty paths are debounced and batched.
- Large generated/vendor folders are not hard ignored, but they can be summarized and deprioritized.
- Query-time reindex only touches files needed for the current question.
- Full rebuild is reserved for explicit repair, parser version changes, or severe index corruption.

---

## Model Behavior Rules

### Source Of Truth Priority

When the model answers project questions, the runtime should guide it with this priority:

```
Current tool result / filesystem read
  > current repo map query
  > current git status / diff
  > session history
  > agent persona
```

This prevents old chat history from overriding changed project files.

### Session History Effect

Session history still matters. It captures:

- user intent
- prior decisions
- edits already made in this session
- task state
- explanations already given

But it should not be treated as project truth. If the user asks about code, the agent should verify through project tools.

### Project Switches

If the user switches from one project to another inside the same agent:

- New project sessions are preferred.
- Existing project sessions remain under their original project.
- If a user explicitly moves a session to another project, clear project tool cache for that session and record a system event:

```
Project changed from <old> to <new>. Verify all paths with tools.
```

This avoids mixing state from two codebases.

---

## Integration With Existing GetClowHub

### Current Relevant Path

The existing chat send path is centered around:

- `OpenClawInstaller/ViewModels/DashboardViewModel.swift`
  - `sendChatMessage`
  - `processAttachments`
  - cancellation/task tracking
- `OpenClawInstaller/Services/GatewayClient.swift`
  - `chat.send`
  - gateway event parsing
  - tool activity classification

The current app already distinguishes tool activity such as read, edit, grep/search, and command execution. Project workspace tools should reuse that activity surface instead of creating a separate progress UI.

### Message Sending

Extend the chat send path to include project runtime metadata:

```
chat.send:
  sessionKey
  message
  attachments?
  projectContext?
    projectId
    rootPath
    repoMapVersion
```

Do not append file maps to the message text.

If the gateway cannot yet accept metadata, a first implementation can start a local agent command with the selected project as working directory, then keep the same UI session and activity stream.

### Session Keys

Project sessions should have stable session keys that include agent and project identity:

```
agent:<agentId>:project:<projectId>:session:<sessionId>
```

General agent sessions keep their current agent/session structure.

The existing pattern used for local image-review chunk sessions shows that GetClowHub can route background work through specialized session keys without changing the entire gateway protocol.

---

## UX Details

### Adding A Project

Under an agent:

- Hover plus or context menu can offer "Open Project..."
- User chooses a folder.
- Project appears under the agent immediately.
- First session can be created automatically or lazily when the user sends a message.

### Project Row

Project row should look like a folder row and behave like existing collapsible agent sections:

- collapsed/expanded chevron
- project display name
- optional subtle sync dot if background indexing is active
- context menu:
  - New chat in project
  - Reveal in Finder
  - Rename display name
  - Remove from this agent

Removing a project from one agent should remove only the `AgentProjectBinding`, not delete the shared project index or sessions under other agents.

### General Sessions

Agent-level sessions without a project appear after project folders. They remain useful for:

- brainstorming
- non-code questions
- agent-specific general work
- tasks that should not inspect a local folder

### No Blocking Index UI

Avoid a large visible `Indexing...` state. Users should not need to understand indexing before using the feature.

Acceptable low-friction indicators:

- subtle dot next to project name
- tooltip: "Preparing project context"
- no modal
- no disabled composer

If indexing fails, show a non-blocking toast and fall back to direct search/read tools.

---

## Error Handling

### Project Missing

If a project folder no longer exists:

- Mark the project row as unavailable.
- Keep sessions visible.
- Offer "Locate Folder..." and "Remove from this agent".

### Index Corrupt

If the repo map cannot load:

- Move bad index files aside.
- Rebuild in background.
- Keep chat usable through direct tools.

### File Moved

If a map result points to a missing file:

- Re-search by symbol name.
- Reindex dirty paths.
- Return the new path if found.
- Otherwise tell the model the old path no longer exists.

### Large Projects

For very large repositories:

- Start with shallow project map.
- Prioritize source files near manifests and user-mentioned paths.
- Deprioritize huge generated/vendor directories without hiding them.
- Build deeper symbol maps on demand.

---

## Phased Implementation

### Phase 1: Sidebar And Project Registry

- Add `ProjectRecord`.
- Add `AgentProjectBinding`.
- Extend session metadata with optional `projectId`.
- Render project folders under agents.
- Place general sessions after project folders.
- Persist collapsed state per agent-project binding.

### Phase 2: Runtime Context

- Track active `agentId + projectId? + sessionId`.
- Pass project context through `sendChatMessage`.
- Scope local command execution to `projectRoot`.
- Add project session keys.
- Reuse existing gateway activity parsing for read/search/edit/command events.

### Phase 3: Semantic Repo Map

- Implement `SemanticRepoMapService`.
- Store indexes in Application Support.
- Add parsers:
  - SourceKit-LSP for Swift when practical.
  - tree-sitter for common languages.
  - ctags fallback.
  - ripgrep fallback.
- Expose project tools for overview, symbol search, text search, and bounded file reads.

### Phase 4: Change Tracking

- Add FSEvents watcher for active/recent projects.
- Add dirty-path queue.
- Add debounced incremental reindex.
- Trigger reindex from successful agent edits.
- Add query-time freshness checks.

### Phase 5: Polish

- Add subtle background indexing indicator.
- Add project context tooltips.
- Add "Reveal in Finder" and "Remove from this agent".
- Add recovery UI for missing folders or corrupt indexes.
- Add lightweight diagnostics for index size and freshness.

---

## Open Questions

1. Should "Open Project..." live on each agent row only, or also in the top-level sidebar actions?
2. Should the first project session be created immediately when a project is added, or only when the user sends the first message?
3. Should project display names be global per project or customizable per agent binding?
4. Should the shared repo map be deleted when the last agent binding is removed, or kept as a recent project cache?
5. Should non-code projects use a document-oriented map instead of the code-oriented semantic map?

---

## Key Design Decisions

| Topic | Decision |
| --- | --- |
| Sidebar | Projects live under agents; general sessions shown after project folders |
| Relationship | Agents and projects are many-to-many |
| Sessions | Project sessions are stored in GetClowHub session storage, not user project folders |
| Index storage | Repo maps live in Application Support |
| Index sharing | Same local project shares one repo map across agents |
| Index UX | Background and non-blocking |
| Model context | Model receives project identity and uses tools; no full project prompt injection |
| Change detection | FSEvents + agent edit notifications + query-time freshness |
| Reindex strategy | Incremental, debounced, lazy |
| Truth source | Local filesystem/tool results beat repo map and chat history |

