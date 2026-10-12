defmodule AshA2ui.LinkResolver do
  @moduledoc """
  Maps a reference-link target onto the host's surface vocabulary — and
  vetoes links the actor may not open.

  Fields declared with `link` / `links` (see the `field` DSL entity) render
  as references to other records. The library knows the target *record*;
  only the host knows which *surface* shows it (and whether this actor may
  open that surface at all). Configure a resolver:

      config :ash_a2ui, :link_resolver, MyApp.A2uiLinks

      defmodule MyApp.A2uiLinks do
        @behaviour AshA2ui.LinkResolver

        @impl true
        def surface_for({:resource, MyApp.People.Person}, _context), do: "person"
        def surface_for({:surface, "person"}, _context), do: "person"
        def surface_for(_target, _context), do: nil
      end

  `surface_for/2` is called once per linked field per render (never per
  row) with:

    * `target` — `{:resource, module}` for relationship links (`link :owner`,
      `links :participants`), `{:surface, key}` for explicit
      `{surface_key, id_path}` links;
    * `context` — `%{actor: actor, tenant: tenant}` of the render.

  Return the surface key (a string) or `nil` for "not openable": the field
  then renders its plain value with no link. A `{module, function, args}`
  tuple is accepted too (called as `apply(module, function, [target,
  context | args])`).

  Links are UX, not authorization: the opened surface enforces its own
  policies. Relationship links are additionally pruned per record by the
  authorized relationship load — a target the actor cannot read is not
  loaded, so it is never linked.

  Without a configured resolver, `{:surface, key}` targets keep their key
  and `{:resource, module}` targets map to the underscored short name of the
  resource (`MyApp.People.Person` → `"person"`, the default surface id).
  """

  @typedoc "What a link points at, before the host maps it to a surface key."
  @type target :: {:resource, module} | {:surface, String.t()}

  @typedoc "The render's actor and tenant."
  @type context :: %{actor: term, tenant: term}

  @doc "The surface key showing `target` for this render, or `nil` (no link)."
  @callback surface_for(target, context) :: String.t() | nil

  @doc """
  Resolves `target` through the configured resolver (or the default
  mapping). Any non-binary return (or an empty string) means no link.
  """
  @spec resolve(target, context) :: String.t() | nil
  def resolve(target, context) do
    :ash_a2ui
    |> Application.get_env(:link_resolver)
    |> call(target, context)
    |> surface_key()
  end

  defp call(nil, target, _context), do: default(target)

  defp call({module, function, args}, target, context),
    do: apply(module, function, [target, context | args])

  defp call(module, target, context) when is_atom(module), do: module.surface_for(target, context)

  defp surface_key(key) when is_binary(key) and key != "", do: key
  defp surface_key(key) when is_boolean(key) or is_nil(key), do: nil
  defp surface_key(key) when is_atom(key), do: Atom.to_string(key)
  defp surface_key(_none), do: nil

  @doc "The resolver-less mapping (see the module docs)."
  @spec default(target) :: String.t()
  def default({:surface, key}), do: to_string(key)

  def default({:resource, resource}) do
    resource |> Module.split() |> List.last() |> Macro.underscore()
  end
end
