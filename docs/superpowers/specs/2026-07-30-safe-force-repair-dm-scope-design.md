# Safe Force Repair for DingTalk DM Session Isolation

## Status

Approved for implementation planning.

## Context

The macOS client currently exposes a **Force Repair Gateway** action. Its
implementation is intentionally destructive: it repairs basic config-file
damage, truncates oversized logs, force-kills Gateway processes, and starts the
Gateway again.

A production DingTalk incident showed a separate, recoverable failure mode:

- `session.dmScope` was missing, so OpenClaw used its `main` default.
- Direct messages from different DingTalk users shared one agent session.
- A stale processing state and queued messages accumulated in that shared
  session.
- Replies appeared delayed, repeated, or permanently stuck.

The desired first release is deliberately small. It extends the existing repair
entry instead of adding a new Gateway management or session-management screen.

## Goals

- Detect whether `session.dmScope` is exactly `per-channel-peer`.
- Repair a missing or different value to `per-channel-peer`.
- Never modify config or restart a reachable Gateway while real tasks are
  active.
- Use a graceful restart when the Gateway is reachable and idle.
- Preserve the existing force-kill repair as an explicitly confirmed emergency
  fallback when activity cannot be checked.
- Validate the resulting config and verify that Gateway and DingTalk recover.
- Preserve all unrelated configuration and existing chat transcripts.

## Non-goals

- A general-purpose Gateway administration screen.
- Per-session inspection, search, deletion, or bulk recovery.
- Persistent background waiting for active tasks to finish.
- Automatically terminating active tasks.
- Automatically applying the repair without a user action.
- Changing session records or deleting the former shared DingTalk session.

## User Experience

The existing repair button remains the only entry.

When the user starts repair, the client runs a preflight:

1. Inspect the local config and determine whether `session.dmScope` needs
   repair.
2. If the Gateway is reachable, request the total count of real active tasks.
3. Choose one of three outcomes:

   - **Reachable and busy:** make no changes and show
     "There are currently N active tasks. Try repair again after they finish."
   - **Reachable and idle:** run the safe repair flow.
   - **Unreachable or activity unknown:** explain that task safety cannot be
     verified and offer the existing emergency force repair behind a second,
     destructive confirmation.

The success summary reports whether the setting was already correct or changed,
whether config validation passed, whether the Gateway restarted, and whether
the DingTalk channel reconnected.

## Safe Repair Flow

For a reachable, idle Gateway:

1. Read and parse `~/.openclaw/openclaw.json`.
2. Preserve the complete JSON object and build a candidate that sets only:

   ```json
   {
     "session": {
       "dmScope": "per-channel-peer"
     }
   }
   ```

3. Write the candidate to a temporary file and validate it with the installed
   OpenClaw core using that temporary file as the config path.
4. If validation fails, remove the temporary file and stop. The live config has
   not changed.
5. When a config change is needed, create a timestamped backup and atomically
   replace the live config with the validated candidate.
6. Request a graceful Gateway restart. This step still runs when `dmScope` was
   already correct because the restart is also responsible for clearing stale
   in-memory processing and queue state.
7. Wait for the Gateway to become healthy.
8. Verify through the effective config that
   `session.dmScope == "per-channel-peer"`.
9. Verify the DingTalk channel is configured and connected.

The restart clears in-memory queues and stale processing state. The old shared
session remains on disk as history but new DingTalk direct messages route to
per-channel-peer session keys, so that session is no longer reused.

## Active Task Check

The macOS client's local chat state is not sufficient because it does not see
tasks started by DingTalk or other external channels.

The Gateway therefore needs one minimal, read-only status capability that
returns a total count of real active tasks. A representative response is:

```json
{
  "activeTaskCount": 2
}
```

Only live runs count as active. A stale `processing` marker without a
corresponding run must not keep the Gateway permanently busy.

This first release does not need task details, queue editing, session keys, or a
session-management API in the client. If the status capability is unavailable,
the client treats activity as unknown and does not take the safe restart path.

## Emergency Fallback

The current process-purge and cold-start behavior remains available only when
the Gateway is unreachable or activity cannot be verified.

The fallback must:

- use a separate destructive confirmation;
- state that running work may be interrupted;
- run the same config repair and validation before cold start when possible;
- retain the existing BOM repair, invalid-config quarantine, log cleanup,
  runtime check, process purge, and cold start behavior.

The safe path must never call the force-kill implementation.

## Configuration Safety

- Preserve every unrelated config key.
- Preserve existing keys inside `session`.
- Use an atomic file write.
- Create a timestamped backup before mutation.
- Never log tokens, API keys, or the full config.
- Validate a temporary candidate before replacing the live config.
- If restart fails after validation, keep the valid repaired config and report
  the concrete Gateway startup failure; do not silently switch session
  isolation back to the unsafe value.

## Component Boundaries

- `OpenClawServiceForceRepair` owns preflight selection, config triage, the safe
  repair sequence, and the existing emergency fallback.
- `OpenClawService` owns Gateway reachability, graceful restart, health polling,
  config validation, and channel-status requests.
- `DashboardViewModel` maps structured repair outcomes to user-facing messages
  and confirmation state.
- `StatusTabView` keeps the existing repair entry and presents the extra
  emergency confirmation only when required.
- The Gateway runtime exposes the minimal read-only active-task count.

The repair result should be structured rather than inferred from localized
strings. It needs to distinguish at least: busy, safely repaired, already
correct, validation failed and restored, graceful restart failed, verification
failed, and emergency fallback required.

## Failure Handling

- Missing config: retain the current behavior that allows normal startup to
  regenerate it, then ensure the desired setting is applied before success is
  reported.
- Invalid config: retain quarantine behavior for emergency repair; safe repair
  stops and explains that emergency repair is required.
- Candidate validation failure: leave the live config unchanged and stop.
- Backup failure: stop before replacing the live config.
- Atomic replacement failure: leave the original config intact and stop.
- Activity status unavailable: do not restart; offer emergency fallback.
- Gateway restart failure: report the parsed startup reason.
- DingTalk reconnect failure: report partial repair success and keep the
  repaired, validated config.

## Verification

Automated coverage should include:

- missing `session` object;
- missing `dmScope`;
- `dmScope` set to `main`, `per-peer`, and `per-account-channel-peer`;
- already-correct `per-channel-peer`;
- preservation of sibling `session` fields and unrelated config;
- backup and atomic-write behavior;
- candidate validation failure without live-config mutation;
- reachable Gateway with zero active tasks;
- reachable Gateway with one or more active tasks and no mutation;
- already-correct config still restarting when the Gateway is idle;
- unavailable activity status and emergency-fallback selection;
- graceful path never invoking process purge;
- emergency path retaining existing repair steps;
- post-restart config verification;
- DingTalk connected and disconnected verification results;
- secrets excluded from logs and repair summaries.

Manual verification should send direct messages from two different DingTalk
users after repair and confirm that the resulting session keys are distinct.
