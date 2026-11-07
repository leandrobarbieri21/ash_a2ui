# External Transports (AG-UI and A2A)

AshA2ui's protocol core emits plain A2UI message maps and consumes plain
action envelopes — [Rendering Clients](rendering-clients.md) covers the two
in-app transports (LiveView, plain JSON endpoints). This topic covers making
surfaces consumable by **external agents and non-Phoenix hosts** through the
interoperability stack around A2UI:

* **AG-UI** (agent ↔ user-facing app; CopilotKit's native protocol) —
  **shipped**, via `AshA2ui.AgUi`.
* **A2A** (agent ↔ agent; Google) — **designed, not yet implemented**;
  the binding is documented at the end of this topic.

## The stack, verified

Some precision is warranted, because the ecosystem naming is confusing:

* **A2UI** is the *generative-UI payload spec* — the `createSurface` /
  `updateComponents` / `updateDataModel` messages AshA2ui already emits. It
  is deliberately transport-agnostic.
* **AG-UI** is a *runtime interaction protocol*: ~25 typed JSON event kinds
  (run lifecycle, streamed text, tool calls, state, activities) flowing
  from an agent endpoint to a client, plus a `RunAgentInput` request shape
  flowing back. The default transport encoding is HTTP POST + Server-Sent
  Events. AG-UI is what CopilotKit clients speak natively.
* A2UI payloads ride AG-UI inside **activity events** — there is no
  first-class A2UI event type. The binding (established by
  `@ag-ui/a2ui-middleware`, consumed by CopilotKit's built-in A2UI
  renderer) is an `ACTIVITY_SNAPSHOT` event with `activityType:
  "a2ui-surface"` whose `content` carries the A2UI message list under the
  `"a2ui_operations"` key.

An "AG-UI-compatible server" is therefore small and concrete: **one HTTP
endpoint** that accepts a `POST` with a `RunAgentInput` JSON body
(`threadId`, `runId`, `messages`, `state`, `tools`, `context`,
`forwardedProps`) and streams `data: <event-json>\n\n` SSE frames — opening
with `RUN_STARTED` and closing with `RUN_FINISHED` or `RUN_ERROR`.

> #### Renderer versions {: .warning}
>
> As of July 2026, CopilotKit's shipped A2UI renderer
> (`@copilotkit/a2ui-renderer`, mounted by `createA2UIMessageRenderer` from
> `@copilotkit/react-core/v2`) processes **A2UI v0.9 messages** — its
> `MessageProcessor` is the `@a2ui/web_core/v0_9` implementation, and no
> published release ships a v1.0 runtime. Emit **v0.9.1** payloads on this
> transport. Every surface-building entry point accepts a per-call
> `spec_version:` override (`AshA2ui.Info.build_surface/2`,
> `AshA2ui.Dynamic.resolve/2`, `AshA2ui.ActionHandler.handle/3`) so the
> transport pins the wire version without touching surface DSLs — flip to
> `"1.0"` (inline `createSurface`, `actionResponse` handshake) the day the
> renderer supports it.

## What `AshA2ui.AgUi` provides

`AshA2ui.AgUi` is the protocol layer, deliberately framework-free (it
depends only on `Jason`, is always compiled, and works under `NO_PHOENIX`
builds):

| Function | Role |
|---|---|
| `run_started/2`, `run_finished/3`, `run_error/2` | Run lifecycle events |
| `text_message_start/2`, `text_message_content/2`, `text_message_end/1` | Streamed assistant tokens |
| `tool_call_start/3`, `tool_call_args/2`, `tool_call_end/1`, `tool_call_result/3` | Tool activity |
| `pending_tool_call/4` | A tool call left unresolved at `RUN_FINISHED` — the human-in-the-loop pause |
| `surface_activity/2` | An A2UI surface as an `a2ui-surface` activity snapshot |
| `refresh_activity/3` | Re-emit a surface with a freshly rebuilt data model |
| `custom/2` | App-specific extension events |
| `encode_sse/1` | One event → one `data: <json>\n\n` frame |
| `decode_run_input/1` | `RunAgentInput` body → thread/run ids, chat messages, tool results, `a2uiAction` |
| `decode_action/1` | AG-UI client action → the v0.9.1 envelope `ActionHandler` consumes |
| `resolve_pending/2` | Does this run answer a pending human-in-the-loop call? |

The HTTP endpoint itself stays in the host — that is where authentication,
actor resolution, and process supervision belong (and it keeps the
extension free of a Plug dependency).

## A Phoenix endpoint, end to end

A minimal AG-UI endpoint serving one surface-aware agent turn:

```elixir
defmodule MyAppWeb.AgUiController do
  use MyAppWeb, :controller

  alias AshA2ui.AgUi

  # Router: pipe_through your authenticated admin pipeline. The actor comes
  # from the session — NEVER from the request body.
  def run(conn, _params) do
    input = AgUi.decode_run_input(conn.body_params)
    actor = conn.assigns.current_user

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    {:ok, conn} = send_event(conn, AgUi.run_started(input.thread_id, input.run_id))

    conn =
      case input.a2ui_action do
        nil -> chat_turn(conn, input, actor)
        action -> surface_action(conn, input, action, actor)
      end

    {:ok, conn} = send_event(conn, AgUi.run_finished(input.thread_id, input.run_id))
    conn
  end

  defp send_event(conn, event), do: chunk(conn, AgUi.encode_sse(event))

  defp chat_turn(conn, input, actor) do
    # Drive your agent loop with input.messages; as it streams, map its
    # events onto AG-UI events (text_message_*, tool_call_*) and chunk them.
    # When the agent decides to show a surface:
    messages =
      AshA2ui.Info.build_surface(MyApp.UI.TicketUI,
        actor: actor,
        spec_version: "0.9.1"
      )

    {:ok, conn} = send_event(conn, AgUi.surface_activity("surface-tickets", messages))
    conn
  end

  defp surface_action(conn, _input, action, actor) do
    {:ok, envelope} = AgUi.decode_action(action)

    follow_ups =
      case AshA2ui.ActionHandler.handle(MyApp.UI.TicketUI, envelope,
             actor: actor,
             spec_version: "0.9.1"
           ) do
        {:ok, messages} -> messages
        {:error, messages} -> messages
      end

    # Re-emit the surface activity with the follow-ups appended; the client
    # replaces the rendered surface in place (same messageId).
    messages =
      AshA2ui.Info.build_surface(MyApp.UI.TicketUI, actor: actor, spec_version: "0.9.1")

    {:ok, conn} =
      send_event(conn, AgUi.surface_activity("surface-tickets", messages ++ follow_ups))

    conn
  end
end
```

Real hosts run the agent loop in a supervised task and receive its events
in the request process (so a crashed LLM call becomes a clean `RUN_ERROR`
frame); see the shape of `AshA2ui.LiveRenderer`'s task handling for the
same pattern in LiveView.

### The event mapping for an agent loop

For a tool-loop agent (e.g. `AshAi.ToolLoop`-style streams), the natural
mapping is:

| Agent loop event | AG-UI event(s) |
|---|---|
| turn starts | `run_started/2` |
| streamed assistant token | `text_message_start/2` (first token) + `text_message_content/2` |
| tool call begins | `text_message_end/1` (close any open message) + `tool_call_start/3` + `tool_call_args/2` + `tool_call_end/1` |
| tool result | `tool_call_result/3` |
| tool renders a surface | `surface_activity/2` with the built A2UI messages |
| turn ends | `text_message_end/1` + `run_finished/3` |
| turn crashes | `run_error/2` |

## The client-action round trip

When a user interacts with a rendered surface, CopilotKit's action bridge
attaches the action to the **next run**: it sets
`forwardedProps.a2uiAction = %{"userAction" => %{...}}`, runs the agent
once, and clears the property. On the server:

1. `decode_run_input/1` exposes the payload as `:a2ui_action`.
2. `decode_action/1` converts it into a spec-valid v0.9.1 client envelope
   (renderer extras dropped, required-but-omitted fields defaulted).
3. Route the envelope through `AshA2ui.ActionHandler.handle/3` (declared
   surfaces) or `AshA2ui.Dynamic.handle_action/3` (agent-composed
   surfaces) **with the session-derived actor** — the row-action
   allowlist, `visible_when` enforcement, query allowlists, and Ash
   policies all apply exactly as on in-app transports.
4. Append the returned `updateDataModel` follow-ups to the surface's
   operations and re-emit `surface_activity/2` under the same
   `messageId` — the client updates in place.

Because HTTP runs are stateless, a host that serves actions must remember
*which* surface a thread is showing (the UI module or the resolved
`AshA2ui.Dynamic.Surface` — the Dynamic host contract requires the
server-held struct). Key that state by **authenticated actor + thread id**,
never by client-supplied thread id alone.

## Human in the loop: pausing a turn on a surface decision

Some agent actions should not execute on the LLM's say-so — the agent
proposes, a human disposes. The AG-UI shape for this is a tool call that
the run **finishes without resolving**, answered on a later run. Bound to
surfaces, the convention is:

1. **Pause.** When the agent loop reaches the gated step, the host stops
   the loop and emits `pending_tool_call/4` (a `TOOL_CALL_START` /
   `TOOL_CALL_ARGS` / `TOOL_CALL_END` triple with **no**
   `TOOL_CALL_RESULT`), then a confirmation surface via
   `surface_activity/2`, then `run_finished/3`. The transcript shows an
   open question; the surface is how the user answers it.
2. **Remember.** Store the pending call — its tool call id plus the
   confirmation surface's id — scoped to **authenticated actor + thread
   id** (the same scoping rule as all per-thread surface state).
3. **Resume.** On each subsequent run, call `resolve_pending/2` with the
   decoded input and the stored pending descriptor *before* dispatching
   the run as a chat turn or ordinary surface action. It recognizes three
   answer shapes: a surface action whose context carries the pending id
   under `"toolCallId"`, any action originating from the stored
   confirmation surface id, or a `role: "tool"` result message for the id
   in the run's message history (the standard AG-UI frontend-tool path;
   `decode_run_input/1` collects these under `:tool_results`).
