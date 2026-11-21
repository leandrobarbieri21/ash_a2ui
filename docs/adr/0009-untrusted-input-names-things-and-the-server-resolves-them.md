# 0009. Agent and client input only names things; the server resolves them through an allowlist it holds

- Status: proposed
- Date: 2026-11-14
- Plane: AST-187

## Context

Three features let an outsider drive the surface by name:

- **Agent-composed surfaces** (`AshA2ui.Dynamic`, `lib/ash_a2ui/dynamic.ex`): a language
  model emits a JSON spec naming resources, attributes, actions and presets.
- **The canvas** (`AshA2ui.Canvas`, `lib/ash_a2ui/canvas.ex`): a client asks "what exists?"
  with opaque references such as `"resource:app.thing"` or `"record:app.thing:pk"`.
- **The command shell** (`AshA2ui.Shell`, `lib/ash_a2ui/shell.ex`): a person types
  `/open people 3`, which becomes an invocation.

Each one is a way to turn a string from outside into a module, an action or a record. The
obvious implementation (`String.to_existing_atom`, `Module.concat`) lets a crafted string
reach any resource in the application, and an LLM is a source of crafted strings.

## Decision

1. **A name is looked up in a host-held allowlist and is never converted.**
   - `Dynamic.resolve/2` requires `:allowlist` and resolves the spec's resource, every
     context resource, every related table and every `sections` source against it
     (`AshA2ui.Dynamic.allowlist/1`, by short module name). A `via`-delegated row action
     (host code) is rejected unless the host passes `:via_allowlist`; the parser checks it
     again independently.
   - `Canvas` resolves a reference by matching it as a string against the domains the host's
     `AshA2ui.Canvas.Registry` lists. "What the registry does not list does not exist"
     (`CANVAS-SEC-005`); no client string becomes an atom or module (`CANVAS-SEC-006`); a
     failure is the bare `{:error, :unknown_object}` with no registry content in it
     (`canvas/object_ref.ex`).
   - `Shell` matches a line only against the command and surface lists the host passed in,
     and "filters and routes; it never widens". The host builds those lists from the same
     policies the transports enforce.
2. **Outsider input goes through the same validators and the same policies as declared
   input.** A composed spec is parsed through Spark's own entity schemas
   (`Dynamic.Parser`) and then the compile-time verifiers (ADR 0008). A composed surface's
   actions run through `ActionHandler` with `authorize?: true` (ADR 0007).
3. **The server is the only source of a spec, and it holds the resolved surface.** The
   client never echoes a spec back. The host resolves once, keeps the
   `%AshA2ui.Dynamic.Surface{}` in server state keyed by `surface_id`, and serves actions
   from that struct (`dynamic/surface.ex` "Host contract"). `Surface` must only be built by
   `resolve/2`. Specs hold no secrets and validation is deterministic, so re-resolving the
   stored raw spec after a reconnect is also sound.
4. **Capabilities are derived data, never input.** `Canvas.Capability` is computed from Ash
   metadata and `Ash.can?/3`; a client-built capability envelope is ignored by the resolver
   and the tests pin that (`A2UI-103/AC-2`). Structural canvas objects read no records;
   record references enter through an authorized read by primary key.
5. **Resource limits are part of the contract.** A composed board is capped at 12 cells
   (`Dynamic.max_composed_cells/0`).
6. **Composer errors are for the agent, and say what is available.** `Dynamic.Error`
   messages reuse the verifiers' wording and stay English, so a tool loop can feed them back
   to the model for self-correction.

## Consequences

- A model can compose a useful surface and cannot reach a resource, action or module the
  host did not offer, nor widen what a policy allows.
- The host owns the discipline in point 3. The library cannot enforce that a host stores
  the struct instead of the client's echo; it documents the contract and makes the unsafe
  path hard to type (`Surface` is "opaque").
- The default allowlist, `extension_resources/1` ("what already has a declared surface may
  also be composed"), is convenient and is also a way to offer more than intended. A host
  with a sensitive resource that carries the extension should pass an explicit list.
- A Canvas or shell feature that wants a new kind of reference adds a string form to the
  parser, not a conversion.

## Reversal

Dropping the allowlist (composing against any resource of an OTP app) would make the
agent's reach equal to the application's. That is a security decision, and needs its own
ADR that names who can approve it.
