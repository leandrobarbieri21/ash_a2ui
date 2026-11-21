# 0007. Authorization has no side channel: Ash policies decide, and the host supplies the actor through hooks

- Status: proposed
- Date: 2026-11-14
- Plane: AST-187

## Context

A surface that renders records and runs actions is an access-control surface. ash_a2ui
sits between an Ash resource and a remote client that is partly untrusted: the browser
sends action names, record ids and filter values, and an agent-composed surface (ADR 0009)
is written by a model. The package has to answer three questions:

1. Whose policies decide what a surface shows and does?
2. How does the host say who the actor and tenant are, for every transport?
3. What is the client allowed to influence?

It also has to be honest about what it does not enforce. A policy-less resource has no
access control, however the surface is rendered.

## Decision

1. **Ash policies are the only authorization.** Every read and write goes through ordinary
   Ash actions with `actor:`, `tenant:` and `authorize?: true`
   (`lib/ash_a2ui/action_handler.ex`, `lib/ash_a2ui/query_runner.ex`). The package adds no
   permission model, no second policy DSL and no role vocabulary
   (`documentation/topics/actions-and-authorization.md`).
2. **The actor and tenant are a host hook, never ambient.** `AshA2ui.LiveRenderer` takes
   `:actor_fn` and `:tenant_fn`, 1-arity functions of the socket, evaluated on mount and
   passed to every build, refresh and action call (`lib/ash_a2ui/live_renderer.ex`). The
   default is `nil`, so a host that forgets the hook gets policies evaluated against no
   actor, which fails closed on any resource with policies. A non-LiveView transport passes
   `actor:` and `tenant:` to `Info.build_surface/2` and `ActionHandler.handle/3` itself.
   Navigation from a reference link is a hook too (`:open_surface`, `:open_surface_url`),
   and the opened surface authorizes its own read: the link check proves the link was
   offered, not that the target is allowed.
3. **Rendering is an action.** `AshA2ui.Transformers.AddRenderAction` adds a `render_a2ui`
   generic action to every extended resource, running `AshA2ui.RenderA2uiAction`, so surface
   building goes through the policy pipeline, code interfaces and tracing. A host opts out
   with `add_render_action? false`.
4. **The client names, the server decides.** Record ids sent by a client are re-read
   through an authorized read before use; spoofed ids never reach `/form`. Row actions are
   restricted to the declared allowlist, and `visible_when` is enforced server-side on each
   invocation, not only drawn. Query filters come from the declared `query` allowlist; "the
   client contributes no filter" (`action_handler.ex` comments, `query_runner.ex`).
5. **`Ash.can?` is a UX aid, never the boundary.** `start_edit` pre-flights the update
   authorization so the panel never opens on a write the server would refuse, and
   `AshA2ui.Canvas.Capability` reports per-object verdicts. Execution always re-authorizes
   through the action path.
6. **Failures do not leak policy detail.** `Ash.Error.Forbidden` produces one fixed
   `FORBIDDEN` message and no field errors. An error not written for the user becomes "The
   action failed." with its text sent to `Logger.error/1` only, since a raw error can carry
   row values (`ActionHandler` moduledoc, error table in the authorization topic).
7. **The `:authorize?` option exists, defaults to `true`, and is not a host feature.** The
   handler accepts `authorize?: false` for tests and trusted internal callers. A host
   transport must not expose it.
8. **One named exception: the actor picker.** `AshA2ui.Actor` (`lib/ash_a2ui/actor.ex`)
   lists and loads actor records with `authorize?: false`, because the picker has to show
   actors before one is chosen, as any sign-in screen does. It is for hosts without
   authentication (demos, internal tools). It validates the session id with a primary-key
   read on every switch and mount, and a stale id degrades to "no actor". It must not sit in
   front of a production surface.

## Consequences

- A host gets authorization by writing Ash policies it needs anyway, and the surface and the
  API cannot disagree.
- **A surface on a policy-less resource is not access-controlled.** `authorize?: true` is a
  no-op there. The docs say so in the first screen of the topic. There is no compile-time
  check that rejects a surface on a resource without policies; that choice keeps the library
  from deciding a host's security posture, and costs a host the safety net.
- The hook defaults fail closed on a policied resource and open on an unpolicied one.
- Nothing in the package can grant access the Ash resource refuses. Features that need a
  looser read (a public landing surface) have to be a resource with a policy that allows it.
- Points 4 and 6 are the audit list for a review of a new action in the handler: what does
  the client name, is it re-read through an authorized action, and what does a failure say.

## Reversal

A policy of the package's own (for example a per-surface visibility rule) would be a new
layer over Ash and a second source of truth. Do not add it without an ADR that answers why
an Ash policy or a calculation cannot express it.

## Follow-ups

- A verifier or a startup warning for an extended resource with no policies, opt-out per
  resource.
