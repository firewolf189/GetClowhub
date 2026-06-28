## 1. Chat Layout States

- [x] 1.1 Split `ChatView` rendering into explicit empty-chat and non-empty timeline branches.
- [x] 1.2 Move the empty `New chat` title and composer into a centered main-panel composition surface.
- [x] 1.3 Ensure the normal bottom composer is not rendered for empty sessions.
- [x] 1.4 Ensure sending the first message from the centered composer switches to the normal timeline layout.

## 2. Scroll Anchors And Divider Cleanup

- [x] 2.1 Keep `chatTop` and `chatBottom` anchors only in the non-empty timeline branch.
- [x] 2.2 Make scroll anchors fully invisible and contained inside the chat panel.
- [x] 2.3 Remove any top horizontal divider or border that visually crosses into the left sidebar.
- [x] 2.4 Remove the lower-left stray line while preserving real component borders where needed.

## 3. Gray Bubble Styling

- [x] 3.1 Replace bubble backgrounds with explicit dynamic gray fills that remain visible in light and dark appearance.
- [x] 3.2 Apply the same rounded bubble container treatment to assistant markdown and user plain-text messages.
- [x] 3.3 Tighten user and assistant bubble corner radii so they read as lightly rounded desktop panels instead of large pills.
- [x] 3.4 Verify code blocks, markdown, long Chinese text, and copy-toolbar controls remain readable inside gray bubbles.

## 4. Composer Agent And Model Selector

- [x] 4.1 Add a reusable composer control that displays the selected agent and model as `Agent · Model v`.
- [x] 4.2 Build a custom anchored selector panel listing available agents.
- [x] 4.3 Add a `Model >` row that reveals an adjacent model list panel without using a native submenu.
- [x] 4.4 Wire agent selection to the existing selected-agent behavior.
- [x] 4.5 Wire model selection to existing model update behavior or add a narrow ViewModel helper.
- [x] 4.6 Use the same selector in centered empty composer and bottom timeline composer.

## 5. Fixed Top-Right Panel Control

- [x] 5.1 Add an Outputs panel control in the existing-conversation shell header.
- [x] 5.2 Keep the control visible for named existing conversations and hidden for empty new-chat states.
- [x] 5.3 Connect the control to the Outputs/workspace-style panel behavior.
- [x] 5.4 Add smooth expand/collapse animation using right-sidebar width interpolation.
- [x] 5.5 Make the top-right control click-only; hover must not reveal or expand the Outputs surface.

## 6. Sidebar Header Polish

- [x] 6.1 Remove the top-left sidebar logo/icon from the header while preserving app title spacing.

## 7. Stable Floating Composer Selector

- [x] 7.1 Move the composer agent/model selector panels into a true overlay that does not affect composer layout height.
- [x] 7.2 Keep the composer card in the same screen position while opening the selector, showing `Model >`, selecting an agent, and selecting a model.
- [x] 7.3 Add bounded positioning for narrow windows so the adjacent model panel remains visible without moving the composer.

## 8. Sidebar Navigation And Localization

- [x] 8.1 Remove the left-sidebar `Outputs` navigation row.
- [x] 8.2 Add a localized `Market` navigation row directly under `Automation`.
- [x] 8.3 Wire `Market` to the existing marketplace/expert-team overview and detail flow.
- [x] 8.4 Localize sidebar chrome labels including Search, Skills, Plugins, Automation, Market, Chat History, empty-session labels, and no-match labels.
- [x] 8.5 Ensure chat message bodies and stored session titles are not translated by UI language switching.
- [x] 8.6 Handle any stale `.outputs` selected-tab state by falling back to chat or opening the top-right panel route.
- [x] 8.7 Show a delete affordance on the right side of hovered chat-session rows and keep it separate from row navigation.

## 9. Anchored Outputs Panel

- [x] 9.1 Move the Outputs panel button into the requested shell header chrome position.
- [x] 9.2 Make the Outputs/workspace panel collapse back toward the top-right button with a right-sidebar width transition instead of remaining as a permanently expanded side sheet.
- [x] 9.3 Move the Outputs/workspace panel out of the overlay layer and into a real right-sidebar layout column.
- [x] 9.4 Preserve existing workspace file browsing/editing behavior inside the panel.
- [x] 9.5 Remove the closed-state right-sidebar strip so Outputs closed state reserves no trailing column, divider, folder icon, or sidebar icon.
- [x] 9.6 Keep the chat timeline and composer on a stable max-width column that recenters when either sidebar changes width.
- [x] 9.7 Keep the shell header Outputs button as the only visible closed-state Outputs entry point and ensure it opens the expanded right-sidebar panel.

