## Context

The current macOS Force Repair flow is an emergency path: it repairs basic
config-file damage, truncates oversized logs, force-kills Gateway processes,
checks the Node runtime, and cold-starts the Gateway.

When `session.dmScope` is absent, OpenClaw defaults to `main`. Different
DingTalk direct-message users can then share one agent session. A stale
processing marker and queued messages in that shared session can produce
delayed, repeated, or permanently stuck replies.

The first release stays inside the existing repair entry. It does not introduce
a general Gateway administration or session-management screen.

## Goals

- Repair `session.dmScope` to `per-channel-peer`.
- Protect real tasks started by DingTalk or any other channel.
- Prefer a graceful restart when the Gateway is reachable and idle.
- Preserve the existing emergency repair for unobservable or broken states.
- Preserve unrelated configuration and historical transcripts.
- Report a structured, verifiable result.

## Non-goals

- Per-session inspection, deletion, or bulk recovery.
- Persistent background waiting for tasks to finish.
- Automatically terminating active tasks.
- Automatically repairing without user action.
- Replacing the existing repair entry with a new management screen.

## Decisions

1. **Use the existing repair entry.**
   - The button starts with a read-only preflight.
   - The flow chooses safe repair, busy refusal, or emergency confirmation.
   - No new navigation or management page is introduced.

2. **Use Gateway-wide activity, not client-local chat state.**
   - The client must see tasks initiated through DingTalk and other channels.
   - The Gateway exposes a minimal read-only active-task count.
   - Only live runs count as active; stale `processing` markers do not.
   - If the capability is unavailable, activity is unknown and safe restart is
     forbidden.

3. **Validate before touching the live config.**
   - Parse the complete current JSON object.
   - Preserve all existing keys and set only
     `session.dmScope = "per-channel-peer"`.
   - Write the candidate to a temporary file.
   - Validate the candidate with the installed OpenClaw core using the
     temporary file as the config path.
   - Create a timestamped backup and atomically replace the live config only
     after validation succeeds.

4. **Restart an idle Gateway even when config is already correct.**
   - A graceful restart clears stale in-memory queues and processing state.
   - The former shared session remains on disk as history.
   - New DingTalk direct messages route to per-channel-peer session keys, so the
     old shared session is no longer reused.

5. **Keep process purge as a separate emergency action.**
   - Reachable and idle uses only graceful restart.
   - Reachable and busy performs no mutation and no restart.
   - Unreachable or activity-unknown states require a second destructive
     confirmation before using the existing force-kill path.

6. **Return structured outcomes.**
   - The service result distinguishes busy, already correct, safely repaired,
     candidate validation failure, graceful restart failure, verification
     failure, and emergency fallback required.
   - Localized UI text is derived from the result rather than parsed back into
     control flow.

## Safe Repair Sequence

1. Read and parse `~/.openclaw/openclaw.json`.
2. Check Gateway reachability and global active-task count.
3. If the count is greater than zero, stop without mutation.
4. Build and validate a temporary candidate config.
5. If a change is needed, create a backup and atomically replace the live
   config.
6. Request a graceful Gateway restart.
7. Wait for Gateway health.
8. Verify the effective `session.dmScope`.
9. Verify the DingTalk channel is configured and connected.

## Emergency Sequence

When reachability or activity cannot be established, the UI explains that
running work may be interrupted and asks for a separate destructive
confirmation. After confirmation, the existing BOM repair, invalid-config
quarantine, oversized-log cleanup, runtime check, process purge, and cold start
remain available. The emergency path applies the DM-scope repair and config
validation when the config is parseable.

## Configuration and Privacy Safety

- Never log the complete config, tokens, or API keys.
- Preserve sibling fields inside `session` and all unrelated sections.
- Stop before mutation when candidate validation fails.
- Stop before mutation when the backup cannot be created.
- Use atomic replacement for the live config.
- Keep the repaired, validated config if restart later fails; do not silently
  restore the unsafe session isolation value.
- Do not delete session stores or transcripts.

## Risks / Trade-offs

- The minimal Gateway activity capability is an upstream dependency. Without
  it, the safe path must conservatively stop and offer emergency repair.
- A Gateway may be reachable during preflight but fail during restart. Existing
  failure-reason parsing should surface the concrete startup error.
- DingTalk may reconnect later than the Gateway. Report this as partial success
  rather than reverting a valid configuration.
