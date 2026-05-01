# Multi-Agent Collaborative Task Design

## Overview

在 GetClawHub Chat 页面实现多 Agent 协同对话功能，通过专用 commander agent 拆解大任务、分派给专业 agent 并行执行、汇总结果，配合独立的协同任务窗口展示实时进度。

## Core Decisions

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Collaboration model | Commander mode | Commander decomposes and delegates |
| Commander identity | Dedicated commander agent | Clean separation from daily chat |
| Trigger method | `/collab` command | Explicit, user-controlled |
| UI display | Task cards in separate window | Chat stays for conversation, collab window for progress |
| Orchestration | App-side (Swift) | Full control over task card state updates |
| Session isolation | `getclawhub-collab-<taskId>-<agentId>` | Per-task, per-agent isolation |
| Missing agents | Fallback to main + role injection | Works out of the box, no setup required |
| User intervention | Commander parses natural language → structured JSON action | AI handles NLU, App executes |

## Architecture

### Overall Flow

```
User: /collab <task description>
        │
        ▼
  ┌─────────────────┐
  │  Commander    │  Step 1: Decompose
  │  Returns JSON    │
  └────────┬────────┘
           │ App parses JSON, renders task cards
           │ Opens Collab Window
           ▼
  ┌────┬────┬────┐
  │ Task1  │ Task2  │ Task3  │   Task cards (all "pending")
  └──┬─┘└──┬─┘└──┬─┘
     │     │     │
     ▼     ▼     ▼           Step 2: Execute
  App calls: openclaw agent --agent <agentId>
             --session-id getclawhub-collab-<taskId>-<agentId>
             -m '<subtask prompt>'
  Card status updates in real-time
           │
           ▼ All completed
  ┌─────────────────┐
  │  Commander    │  Step 3: Summarize
  │  Final result    │
  └────────┬────────┘
           │
           ▼
     Final result displayed in Chat
```

### Three API Rounds

1. **Decompose** — Send task to commander, receive subtask JSON
2. **Execute** — App calls each sub-agent, collects results
3. **Summarize** — Feed all results back to commander, display final answer

## Commander Agent

### Persona

Commander is a dedicated agent created in `~/.openclaw/openclaw.json` under `agents.list`. Its persona is optimized for:

- Understanding task requirements
- Decomposing into discrete subtasks
- Matching subtasks to available agents by capability
- Generating structured JSON output
- Summarizing results from multiple agents

### Input Format (Decompose Phase)

App injects available agents and user task into the message:

```
[Available Agents]
- coder: Skilled in writing code, debugging, refactoring
- reviewer: Skilled in code review, quality analysis
- writer: Skilled in documentation, content creation

[User Task]
Build a TODO app with complete code and documentation

Please decompose this task into subtasks and assign to available agents.
Return your response as JSON in the following format:
{
  "summary": "Brief description of the plan",
  "tasks": [
    {
      "id": 1,
      "title": "Task title",
      "agent": "agent_id or null if no match",
      "role": "Role description for fallback (used when agent is null)",
      "prompt": "Detailed prompt for the sub-agent",
      "depends_on": []
    }
  ]
}
```

### Output Format (Decompose Phase)

```json
{
  "summary": "Build TODO app: 3 subtasks",
  "tasks": [
    {
      "id": 1,
      "title": "Write core code",
      "agent": "coder",
      "role": null,
      "prompt": "Build a TODO app in Swift with add/delete/toggle...",
      "depends_on": []
    },
    {
      "id": 2,
      "title": "Review code quality",
      "agent": "reviewer",
      "role": null,
      "prompt": "Review the following TODO app code...",
      "depends_on": [1]
    },
    {
      "id": 3,
      "title": "Write documentation",
      "agent": null,
      "role": "Technical Writer",
      "prompt": "Write user documentation for this TODO app...",
      "depends_on": [1]
    }
  ]
}
```

- `agent`: matches an existing agent ID; `null` when no suitable agent exists
- `role`: fallback role description, used when `agent` is null (main agent + role injection)
- `depends_on`: task IDs that must complete before this task can start; empty = can start immediately

### Execution Logic

```
Parse tasks from JSON
Build dependency graph

while (incomplete tasks exist):
    Find tasks where all depends_on are completed
    Execute them (parallel if multiple are ready):
        if task.agent exists and is available:
            openclaw agent --agent <task.agent>
                           --session-id getclawhub-collab-<taskId>-<task.agent>
                           -m '<task.prompt>'
        else:
            openclaw agent --agent main
                           --session-id getclawhub-collab-<taskId>-main
                           -m '[Role: <task.role>] <task.prompt>'
    Collect results, update card status
    Inject completed task results into dependent task prompts

Feed all results to commander for final summary
```

### Fallback Strategy

Priority: **Dedicated agent > main + role injection**

When `task.agent` is `null` or the specified agent doesn't exist in the system:
- Use `main` agent with role injection in the prompt
- Example: `-m "[Role: Technical Writer] Please write documentation for..."`
- This ensures `/collab` works out of the box even with zero custom agents

## Dual-Window Design

### Chat Page (existing)

- User sends `/collab <task>` to trigger collaboration
- Commander replies in Chat: "Decomposed into N subtasks, executing..."
- Collab window opens automatically
- User can continue chatting with commander:
  - Ask progress: "How's it going?"
  - Give commands: "Skip task 3", "Retry task 2"
  - Modify requirements: "Add a deadline feature to task 1"

### Collab Window (new, separate window)

Similar to HelpAssistantWindow pattern. Displays:

