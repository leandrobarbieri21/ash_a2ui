defmodule AshA2ui.Dynamic.Surface do
  @moduledoc """
  A validated, server-held agent-composed surface — the artifact
  `AshA2ui.Dynamic.resolve/2` returns and every other `AshA2ui.Dynamic`
  function consumes.

  It wraps the synthetic DSL state the spec resolved to, plus the identifying
  metadata hosts render around it. Treat it as opaque: **only construct it
  through `AshA2ui.Dynamic.resolve/2`** — a hand-built or client-supplied
  struct bypasses the allowlist and verifier pipeline that makes dynamic
  surfaces safe.

  ## Host contract (tamper-proofing)

  The client is never trusted to echo the spec back. Hosts must:

    1. resolve the spec **once**, server-side, and keep the returned
       `%Surface{}` in server state (a LiveView assign, ETS, a cache) keyed
       by `surface_id`,
    2. route client `action` envelopes to
       `AshA2ui.Dynamic.handle_action(surface, envelope, opts)` using the
       **server-held** struct looked up by the envelope's surface id —
       never anything reconstructed from client input,
    3. drop the stored struct when the surface is dismissed.

  Everything the client sends remains plain envelope data validated the same
  way declared surfaces validate it (`row_actions` allowlist, query
  allowlists, authorized reads, `authorize?: true` Ash calls).
  """

  defstruct [:surface_id, :resource, :title, :spec, :dsl_state, imported?: false]

  @type t :: %__MODULE__{
          surface_id: String.t(),
          resource: module,
          title: String.t() | nil,
          spec: map,
          dsl_state: map,
          imported?: boolean
        }
end