## 10. Top Divider Cleanup

- [x] 10.1 Identify whether the remaining top horizontal line comes from the sidebar header divider, NavigationSplitView/window chrome, or another container border.
- [x] 10.2 Remove or visually suppress the global top divider so it no longer spans across the sidebar/main-panel boundary.
- [x] 10.3 Preserve only local separators that belong to actual components.
- [x] 10.4 Reduce the top gutter above the first visible chat message after the divider cleanup.

## 11. Chat Header Title

- [x] 11.1 Show the active session title near the left side of the chat surface when the current session has a non-empty name.
- [x] 11.2 Keep empty/new chat sessions on the existing composition title without duplicating a second header title.

## 12. Gateway Settings Grouping

- [x] 12.1 Add a `Gateway` heading at the top of the provider settings area.
- [x] 12.2 Put GetClawHub Official Service and Custom API Provider controls into one grouped Gateway container.
- [x] 12.3 Preserve provider selection, API base URL, API key visibility, sync/manage actions, and validation state.

## 13. Verification

- [x] 13.1 Run `openspec validate --all --strict`.
- [x] 13.2 Run `git diff --check`.
- [x] 13.3 Build the macOS app with the repository's Xcode build command.
- [x] 13.4 Re-run `openspec validate --all --strict` after the new OpenSpec requirements are added.
- [x] 13.5 Run `git diff --check` after implementation.
- [x] 13.6 Build the macOS app with the repository's Xcode build command after implementation.
- [x] 13.7 Visually verify light-mode empty `New chat` centered composer, gray bubbles, absence of stray lines, missing sidebar logo icon, localized sidebar labels, Market placement, and no left-sidebar Outputs entry.
- [x] 13.8 Visually verify dark-mode existing conversation, shell header Outputs control, anchored smooth panel expand/collapse, and grouped Gateway settings.
- [x] 13.9 Visually verify tightened bubble corner radius, session-row hover delete affordance, named-session chat title, no closed-state right-sidebar strip, stable centered chat width, and reduced top gutter.

## 14. Right Sidebar Ownership Parity

- [x] 14.1 Move right workspace sidebar open or close state out of chat-local overlay logic into app-shell sidebar state.
- [x] 14.2 Keep the top-right chat control as the only entry point while making the right sidebar participate in the same layout-level ownership model as the left sidebar.
- [x] 14.3 Preserve open state and selected workspace item across ordinary chat rerenders, agent switches, and session switches unless an explicit reset is required.

## 15. Workspace Output Filtering

- [x] 15.1 Hide `AGENTS.md`, `IDENTITY.md`, `SOUL.md`, and `MEMORY.md` from the workspace file tree.
- [x] 15.2 Apply the same exclusion rules to workspace file search results.
- [x] 15.3 Keep agent persona/config files editable only from dedicated agent-management surfaces, not from the workspace output browser.

## 16. Sidebar Agent Category

- [x] 16.1 Add a localized `Agent` category to the left sidebar using the existing sidebar section styling.
- [x] 16.2 Render the current available-agent list from this category and switch chat context when an agent is selected.
- [x] 16.3 Add an add-agent affordance to this category that opens the existing `CreateAgentSheet`.
- [x] 16.4 Refresh the sidebar agent list and select the new agent after successful creation.

## 17. Per-Agent Session Storage

- [x] 17.1 Change chat-session persistence paths so each agent stores session files under that agent's own workspace directory.
- [x] 17.2 Store main-agent sessions under the main workspace session directory and sub-agent sessions under `workspace-<agentId>` session directories.
- [x] 17.3 Add migration or backward-compatible loading so legacy globally stored sessions remain visible after the storage-path change.
- [x] 17.4 Keep sidebar history filtering aligned with the selected agent after the persistence change.

## 18. Session Search Entry Consolidation

- [x] 18.1 Remove the redundant top-level sidebar `Search` row.
- [x] 18.2 Keep the chat-history session-search control as the only session-search entry point in the sidebar.
- [x] 18.3 Focus the session-search input when the user activates search.
- [x] 18.4 Ensure session search filters all chat history globally and does not affect workspace-file search.

## 19. Final Shell Header And Right Sidebar Layout

- [x] 19.1 Move the active conversation title out of `ChatView` and into the center app-shell header.
- [x] 19.2 Render the center shell header only for existing/named conversations; empty new chats must show no header or header separator.
- [x] 19.3 Update the active conversation title typography to 16pt.
- [x] 19.4 Keep the right Outputs sidebar as a shell-level sibling column, not a chat overlay or chat-internal child.
- [x] 19.5 Keep right-sidebar expansion click-only; hover must not open, reveal, or resize it.
- [x] 19.6 Ensure left/right sidebar width changes reduce or expand the center chat area's available width while the chat column remains max-width constrained and responsive.

