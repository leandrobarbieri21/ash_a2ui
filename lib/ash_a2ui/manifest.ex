defmodule AshA2ui.Manifest do
  @moduledoc """
  A per-surface description of what a surface's tables and row actions are,
  as plain data, for tools that exercise a surface without knowing its
  domain: a browser test generator, an accessibility audit, a coverage
  ledger.

      AshA2ui.Manifest.for_surface(MyApp.Tickets.Ticket, catalog: :admin_v1)
      #=> %{version: 1, surface_id: "tickets", tables: [...], row_actions: [...], ...}

  The manifest is derived from the same resolved view the encoder renders
  from (`AshA2ui.ResolvedView.resolve/2`), with the same label functions, so
  it never drifts from the payload: a row action's `label` is the text of
  its rendered button, translated with the same options, and a prompt's
  `confirm_label` is the text of its rendered confirm control. Building a
  manifest reads no records and needs no actor.

  ## Options

  The options of `AshA2ui.Info.build_surface/2` that change what renders:
  `:catalog` (`:basic` or `:admin_v1`, defaulting to the configured catalog),
  `:locale`, `:gettext_backend`, `:gettext_fn`,
  `:metadata_domain`. Pass the ones the transport passes, so the labels are
  the ones the reader sees. Other options are accepted and ignored.

  ## Shape

  Version 2 (`version/0`; version 1 also carried the surface's A2UI protocol
  version, which is now always 1.0). Names of Ash things (actions, attributes,
  arguments, presets) are atoms; ids, labels and selectors are strings.

      %{
        version: 2,
        surface_id: "referrals",
        module: MyApp.Referral,           # the resource or standalone UI module
        resource: MyApp.Referral,
        title: "Referral",                # the surface heading
        catalog: :admin_v1,
        tables: [table],
        row_actions: [row_action],
        attributes: %{row_id: "data-a2ui-row-id", action: "data-a2ui-action",
                      component: "data-a2ui-id"}
      }

  A **table** (one per `:table` component, in declaration order):

      %{
        id: "table",                      # the component name; "table" when unnamed
        label: "Referral",                # the grid's accessible name (admin catalog)
        resource: MyApp.Referral,         # the resource the table reads
        read_action: :read,               # the read without a preset
        display: :list,                   # :list | :rows | :cards | :board | :calendar | :timeline | :matrix
        sectioned: false,                 # true: one rendered table per section record
        component_id: "data_grid",        # the element carrying the rows (see Selectors)
        records_path: "/records",
        columns: [%{name: :code, label: "Code"}],
        query: %{name: :default, default_preset: :active, preset_picker_label: "View",
                 page_size: 5, default_sort: [%{field: :code, direction: :asc}]} | nil,
        presets: [%{name: :active, label: "Active", read_action: :read,
                    filter: [%{field: :deleted_at, op: :is_nil, value: nil}]}],
        context_filter: [%{field: :user_id, context: :user}],
        require_context: [:user],
        row_actions: ["table.approve"]    # ids of this table's row actions
      }

  A table's rows are the records `read_action` returns for the actor (as
  `preset.read_action` with `preset.filter` ANDed on when a preset is
  selected, the query's `default_preset` when none is), scoped by any
  selected `context_filter` contexts; a table with `require_context` reads
  nothing until one of them is selected. `filter_input/1` turns a preset's
  `filter` into Ash filter input.

  A **row action** (one per declared row action per table, in order):

      %{
        id: "table.decline",              # "<table id>.<action>": stable across label changes
        table: "table",
        label: "Decline",                 # the rendered button's text and accessible name
        resource: MyApp.Referral,
        ash_action: :decline,
        action_type: :update,             # :create | :read | :update | :destroy | :action
        via: false,                       # true: dispatched through a host function (`via`)
        visible_when: [%{field: :status, op: :in, value: [:pending, :approved]}],
        prompt_title: "Decline referral", # nil without prompt_fields
        prompt_fields: [%{name: :notes, label: "Notes", type: Ash.Type.String,
                          widget: :text_field, required: true, options: nil}],
        confirm: :prompt,                 # :prompt | :destructive | nil
        confirm_label: "Confirm",         # the confirm control's text, nil without one
        selector: ~s([data-a2ui-action="decline"])
      }

  `visible_when` lists the action's conditions, ANDed: `op` is `:eq`,
  `:in` (`value` is a list) or `:is_nil`. `visible?/2` evaluates them
  against a record or a row map; `filter_input/1` turns them into Ash
  filter input selecting the rows the action is offered on. An action
  whose conditions match no row renders no button anywhere.

  A **prompt field**'s `widget` is the input the prompt renders
  (`:text_field`, `:choice_picker`, `:check_box`, `:date_time_input`, or
  `:select` for a relationship); `options` lists `%{value:, label:}` for a
  `:choice_picker` and is `nil` otherwise (a `:select` loads its options
  for the actor at runtime, from `relationship`). `required` is true when
  the action refuses an empty value.

  `confirm` says what happens after the row button is clicked: `:prompt`
  opens the prompt, whose `confirm_label` control invokes the action;
  `:destructive` (the admin catalog, a destroy action without a prompt)
  opens a confirmation dialog whose `confirm_label` control does; `nil`
  invokes the action on click.

  ## Selectors

  The AshA2ui catalogs mark what a test needs to find without relying on
  text (`attributes` in the manifest):

    * `data-a2ui-id="<component id>"` on the element carrying a table's
      rows: the admin catalog's `dataGrid` element, or the basic catalog's
      record row content (a `Row`), or the card body of a table with a
      `row_layout` (a `Column`). A table's
      `component_id` names it; it is `nil` where the id is not static
      (sectioned tables) or the display is not a list.
    * `data-a2ui-row-id="<record id>"` on each rendered row: the admin
      grid's `<tr>` and its narrow-layout card `<li>`, or the basic record
      row content element (which carries `data-a2ui-id` too).
    * `data-a2ui-action="<action>"` on each row action control: a wrapper
      around the admin grid's button (so a host-drawn button is covered),
      or the basic catalog's button element. A row action's `selector`
      matches it.

  The admin grid draws its rows in its own shadow root, inside a
  `<table>` named by the table's `label`: `tr` and `[role=row]` find them
  there, but not on the basic catalog, whose rows are Cards with no row
  semantics, nor on the admin grid's narrow (card) layout.
  """

  import AshA2ui.Gettext, only: [msg: 1]

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.Encoder
  alias AshA2ui.Experience
  alias AshA2ui.Gettext.Metadata
  alias AshA2ui.L10n
  alias AshA2ui.Label
  alias AshA2ui.ResolvedView

  @version 2

  @attributes %{
    row_id: "data-a2ui-row-id",
    action: "data-a2ui-action",
    component: "data-a2ui-id"
  }

  @resolve_opts [
    :catalog,
    :locale,
    :gettext_backend,
    :gettext_fn,
    :metadata_domain
  ]

  @type condition :: %{field: atom, op: :eq | :in | :is_nil, value: term}

  @type prompt_field :: %{
          name: atom,
          label: String.t(),
          type: module,
          widget: :text_field | :choice_picker | :check_box | :date_time_input | :select,
          required: boolean,
          options: [%{value: String.t(), label: String.t()}] | nil,
          relationship: %{destination: module, option_value: atom, option_label: atom} | nil
        }

  @type row_action :: %{
          id: String.t(),
          table: String.t(),
          label: String.t(),
          resource: module,
          ash_action: atom,
          action_type: :create | :read | :update | :destroy | :action,
          via: boolean,
          visible_when: [condition],
          prompt_title: String.t() | nil,
          prompt_fields: [prompt_field],
          confirm: :prompt | :destructive | nil,
          confirm_label: String.t() | nil,
          selector: String.t()
        }

  @type preset :: %{
          name: atom,
          label: String.t(),
          read_action: atom,
          filter: [condition]
        }

  @type table :: %{
          id: String.t(),
          label: String.t(),
          resource: module,
          read_action: atom,
          display: atom,
          sectioned: boolean,
          component_id: String.t() | nil,
          records_path: String.t(),
          columns: [%{name: atom, label: String.t()}],
          query: map | nil,
          presets: [preset],
          context_filter: [%{field: atom, context: atom}],
          require_context: [atom],
          row_actions: [String.t()]
        }

  @type t :: %{
          version: pos_integer,
          surface_id: String.t(),
          module: module,
          resource: module,
          title: String.t(),
          catalog: :basic | :admin_v1,
          tables: [table],
          row_actions: [row_action],
          attributes: %{row_id: String.t(), action: String.t(), component: String.t()}
        }

  @doc "The manifest format version, bumped on any incompatible change."
  @spec version() :: pos_integer
  def version, do: @version

  @doc """
  The manifest of one surface: a resource using the `AshA2ui` extension or
  an `AshA2ui.Standalone` UI module. See the moduledoc for the shape and
  the options.
  """
  @spec for_surface(module, keyword) :: t()
  def for_surface(resource_or_ui_module, opts \\ []) do
    view = ResolvedView.resolve(resource_or_ui_module, Keyword.take(opts, @resolve_opts))
    tables = Enum.map(view.tables, &table(view, &1))

    %{
      version: @version,
      surface_id: view.surface_id,
      module: resource_or_ui_module,
      resource: view.resource,
      title: Experience.surface_title(view),
      catalog: if(Experience.admin?(view), do: :admin_v1, else: :basic),
      tables: tables,
      row_actions: Enum.flat_map(view.tables, &row_actions(view, &1)),
      attributes: @attributes
    }
  end

  @doc """
  The manifests of several surfaces, keyed by surface id. Raises when two
  of them declare the same surface id.
  """
  @spec for_surfaces([module], keyword) :: %{String.t() => t()}
  def for_surfaces(modules, opts \\ []) do
    Enum.reduce(modules, %{}, fn module, acc ->
      manifest = for_surface(module, opts)

      if existing = acc[manifest.surface_id] do
        raise ArgumentError,
              "#{inspect(module)} and #{inspect(existing.module)} both declare the surface " <>
                "id #{inspect(manifest.surface_id)}"
      end

      Map.put(acc, manifest.surface_id, manifest)
    end)
  end

  @doc """
  Every module of `otp_app` that declares an A2UI surface: resources using
  the `AshA2ui` extension and `AshA2ui.Standalone` UI modules, sorted by
  module name. Pass the result to `for_surfaces/2`.
  """
  @spec surfaces(atom) :: [module]
  def surfaces(otp_app) do
    # The surfaces the metadata extractor walks, less the canvas registries
    # (which declare no `a2ui` section).
    otp_app
    |> Metadata.surfaces()
    |> Enum.filter(&function_exported?(&1, :spark_dsl_config, 0))
  end

  @doc """
  Whether `row` satisfies `conditions` (or a row action's `visible_when`):
  `row` is an Ash record, or a map with atom or string keys such as a row of
  the surface's data model. An empty list always matches.

  Values compare as the encoder writes them, so `:pending`, `"pending"` and
  a matching enum all match `:pending`; a data-model row's raw value under
  `"_values"` is used over its display label. Given a row action and a
  data-model row that carries the server's own verdict
  (`"_visible_<action>"`), that verdict is the answer. A data-model row
  holds only the rendered fields: a condition on a field it lacks sees
  `nil`, so prefer a record when the conditions name unrendered fields.
  """
  @spec visible?(row_action | %{visible_when: [condition]} | [condition], map) :: boolean
  def visible?(%{ash_action: name, visible_when: conditions}, row) when not is_struct(row) do
    case Map.fetch(row, "_visible_#{name}") do
      {:ok, slot} when is_list(slot) -> slot != []
      _no_verdict -> visible?(conditions, row)
    end
  end

  def visible?(%{visible_when: conditions}, row), do: visible?(conditions, row)

  def visible?(conditions, row) when is_list(conditions) do
    Enum.all?(conditions, &condition_matches?(&1, row))
  end

  @doc """
  Ash filter input (for `Ash.Query.filter_input/2`) selecting the records
  that satisfy `conditions` (or a row action's `visible_when`, or a
  preset's `filter`). An empty list gives `%{}`, matching every record.

      iex> AshA2ui.Manifest.filter_input([
      ...>   %{field: :status, op: :in, value: [:pending, :approved]},
      ...>   %{field: :deleted_at, op: :is_nil, value: nil}
      ...> ])
      %{"and" => [%{"status" => %{"in" => [:pending, :approved]}}, %{"deleted_at" => %{"is_nil" => true}}]}
  """
  @spec filter_input(%{visible_when: [condition]} | %{filter: [condition]} | [condition]) :: map
  def filter_input(%{visible_when: conditions}), do: filter_input(conditions)
  def filter_input(%{filter: conditions}), do: filter_input(conditions)
  def filter_input([]), do: %{}

  def filter_input(conditions) when is_list(conditions) do
    %{"and" => Enum.map(conditions, &condition_input/1)}
  end

  # --- tables -----------------------------------------------------------------

  defp table(view, table) do
    %{
      id: to_string(table.name),
      label: Experience.collection_label(view, table),
      resource: table.resource,
      read_action: table.read_action,
      display: table.component.display,
      sectioned: not is_nil(table.sections),
      component_id: component_id(view, table),
      records_path: table.records_path,
      columns: columns(view, table),
      query: query_controls(view, table.query),
      presets: presets(view, table),
      context_filter:
        Enum.map(table.context_filter, fn {field, context} ->
          %{field: field, context: context}
        end),
      require_context: table.require_context,
      row_actions: Enum.map(table.row_actions, &row_action_id(table, &1))
    }
  end

  # The element the catalog marks with `data-a2ui-id` for this table: only
  # on list tables whose component ids are static (a sectioned table gets a
  # runtime suffix per section).
  defp component_id(view, table) do
    cond do
      table.sections || table.component.display not in [:list, :rows, :cards] -> nil
      Experience.admin?(view) -> "data_grid#{table_suffix(view, table)}"
      table.component.row_layout -> "record_row#{table_suffix(view, table)}_body"
      true -> "record_row#{table_suffix(view, table)}_content"
    end
  end

  defp table_suffix(view, table) do
    if ResolvedView.multi_table?(view), do: "_#{table.name}", else: ""
  end

  defp columns(view, table) do
    fields =
      if Experience.admin?(view),
        do: Encoder.grid_column_fields(table),
        else: table.component.fields

    Enum.map(fields, &%{name: &1, label: view.fields[&1].label})
  end

  defp query_controls(_view, nil), do: nil

  defp query_controls(view, query) do
    %{
      name: query.name,
      default_preset: query.default_preset,
      preset_picker_label:
        if(query.presets != [] and query.preset_picker != false,
          do: L10n.t(view.l10n, msg("View"))
        ),
      page_size: query.page_size,
      default_sort:
        Enum.map(query.default_sort, fn {field, direction} ->
          %{field: field, direction: direction}
        end)
    }
  end

  defp presets(_view, %{query: nil}), do: []

  defp presets(view, table) do
    Enum.map(table.query.presets, fn preset ->
      %{
        name: preset.name,
        label: Label.resolve(view.l10n, nil, preset.name),
        read_action: preset.read_action || table.read_action,
        filter: conditions(preset.filter || [])
      }
    end)
  end

  # --- row actions --------------------------------------------------------------

  defp row_actions(view, table) do
    Enum.map(table.row_actions, &row_action(view, table, &1))
  end

  defp row_action(view, table, name) do
    setting = Map.get(view.actions, name)
    ash_action = ResourceInfo.action(table.resource, name)
    prompt? = match?(%{prompt_fields: [_ | _]}, setting)
    {confirm, confirm_label} = confirm(view, ash_action, prompt?, name)

    %{
      id: row_action_id(table, name),
      table: to_string(table.name),
      label: ResolvedView.action_label(view, name),
      resource: table.resource,
      ash_action: name,
      action_type: ash_action.type,
      via: match?(%{via: via} when not is_nil(via), setting),
      visible_when: conditions((setting && setting.visible_when) || []),
      prompt_title: if(prompt?, do: prompt_title(view, name, setting)),
      prompt_fields: prompt_fields(view, ash_action, name),
      confirm: confirm,
      confirm_label: confirm_label,
      selector: ~s([data-a2ui-action="#{name}"])
    }
  end

  defp row_action_id(table, name), do: "#{table.name}.#{name}"

  # The prompt's confirm button (both catalogs, the encoder's "Confirm"); the
  # admin grid's destructive ConfirmDialog, whose confirm button reads the
  # action's label (ash_admin_catalog.js syncConfirmDialog); else none.
  defp confirm(view, _ash_action, true, _name), do: {:prompt, L10n.t(view.l10n, msg("Confirm"))}

  defp confirm(view, %Ash.Resource.Actions.Destroy{}, false, name) do
    if Experience.admin?(view),
      do: {:destructive, ResolvedView.action_label(view, name)},
      else: {nil, nil}
  end

  defp confirm(_view, _ash_action, false, _name), do: {nil, nil}

  defp prompt_title(view, name, setting) do
    case setting.prompt_title do
      nil -> ResolvedView.action_label(view, name)
      title -> Label.translate(view.l10n, title)
    end
  end

  defp prompt_fields(view, ash_action, name) do
    view.prompts
    |> Map.get(name, [])
    |> Enum.map(fn field ->
      {type, required} = input_type(view.resource, ash_action, field.name)

      %{
        name: field.name,
        label: field.label,
        type: type,
        widget: field.widget,
        required: required,
        options: options(field),
        relationship: relationship(field)
      }
    end)
  end

  defp options(%{widget: :choice_picker, choices: choices}) do
    Enum.map(choices, fn {value, label} -> %{value: to_string(value), label: label} end)
  end

  defp options(_field), do: nil

  defp relationship(%{widget: :select, select: %{} = select}) do
    %{
      destination: select.destination,
      option_value: select.option_value,
      option_label: select.option_label
    }
  end

  defp relationship(_field), do: nil

  # The Ash type of a prompt field, and whether the action refuses it empty:
  # an argument with `allow_nil? false`, or an accepted attribute the action
  # requires (`require_attributes`, or a non-nil attribute without a default
  # on a create).
  defp input_type(resource, ash_action, name) do
    case Enum.find(ash_action.arguments, &(&1.name == name)) do
      %{type: type, allow_nil?: allow_nil?} ->
        {Ash.Type.get_type(type), not allow_nil?}

      nil ->
        attribute = ResourceInfo.attribute(resource, name)
        {Ash.Type.get_type(attribute.type), attribute_required?(ash_action, attribute)}
    end
  end

  defp attribute_required?(ash_action, attribute) do
    allow_nil_input = Map.get(ash_action, :allow_nil_input, [])

    attribute.name in Map.get(ash_action, :require_attributes, []) or
      (ash_action.type == :create and not attribute.allow_nil? and is_nil(attribute.default) and
         attribute.name not in allow_nil_input)
  end

  # --- conditions ---------------------------------------------------------------

  defp conditions(keyword) do
    Enum.map(keyword, fn
      {field, nil} -> %{field: field, op: :is_nil, value: nil}
      {field, values} when is_list(values) -> %{field: field, op: :in, value: values}
      {field, value} -> %{field: field, op: :eq, value: value}
    end)
  end

  defp condition_input(%{field: field, op: :is_nil}),
    do: %{to_string(field) => %{"is_nil" => true}}

  defp condition_input(%{field: field, op: :in, value: values}),
    do: %{to_string(field) => %{"in" => values}}

  defp condition_input(%{field: field, op: :eq, value: value}),
    do: %{to_string(field) => %{"eq" => value}}

  defp condition_matches?(%{field: field, op: op, value: expected}, row) do
    actual = row_value(row, field)

    case op do
      :is_nil -> is_nil(actual)
      :in -> Enum.any?(expected, &same?(&1, actual))
      :eq -> same?(expected, actual)
    end
  end

  defp row_value(row, field) when is_struct(row) do
    value = Map.get(row, field)
    if is_struct(value, Ash.NotLoaded), do: nil, else: value
  end

  # A data-model row: a field with declared choices renders as its label,
  # its value kept under "_values".
  defp row_value(row, field) do
    key = to_string(field)

    case row do
      %{"_values" => %{^key => value}} -> value
      %{^field => value} -> value
      %{^key => value} -> value
      _missing -> nil
    end
  end

  defp same?(expected, actual) when is_nil(expected) or is_nil(actual), do: expected == actual

  defp same?(expected, actual),
    do: expected == actual or comparable(expected) == comparable(actual)

  defp comparable(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp comparable(value) when is_binary(value), do: value
  defp comparable(%Ash.CiString{} = value), do: Ash.CiString.value(value)
  defp comparable(value), do: if(String.Chars.impl_for(value), do: to_string(value), else: value)
end
