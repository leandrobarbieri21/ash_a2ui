defmodule AshA2ui.Verifiers.VerifyPageLayout do
  @moduledoc """
  Verifies the record page's own layout (admin catalog 3.5):

    * a `page_header` reads a declared context; its `title`, its items'
      fields (`field`, `tone`, `icon_field`, `help_field`) and its buttons'
      `href` and `visible` are public attributes, calculations or aggregates
      of that context's resource; each `header_action` has exactly one of
      `run` (an update action of that resource) and `href`, under a name
      unique in the header;
    * a `section_nav` entry names a component that starts a `section` (the
      first component declaring it), under an anchor unique in the nav;
    * `lead` is only on `:detail` components outside any `section`, and
      `visible` only on lead ones, naming a public field of the context's
      resource;
    * an `alert` is only on a `:detail` component, its `message`,
      `link_href` and `link_label` public fields of the context's resource.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    entities = Verifier.get_entities(dsl_state, [:a2ui])

    contexts =
      for %AshA2ui.Context{} = context <- entities, into: %{}, do: {context.name, context}

    components = for %AshA2ui.Component{} = component <- entities, do: component

    with :ok <- verify_header(entities, contexts, module),
         :ok <- verify_nav(entities, components, module) do
      verify_components(components, contexts, module)
    end
  end

  # --- page_header ---------------------------------------------------------

  defp verify_header(entities, contexts, module) do
    case Enum.find(entities, &is_struct(&1, AshA2ui.PageHeader)) do
      nil -> :ok
      header -> header_error(header, contexts, module)
    end
  end

  defp header_error(header, contexts, module) do
    error = fn path, message -> error(module, [:a2ui, :page_header | path], message) end

    case contexts[header.context] do
      nil ->
        error.([:context], "page_header reads undeclared context #{inspect(header.context)}")

      %{resource: resource} ->
        if loaded?(resource) do
          header_fields_error(header, resource, error)
        else
          :ok
        end
    end
  end

  defp header_fields_error(header, resource, error) do
    known = known_field_names(resource)

    item_refs =
      for item <- header.tags ++ header.meta,
          {option, name} <- [
            field: item.field,
            tone: item.tone,
            icon_field: item.icon_field,
            help_field: item.help_field
          ],
          not is_nil(name),
          do: {[item.kind, item.field, option], name}

    action_refs =
      for action <- header.actions,
          {option, name} <- [href: action.href, visible: action.visible],
          not is_nil(name),
          do: {[:header_action, action.name, option], name}

    unknown =
      Enum.find([{[:title], header.title} | item_refs ++ action_refs], fn {_path, name} ->
        not MapSet.member?(known, name)
      end)

    case unknown do
      {path, name} ->
        error.(
          path,
          "#{inspect(name)} is not a public attribute, calculation or aggregate of " <>
            inspect(resource)
        )

      nil ->
        header_actions_error(header, resource, error)
    end
  end

  defp header_actions_error(header, resource, error) do
    duplicate =
      header.actions
      |> Enum.frequencies_by(& &1.name)
      |> Enum.find(fn {_name, count} -> count > 1 end)

    if duplicate do
      {name, _count} = duplicate
      error.([:header_action, name], "header_action #{inspect(name)} is declared twice")
    else
      Enum.find_value(header.actions, :ok, &header_action_error(&1, resource, error))
    end
  end

  defp header_action_error(%{run: nil, href: nil} = action, _resource, error) do
    error.(
      [:header_action, action.name],
      "header_action #{inspect(action.name)} needs `run` (an action) or `href` (a link)"
    )
  end

  defp header_action_error(%{run: run, href: href} = action, _resource, error)
       when not is_nil(run) and not is_nil(href) do
    error.(
      [:header_action, action.name],
      "header_action #{inspect(action.name)} declares both `run` and `href`; pick one"
    )
  end

  defp header_action_error(%{run: nil}, _resource, _error), do: nil

  defp header_action_error(%{run: run} = action, resource, error) do
    case Info.action(resource, run) do
      %{type: :update} ->
        nil

      _other ->
        error.(
          [:header_action, action.name, :run],
          "#{inspect(run)} is not an update action of #{inspect(resource)}"
        )
    end
  end

  # --- section_nav ---------------------------------------------------------

  defp verify_nav(entities, components, module) do
    case Enum.find(entities, &is_struct(&1, AshA2ui.SectionNav)) do
      nil -> :ok
      nav -> nav_error(nav, components, module)
    end
  end

  defp nav_error(nav, components, module) do
    starts = section_starts(components)

    duplicate =
      nav.items
      |> Enum.frequencies_by(& &1.anchor)
      |> Enum.find(fn {_anchor, count} -> count > 1 end)

    cond do
      duplicate ->
        {anchor, _count} = duplicate

        error(
          module,
          [:a2ui, :section_nav],
          "section_nav anchor #{inspect(anchor)} is used twice"
        )

      item = Enum.find(nav.items, &(&1.component not in starts)) ->
        error(
          module,
          [:a2ui, :section_nav, :nav_item, item.component],
          "nav_item #{inspect(item.component)} does not name the first component of a section " <>
            "(one of: #{Enum.map_join(starts, ", ", &inspect/1)})"
        )

      true ->
        :ok
    end
  end

  # The components each `section` starts with.
  defp section_starts(components) do
    components
    |> Enum.reject(&is_nil(&1.section))
    |> Enum.chunk_by(& &1.section)
    |> Enum.map(&AshA2ui.Component.key(hd(&1)))
  end

  # --- lead, visible, alert ------------------------------------------------

  defp verify_components(components, contexts, module) do
    Enum.find_value(components, :ok, &component_error(&1, contexts, module))
  end

  defp component_error(component, contexts, module) do
    key = AshA2ui.Component.key(component)
    error = fn option, message -> error(module, [:a2ui, :component, key, option], message) end

    case placement_error(component) do
      {option, message} -> error.(option, message)
      nil -> component_fields_error(component, contexts, error)
    end
  end

  defp placement_error(%{lead: true, name: name}) when name != :detail,
    do: {:lead, "only :detail components can be lead"}

  defp placement_error(%{lead: true, section: section}) when not is_nil(section),
    do: {:lead, "a lead component sits above the sections, so it takes no `section`"}

  defp placement_error(%{lead: false, visible: visible}) when not is_nil(visible),
    do: {:visible, "`visible` gates lead components only"}

  defp placement_error(%{alert: alert, name: name}) when not is_nil(alert) and name != :detail,
    do: {:alert, "only :detail components can be drawn as an alert"}

  defp placement_error(_component), do: nil

  defp component_fields_error(%{name: :detail} = component, contexts, error) do
    resource = contexts[component.context] && contexts[component.context].resource

    if resource && loaded?(resource) do
      known = known_field_names(resource)

      component
      |> component_refs()
      |> Enum.find_value(fn {option, name} ->
        unknown_field_error(known, resource, option, name, error)
      end)
    end
  end

  defp component_fields_error(_component, _contexts, _error), do: nil

  # The fields a component names beside its `fields`: its gate and its alert's.
  defp component_refs(component) do
    alert =
      case component.alert do
        nil ->
          []

        alert ->
          [message: alert.message, link_href: alert.link_href, link_label: alert.link_label]
      end

    Enum.reject([visible: component.visible] ++ alert, fn {_option, name} -> is_nil(name) end)
  end

  defp unknown_field_error(known, resource, option, name, error) do
    if not MapSet.member?(known, name) do
      error.(
        option,
        "#{inspect(name)} is not a public attribute, calculation or aggregate of " <>
          inspect(resource)
      )
    end
  end

  defp loaded?(resource), do: Code.ensure_loaded?(resource) and Info.resource?(resource)

  defp known_field_names(resource) do
    [
      Info.public_attributes(resource),
      Info.public_calculations(resource),
      Info.public_aggregates(resource)
    ]
    |> Enum.concat()
    |> MapSet.new(& &1.name)
  end

  defp error(module, path, message),
    do: {:error, DslError.exception(module: module, path: path, message: message)}
end
