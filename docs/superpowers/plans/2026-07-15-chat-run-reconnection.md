# Chat Run Reconnection Architecture

**Goal:** Preserve an in-progress chat run across transient gateway failures without resending the prompt, misrouting the result, or treating transport exhaustion as model failure.

## State Boundaries

The implementation has three independent state machines:

1. `GatewayConnectionState` owns WebSocket transport lifecycle only. A failed connection attempt never decides the result of a model run.
2. `ChatRunState` owns one UI task identified by `messageId` and `sessionId`. Its current `ChatGatewayRunBinding` owns `sessionKey`, `idempotencyKey`, child-run `startedAt`, and the acknowledged `runId`; this keeps a multi-chunk image task's parent lifetime separate from each backend run's recovery window. Its execution kind records whether terminalization belongs to the visible conversation or to an orchestrated image-review batch.
3. `ChatActiveStreamState` owns transient draft text and activity. Persisted `ChatMessage.content` receives only terminal content.

This separation allows the UI to reconnect or switch sessions without changing the backend identity of an active run.

## Transport Policy

- A connection handshake has a 30-second timeout.
- Automatic reconnect performs at most five attempts with delays of 1, 2, 4, 8, and 16 seconds.
- Reconnect exhaustion produces `recoveryExhausted`, retains unresolved runs, and exposes a manual retry.
- Event subscribers remain registered across reconnect attempts. Events are routed by run/session before entering a bounded 128-event stream; full accumulated deltas make dropping older buffered deltas safe, while terminal events are retained and finish the subscription.
- A successful reconnect broadcasts `connected` so every unresolved run can schedule reconciliation.
- A live unacknowledged submission may call `chat.send` again at most twice with the exact same idempotency key. This happens only before any delta, activity, or terminal event proves acceptance. Confirmed runs are never resubmitted, preventing duplicate billing, messages, and tool execution.
- A global connection observer wakes crash-recovered runs that have no live event subscription. Live subscribers remain responsible for draining their own ordered event stream.

## Run Reconciliation

Each unresolved run has one coordinator task keyed by `messageId`. After every suspension, it revalidates `messageId`, `runId`, and `sessionKey` before applying a result. The resolver returns an owner-neutral terminal/suspended/superseded result; only the conversation wrapper may complete a visible message directly. Image-review child runs return that result to their batch owner.

1. Call `agent.wait(runId, timeoutMs: 0)` through a request-id registry.
2. Treat the gateway RPC timeout as `running`; it is not a model timeout.
3. If the run is running, poll again after 15 seconds.
4. If the run is completed, fetch timestamped `chat.history` and accept assistant content only inside the run window. Gateway `startedAt` wins; when OpenClaw's chat terminal cache omits it, the persisted binding start time is the lower bound. Gateway `endedAt` remains mandatory.
5. If status or correlated history is temporarily unavailable, retry five times and then enter nonterminal `recoveryUnavailable`.
6. Finish only on `final`, `error`, `aborted`, authoritative run status, or the background hard deadline.

An unacknowledged submission is a pre-run delivery state, not a model run. If OpenClaw repeatedly reports the exact `timeoutPhase=queue, providerStarted=false` missing-run shape for 60 seconds, the client ends that submission as not sent instead of polling forever. This limit never applies after acknowledgement or any run event.

There is no latest-message fallback and no text-length comparison. If ownership cannot be proven, the client keeps the run unresolved.

## Lifetime And Cancellation

- Foreground chat has no fixed client-side total timeout; the user controls its lifetime.
- Background chat has a one-hour hard deadline owned by the view model, not a SwiftUI row.
- Cancellation first records intent. A sent run becomes cancelled only when `chat.abort` returns `aborted=true` and includes the exact requested `runId`; a successful RPC envelope with `aborted=false` is not a terminal result. A local preparing run may cancel immediately.
- Cancellation, reconnect, final delivery, and launch recovery all use the same run registry and terminalization path.
- A provider-originated `LLM request timed out` error remains a terminal backend failure. Reconnecting the transport must not hide or extend it.
- OpenClaw's `agent.wait status=timeout` is interpreted from lifecycle metadata: a wait-only expiry remains running, while provider/runtime timeout metadata is terminal. Current gateways expose user abort and the chat stop command as `status=timeout` with an exact `stopReason=rpc` or `stop`; the same `stop` reason under `status=ok` remains a normal provider completion.

## UI And Rendering

- Timeline rows receive a projection of only their own run state.
- The work-status area can display connecting, connection lost, reconnecting, restoring, cancelling, and recovery unavailable states.
- Streaming text uses the lightweight native path and remains selectable.
- Rich Markdown, tables, MathJax, and WebView rendering start only after terminal final content is persisted.
- `ChatRuntimeState` and `TaskActivityState` are observed directly by chat surfaces; their high-frequency publications are no longer forwarded through `ChatViewModel` into the whole dashboard.
- Switching sessions does not change the session binding of an active run.
- After an image-review child loses live delivery, its event subscription is removed before polling authoritative state. This prevents an unbounded broadcast stream from buffering unrelated chat events while the batch waits for recovery or manual retry.

## Verification

Executable tests cover:

- five-attempt reconnect policy and transport event fan-out;
- typed run transitions and foreground/background placement;
- lifecycle coordinator cancellation and replacement;
- reconciliation retry thresholds;
- request-id routing with reverse-order, mismatched, cancelled, and late responses;
- semantic `chat.abort` routing, including `aborted=false`, mismatched run ids, RPC rejection, and transport loss;
- exact run-status parsing and timestamp-correlated history;
- failure-versus-cancellation classification;
- streaming, cancellation, session ownership, background preservation, timeline isolation, and localization structure.

The Xcode project, String Catalog, structural scripts, standalone tests, and macOS Debug build are the final verification gates.
