# What is AshA2ui?

AshA2ui is an [Ash](https://hexdocs.pm/ash) extension that turns the
declarative knowledge already inside your Ash resources — attributes, types,
actions, policies — into
[A2UI (Agent to UI)](https://github.com/a2ui-project/a2ui) protocol
payloads — **v0.9.1** by default, **v1.0 (RC)** per surface — a standard,
JSON-based description of a user interface that a remote renderer turns
into live, interactive UI. To our knowledge it is the first framework with
an executable A2UI 1.0 conformance suite: the spec's own schemas and test
cases are vendored at a pinned RC commit and run in CI against every
message the framework can emit (see [A2UI 1.0](a2ui-1-0.md)).

You write a small `a2ui` block describing *what* a surface shows; AshA2ui
generates the wire messages, routes user interactions back into Ash actions,
and enforces your authorization along the way.

## The idea: server-driven UI for the agent era

Server-driven UI is old (every native app with a "backend-driven" home feed
does it). What's new is *who renders*: agent canvases, chat surfaces, and
embeddable web components now accept a standardized UI description and render
it wherever the user happens to be. A2UI is Google's open protocol for exactly
that: the server sends `createSurface` → `updateComponents` →
`updateDataModel` messages (plus `deleteSurface`), and the client sends back a
single `action` envelope when the user does something.

Ash sits on the other end of a happy coincidence: an Ash resource is already
the most machine-readable description of your domain that exists in your
codebase. Field names, types, constraints, which actions accept what, who's
allowed to do which — it's all introspectable. AshA2ui is the bridge:

```text
Ash resource (+ a2ui DSL block)
      │  AshA2ui.ResolvedView.resolve/2   (normalization seam)
      ▼
ResolvedView struct
      │  AshA2ui.Encoder.V0_9_1 / .V1_0   (versioned encoders, per spec_version)
      ▼
A2UI messages  ──► any transport ──► any A2UI renderer
      ▲
      │  AshA2ui.ActionHandler.handle/3   (action envelope → Ash action)
      └────────────────  client `action` envelopes
```

The protocol core (everything above) depends only on `ash`. Transports are
pluggable:

- **`AshA2ui.LiveRenderer`** — a batteries-included LiveView transport
  (optional `phoenix_live_view` dependency) that pushes messages over the
  LiveView socket to a JS hook hosting `<a2ui-surface>`, receives actions as
  LiveView events, and live-refreshes data via `Ash.Notifier.PubSub`.
- **Plain JSON endpoints** — a controller returning
  `AshA2ui.Info.build_surface/2`'s message list is a complete read transport;
  post `action` envelopes to `AshA2ui.ActionHandler.handle/3` for writes.

See [Rendering Clients](rendering-clients.md) for both in detail.

## What v0 covers

- **Table + form components** — tables composed from the basic catalog's
  `List` + `Row`/`Column` (the catalog has no Table component), forms bound to
  create/update actions.
- **Row actions** — per-row buttons mapped to Ash actions; the declared list
  is the server-side allowlist.
- **Field inference** — omit `fields` and they're derived from public
  attributes (tables) or action `accept`s (forms).
- **Type → widget mapping** — sensible widget defaults from Ash types, with
  per-field overrides.
- **Compile-time verifiers** — referenced fields and actions are checked when
  the resource compiles.
- **Actor-aware authorization** — all reads and actions run with your
  `actor:`/`tenant:` and `authorize?: true`;
  see [Actions and Authorization](actions-and-authorization.md).
- **PubSub live refresh** — via the LiveView transport.
- **Server-enforced queries** — named search/sort/filter/pagination
  allowlists; see [Queries and Pagination](queries-and-pagination.md).
- **Relationship rendering** — `belongs_to` form selects and `source` table
  columns; see [Relationship Rendering](relationships.md).
- **A2UI v1.0 (RC)** — per-surface `spec_version "1.0"`: single-message
  surfaces, the `actionResponse` per-action feedback contract, and an
  executable conformance suite; see [A2UI 1.0](a2ui-1-0.md).

Everything else (overrides, custom catalogs, non-LiveView streaming
transports…) is deliberately roadmap — see the
[README](../../README.md) for the list.

## When it pays off — and when it doesn't

Be honest with yourself about this boundary; AshA2ui is *not* trying to
replace your rendering stack.

**It pays off when the UI description must travel:**

- The renderer isn't your Phoenix app: an agent canvas, a chat surface, an
  embedded panel in someone else's product, a native shell.
- Multiple clients should render the same surface (web + mobile + agent) and
  you want one source of truth on the server.
- The surface is a straightforward projection of a resource — a table, a
  form, a handful of actions — and you'd rather declare it than build it.
- You want the *contract* (which fields, which actions, who may invoke them)
  enforced server-side at compile time, not re-implemented per client.

**Prefer something else when:**

- You need a full internal admin across many resources *now* —
  [AshAdmin](https://hexdocs.pm/ash_admin) gives you that with near-zero
  per-resource config, rendered in-process with no protocol in between.
- The page needs bespoke interactions, pixel-level control, or rich
  domain-specific widgets — plain LiveView (or
  [Backpex](https://hexdocs.pm/backpex) for Ecto-first admin panels) will
  fight you less. A protocol with a fixed component catalog is a ceiling, not
  a floor.
- The UI is deeply stateful and server-coupled (server round trips per
  keystroke, collaborative editing, multi-step flows that branch on an
  answer, upload files or wait on background work) — that's LiveView's home
  turf. Linear, server-validated steps over one Ash action are covered by
  form `step`s (see [Wizard Steps](wizard-steps.md)).
- You only have one Phoenix web client and no agent/embedding story on the
  horizon: the protocol indirection buys you nothing yet.

### A real data point

The reference proof-of-concept replaces a hand-written admin LiveView
(master–detail list, create/edit form, row action, flash feedback) weighing
**437 lines** (179 LiveView + 258 HEEx) with an `a2ui` block plus a thin
LiveView shell: **92 lines** (38 standalone UI module + 35 LiveView + 19
JSON controller, moduledocs included; see the coverage matrix in the
[README](../../README.md)).

One parity gap surfaced in the POC: the row action returns a secret into the
client data model (`/ui/action_result`), but no catalog component displays
it — the old page showed it in a selectable field. That's roadmap material
(an action-result display component), not a backend workaround.

The honest reading: the win isn't only line count — it's that the replacement
is a declaration checked at compile time, renders through a standard protocol
any A2UI client can consume, and gained PubSub live refresh for free. If none
of those properties matter for your page, 437 lines of LiveView you fully
control may well be the better deal.
