defmodule AshA2ui.Canvas.ObjectResolver do
  @moduledoc """
  Turns an opaque ref into a resolved `%AshA2ui.Canvas.Object{}`.

  The pipeline is strictly: **parse** (`AshA2ui.Canvas.ObjectRef.parse/1`,
  pure string shape validation) → **registry match** (string comparison of
  the parsed path against the compile-known short names of the registry's
  domains and their resources) → **materialize** (pure introspection for
  structural objects; one authorized read by primary key for records).

  Security invariants, pinned by the acceptance tests:

    * no input is ever converted to an atom or a module (`CANVAS-SEC-006`).
      Module names enter only through the registry's `domains/0`; client
      strings are compared, never instantiated;
    * malformed, unknown, and unregistered refs — and record reads that
      fail (not found *or* forbidden; a record the actor cannot read does
      not exist for them) — all return the bare `{:error, :unknown_object}`,
      leaking nothing about the registry's contents;
    * capability-shaped options are not inputs: capabilities are derived
      server-side, and any extra options (forged or otherwise) cannot
      influence the resolved object.
  """

  require Ash.Query

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.Canvas.Capability
  alias AshA2ui.Canvas.Object
  alias AshA2ui.Canvas.ObjectRef
  alias AshA2ui.Canvas.Registry
  alias AshA2ui.Label

  # Every emitted projection must be one of the declared kinds, in the
  # declared order.
  @projections [:inspect, :browse, :view, :create, :edit, :act, :diagram, :history]

  defp declared(projections), do: Enum.filter(@projections, &(&1 in projections))

  @doc """
  Resolves `ref` under `opts` (see `AshA2ui.Canvas.resolve/2`).
  """
  @spec resolve(term, keyword) :: {:ok, Object.t()} | {:error, :unknown_object}
  def resolve(ref, opts) when is_binary(ref) and is_list(opts) do
    registry = Keyword.get(opts, :registry)

    if Registry.domains(registry) == [] do
      {:error, :unknown_object}
    else
      with {:ok, parsed} <- ObjectRef.parse(ref),
           {:ok, match} <- match_registry(parsed, registry) do
        materialize(parsed, match, opts)
      end
    end
  end

  def resolve(_not_a_string, _opts), do: {:error, :unknown_object}

  # --- registry matching -------------------------------------------------------

  # Client input is compared against registry-derived strings only. Every
  # mismatch collapses to the same unknown-object error.
  defp match_registry(%ObjectRef{kind: :application} = ref, registry) do
    if ref.id == Registry.application_id(registry) do
      {:ok, {:application}}
    else
      {:error, :unknown_object}
    end
  end

  defp match_registry(%ObjectRef{kind: :domain} = ref, registry) do
    wanted = domain_path(ref.id)

    case Enum.find(registry_domains(registry), &(&1.short == wanted)) do
      nil -> {:error, :unknown_object}
      entry -> {:ok, {:domain, entry.module}}
    end
  end

  defp match_registry(%ObjectRef{kind: :resource} = ref, registry) do
    [domain_wanted, resource_wanted] = resource_path(ref.id)

    with {:ok, domain} <- find_domain(registry, domain_wanted),
         {:ok, resource} <- find_resource(domain, resource_wanted) do
      {:ok, {:resource, domain, resource}}
    end
  end

  defp match_registry(%ObjectRef{kind: :record} = ref, registry) do
    [domain_wanted, resource_wanted] = resource_path(ref.id)

    with {:ok, domain} <- find_domain(registry, domain_wanted),
         {:ok, resource} <- find_resource(domain, resource_wanted) do
      {:ok, {:record, domain, resource}}
    end
  end

  defp registry_domains(registry) do
    registry
    |> Registry.domains()
    |> Enum.map(&%{short: Ash.Domain.Info.short_name(&1) |> Atom.to_string(), module: &1})
    |> Enum.sort_by(& &1.short)
  end

  defp find_domain(registry, short) do
    case Enum.find(registry_domains(registry), &(&1.short == short)) do
      nil -> {:error, :unknown_object}
      entry -> {:ok, entry.module}
    end
  end

  defp find_resource(domain, short) do
    domain
    |> Ash.Domain.Info.resources()
    |> Enum.find(&(&1 |> resource_short() == short))
    |> case do
      nil -> {:error, :unknown_object}
      resource -> {:ok, resource}
    end
  end

  # `application:foo` -> "foo"; `domain:blog` -> "blog";
  # `resource:blog.post` -> ["blog", "post"]; `record:blog.post:<pk>` -> ["blog", "post"]
  # (the encoded pk rides behind the third colon and is handled separately).
  defp domain_path(id), do: tail_segment(id)

  defp resource_path(id) do
    id
    |> String.split(":", parts: 3)
    |> Enum.at(1)
    |> String.split(".", parts: 2)
  end

  defp tail_segment(id), do: id |> String.split(":", parts: 2) |> List.last()

  defp resource_short(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  # --- materialization --------------------------------------------------------

  defp materialize(%ObjectRef{kind: :application} = ref, {:application}, opts) do
    registry = Keyword.fetch!(opts, :registry)

    object = %Object{
      ref: ref,
      label:
        Label.translate(
          l10n(opts),
          Registry.label(registry, :application) ||
            Registry.application_id(registry) |> tail_segment() |> Label.humanize()
        ),
      description: nil,
      projections: [:browse],
      capabilities: [],
      provenance: %{registry: registry}
    }

    {:ok, object}
  end

  defp materialize(%ObjectRef{kind: :domain} = ref, {:domain, domain}, opts) do
    registry = Keyword.fetch!(opts, :registry)

    object = %Object{
      ref: ref,
      label:
        Label.translate(
          l10n(opts),
          Registry.label(registry, domain) ||
            domain |> Ash.Domain.Info.short_name() |> Atom.to_string() |> Label.humanize()
        ),
      description: nil,
      projections: [:browse],
      capabilities: [],
      provenance: %{domain: domain}
    }

    {:ok, object}
  end

  defp materialize(%ObjectRef{kind: :resource} = ref, {:resource, domain, resource}, opts) do
    registry = Keyword.fetch!(opts, :registry)

    object = %Object{
      ref: ref,
      label:
        Label.translate(
          l10n(opts),
          Registry.label(registry, resource) || Label.humanize(resource_short(resource))
        ),
      description: nil,
      projections: host_projections(registry, resource, resource_projections(resource)),
      capabilities: resource_capabilities(ref, resource, registry, l10n(opts)),
      provenance: %{domain: domain, resource: resource}
    }

    {:ok, object}
  end

  defp materialize(%ObjectRef{kind: :record} = ref, {:record, domain, resource}, opts) do
    with {:ok, pk} <- ObjectRef.decode_pk(encoded_pk(ref.id)),
         {:ok, record} <- fetch_record(resource, pk, opts) do
      registry = Keyword.fetch!(opts, :registry)
      capabilities = record_capabilities(ref, resource, record, opts)

      object = %Object{
        ref: ref,
        label: Registry.label(registry, record) || default_record_label(record),
        description: nil,
        projections: host_projections(registry, record, record_projections(capabilities)),
        capabilities: capabilities,
        provenance: %{domain: domain, resource: resource, record: record}
      }

      {:ok, object}
    end
  end

  defp encoded_pk(record_ref_id) do
    record_ref_id |> String.split(":", parts: 3) |> List.last()
  end

  # The one authorized read in the whole namespace: record refs enter
  # through the resource's primary read by primary key, under the scene's
  # actor and tenant. Any failure — not found *or* forbidden — collapses to
  # the same unknown-object error (existential non-disclosure).
  defp fetch_record(resource, pk, opts) do
    resource
    |> Ash.get(pk,
      actor: opts[:actor],
      tenant: opts[:tenant],
      authorize?: Keyword.get(opts, :authorize?, true)
    )
    |> case do
      {:ok, record} -> {:ok, record}
      _not_found_or_forbidden -> {:error, :unknown_object}
    end
  end

  # --- capabilities -----------------------------------------------------------

  # Resource level: presence only. Execution still routes through the
  # library's authorized action paths.
  defp resource_capabilities(ref, resource, registry, l10n) do
    resource
    |> ResourceInfo.actions()
    |> Enum.sort_by(&to_string(&1.name))
    |> Enum.map(fn action ->
      {verb, derived} = classify(action.type)
      consequence = Registry.consequence(registry, resource, action.name, derived)
      capability(ref, verb, action.name, consequence, true, l10n)
    end)
  end

  # Record level: `Ash.can?/3` per action, with the scene's actor and
  # tenant, scoped to the actual record (the read runs through a query
  # filtered to its primary key; the update through a changeset built on
  # the record; generic actions are resource-scoped by nature). The
  # capability exists with its `authorized?` verdict — an unauthorized edit
  # is visible as unauthorized, never as available.
  defp record_capabilities(ref, resource, record, opts) do
    actor = opts[:actor]
    tenant = opts[:tenant]
    primary_key = ResourceInfo.primary_key(resource)

    can_read? = fn action_name ->
      query =
        resource
        |> Ash.Query.for_read(action_name, %{}, actor: actor, tenant: tenant)

      query =
        Enum.reduce(primary_key, query, fn pk_field, query ->
          Ash.Query.filter(query, ^Ash.Expr.ref(pk_field) == ^Map.get(record, pk_field))
        end)

      Ash.can?(query, actor) == true
    end

    can_update? = fn action_name ->
      record
      |> Ash.Changeset.for_update(action_name, %{}, actor: actor, tenant: tenant)
      |> Ash.can?(actor) == true
    end

    can_act? = fn action_name ->
      Ash.can?({resource, action_name}, actor, tenant: tenant) == true
    end

    read = primary(resource, :read)
    update = primary(resource, :update)
    registry = Keyword.fetch!(opts, :registry)
    consequence = &Registry.consequence(registry, resource, &1, &2)

    view_capability =
      read &&
        capability(
          ref,
          :view,
          read.name,
          consequence.(read.name, :read),
          can_read?.(read.name),
          l10n(opts)
        )

    edit_capability =
      update &&
        capability(
          ref,
          :edit,
          update.name,
          consequence.(update.name, :mutation),
          can_update?.(update.name),
          l10n(opts)
        )

    act_capabilities =
      resource
      |> ResourceInfo.actions()
      |> Enum.filter(&(&1.type == :action))
      |> Enum.sort_by(&to_string(&1.name))
      |> Enum.map(
        &capability(
          ref,
          :act,
          &1.name,
          consequence.(&1.name, :mutation),
          can_act?.(&1.name),
          l10n(opts)
        )
      )

    List.wrap(view_capability) ++ List.wrap(edit_capability) ++ act_capabilities
  end

  # The surface translator (`AshA2ui.L10n`) built from the same options an
  # A2UI surface takes; `nil` without one.
  defp l10n(opts), do: AshA2ui.L10n.new(opts)

  defp capability(ref, verb, action_name, consequence, authorized?, l10n) do
    confirmation = if consequence == :destructive, do: :required, else: :none

    %Capability{
      id: "#{ref.id}#capability:#{verb}:#{action_name}",
      verb: verb,
      action_name: to_string(action_name),
      object_ref: ref.id,
      label: Label.resolve(l10n, nil, action_name),
      consequence: consequence,
      confirmation: confirmation,
      authorized?: authorized?
    }
  end

  defp classify(:read), do: {:view, :read}
  defp classify(:create), do: {:create, :mutation}
  defp classify(:update), do: {:edit, :mutation}
  defp classify(:destroy), do: {:destroy, :destructive}
  defp classify(:action), do: {:act, :mutation}

  defp primary(resource, type) do
    case ResourceInfo.primary_action(resource, type) do
      %{name: name} -> %{name: name}
      nil -> nil
    end
  end

  # --- projections ------------------------------------------------------------

  # The host may replace the derived list -- `:diagram` and `:history` cannot be
  # read off a resource's actions, so only the host knows it ships a renderer.
  # Re-filtered through `declared/1` afterwards, so a host overriding this
  # cannot introduce a projection kind the experience compiler has no meaning
  # for; the override chooses among the vocabulary, it does not extend it.
  defp host_projections(registry, target, derived) do
    registry
    |> Registry.projections(target, derived)
    |> declared()
  end

  defp resource_projections(resource) do
    actions = ResourceInfo.actions(resource)

    projections = [:inspect, :browse]

    projections =
      if Enum.any?(actions, &(&1.type == :create)),
        do: projections ++ [:create],
        else: projections

    projections =
      if Enum.any?(actions, &(&1.type == :update)), do: projections ++ [:edit], else: projections

    declared(projections)
  end

  defp record_projections(capabilities) do
    projections = [:view]

    projections =
      if Enum.any?(capabilities, &(&1.verb == :edit and &1.authorized?)) do
        projections ++ [:edit]
      else
        projections
      end

    projections =
      if Enum.any?(capabilities, &(&1.verb == :act and &1.authorized?)) do
        projections ++ [:act]
      else
        projections
      end

    declared(projections)
  end

  # --- labels -----------------------------------------------------------------

  defp default_record_label(record) do
    Enum.find_value([:name, :title, :label], fn attr ->
      case Map.get(record, attr) do
        nil -> nil
        value -> to_string(value)
      end
    end) || "record"
  end
end
