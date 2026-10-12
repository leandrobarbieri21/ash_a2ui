defmodule AshA2ui.Verifiers.VerifyContexts do
  @moduledoc """
  Verifies at compile time that `context` entities — and everything that
  references them — are sound:

    * context names are unique, and don't collide with searchable
      relationship-select fields or `nested_form` arguments (they share the
      reserved `/options/<name>` data-model namespace),
    * every context `resource` is an Ash resource,
    * `option_label` / `option_value` / `option_sort` are public attributes
      of the context's resource; a resource with a composite primary key
      needs an explicit `option_value`,
    * `option_search` entries are public string-typed attributes (matched
      with a case-insensitive contains by the `"context_search"` action),
    * `depends_on` names a **previously declared** context (dependencies
      follow declaration order, which also rules out cycles), and comes
      paired with a `depends_on_path` whose steps are public relationships
      of the context's resource ending in a public attribute,
    * a table's `context_filter` references declared contexts and public
      attributes of the table's resource; `require_context` entries appear
      among the `context_filter` contexts (requiring a context that doesn't
      scope the table would be meaningless),
    * a table's `select_context` names a declared context whose resource is
      the table's resource (the selected row becomes the context's record),
    * every `:detail` component names a declared `context` and renders
      public attributes / calculations / aggregates of that context's
      resource,
    * context options stay on the components they belong to:
      `context_filter` / `require_context` / `select_context` are
      table-only, `context` is detail-only.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.Verifiers.VerifyRelationships
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @option_keys [:option_label, :option_value, :option_sort]

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    contexts = entities(dsl_state, AshA2ui.Context)
    components = entities(dsl_state, AshA2ui.Component)
    names = MapSet.new(contexts, & &1.name)

    with :ok <- verify_unique_names(contexts, module),
         :ok <- verify_options_namespace(contexts, dsl_state, module),
         :ok <- verify_contexts(contexts, module),
         :ok <- verify_tables(components, contexts, dsl_state, module) do
      verify_details(components, names, contexts, dsl_state, module)
    end
  end

  # --- context entities ---------------------------------------------------------

  defp verify_unique_names(contexts, module) do
    contexts
    |> Enum.frequencies_by(& &1.name)
    |> Enum.find(fn {_name, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {name, _count} ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :context, name],
           message: "duplicate context #{inspect(name)}: context names must be unique"
         )}
    end
  end

  # Contexts share the /options/<name> namespace with searchable
  # relationship selects (/options/<field>) and nested forms
  # (/options/<argument>).
  defp verify_options_namespace(contexts, dsl_state, module) do
    taken =
      MapSet.new(
        Enum.map(entities(dsl_state, AshA2ui.NestedForm), & &1.argument) ++
          for(%{option_search: [_ | _]} = f <- entities(dsl_state, AshA2ui.Field), do: f.name)
      )

    case Enum.find(contexts, &MapSet.member?(taken, &1.name)) do
      nil ->
        :ok

      context ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :context, context.name],
           message:
             "context #{inspect(context.name)} collides with a searchable select field or " <>
               "nested_form argument of the same name: they share the reserved " <>
               "/options/<name> data-model namespace — rename one of them"
         )}
    end
  end

  defp verify_contexts(contexts, module) do
    contexts
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {context, index}, :ok ->
      earlier = MapSet.new(Enum.take(contexts, index), & &1.name)

      case verify_context(context, earlier, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_context(context, earlier, module) do
    with :ok <- verify_resource(context, module),
         :ok <- verify_option_attributes(context, module),
         :ok <- verify_option_value_pk(context, module),
         :ok <-
           VerifyRelationships.verify_option_search(
             context.option_search,
             context.resource,
             module,
             [:a2ui, :context, context.name, :option_search],
             "context #{inspect(context.name)}"
           ) do
      verify_dependency(context, earlier, module)
    end
  end

  defp verify_resource(context, module) do
    if Code.ensure_loaded?(context.resource) and ResourceInfo.resource?(context.resource) do
      :ok
    else
      {:error,
       DslError.exception(
         module: module,
         path: [:a2ui, :context, context.name, :resource],
         message:
           "context #{inspect(context.name)} resource #{inspect(context.resource)} " <>
             "is not an Ash resource"
       )}
    end
  end

  defp verify_option_attributes(context, module) do
    @option_keys
    |> Enum.reject(&is_nil(Map.get(context, &1)))
    |> Enum.reduce_while(:ok, fn option, :ok ->
      name = Map.get(context, option)

      if public_attribute?(context.resource, name) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          DslError.exception(
            module: module,
            path: [:a2ui, :context, context.name, option],
            message:
              "#{option} #{inspect(name)} on context #{inspect(context.name)} must be a " <>
                "public attribute of #{inspect(context.resource)}"
          )}}
      end
    end)
  end

  defp verify_option_value_pk(%{option_value: nil} = context, module) do
    case ResourceInfo.primary_key(context.resource) do
      [_single] ->
        :ok

      composite ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :context, context.name, :option_value],
           message:
             "context #{inspect(context.name)} selects #{inspect(context.resource)}, which " <>
               "has a composite primary key #{inspect(composite)} — set option_value explicitly"
         )}
    end
  end

  defp verify_option_value_pk(_context, _module), do: :ok

  defp verify_dependency(%{depends_on: nil, depends_on_path: nil}, _earlier, _module), do: :ok

  defp verify_dependency(%{depends_on: nil} = context, _earlier, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :context, context.name, :depends_on_path],
       message:
         "context #{inspect(context.name)} sets depends_on_path without depends_on — " <>
           "they come as a pair"
     )}
  end

  defp verify_dependency(%{depends_on_path: nil} = context, _earlier, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :context, context.name, :depends_on],
       message:
         "context #{inspect(context.name)} sets depends_on without depends_on_path — " <>
           "declare the relationship path whose terminal attribute must equal the parent's " <>
           "selected value (e.g. [:memberships, :user_id])"
     )}
  end

  defp verify_dependency(context, earlier, module) do
    cond do
      not MapSet.member?(earlier, context.depends_on) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :context, context.name, :depends_on],
           message:
             "context #{inspect(context.name)} depends on #{inspect(context.depends_on)}, " <>
               "which is not a previously declared context — contexts may only depend on " <>
               "contexts declared before them (this also rules out dependency cycles)"
         )}

      context.depends_on_path == [] ->
        {:error, dependency_path_error(context, module, "must have at least one step")}

      true ->
        verify_dependency_path(context, module)
    end
  end

  defp verify_dependency_path(context, module) do
    {relationship_steps, [terminal]} = Enum.split(context.depends_on_path, -1)

    case walk_relationships(relationship_steps, context.resource) do
      {:error, step} ->
        {:error,
         dependency_path_error(
           context,
           module,
           "step #{inspect(step)} is not a public relationship of #{inspect(context.resource)}"
         )}

      {:ok, destination} ->
        if public_attribute?(destination, terminal) do
          :ok
        else
          {:error,
           dependency_path_error(
             context,
             module,
             "terminal step #{inspect(terminal)} is not a public attribute of " <>
               inspect(destination)
           )}
        end
    end
  end

  defp dependency_path_error(context, module, detail) do
    DslError.exception(
      module: module,
      path: [:a2ui, :context, context.name, :depends_on_path],
      message:
        "depends_on_path #{inspect(context.depends_on_path)} on context " <>
          "#{inspect(context.name)} is invalid: #{detail}. Every step but the last must be " <>
          "a public relationship, and the last a public attribute of the final destination."
    )
  end

  # --- table context options ----------------------------------------------------

  defp verify_tables(components, contexts, dsl_state, module) do
    target = target_resource(dsl_state)
    by_name = Map.new(contexts, &{&1.name, &1})

    Enum.reduce_while(components, :ok, fn component, :ok ->
      case verify_component_context_options(component, by_name, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component_context_options(%{name: :table} = component, by_name, target, module) do
    # A related table (`resource`) is scoped and selected against its own resource.
    target =
      if target, do: AshA2ui.Component.resource(component, target), else: component.resource

    key = AshA2ui.Component.key(component)

    with :ok <- verify_context_filter(component, key, by_name, target, module),
         :ok <- verify_require_context(component, key, module) do
      verify_select_context(component, key, by_name, target, module)
    end
  end

  defp verify_component_context_options(%{name: :detail}, _by_name, _target, _module), do: :ok

  defp verify_component_context_options(component, _by_name, _target, module) do
    case Enum.find(
           [:context_filter, :require_context, :select_context, :context],
           &(Map.get(component, &1) not in [nil, []])
         ) do
      nil ->
        :ok

      option ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, component.name, option],
           message:
             "#{option} is not supported on #{inspect(component.name)} components: " <>
               "context_filter/require_context/select_context are table-only, " <>
               "context is detail-only"
         )}
    end
  end

  defp verify_context_filter(component, key, by_name, target, module) do
    Enum.reduce_while(component.context_filter, :ok, fn {attribute, context_name}, :ok ->
      cond do
        not Map.has_key?(by_name, context_name) ->
          {:halt,
           {:error,
            context_filter_error(
              key,
              module,
              "#{inspect(context_name)} is not a declared context"
            )}}

        not is_nil(target) and not public_attribute?(target, attribute) ->
          {:halt,
           {:error,
            context_filter_error(
              key,
              module,
              "#{inspect(attribute)} is not a public attribute of #{inspect(target)}"
            )}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp context_filter_error(key, module, detail) do
    DslError.exception(
      module: module,
      path: [:a2ui, :component, key, :context_filter],
      message:
        "context_filter on table #{inspect(key)} is invalid: #{detail}. Every entry maps a " <>
          "public attribute of the table's resource to a declared context " <>
          "(`context_filter user_id: :user`)."
    )
  end

  defp verify_require_context(component, key, module) do
    scoped = MapSet.new(component.context_filter, fn {_attribute, name} -> name end)

    case Enum.find(component.require_context, &(not MapSet.member?(scoped, &1))) do
      nil ->
        :ok

      name ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :require_context],
           message:
             "require_context entry #{inspect(name)} on table #{inspect(key)} does not " <>
               "appear in the table's context_filter — requiring a context that doesn't " <>
               "scope the table would be meaningless"
         )}
    end
  end

  defp verify_select_context(%{select_context: nil}, _key, _by_name, _target, _module), do: :ok

  defp verify_select_context(component, key, by_name, target, module) do
    cond do
      not Map.has_key?(by_name, component.select_context) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :select_context],
           message:
             "select_context #{inspect(component.select_context)} on table #{inspect(key)} " <>
               "is not a declared context"
         )}

      not is_nil(target) and by_name[component.select_context].resource != target ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :select_context],
           message:
             "select_context #{inspect(component.select_context)} on table #{inspect(key)} " <>
               "must name a context over the table's own resource #{inspect(target)} — " <>
               "the selected row becomes the context's record"
         )}

      true ->
        :ok
    end
  end

  # --- detail components ---------------------------------------------------------

  defp verify_details(components, names, contexts, dsl_state, module) do
    by_name = Map.new(contexts, &{&1.name, &1})

    # Declared projection fields (source / link / links) are verified
    # against the SURFACE's resource by VerifyRelationships, so a detail may
    # render them when its context selects that same resource.
    projections = %{
      target: target_resource(dsl_state),
      names:
        dsl_state
        |> entities(AshA2ui.Field)
        |> Enum.filter(&(&1.source || &1.link || &1.links))
        |> MapSet.new(& &1.name)
    }

    components
    |> Enum.filter(&(&1.name == :detail))
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_detail(component, names, by_name, projections, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_detail(component, names, by_name, projections, module) do
    key = AshA2ui.Component.key(component)

    cond do
      is_nil(component.context) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :context],
           message:
             ":detail components must set context: the declared context whose selected " <>
               "record they render"
         )}

      not MapSet.member?(names, component.context) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :context],
           message:
             "detail component #{inspect(key)} references undeclared context " <>
               inspect(component.context)
         )}

      true ->
        verify_detail_fields(component, key, by_name[component.context], projections, module)
    end
  end

  defp verify_detail_fields(component, key, context, projections, module) do
    resource = context.resource

    projection? = fn name ->
      MapSet.member?(projections.names, name) and not is_nil(projections.target) and
        resource == projections.target
    end

    case Enum.find(
           component.fields || [],
           &(not (detail_renderable?(resource, &1) or projection?.(&1)))
         ) do
      nil ->
        :ok

      field ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :fields],
           message:
             "detail component #{inspect(key)} renders #{inspect(field)}, which is not a " <>
               "public attribute, calculation, or aggregate of the context's resource " <>
               inspect(resource) <>
               " (declared source/link/links fields are renderable only by details " <>
               "whose context selects the surface's own resource)"
         )}
    end
  end

  defp detail_renderable?(resource, name) do
    public_attribute?(resource, name) or
      match?(%{public?: true}, ResourceInfo.calculation(resource, name)) or
      match?(%{public?: true}, ResourceInfo.aggregate(resource, name))
  end

  # --- shared helpers ------------------------------------------------------------

  defp walk_relationships(steps, resource) do
    Enum.reduce_while(steps, {:ok, resource}, fn step, {:ok, current} ->
      case ResourceInfo.relationship(current, step) do
        %{public?: true, destination: destination} -> {:cont, {:ok, destination}}
        _private_or_missing -> {:halt, {:error, step}}
      end
    end)
  end

  defp public_attribute?(resource, name) do
    match?(%{public?: true}, ResourceInfo.attribute(resource, name))
  end

  defp entities(dsl_state, struct_module) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, struct_module))
  end

  defp target_resource(dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        module = Verifier.get_persisted(dsl_state, :module)

        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: module

      resource ->
        if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource), do: resource
    end
  end
end
