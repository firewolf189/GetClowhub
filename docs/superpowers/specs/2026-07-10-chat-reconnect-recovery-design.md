# Mac Chat Reconnect Recovery Design

Date: 2026-07-10

## Status

Approved design direction: client-side recoverable chat state machine using the existing Gateway protocol.

## Context

The macOS client currently treats every unexpected WebSocket failure as the end of every active chat stream. `GatewayClient.scheduleReconnect()` finishes all `AsyncStream` continuations, so `ChatHelpers` exits its event loop without receiving a terminal `final`, `error`, or `aborted` event. The client then performs one `chat.history` request and displays “Connection was interrupted. The response may be incomplete.” whenever the returned text is absent or not longer than the last streamed delta.

This behavior has four correctness problems:

1. `isConnected` is updated asynchronously, so recovery can query through the stale failed socket.
2. An active Gateway run is not re-subscribed after reconnection.
3. A single history read can occur before the final assistant message is persisted.
4. Equal-length recovered content is treated as failure even when the run completed successfully.

The visible symptom is a partial or apparently complete answer followed by a generic interruption warning, often after a short network interruption, heartbeat failure, sleep/wake transition, or Gateway restart.

## Goals

- Keep an active run alive in the Mac UI across transient WebSocket reconnects.
- Distinguish a new connection from a stale `isConnected` value.
- Distinguish a reconnect to the same Gateway process from a Gateway restart.
- Determine the original run state without starting a duplicate run.
- Recover a final answer that completed while the client was disconnected.
- Surface the original Gateway error when the run failed.
- Preserve partial streamed content when recovery is impossible.
- Retain the existing one-hour abandonment backstop.

## Non-goals

- Adding a new `chat.status` method to the OpenClaw Gateway protocol.
- Changing Gateway reconnect backoff, heartbeat cadence, or agent timeout policy.
- Recovering multiple ambiguous runs from the same session after a Gateway process restart.
- Redesigning the chat timeline or adding a new reconnect visual treatment.
- Changing OpenClaw server code or its release process.

## Existing Protocol Facts

The implementation relies on existing, versioned Gateway behavior:

- `chat.send` uses `idempotencyKey` as its client run ID.
- Repeating `chat.send` with the same key in the same Gateway process returns:
  - `in_flight` while the original run is active;
  - `ok` after successful completion from the dedupe cache;
  - `error` with the original error after failure.
- The dedupe cache remains available for five minutes after completion.
- `hello-ok.snapshot.uptimeMs` identifies the approximate start time of the current Gateway process.
- `chat.history` returns persisted messages, including message identity/timestamp fields when present.

Repeating `chat.send` is safe only when the client has confirmed that it reconnected to the same Gateway process. After a process restart, the in-memory active-run and dedupe maps are lost, so repeating the request could start a duplicate run and is forbidden.

## Architecture

### 1. Gateway connection identity

`GatewayClient` will maintain a public read-only connection snapshot:

```text
connectionGeneration: monotonically increasing successful-handshake counter
gatewayProcessEpoch: monotonically increasing Gateway-process counter
gatewayStartedAtEstimate: current wall-clock time minus hello uptimeMs
```

`connectionGeneration` increments only after a successful `hello-ok` response. Recovery waits for a generation strictly greater than the run’s last observed generation, rather than waiting on `isConnected` alone.

The Gateway start estimate is compared with the previous estimate using a small tolerance to absorb network and clock measurement jitter. A material change increments `gatewayProcessEpoch`. Missing or malformed uptime data produces an unknown process identity; the client must then use the conservative restart path and must not send an idempotency probe.

All snapshot fields are updated together with the successful connection state on the main queue. Logs include generation and epoch numbers but never authentication tokens, user prompts, or attachment contents.

### 2. Run recovery context

Each active Mac chat turn retains a recovery context for the lifetime of its send task:

```text
runId / idempotencyKey
sessionKey
exact message and attachment parameters used by chat.send
run start timestamp
last successful connection generation
originating Gateway process epoch
optional pre-run assistant-history fingerprint
```

The fingerprint uses stable history metadata when available, falling back to timestamp plus a text digest. It is used only on the conservative process-restart path. It is not used as the primary state check for normal reconnects.

### 3. Idempotent run probe

`GatewayClient` will expose a probe operation using the exact original `chat.send` parameters and the original idempotency key. It returns a typed result:

```text
inFlight
completed
failed(message)
unknown
```

The probe has its own pending-response continuation map and timeout. It does not share the initial-send continuation parser because the initial send and a recovery probe accept different payload states.

The caller may invoke the probe only when the current `gatewayProcessEpoch` equals the originating epoch. The API will also reject the probe locally if this invariant is not satisfied, providing defense in depth against accidental duplicate execution.

