## ADDED Requirements

### Requirement: Repair enforces isolated direct-message sessions
The system SHALL ensure that the effective OpenClaw configuration sets
`session.dmScope` to `per-channel-peer` during a successful repair.

#### Scenario: DM scope is missing or different
- **WHEN** safe repair runs while the Gateway is reachable and idle
- **THEN** the client builds a candidate config with
  `session.dmScope` set to `per-channel-peer`
- **AND** all unrelated config fields are preserved

#### Scenario: DM scope is already correct
- **WHEN** safe repair runs while the effective value is already
  `per-channel-peer`
- **THEN** the client does not rewrite the config unnecessarily
- **AND** the idle Gateway is still gracefully restarted to clear stale
  in-memory state

### Requirement: Safe repair protects active tasks
The system SHALL NOT change configuration or restart a reachable Gateway while
real tasks are active.

#### Scenario: One or more tasks are active
- **WHEN** the Gateway reports an active-task count greater than zero
- **THEN** repair stops without modifying config
- **AND** repair does not restart or force-kill the Gateway
- **AND** the client shows the active-task count

#### Scenario: A stale processing marker has no live run
- **WHEN** the Gateway computes its active-task count
- **THEN** the stale marker is not counted as an active task

### Requirement: Candidate config is validated before replacement
The system SHALL validate a complete candidate config before replacing the live
OpenClaw config.

#### Scenario: Candidate validation succeeds
- **WHEN** the repaired candidate passes validation
- **THEN** the client creates a timestamped backup
- **AND** atomically replaces the live config

#### Scenario: Candidate validation fails
- **WHEN** the repaired candidate does not pass validation
- **THEN** the live config remains unchanged
- **AND** no Gateway restart occurs

### Requirement: Idle repair uses graceful restart
The system SHALL use a graceful restart for a reachable Gateway with no active
tasks.

#### Scenario: Reachable Gateway is idle
- **WHEN** preflight reports zero active tasks and candidate validation succeeds
- **THEN** the client requests a graceful Gateway restart
- **AND** the safe path does not invoke process purge

### Requirement: Unverifiable activity requires emergency confirmation
The system SHALL separate unverified emergency repair from the safe repair
path.

#### Scenario: Gateway activity cannot be verified
- **WHEN** the Gateway is unreachable or does not support the activity query
- **THEN** the client does not automatically modify config or restart
- **AND** the client offers the existing force repair only after a separate
  destructive confirmation

#### Scenario: User declines emergency repair
- **WHEN** the emergency confirmation is cancelled
- **THEN** no process purge or cold start occurs

### Requirement: Successful repair is verified
The system SHALL verify the repaired runtime after restart.

#### Scenario: Gateway restarts successfully
- **WHEN** the Gateway becomes healthy after repair
- **THEN** the effective `session.dmScope` is verified as
  `per-channel-peer`
- **AND** DingTalk channel connectivity is checked

#### Scenario: DingTalk has not reconnected
- **WHEN** the Gateway is healthy and the config is correct but DingTalk is not
  connected
- **THEN** the client reports partial repair success
- **AND** the valid repaired config is retained

### Requirement: Repair preserves user data and secrets
The system SHALL preserve historical sessions and avoid exposing secrets during
repair.

#### Scenario: Repair completes
- **WHEN** safe or emergency repair reports its steps
- **THEN** existing session transcripts are not deleted
- **AND** tokens, API keys, and the complete config are not included in logs or
  user-facing summaries
