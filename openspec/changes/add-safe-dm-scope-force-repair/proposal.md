## Why

The macOS client's current Force Repair action immediately purges Gateway
processes. A DingTalk incident showed that a missing `session.dmScope` can also
route multiple direct-message users into one shared session, leaving replies
queued behind stale processing state. The repair entry should correct that
configuration without interrupting real work when the Gateway is still healthy.

## What Changes

- Check whether `session.dmScope` is exactly `per-channel-peer`.
- Repair a missing or different value while preserving unrelated config.
- Check the Gateway's global active-task count before changing config or
  restarting.
- Refuse the safe path while tasks are active.
- Validate a temporary candidate config before atomically replacing the live
  config.
- Gracefully restart an idle, reachable Gateway even when the setting was
  already correct, clearing stale in-memory session state.
- Keep the existing process-purge repair behind a separate destructive
  confirmation when task activity cannot be verified.
- Verify Gateway health, the effective setting, and DingTalk connectivity after
  restart.

## Capabilities

### New Capabilities

- `gateway-safe-force-repair`: Defines safe DingTalk DM isolation repair,
  active-task protection, graceful restart, emergency fallback, and recovery
  verification.

### Modified Capabilities

None.

## Impact

- Affects the macOS repair flow in `OpenClawServiceForceRepair`,
  `OpenClawService`, `DashboardViewModel`, and `StatusTabView`.
- Requires a minimal read-only Gateway capability that reports the number of
  real active tasks from all channels.
- Adds localized repair states and focused automated coverage.
- Does not add a Gateway management page or session-management UI.
- Does not delete or rewrite historical session transcripts.
