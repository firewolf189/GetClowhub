## 1. Gateway Activity Contract

- [ ] 1.1 Define the minimal read-only response for the global count of real
  active tasks.
- [ ] 1.2 Add or integrate the Gateway activity query so tasks from DingTalk and
  other external channels are included.
- [ ] 1.3 Verify that stale processing markers without a live run are not
  counted as active.

## 2. Configuration Repair

- [ ] 2.1 Add focused config transformation logic that preserves the complete
  document and sets `session.dmScope` to `per-channel-peer`.
- [ ] 2.2 Validate a temporary candidate with the installed OpenClaw core before
  live-config replacement.
- [ ] 2.3 Add timestamped backup and atomic replacement behavior.
- [ ] 2.4 Cover missing `session`, missing `dmScope`, alternate values,
  already-correct values, sibling preservation, validation failure, and write
  failure.

## 3. Safe Repair Orchestration

- [ ] 3.1 Add structured preflight and repair outcome types.
- [ ] 3.2 Stop without mutation or restart when active-task count is greater
  than zero.
- [ ] 3.3 Gracefully restart when the Gateway is reachable and idle, including
  when `dmScope` was already correct.
- [ ] 3.4 Verify Gateway health, effective `dmScope`, and DingTalk connectivity
  after restart.
- [ ] 3.5 Verify that the safe path can never invoke process purge.

## 4. Emergency Fallback

- [ ] 4.1 Preserve the existing BOM, invalid-config, log, runtime, process-purge,
  and cold-start repair steps.
- [ ] 4.2 Require a distinct destructive confirmation when activity cannot be
  verified.
- [ ] 4.3 Apply and validate the DM-scope repair during emergency repair when
  the config remains parseable.
- [ ] 4.4 Cover unreachable, activity-unknown, and explicit emergency-confirmed
  outcomes.

## 5. UI and Localization

- [ ] 5.1 Keep the existing repair entry and present busy, safe-repair, partial
  success, validation failure, and emergency-required states.
- [ ] 5.2 Show the active-task count when safe repair is refused.
- [ ] 5.3 Add the second destructive confirmation without exposing secrets or
  raw config.
- [ ] 5.4 Add Simplified Chinese, Traditional Chinese, and English strings.

## 6. Verification

- [ ] 6.1 Run targeted config, service, view-model, and repair-flow tests.
- [ ] 6.2 Build the macOS app in Debug configuration.
- [ ] 6.3 Manually verify repair on a Gateway with no active tasks.
- [ ] 6.4 Send direct messages from two DingTalk users and confirm distinct
  session keys after repair.
