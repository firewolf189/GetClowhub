## Why

The earlier Codex-style chat work started as visual polish, but the accepted design has become a shell-level app experience update. The remaining contract is no longer only about composer placement or bubble styling; it also defines how the left sidebar, center chat shell, right Outputs sidebar, agent selection, project workspaces, local runtime upgrades, rich message rendering, marketplace pages, channel accounts, session persistence, and search entry points fit together.

This change records the current design as the implementation source of truth so future work does not continue from the older "chat-internal polish" interpretation. The app should behave as an outer three-column shell: the left sidebar owns primary navigation, agent switching, and agent project folders; the center shell owns the conversation header, message rendering, and chat column; and the right Outputs sidebar is a real sibling layout column that appears only when explicitly opened.

## What Changes

- Define the final app-shell layout as left sidebar, center chat shell, and optional right Outputs sidebar sibling columns.
- Render a shell-owned 16pt conversation title and Outputs toggle only for named existing conversations; empty new chats keep the centered composition surface and no header separator.
- Keep the chat timeline and composer on a readable max-width column that recenters within the available center region and shrinks only when the center region becomes too narrow.
- Make the right Outputs sidebar click-only, animated, and layout-owned. It must not open on hover, float over chat, remain as a collapsed strip, or live inside the chat message panel.
- Treat the right sidebar as `Outputs`, not a full workspace browser. It shows generated artifacts and excludes context/config files such as `USER.md`, `AGENTS.md`, `TOOLS.md`, `BOOTSTRAP.md`, `IDENTITY.md`, `SOUL.md`, and `MEMORY.md`.
- Remove the left-sidebar `Outputs` route and the redundant top-level `Search` route. Session search remains the single chat-history search entry point and focuses the session search input when activated.
- Add localized `Agent` and `Market` sidebar sections: `Agent` exposes existing agent selection and creation, while `Market` opens the existing marketplace/expert-team surface under `Automation`.
- Add agent project workspaces under the Agent sidebar: users can add local work folders per agent, see project-scoped sessions before general sessions, and keep project indexing metadata in app-owned storage instead of inside user repos.
- Store sessions under each agent's workspace directory, while preserving access to legacy globally stored sessions through migration or compatible loading.
- Keep local project context lightweight: chat turns may carry a short project orientation, but the app must not inject a full project tree or scan project contents just to render the sidebar.
- Preserve the new assistant rendering policy: native selectable text is the default path, rich markdown upgrades only when needed, and WebView rendering uses cached HTML/height updates to avoid blank flashes and layout churn.
- Add the title hover popover for named conversations so the title can expose user-message jump targets without becoming part of the message timeline.
- Preserve Skills and Plugins marketplace refinements: centered 760pt pages, Recommend/All/Installed modes, search, refresh, detail presentation, manual/custom install paths, and installed-item catalog lookup.
- Preserve channel account behavior, including DingTalk/Feishu-style app-key accounts with default and named account entries rather than overwriting the whole channel type.
- Add silent bundled OpenClaw core upgrade behavior at startup: compare the bundled core manifest with the installed version, stage and verify the new core, swap only the OpenClaw package/bin link, reinstall/restart the gateway, and roll back on failure without adding dashboard status chrome.
- Preserve the accepted chat polish details: centered empty composer, visible gray bubbles with tighter radii, invisible contained scroll anchors, no stray global dividers, hover delete affordance on session rows, localized chrome, and grouped `Gateway` settings.
- Preserve existing chat sending, attachments, model updates, gateway behavior, marketplace behavior, and non-chat tab behavior except where explicitly touched by the shell/sidebar changes.

## Final Layout Clarification

The final accepted layout is an outer three-column app shell, not a chat-internal panel layout. The left sidebar, center chat area, and right Outputs sidebar are siblings in the outer shell. The active conversation title belongs in the center shell header at 16pt, not inside the chat message panel. New/empty chats do not show this center header or its bottom separator.