## 20. Outputs-Only Sidebar Content

- [x] 20.1 Change the expanded right sidebar title from workspace terminology to `Outputs`.
- [x] 20.2 Filter the right sidebar tree and search results to model output artifacts instead of the full workspace.
- [x] 20.3 Exclude context/config documents including `USER.md`, `AGENTS.md`, `TOOLS.md`, `BOOTSTRAP.md`, `IDENTITY.md`, `SOUL.md`, and `MEMORY.md`.
- [x] 20.4 Show an empty Outputs state instead of falling back to the complete workspace when no output artifacts match.

## 21. Final Verification

- [x] 21.1 Run `openspec validate --all --strict`.
- [x] 21.2 Run `git diff --check`.
- [x] 21.3 Build the macOS app with the `build-macos-apps` Xcode build flow.
- [ ] 21.4 Visually smoke-check existing conversation header placement, empty new-chat no-header behavior, click-only right sidebar behavior, and Outputs filtering.

## 22. Agent Project Workspace

- [x] 22.1 Add `ProjectRecord`, `AgentProjectBinding`, and project session grouping models.
- [x] 22.2 Extend chat session metadata with optional project id, project root, and project display name.
- [x] 22.3 Add per-agent project folders in the sidebar before project-less general sessions.
- [x] 22.4 Add an agent work-folder action that uses a local folder picker and explains that files stay local.
- [x] 22.5 Add a lightweight `SemanticRepoMapService` bootstrap manifest in app-owned storage without recursive scanning, watchers, or language-server indexing.
- [x] 22.6 Add compact project orientation for project-scoped chat without injecting full project contents.

## 23. Session Storage And Search

- [x] 23.1 Store agent sessions under the main workspace or `workspace-<agentId>` session directories.
- [x] 23.2 Keep project metadata with session metadata while preserving one owning agent per session.
- [x] 23.3 Keep legacy global session loading compatible.
- [x] 23.4 Keep global session search across agent workspaces separate from right-sidebar file search.

## 24. Assistant Rendering And Title Navigation

- [x] 24.1 Add an assistant render policy for native selectable markdown, WebView fallback, and A2UI cards.
- [x] 24.2 Cache WebView markdown HTML and measured heights with limits.
- [x] 24.3 Guard measured-height writeback so tiny height deltas do not churn the timeline.
- [x] 24.4 Add the named-session title popover that lists user messages and can jump to a selected message.

## 25. Marketplace Utility Pages

- [x] 25.1 Keep Skills and Plugins pages on the shared centered utility column.
- [x] 25.2 Add search, refresh, and segmented Recommend/All/Installed modes for Skills and Plugins.
- [x] 25.3 Resolve installed Skills and Plugins back to catalog metadata when possible while preserving custom installed items.
- [x] 25.4 Preserve manual/custom install entry points.

## 26. Channel Account Configuration

- [x] 26.1 Add account id and display name fields for account-capable channel providers.
- [x] 26.2 Store non-default channel accounts under provider-specific `accounts` data instead of overwriting the provider.
- [x] 26.3 Remove or disable the selected channel account without removing other accounts for the same provider.

## 27. Bundled OpenClaw Core Upgrade

- [x] 27.1 Add bundled OpenClaw core manifest loading and version comparison.
- [x] 27.2 Add startup coordinator that runs the bundled core check once after OpenClaw is detected.
- [x] 27.3 Stage and verify the bundled core before swapping the installed package and bin link.
- [x] 27.4 Reinstall or repair the gateway and restart OpenClaw after a successful swap.
- [x] 27.5 Roll back from backup on failure and keep upgrade status out of dashboard chrome.

## 28. Expanded Scope Verification

- [x] 28.1 Run `scripts/verify_agent_project_workspace_mvp.swift`.
- [x] 28.2 Run `scripts/verify_assistant_message_render_model.swift`.
- [x] 28.3 Run `scripts/verify_markdown_webview_cache_limits.swift`.
- [x] 28.4 Run `scripts/verify_dingtalk_multi_account_channels.swift`.
- [x] 28.5 Run `scripts/verify_openclaw_core_upgrade.swift`.
- [x] 28.6 Run `scripts/verify_plugins_lookup_index_cache.swift`.
- [x] 28.7 Run `scripts/verify_skills_ui_cache_and_hover.swift`.