### 4. Recoverable stream loop

The single-use `for await` loop becomes an outer recovery loop:

1. Subscribe before the initial `chat.send`, preserving the existing race protection.
2. Consume events until a terminal event arrives or the stream is finished by connection loss.
3. On non-terminal stream completion, wait up to 30 seconds for a strictly newer successful connection generation.
4. Once reconnected, install a fresh event subscription before probing the run. This ordering prevents a final event from being lost between an `in_flight` response and re-subscription.
5. Select the recovery action:
   - Same process + `inFlight`: resume the outer event loop with the fresh subscription.
   - Same process + `completed`: stop the fresh stream, fetch history with bounded retries, and finalize the message.
   - Same process + `failed`: finalize with the original error message.
   - Same process + `unknown`: try conservative history recovery; otherwise show an interruption result.
   - New or unknown process: never probe. Try conservative history recovery; otherwise show an interruption result.
6. Repeat the loop for subsequent disconnects until a terminal state or the one-hour abandonment task wins.

When an idempotent probe confirms completion, recovered history may be equal in length to the final streamed delta. Completion is established by the run status, not by string length. History reads use a short bounded retry schedule to cover delayed transcript persistence.

### 5. Conservative history recovery

When exact run status is unavailable, a history result is accepted only when it can be distinguished from the pre-run baseline and its timestamp is consistent with the current run. This keeps the existing safety principle that a message from another turn must not be attributed to the interrupted run.

If history cannot prove completion, the client reports interruption. It does not resend the original task.

### 6. Terminal presentation

- Successful recovery writes the recovered final body and marks the message completed.
- Confirmed Gateway failure writes the actual error and marks the message completed under the existing error presentation.
- User abort remains cancelled.
- Reconnect timeout, process restart without recoverable history, or unknown run state preserves the visible streamed draft and activity events, then appends the interruption warning. Partial output must not be replaced by the warning alone.
- The existing one-hour abandonment task remains the final guard against an indefinitely active task.

No new permanent UI control is introduced. While reconnecting, the current running treatment remains visible.

## Concurrency and Safety Invariants

- A recovery probe is never sent to a different or unidentified Gateway process.
- A fresh event subscription exists before an `in_flight` probe result is acted upon.
- Only one active subscription is registered for a message ID after recovery.
- Terminal message updates are idempotent and guarded against completed, cancelled, or timed-out state.
- The timeout task, stream cleanup, and recovery loop may race, but only the first terminal state is allowed to update the message.
- Pending probe continuations are resumed exactly once on response, send failure, disconnect cleanup, or timeout.
- Existing serialized WebSocket teardown/rebuild behavior remains unchanged.

## Error Handling

- Reconnect does not occur within 30 seconds: preserve partial text and show interruption.
- Gateway process changed: do not probe; use conservative history recovery.
- Probe times out: treat as unknown and use conservative history recovery.
- Probe reports failure: show its error summary.
- Completed probe but history is temporarily empty: retry with bounded backoff.
- Completed probe but history remains unavailable: preserve the last streamed text and append a specific recovery warning rather than claiming the connection alone caused failure.
- A second disconnect during recovery re-enters the same state machine with the latest connection generation.

## Testing and Verification

Add a focused verification script and pure recovery-decision coverage for:

1. Transient disconnect while the run remains `in_flight`.
2. Final event queued immediately after re-subscription.
3. Run completes while disconnected and history is immediately available.
4. Run completes while disconnected and history persistence is delayed.
5. Recovered final text has the same length as the last delta.
6. Gateway reports the original run error.
7. Two consecutive disconnect/reconnect cycles.
8. Gateway process epoch changes; no probe is sent.
9. Uptime/process identity is missing; no probe is sent.
10. Reconnect exceeds 30 seconds and partial text is retained.
11. One-hour abandonment wins during recovery.
12. Probe send failure and timeout resume their continuations once.
13. Existing cancellation, background-task, stream-rendering, and session-persistence checks remain green.

Validation includes:

- the new reconnect recovery verification;
- existing chat stream and task-state verification scripts;
- `git diff --check`;
- a code-signing-disabled Debug build of the `OpenClawInstaller` scheme;
- manual log review confirming generation/epoch transitions and absence of sensitive payloads.

## Rollout and Compatibility

The implementation is client-only and uses fields already present in the supported Gateway protocol. If uptime or idempotent status information is unavailable, behavior falls back to conservative history recovery without resending. This preserves compatibility with older Gateway builds while preventing duplicate work.

The change can be reverted independently because it does not alter persisted session formats or Gateway configuration.