The right sidebar must behave like a sidebar controlled by explicit clicks. It must not expand on hover, must not float over chat as an overlay, and must not be implemented as a child region inside the chat content panel. Opening, closing, or resizing either sidebar changes the center chat area's available width; the chat content keeps a readable max width but shrinks when the available center region becomes smaller.

The expanded right sidebar is titled `Outputs` and shows model output artifacts only. It is not a full workspace browser. Known context/config files such as `USER.md`, `AGENTS.md`, `TOOLS.md`, `BOOTSTRAP.md`, `IDENTITY.md`, `SOUL.md`, `MEMORY.md`, and similar agent setup documents must not appear in the Outputs tree or search results.

## Capabilities

### New Capabilities
- `codex-chat-composer-polish`: Covers the final Codex-style app shell, including centered New chat composition, visible gray message bubbles, contained scroll anchors/divider cleanup, composer agent/model selection, shell-owned conversation header and title popover, click-only right Outputs sidebar, Outputs-only artifact filtering, localized sidebar navigation, Agent and Market sidebar entries, agent project workspaces, per-agent and project-aware session metadata, session-search consolidation, assistant render policy, Skills/Plugins marketplace page refinements, multi-account channel configuration, bundled OpenClaw core upgrades, and Gateway settings grouping.

### Modified Capabilities

None. There are no existing archived OpenSpec capabilities in `openspec/specs/`; this change creates a new capability delta for the active project state.

## Impact

- Affects `OpenClawInstaller/Views/Dashboard/DashboardView.swift` for app-shell layout, sidebar navigation, chat layout, bubble styling, session-row hover actions, shell header/title placement, scroll-anchor containment, stable centered chat width, right-sidebar Outputs column placement, and removal of the closed-state right strip.
- Affects `OpenClawInstaller/ViewModels/DashboardViewModel.swift` for shell/sidebar state, composer-driven model or agent switching helpers, search focus behavior, selected-agent behavior, and any fallback behavior for removed sidebar routes.
- Affects `OpenClawInstaller/Models/ChatSession.swift`, `OpenClawInstaller/Models/ProjectWorkspace.swift`, `OpenClawInstaller/Services/ChatSessionStore.swift`, and `OpenClawInstaller/Services/SemanticRepoMapService.swift` for project-scoped session metadata, per-agent workspace session paths, local project registry/bindings, lightweight repo-map manifest bootstrapping, and legacy-session compatibility.
- Affects `OpenClawInstaller/Views/Dashboard/AssistantMessageRenderer.swift`, `OpenClawInstaller/Views/Dashboard/MarkdownHTML.swift`, and `OpenClawInstaller/Views/Dashboard/SelectableMarkdownView.swift` for assistant render-mode selection, native selectable markdown, WebView fallback rendering, cache limits, and height measurement guards.
- Affects `OpenClawInstaller/Views/Dashboard/SessionTitleUserMessagesPopover.swift` for the named-session title popover and message jump affordance.
- Affects workspace/output browsing code for Outputs-only filtering and exclusion of agent/context configuration documents.
- Affects `OpenClawInstaller/Views/Dashboard/SkillsTabView.swift`, `OpenClawInstaller/Views/Dashboard/PluginsTabView.swift`, marketplace resources, and catalog services for Skills/Plugins marketplace layout, lookup, refresh, search, and install behavior.
- Affects `OpenClawInstaller/Views/Dashboard/ChannelsTabView.swift` and channel-related ViewModel logic for account-specific channel configuration.
- Affects `OpenClawInstaller/Models/OpenClawCoreManifest.swift`, `OpenClawInstaller/Services/OpenClawCoreUpgradeCoordinator.swift`, `OpenClawInstaller/OpenClawInstallerApp.swift`, release resources, and packaging scripts for bundled OpenClaw core upgrade behavior.
- May affect `OpenClawInstaller/Localizable.xcstrings` if new visible labels or accessibility/help strings are introduced.
- Affects `OpenClawInstaller/Views/Dashboard/ConfigTabView.swift` for the grouped Gateway settings layout.
- Does not change backend chat APIs, gateway protocols, or the stored chat-message payload format.
