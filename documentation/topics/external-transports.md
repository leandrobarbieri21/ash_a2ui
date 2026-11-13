# External Transports (A2A)

AshA2ui's protocol core emits plain A2UI 1.0 message maps and consumes plain
renderer messages — [Rendering Clients](rendering-clients.md) covers the two
in-app transports (LiveView, plain JSON endpoints). This topic covers making
surfaces consumable by **external agents and non-Phoenix hosts**. The
agent-to-agent binding (**A2A**) is **designed, not yet implemented**; this
topic documents it, and the contract any external transport must keep.

## The authentication / actor contract

The same contract as every AshA2ui transport, restated because an external
transport faces clients you do not control:

1. **The host authenticates the transport.** Router pipelines or plugs
   decide who may reach the endpoint at all.
2. **The actor comes from the session, never the body.** Everything in an
   incoming message (its context, any thread or task state) is
   client-controlled input.
3. **`authorize?: true` stays on.** AshA2ui never bypasses policies;
   do not pass `authorize?: false` on a network-facing transport.
4. **Per-conversation server state is actor-scoped.** A thread or task id is
   a client claim, not an identity.

## The A2A binding (designed, deferred)

[A2A](https://a2a-protocol.org) is the agent-to-agent protocol; a2ui.org
publishes an official **A2UI extension for A2A** that described in
the upstream specification:

* Activation: the client requests the extension via the transport's
  extension mechanism (the `X-A2A-Extensions` header for JSON-RPC/HTTP);
  agents advertise it (and their `supportedCatalogIds`) in their Agent
  Card `capabilities.extensions`.
* Agent → renderer: A2UI messages are encoded as an A2A `DataPart` with
  `metadata.mimeType: "application/a2ui+json"`; the part's `data` field
  **must be an array** of A2UI messages validating against the
  agent-to-renderer message-list schema.
* Client → server: the same `DataPart` shape, with `data` carrying
  renderer-to-agent messages (`action`, `callAgentFunction` and the others)
  validating against the renderer-to-agent list schema — i.e. exactly the
  messages `AshA2ui.ActionHandler.handle/3` consumes.
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
* a concrete consumer (A2A pays off for agent-to-agent surface handoff).

When that lands it should follow this topic's shape: a framework-free
binding module (`AshA2ui.A2a`) plus host-side documentation, with the
DataPart payloads conformance-tested against the vendored A2UI schemas.