```
┌──────────────────────────────────────────────────┐
│ 🤖 Collaborative Task                    [Close] │
│                                                   │
│ Task: Build a TODO app with code and docs         │
│ Progress: 1/3 completed                           │
│                                                   │
│ ┌───────────────────────────────────────────────┐ │
│ │ ✅ #1 Write core code            coder        │ │
│ │    Completed in 12s                 [Expand ▼] │ │
│ ├───────────────────────────────────────────────┤ │
│ │ 🔄 #2 Review code quality        reviewer     │ │
│ │    In progress (8s)                 [Expand ▼] │ │
│ ├───────────────────────────────────────────────┤ │
│ │ ⏳ #3 Write documentation        main/Writer  │ │
│ │    Waiting for #1                   [Expand ▼] │ │
│ └─────────────────────────────��─────────────────┘ │
│                                                   │
│ [Cancel All]                                      │
└──────────────────────────────────────────────────┘
```

#### Task Card States

| State | Icon | Color | Description |
|-------|------|-------|-------------|
| Pending | ⏳ | Gray | Waiting for dependencies |
| In Progress | 🔄 | Blue | Sub-agent is executing |
| Completed | ✅ | Green | Result received |
| Failed | ❌ | Red | Error, can retry |
| Skipped | ⏭️ | Gray | User chose to skip |

#### Expand Card Content

Clicking "Expand" shows:
- Full agent response text (rendered as Markdown)
- For failed tasks: error message + [Retry] button
- Execution time

## Chat ↔ Collab Window Interaction

### Progress Queries

When user asks about progress in Chat, App injects current state:

```
[Task Status]
#1 Write core code — ✅ Completed (12s)
#2 Review code quality — 🔄 In progress (8s elapsed)
#3 Write documentation — ⏳ Pending (waiting for #1)

[User Question]
How's it going?
```

Commander responds naturally based on injected status.

### User Commands via Chat

User speaks naturally in Chat → commander returns structured JSON action → App executes.

#### Commander Action Response Format

**Progress reply (no action needed):**
```json
{
  "type": "reply",
  "message": "Task 1 is complete, task 2 is in progress..."
}
```

**Action command:**
```json
{
  "type": "action",
  "action": "<action_type>",
  "taskId": 3,
  "message": "OK, skipping task 3"
}
```

#### Available Actions

| Action | Description | Additional Fields |
|--------|-------------|-------------------|
| `skip` | Skip specified task | `taskId` |
| `retry` | Retry specified task | `taskId` |
| `cancel_all` | Cancel entire collaboration | — |
| `modify` | Modify task and re-execute | `taskId`, `newPrompt` |

### Modify Flow

When user says "Add deadline feature to task 1":
1. Commander returns `{"type": "action", "action": "modify", "taskId": 1, "newPrompt": "..."}`
2. App re-executes task 1 with new prompt
3. All tasks that `depends_on: [1]` are also re-executed with updated input

## Session Isolation

```
Regular chat:        --session-id getclawhub-chat-<agentId>
Help assistant:      --session-id getclawhub-help-assistant
Collab tasks:        --session-id getclawhub-collab-<collabTaskId>-<agentId>
```

- `collabTaskId`: UUID generated per `/collab` invocation
- Each agent in a collab task gets its own isolated session
- Collab sessions do not pollute regular chat or help assistant

## Data Model (Swift)

```swift
// Collab task states
enum CollabTaskStatus {
    case pending
    case inProgress
    case completed
    case failed(error: String)
    case skipped
}

// Single subtask
struct CollabSubTask: Identifiable {
    let id: Int
    let title: String
    let agentId: String?       // nil = use main with role injection
    let role: String?          // fallback role for main agent
    let prompt: String
    let dependsOn: [Int]
    var status: CollabTaskStatus = .pending
    var result: String?
    var elapsedTime: TimeInterval?
}

// Entire collab session
struct CollabSession: Identifiable {
    let id: String             // UUID
    let taskDescription: String
    var summary: String
    var subtasks: [CollabSubTask]
    var finalResult: String?
    let createdAt: Date
}

// ViewModel
@MainActor
class CollabViewModel: ObservableObject {
    @Published var session: CollabSession?
    @Published var isRunning = false

    private weak var dashboardViewModel: DashboardViewModel?

    func startCollab(_ taskDescription: String) async { ... }
    func skipTask(_ taskId: Int) { ... }
    func retryTask(_ taskId: Int) async { ... }
    func cancelAll() { ... }
    func modifyTask(_ taskId: Int, newPrompt: String) async { ... }
}
```

## Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `ViewModels/CollabViewModel.swift` | Collab orchestration logic, task execution, state management |
| `Views/Dashboard/CollabWindow.swift` | Separate collab window with task cards UI |
| `Models/CollabModels.swift` | CollabSession, CollabSubTask, CollabTaskStatus data models |

### Modified Files

| File | Changes |
|------|---------|
| `Views/Dashboard/DashboardView.swift` | Handle `/collab` command, open collab window |
| `ViewModels/DashboardViewModel.swift` | Hold CollabViewModel reference, pass to collab window |
| `Resources/commander-persona.md` | Commander agent persona definition (bundled in app) |

### Commander Agent Setup

On first launch or via setup, app creates the commander agent in `~/.openclaw/openclaw.json`:

```json
{
  "agents": {
    "list": {
      "commander": {
        "name": "Commander",
        "emoji": "🎯",
        "prompt": "<commander persona from bundled resource>"
      }
    }
  }
}
```

## Future Enhancements (Not in V1)

- **C mode**: Allow any agent to be the commander (user picks)
- **Collab history**: Save past collab sessions for review
- **Collab templates**: Pre-defined workflows (e.g., "Code + Review + Test")
- **Live streaming**: Stream sub-agent output in real-time inside cards
- **Parallel execution control**: Let user set max concurrent sub-agents