4. **Act.** On `{:resume, tool_call_id, result}`, the host interprets the
   user's decision, performs the gated side effect **itself**
   (actor-authorized, only on an explicit affirmative), and re-enters its
   agent loop with the decision supplied as the pending call's tool
   result — the LLM sees a completed tool call and narrates the outcome.

The library deliberately provides only the protocol pieces: what counts
as a gated action, how the confirmation surface looks, and how the
decision maps onto side effects are host policy.

## Refreshing an open surface (PubSub bridging)

`refresh_activity/3` rebuilds a surface's message list — declared UI
module or server-held `AshA2ui.Dynamic.Surface` — with fresh data and
wraps it as an activity snapshot. Two places to use it:

* **Post-action re-emits**: after routing an action envelope, re-emit the
  surface so the client renders the write's effect.
* **While-run-open live refreshes**: AG-UI is request/response, but the
  SSE response stays open for the whole run — long agent turns can flush
  data changes as they happen. Subscribe to the surface's PubSub topics
  when the stream opens, and in the request process's receive loop turn
  each change notification into a `refresh_activity/3` frame; unsubscribe
  when the run finishes:

```elixir
topics = ["ticket:created", "ticket:updated", "ticket:destroyed"]
Enum.each(topics, &Phoenix.PubSub.subscribe(MyApp.PubSub, &1))

# ... inside the receive loop that streams agent events:
{:record_changed, _payload} ->
  event = AgUi.refresh_activity("surface-tickets", MyApp.UI.TicketUI,
    actor: actor, spec_version: "0.9.1")
  {:ok, conn} = chunk(conn, AgUi.encode_sse(event))

# ... after RUN_FINISHED / RUN_ERROR:
Enum.each(topics, &Phoenix.PubSub.unsubscribe(MyApp.PubSub, &1))
```

