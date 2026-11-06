defmodule AshA2ui.Canvas.Registry do
  @moduledoc """
  The host-configured catalogue of what the canvas knows to exist.

  A registry is a module implementing this behaviour. `domains/0` returns
  the compile-known Ash domain modules the canvas may traverse — this is the
  entire discovery surface (`CANVAS-SEC-005`): what the registry does not
  list does not exist, and no resolver path ever widens it. The optional
  `label/1` callback lets a host override display labels; it receives
  `:application`, a domain module, a resource module, or a record struct,
  and returning `nil` (or not implementing the callback) falls back to the
  library's humanized defaults.

  The library ships `Canvas.Test.Registry` over the test-support fixtures;
  hosts implement their own.
  """

  @doc """
  The domain modules the canvas may traverse. Compile-known modules only —
  the resolver matches client refs against these as strings and never
  converts input into module names.
  """
  @callback domains() :: [module()]

  @doc """
  Optional display-label override. Receives `:application`, a domain
  module, a resource module, or a record struct; `nil` falls back to the
  library default.
  """
  @callback label(target :: :application | module() | struct()) :: String.t() | nil

  @doc """
  Optional projection override. Receives a resource module or a record
  struct together with the projections the library derived from the
  resource's own actions, and returns the list the object should carry;
  `nil` (or not implementing the callback) keeps the derived list.

  This exists because some projections cannot be derived from action shape
  at all. `:diagram` and `:history` are in the vocabulary precisely for
  things like a process definition and a running instance, and no amount of
  reading a resource's actions reveals that one of them is drawable — only
  the host knows it ships a renderer for it.

  The returned list is filtered against the declared vocabulary, so a host
  cannot introduce a projection kind the experience compiler has no meaning
  for. Returning `[]` is allowed and means "no projections", which is not
  the same as returning `nil`.
  """
  @callback projections(target :: module() | struct(), derived :: [atom()]) :: [atom()] | nil

  @doc """
  Optional consequence override. Receives the resource module, the action
  name and the consequence the library derived from the action's type
  (`:read` for a read, `:destructive` for a destroy, `:mutation` otherwise),
  and returns the consequence the capability should carry; `nil` (or not
  implementing the callback) keeps the derived one.

  A host that keeps its own declaration of what each action does (reads
  only, changes data, deletes or reaches outside) answers from it, so a
  generic action that only reads is not shown as a change, and one that
  removes data asks for confirmation. The consequence drives the
  capability's `confirmation` (`:required` for `:destructive`).

  Anything other than `:read`, `:mutation` or `:destructive` keeps the
  derived consequence: an unrecognised answer is never read as a lighter
  one.
  """
  @callback consequence(resource :: module(), action :: atom(), derived :: consequence()) ::
              consequence() | nil

  @typedoc "What running an action does, as a capability states it."
  @type consequence :: :read | :mutation | :destructive

  @optional_callbacks [label: 1, projections: 2, consequence: 3]

  @consequences [:read, :mutation, :destructive]

  @doc false
  # The registry's domain list, with a fail-loud check: a registry that does
  # not implement the behaviour is a configuration error, not an empty
  # canvas.
  def domains(registry) do
    if Code.ensure_loaded?(registry) and function_exported?(registry, :domains, 0) do
      registry.domains()
    else
      raise ArgumentError,
            "#{inspect(registry)} is not an AshA2ui.Canvas.Registry: it does not implement domains/0"
    end
  end

  @doc false
  # The registry's label for `target`, or nil when the host provides no
  # override.
  def label(registry, target) do
    if Code.ensure_loaded?(registry) and function_exported?(registry, :label, 1) do
      registry.label(target)
    else
      nil
    end
  end

  @doc false
  # The host's projections for `target`, defaulting to the library's derived
  # list. The caller re-filters against the declared vocabulary; this only
  # decides whose list is used.
  def projections(registry, target, derived) do
    if Code.ensure_loaded?(registry) and function_exported?(registry, :projections, 2) do
      case registry.projections(target, derived) do
        nil -> derived
        list when is_list(list) -> list
        _not_a_list -> derived
      end
    else
      derived
    end
  end

  @doc false
  # The host's consequence for `resource`'s `action`, defaulting to the
  # library's derived one. An answer outside the vocabulary keeps `derived`.
  def consequence(registry, resource, action, derived) do
    if Code.ensure_loaded?(registry) and function_exported?(registry, :consequence, 3) do
      case registry.consequence(resource, action, derived) do
        consequence when consequence in @consequences -> consequence
        _nil_or_unknown -> derived
      end
    else
      derived
    end
  end

  @doc false
  # The application id used for the root node and `application:` refs:
  # derived from the registry module's own (compile-known) name, so it is
  # stable and never client-influenced.
  def application_id(registry) do
    short =
      registry
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    "application:" <> short
  end
end