Between runs no stream is open — a change that happens then reaches the
client on the next run's re-emit (rebuilds always load fresh data). Pass
`:query_state`/`:context_state` from the surface's last known client
state to preserve the user's filters and selections across refreshes.

## Wiring a CopilotKit client (no Node middleman)

CopilotKit's production-supported `selfManagedAgents` prop connects the
React client **directly** to your Phoenix endpoint — no CopilotRuntime /
Node.js layer:

```tsx
import { HttpAgent } from "@ag-ui/client";
import { CopilotKit, CopilotChat, createA2UIMessageRenderer }
  from "@copilotkit/react-core/v2";
import "@copilotkit/react-core/v2/styles.css";

const agent = new HttpAgent({
  url: "/my/ag-ui/endpoint",
  headers: { "x-csrf-token": readCsrfTokenFromMetaTag() },
});

// With a self-managed agent there is no runtime /info discovery, so mount
// the A2UI renderer explicitly:
const renderers = [createA2UIMessageRenderer({ theme: myTheme })];

<CopilotKit
  selfManagedAgents={{ "my-agent": agent }}
  renderActivityMessages={renderers}
>
  <CopilotChat agentId="my-agent" />
</CopilotKit>;
```

Authentication rides your existing web session: `HttpAgent` uses `fetch`,
which sends same-origin cookies by default; add your CSRF token header for
POST endpoints behind `protect_from_forgery`.

## The authentication / actor contract

The same contract as every AshA2ui transport, restated because this one
faces external clients:

1. **The host authenticates the transport.** Router pipelines or plugs
   decide who may reach the endpoint at all.
2. **The actor comes from the session, never the body.** Everything in
   `RunAgentInput` (`threadId`, `state`, `forwardedProps`, messages) is
   client-controlled input.
3. **`authorize?: true` stays on.** AshA2ui never bypasses policies;
   do not pass `authorize?: false` on a network-facing transport.
4. **Per-thread server state is actor-scoped.** A thread id is a client
   claim, not an identity.

## The A2A binding (designed, deferred)

[A2A](https://a2a-protocol.org) is the agent-to-agent protocol; a2ui.org
publishes an official **A2UI extension for A2A** that we verified against
the v0.9.1 and v1.0 extension specifications:

* Activation: the client requests the extension via the transport's
  extension mechanism (the `X-A2A-Extensions` header for JSON-RPC/HTTP);
  agents advertise it (and their `supportedCatalogIds`) in their Agent
  Card `capabilities.extensions`.
* Server → client: A2UI messages are encoded as an A2A `DataPart` with
  `metadata.mimeType: "application/a2ui+json"`; the part's `data` field
  **must be an array** of A2UI messages validating against the
  server-to-client message-list schema.
* Client → server: the same `DataPart` shape, with `data` carrying
  `action` messages validating against the client-to-server list schema —
  i.e. exactly the envelopes `AshA2ui.ActionHandler.handle/3` consumes.
* Metadata: `a2uiClientCapabilities` (supported catalogs) travels in every
  client message's `metadata`; when `sendDataModel` is enabled the client
  echoes `a2uiClientDataModel` the same way. A2UI sessions map to A2A
  `contextId`. `AshA2ui.Experience.catalog_for/1` turns those capabilities
  into the `:catalog` build option (or `{:error, :no_common_catalog}`), and
  any transport whose client sends them can use it today.

Since AshA2ui's message lists are already spec-valid maps, the eventual
implementation is thin: wrap `AshA2ui.Info.build_surface/2` output in a
`DataPart` (`%{"kind" => "data", "data" => messages, "metadata" =>
%{"mimeType" => "application/a2ui+json"}}`) inside an A2A task/message
envelope, and unwrap incoming parts into `ActionHandler`. What it waits on:

* an A2A server to embed in (there is no mature Elixir A2A server library
  as of July 2026 — the JSON-RPC task lifecycle, Agent Card serving, and
  push notifications are the actual work, none of it A2UI-specific);
* a concrete consumer (the AG-UI path already covers user-facing chat
  clients; A2A pays off for agent-to-agent surface handoff).

When that lands it should follow this topic's shape: a framework-free
binding module (`AshA2ui.A2a`) plus host-side documentation, with the
DataPart payloads conformance-tested against the vendored A2UI schemas.
