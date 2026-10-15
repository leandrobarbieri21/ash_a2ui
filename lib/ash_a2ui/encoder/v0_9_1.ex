# The module name mirrors the spec version (v0.9.1) and is part of the frozen
# cross-track contract, so the PascalCase naming check is disabled here.
# credo:disable-for-this-file Credo.Check.Readability.ModuleNames
defmodule AshA2ui.Encoder.V0_9_1 do
  @moduledoc """
  A2UI v0.9.1 encoder: emits the protocol envelope and basic-catalog component
  composition. Tables are `List` + `Row` composition (the basic catalog has no
  Table component); all keys are string camelCase and children are always ID
  references.

  ## Component tree

  The root is a `Column` with id `"root"`. Its children, in order (each only
  present when the corresponding DSL component is declared):

    * `table_heading` — `Text` (h2) with the humanized resource name
    * `query_controls` — only when the table declares a `query`: a `Row` of a
      search `TextField` (`query_search_input`, bound to `/query/search`,
      omitted when the query has no `search_fields`), a preset `ChoicePicker`
      (`query_preset_picker`, bound to `/query/preset`, only when the query
      declares presets — options are the preset names, preceded by an
      `"All"`/`""` option unless a `default_preset` is declared), one
      `ChoicePicker` per declared filter (`query_filter_<name>`, bound to
      `/query/filters/<name>`, with an `"All"` option first) and a
      `query_apply_button` (event `query`, context
      `{"query": {"path": "/query"}, "page": 1}` — the page-1 reset)
    * `records_list` — `List` whose children are a template
      `{"componentId": "record_row", "path": "/records"}`; `record_row` is a
      `Card` wrapping `record_row_content`, a `Row` of per-field labeled
      cells — each `table_cell_<field>` is a `Row` of a caption `Text`
      (`table_cell_<field>_label`, the humanized field name) and a value
      `Text` (`table_cell_<field>_value`, bound to the template-relative
      path `<field>`, `format: :date` rendered through `formatDate`) —
      one `Button` per row action
      (`row_action_<action>_button`: event `invoke`, context
      `{"action": "<name>", "recordId": {"path": "id"}}`) and — only on
      surfaces with a `:form` component — a `row_select_button` (event
      `select_row`, context `{"recordId": {"path": "id"}}`; `select_row`
      populates `/form`, so formless surfaces omit the button rather than
      render a control with no visible effect). Tables declaring a `row_layout`
      swap the card's content for a header + metadata-grid structure —
      see the Layout topic and `card_row_components/4`

  ## Row-action prompts (prompt_fields)

  A row action whose `action` entity declares `prompt_fields` renders as a
  `Modal` (`row_action_<action>_modal`) instead of a bare button: the row
  slot holds the Modal, whose `trigger` is the usual
  `row_action_<action>_button` — now dispatching event `prompt` with context
  `{"action": "<name>", "recordId": {"path": "id"}, "component": "<table>"}`
  so the server pre-fills `/prompt/values/<action>` — and whose `content` is
  `row_action_<action>_prompt`, a `Column` of a title `Text`, one `TextField`
  per prompt field (bound to the absolute `/prompt/values/<action>/<field>`
  path; template-relative paths cannot reach the shared prompt state), a
  per-field error `Text` (bound to `/errors/<field>`) and a confirm `Button`
  (`row_action_<action>_confirm_button`: event `invoke`, context carrying
  `"values": {"path": "/prompt/values/<action>"}` alongside the usual
  `"action"`/`"recordId"`/`"component"`). Modal open/close is client-side
  (the v0.9.1 protocol has no server-controlled open state); the server
  contract is only the `prompt` pre-fill and the `invoke` values.

  ## Conditional row actions (visible_when)

  A row action whose `action` entity declares `visible_when` conditions is
  wrapped in `row_action_<action>_slot` — a `List` templated over the
  row-relative `_visible_<action>` path (`[%{"id" => id}]` when visible,
  `[]` when hidden, computed server-side; see `AshA2ui.Conditions`).
  Renderers supporting nested templates render zero or one button per row;
  rows also carry `"_actions"` (the visible action names) for renderers that
  don't. Rendering is best-effort — enforcement lives in
  `AshA2ui.ActionHandler`, which re-evaluates the conditions on every
  invoke.
    * `query_pagination` — only when the table declares a `query`: a `Row` of
      `query_prev_button` / `query_page_text` (bound to `/query/page`) /
      `query_next_button`; the buttons carry event `query` with context
      `{"query": {"path": "/query"}, "pageDelta": -1 | 1}`
    * `form` — `Column` of `form_input_<field>` + `form_error_<field>` pairs
      and a `form_submit_button` (event `submit_form`, context
      `{"values": {"path": "/form"}, "recordId": {"path": "/form/id"}}`).
      Inputs use the field's resolved widget (`TextField` / `CheckBox` /
      `ChoicePicker` / `DateTimeInput`), bind `value` to `/form/<field>`, and
      errors are `Text` (caption) bound to `/errors/<field>`. Relationship
      selects render as `ChoicePicker`s whose loaded options are emitted
      inline (the v0.9.1 basic catalog requires a literal options array) and
      mirrored at `/options/<field>` in the data model
    * `status_text` — `Text` bound to `/ui/status`
    * `action_result_panel` — `Column` wrapping `action_result_text`, a
      `Text` bound to `/ui/action_result_text` (the display text of
      map-returning generic action results; empty until an action produces
      one)

  ## Bulk actions

  A table declaring `bulk_actions` gains a `CheckBox`
  (`record_row<sfx>_selected`, bound to the row-relative `_selected` path)
  as the first child of its row (the card header under a `row_layout`), and
  a toolbar Row `bulk<sfx>_toolbar` right above `records_list<sfx>`: one
  `bulk<sfx>_<action>_button` per bulk action (event `bulk_invoke`, context
  `{"action", "component", "records": {"path": <records path>}}` plus the
  usual query/contexts bindings), then `bulk<sfx>_select_page_button` and
  `bulk<sfx>_clear_button` (event `bulk_select` with `"selected"` true /
  false). Its rows carry `"_selected": false` and the data model a
  `"bulk"` entry per such table (see `AshA2ui.Bulk`). Under the admin
  catalog such a table stays basic-composed. Tables without bulk actions
  are unchanged.

  ## Data model

  The reserved-path value shape (see `topics/data-model-conventions`):

      %{
        "records" => [%{"id" => ..., "<field>" => ...}, ...],
        "form" => %{},
        "errors" => %{},
        "options" => %{"<field>" => [%{"label" => ..., "value" => ...}]},
        "ui" => %{"status" => "", "action_result" => %{}, "action_result_text" => ""}
      }

  Surfaces with prompt-enabled row actions additionally carry `"prompt"` —
  `%{"values" => %{"<action>" => %{"<field>" => ""}}}` — and rows of tables
  with `visible_when` row actions gain the `"_actions"` /
  `"_visible_<action>"` keys (see the sections above).

  `source` table columns serialize by walking the loaded relationship path
  (`[:user, :email]` -> `record.user.email`); a nil or unloaded relationship
  serializes to `""`.

  Query-enabled surfaces additionally carry `"query"` — the `/query` state
  shape documented on `AshA2ui.QueryRunner` — and their `submit_form`/`invoke`
  contexts include `"query": {"path": "/query"}` so success refreshes respect
  the client's active search/filters/sort/page.

  Record values are JSON-safe: dates/datetimes via `to_iso8601`, decimals and
  atoms via `to_string`.

  ## Wizard steps

  A form declaring `step` entities replaces its field children with the
  `form_wizard` subtree and carries `/ui/wizard` in the data model; see
  `AshA2ui.Wizard`. Forms without steps are unchanged.

  ## Experience v2

  With experience v2 (the default; pin
  `config :ash_a2ui, :experience_version, 1` for the shapes above) the
  shapes change
  behind the `AshA2ui.Experience` module: the form is gated behind the
  `/ui/panel/visible` sentinel with a task heading and a bound primary
  label, row controls become View/Edit, a create affordance appears, the
  pagination row and prev/next hide behind query-state sentinels, tables
  gain a data-driven empty state, and the status Text reads the typed
  feedback message. Every change is strictly gated — under the default
  version `1` the output is byte-identical to this documentation.
  """

  @behaviour AshA2ui.Encoder

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.ResolvedView

  @version "v0.9.1"
  @catalog_id "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"

  @numeric_types [Ash.Type.Integer, Ash.Type.Decimal, Ash.Type.Float]

  @impl true
  def encode_surface(resolved_view, records, opts) do
    [
      %{
        "version" => @version,
        "createSurface" => %{
          "surfaceId" => resolved_view.surface_id,
          "catalogId" => catalog_id()
        }
      },
      %{
        "version" => @version,
        "updateComponents" => %{
          "surfaceId" => resolved_view.surface_id,
          "components" => components(resolved_view, select_options(resolved_view, opts))
        }
      },
      encode_data_model(resolved_view, records, opts)
    ]
  end

  # The admin catalog (v2 + `catalog: :admin_v1`) surfaces declare their own
  # catalog id; everything else stays the basic catalog.
  defp catalog_id do
    if AshA2ui.Experience.effective_admin?(),
      do: AshA2ui.Experience.admin_catalog_id(),
      else: @catalog_id
  end

  @doc """
  Encodes a data-only refresh (`updateDataModel`), usable for PubSub-driven
  refresh pushes.

  By default replaces the entire data model (`path: "/"`) with the full
  reserved-path value shape, resetting `form`/`errors`/`ui`. Pass
  `scope: :records` to replace only `/records`, preserving in-flight form
  state on the client.
  """
  @impl true
  def encode_data_model(resolved_view, records, opts) do
    serialized = records_value(resolved_view, records, opts)

    {path, value} =
      case Keyword.get(opts, :scope, :full) do
        :records ->
          {"/records", serialized}

        :full ->
          {"/",
           %{
             "records" => serialized,
             "form" => ResolvedView.initial_form(resolved_view),
             "errors" => %{},
             "options" => options_data(resolved_view, opts),
             "ui" => %{"status" => "", "action_result" => %{}, "action_result_text" => ""}
           }
           |> put_query_state(resolved_view, opts)
           |> put_prompt_state(resolved_view)
           |> put_select_state(resolved_view)
           |> put_context_data(resolved_view, opts)
           |> put_report_state(resolved_view)
           |> put_export_state(resolved_view)
           |> put_bulk_state(resolved_view)
           |> put_experience_state(resolved_view)
           |> put_lane_totals(resolved_view)
           |> put_wizard_state(resolved_view)}
      end

    %{
      "version" => @version,
      "updateDataModel" => %{
        "surfaceId" => resolved_view.surface_id,
        "path" => path,
        "value" => value
      }
    }
  end

  # The value at "/records": on single-table surfaces the serialized row
  # list (records arrive as a list); on multi-table surfaces an object keyed
  # by table component name (records arrive as %{table_name => [record]},
  # see AshA2ui.Info) — every declared table gets a key, missing ones [].
  defp records_value(view, records, opts) do
    if ResolvedView.multi_table?(view) do
      unless is_map(records) do
        raise ArgumentError,
              "multi-table surfaces expect records as a map keyed by table component " <>
                "name (%{table_name => [record]}), got: #{inspect(records)}"
      end

      Map.new(view.tables, fn table ->
        rows = Map.get(records, table.name, [])
        links = table_links(view, table, opts)
        {to_string(table.name), Enum.map(rows, &serialize_record(view, table, &1, links))}
      end)
    else
      table = List.first(view.tables)
      links = table_links(view, table, opts)
      Enum.map(records, &serialize_record(view, table, &1, links))
    end
  end

  # The per-render link context of a table's linked fields (nil without
  # any — rows then carry no "_links" key).
  defp table_links(_view, nil, _opts), do: nil

  defp table_links(view, table, opts),
    do: AshA2ui.Links.context(table.resource, view.fields, table.component.fields, opts)

  # --- select options ---

  # Options for relationship selects and pick_existing nested forms are
  # loaded by the caller (`AshA2ui.Info`) and passed via `opts[:options]` as
  # `%{name => [%{"label" => _, "value" => _}]}`. Direct encoder calls
  # without the option fall back to empty option lists per source.
  defp select_options(view, opts) do
    context_defaults =
      for {name, %{picker: true}} <- view.contexts, into: %{}, do: {name, []}

    defaults =
      view
      |> ResolvedView.option_sources()
      |> Map.new(fn {name, _source} -> {name, []} end)
      |> Map.merge(context_defaults)

    Map.merge(defaults, Keyword.get(opts, :options) || %{})
  end

  # The reserved /report state (per-report params + rows). Omitted entirely
  # on surfaces without :report components (frozen shape unchanged).
  defp put_report_state(value, view) do
    case ResolvedView.report_state(view) do
      state when state == %{} -> value
      state -> Map.put(value, "report", state)
    end
  end

  # The reserved /export state (per-component column selection, all checked
  # initially). Omitted entirely on surfaces without column-selectable
  # exports (frozen shape unchanged).
  defp put_export_state(value, view) do
    case ResolvedView.export_state(view) do
      state when state == %{} -> value
      state -> Map.put(value, "export", state)
    end
  end

  # The reserved /bulk state (per-table last bulk result, see
  # AshA2ui.Bulk). Omitted entirely on surfaces without bulk actions
  # (frozen shape unchanged).
  defp put_bulk_state(value, view) do
    case AshA2ui.Bulk.state(view) do
      state when state == %{} -> value
      state -> Map.put(value, "bulk", state)
    end
  end

  # The reserved /select state (searchable-select search text + selected
  # label, pick_existing search text + picked value). Omitted entirely on
  # surfaces without wave-5 relationship inputs (frozen shape unchanged).
  defp put_select_state(value, view) do
    case ResolvedView.select_state(view) do
      state when state == %{} -> value
      state -> Map.put(value, "select", state)
    end
  end

  # The `/options/<field>` data-model mirror of the inline ChoicePicker
  # options (string keys, same list shape).
  defp options_data(view, opts) do
    view
    |> select_options(opts)
    |> Map.new(fn {name, options} -> {to_string(name), options} end)
  end

  # The reserved /context and /detail state (see AshA2ui.ContextRunner):
  # the caller-resolved values when given (AshA2ui.Info passes them after
  # loading under the carried :context_state), the empty initial shapes
  # otherwise. Omitted entirely on context-less surfaces (frozen shape
  # unchanged).
  defp put_context_data(value, view, opts) do
    if ResolvedView.contexts?(view) do
      value
      |> Map.put(
        "context",
        Keyword.get(opts, :context_values) || ResolvedView.context_state(view)
      )
      |> put_detail_data(view, opts)
    else
      value
    end
  end

  defp put_detail_data(value, view, opts) do
    case ResolvedView.detail_state(view) do
      state when state == %{} ->
        value

      state ->
        resolved =
          Map.new(
            Keyword.get(opts, :detail_values) || %{},
            fn {name, detail_value} -> {to_string(name), detail_value} end
          )

        Map.put(value, "detail", Map.merge(state, resolved))
    end
  end

  # --- component tree ---

  # Multi-table id scheme: single-table surfaces keep the frozen unsuffixed
  # ids ("records_list", "table_cell_<field>", "query_apply_button", ...);
  # multi-table surfaces infix the table component name right after the id's
  # leading noun ("records_list_<name>", "table_cell_<name>_<field>",
  # "query_<name>_apply_button", ...) — see the sfx/1-using call sites.
  defp components(view, options) do
    if AshA2ui.Experience.effective_admin?() do
      admin_components(view, options)
    else
      basic_components(view, options)
    end
  end

  defp basic_components(view, options) do
    form = Enum.find(view.components, &(&1.name == :form))

    context_sections =
      Enum.flat_map(view.context_order, &context_picker_components(view, view.contexts[&1]))

    table_sections =
      view.tables
      |> Enum.reject(&AshA2ui.Board.lane?/1)
      |> Enum.flat_map(fn table ->
        sfx = table_suffix(view, table)

        table_components(view, table, sfx) ++
          query_components(view, table, sfx) ++
          create_button_components(view, table, sfx) ++
          table_export_components(view, table, sfx) ++
          table_descendants(view, table, sfx) ++
          empty_state_components(view, table, sfx)
      end)
      |> Kernel.++(board_components(view))

    detail_sections = Enum.flat_map(view.details, &detail_components(view, &1))
    report_sections = Enum.flat_map(view.reports, &report_components(view, &1))

    form_components = (form && form_components(view, form)) || []

    root = %{
      "id" => "root",
      "component" => "Column",
      "children" => root_children(view, form)
    }

    status = %{
      "id" => "status_text",
      "component" => "Text",
      "text" => %{"path" => status_path()}
    }

    [
      root
      | surface_title_components(view) ++
          context_sections ++
          table_sections ++ detail_sections ++ report_sections ++ form_components
    ] ++
      form_descendants(view, form, options) ++ [status | action_result_components()]
  end

  # The surface title, as the first root child (v2). Titles are declared
  # on every surface and were silently dropped in basic mode — only the
  # admin entityPage consumed them — leaving pages without an h1 and the
  # first heading mislabeling the page (the CLIN-10 audit's finding #4).
  # The merged catalog's Text override carries the display tier for this
  # exact id; the wire shape is a plain heading Text either way.
  defp surface_title_components(view) do
    if AshA2ui.Experience.v2?() and is_binary(view.title) and view.title != "" do
      [
        %{
          "id" => "surface_title",
          "component" => "Text",
          "text" => view.title,
          "variant" => "h1"
        }
      ]
    else
      []
    end
  end

  # Under experience v2 the status Text reads the typed feedback message
  # (the classic /ui/status writes keep flowing server-side; the kind value
  # sits alongside at /ui/feedback/kind). v1 keeps the frozen binding.
  defp status_path do
    if AshA2ui.Experience.v2?(), do: "/ui/feedback/message", else: "/ui/status"
  end

  # --- admin catalog composition (v2 + catalog :admin_v1) ---

  # The admin emission upgrades the CORE subtree — collection → dataGrid
  # (+ emptyState + pagination), form → recordPanel (+ fieldDisplays,
  # formSection + actionBar), status → statusBanner, root → entityPage —
  # and keeps everything else basic: context pickers and query controls are
  # basic by contract, the create affordance stays a basic button, the
  # action-result panel is untouched, and advanced-feature subtrees
  # (dynamic sections, export, inline editing, nested forms, reports,
  # details) emit their basic-v2 composition byte-equal (see
  # notes/2026-09-07-admin-catalog-contract.md). Action envelopes are the
  # exact A2UI-101 shapes — the handler learns nothing new.
  defp admin_components(view, options) do
    form = Enum.find(view.components, &(&1.name == :form))

    context_sections =
      Enum.flat_map(view.context_order, &context_picker_components(view, view.contexts[&1]))

    {table_section_lists, table_children_lists} =
      view.tables
      |> Enum.map(&admin_table_section(view, &1, options))
      |> Enum.unzip()

    table_sections = List.flatten(table_section_lists)
    table_children = List.flatten(table_children_lists)

    detail_sections = Enum.flat_map(view.details, &admin_detail_components(view, &1))
    report_sections = Enum.flat_map(view.reports, &report_components(view, &1))

    detail_children =
      Enum.flat_map(view.components, fn
        %{name: :detail} = component -> ["detail_#{AshA2ui.Component.key(component)}"]
        %{name: :report} = component -> ["report_#{AshA2ui.Component.key(component)}"]
        _other -> []
      end)

    {form_sections, form_children} = admin_form_sections(view, form, options)

    root = %{
      "id" => "root",
      "component" => "entityPage",
      "title" => AshA2ui.Experience.surface_title(view),
      # Record-task panel first (zero jank: an open task is
      # front-and-center), the typed-feedback banner right below it (the
      # near-action outcome home), then context pickers, tables, details.
      "children" =>
        form_children ++
          ["status_banner"] ++
          context_children(view) ++
          table_children ++ detail_children ++ ["action_result_panel"]
    }

    [
      root
      | context_sections ++
          table_sections ++ detail_sections ++ report_sections ++ form_sections
    ] ++ [admin_status_banner() | action_result_components()]
  end

  defp context_children(view) do
    for name <- view.context_order, view.contexts[name].picker, do: "context_#{name}"
  end

  # A table whose whole subtree upgrades to the semantic components: no
  # dynamic sections, no export controls, no inline cell editing — the
  # contract's advanced-feature list. Everything else (and the form's
  # nested_form case below) falls back to its byte-equal basic-v2 subtree.
  # Expanded section tables carry `section` (their template's `sections`
  # key is gone), so both mark a dynamic table set.
  defp admin_core_table?(table) do
    is_nil(Map.get(table, :sections)) and is_nil(Map.get(table, :section)) and
      is_nil(table.export) and is_nil(table.editable) and not AshA2ui.Bulk.enabled?(table)
  end

  # Board lanes fall back to the basic board composition (the board
  # container rides on its template's first lane).
  defp admin_table_section(view, %{component: %{display: :board}} = table, _options) do
    {board_lane_components(view, table), component_root_children(view, table.component)}
  end

  defp admin_table_section(view, table, _options) do
    sfx = table_suffix(view, table)

    if admin_core_table?(table) do
      {query_control_components(view, table, sfx) ++
         create_button_components(view, table, sfx) ++
         admin_data_grid_components(view, table, sfx),
       ((table.query && ["query#{sfx}_controls"]) || []) ++
         create_button_ids(view, table, sfx) ++ ["data_grid#{sfx}"]}
    else
      {table_components(view, table, sfx) ++
         query_components(view, table, sfx) ++
         create_button_components(view, table, sfx) ++
         table_export_components(view, table, sfx) ++
         table_descendants(view, table, sfx) ++
         empty_state_components(view, table, sfx), component_root_children(view, table.component)}
    end
  end

  # The form subtree: recordPanel (+ fieldDisplay children for view mode,
  # formSection + actionBar for create/edit) on core surfaces; the
  # byte-equal basic-v2 form_slot composition when nested forms or wizard
  # steps are declared.
  defp admin_form_sections(_view, nil, _options), do: {[], []}

  defp admin_form_sections(view, form, options) do
    if form.nested_forms == [] and form.steps == [] do
      {[admin_record_panel(form) | admin_panel_descendants(view, form, options)],
       ["record_panel"]}
    else
      {form_components(view, form) ++ form_descendants(view, form, options), [form_root_child()]}
    end
  end

  defp admin_status_banner do
    %{
      "id" => "status_banner",
      "component" => "statusBanner",
      "kind" => %{"path" => "/ui/feedback/kind"},
      "message" => %{"path" => "/ui/feedback/message"}
    }
  end

  defp admin_data_grid_components(view, table, sfx) do
    pagination_children = if table.query, do: ["pagination#{sfx}"], else: []

    data_grid =
      %{
        "id" => "data_grid#{sfx}",
        "component" => "dataGrid",
        "columns" => admin_columns(view, table),
        "rows" => %{"path" => table.records_path},
        "rowId" => "id",
        "label" => AshA2ui.Experience.collection_label(view, table),
        "rowActions" => admin_row_actions(view, table),
        "children" => ["empty_state#{sfx}" | pagination_children]
      }
      |> put_row_click(view, table)

    [data_grid, admin_empty_state(sfx) | admin_pagination_components(view, table, sfx)]
  end

  # Whole-row click: the row's primary action — the master/detail select
  # (`select_context`) when declared, else View when the surface has a
  # record panel. The envelope is byte-identical to the matching rowActions
  # entry, so clicking a row is exactly clicking that button.
  defp put_row_click(grid, view, table) do
    case select_context_entries(view, table) do
      [entry | _] ->
        Map.put(grid, "rowClick", entry)

      [] ->
        if form_target?(view),
          do: Map.put(grid, "rowClick", admin_row_envelope("View", "view_record", table)),
          else: grid
    end
  end

  # One column per visible field, derived exactly like the basic Row/Card
  # composition derives its cells: the declared field order (or the row
  # layout's title/badge/meta sequence for card-style rows). Paths are
  # row-relative — rows are items of the records list, like the record_row
  # template.
  defp admin_columns(view, table) do
    fields =
      case table.component.row_layout do
        nil ->
          table.component.fields

        layout ->
          [layout.title, layout.badge]
          |> Enum.reject(&is_nil/1)
          |> Kernel.++(layout.meta)
          |> Enum.uniq()
      end

    layout = table.component.row_layout

    Enum.map(fields, fn field ->
      %{"label" => view.fields[field].label, "path" => to_string(field)}
      |> put_column_presentation(view, table.resource, field)
      |> put_column_badge(layout, field)
      |> put_link_binding(view, field, "_links/#{field}")
    end)
  end

  # Per-type presentation hints (additive; renderers that read only
  # label/path are unaffected): `format` (number/datetime/boolean, as
  # FieldDisplay), `align: "end"` for numbers, `mono: true` for identifiers.
  # Link columns render labels, never raw ids — no mono there.
  defp put_column_presentation(column, view, resource, field) do
    format = display_format(view, resource, field)

    column
    |> maybe_put("format", format)
    |> maybe_put("align", if(format == "number", do: "end"))
    |> maybe_put("mono", if(identifier?(view, resource, field), do: true))
  end

  defp identifier?(view, resource, field) do
    not AshA2ui.Links.link_field?(view.fields[field]) and
      (field == :id or attribute_type(resource, field) in [Ash.Type.UUID, Ash.Type.UUIDv7])
  end

  # The row_layout badge column renders as a pill: its text is the
  # server-computed `_badge_<field>` row key (the badge_text mapping), its
  # tone the `_badge_tone_<field>` key when `badge_tones` are declared.
  defp put_column_badge(column, %{badge: field} = layout, field) do
    badge =
      case layout.badge_tones do
        [] -> %{"path" => "_badge_#{field}"}
        _tones -> %{"path" => "_badge_#{field}", "tonePath" => "_badge_tone_#{field}"}
      end

    Map.put(column, "badge", badge)
  end

  defp put_column_badge(column, _layout, _field), do: column

  # Linked fields bind their `_links` entry (row-relative in grids,
  # absolute for detail/panel field displays).
  defp put_link_binding(component, view, field, path) do
    if AshA2ui.Links.link_field?(view.fields[field]),
      do: Map.put(component, "link", %{"path" => path}),
      else: component
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # The row action envelopes, reusing the exact context shapes the
  # basic-v2 record controls and invoke/confirm buttons emit: View always;
  # Edit when the view has an update action; declared row actions as their
  # existing invoke envelopes (the prompt-fields confirm envelope when the
  # action declares prompt_fields) — destructive: true when the action is
  # a destroy, so the renderer confirms through ConfirmDialog and
  # dispatches the envelope unchanged.
  defp admin_row_actions(view, table) do
    # View only when the surface has a record panel to open (formless
    # surfaces ship no dead affordance); Edit only with a declared update
    # action — the same gates the basic emission applies.
    view_entries =
      if form_target?(view), do: [admin_row_envelope("View", "view_record", table)], else: []

    edit_entries =
      if view.update_action, do: [admin_row_envelope("Edit", "start_edit", table)], else: []

    declared_entries =
      Enum.map(table.row_actions, fn action ->
        setting = Map.get(view.actions, action)

        context =
          %{
            "action" => to_string(action),
            "recordId" => %{"path" => "id"},
            "component" => to_string(table.name)
          }
          |> put_query_binding(view)
          |> put_contexts_binding(view)
          |> put_admin_prompt_values(setting)

        %{"label" => humanize(action), "action" => "invoke", "context" => context}
        |> maybe_destructive(view.resource, action)
      end)

    view_entries ++ select_context_entries(view, table) ++ edit_entries ++ declared_entries
  end

  # The master/detail row button (`select_context`): the same
  # `context_select` envelope the basic composition's per-row button
  # dispatches, so selecting a row into a context — and with it the
  # `:detail` components bound to that context — works on admin surfaces
  # too. Without it an admin grid silently dropped the only way to fill a
  # pickerless context.
  defp select_context_entries(_view, %{select_context: nil}), do: []

  defp select_context_entries(view, table) do
    name = table.select_context

    [
      %{
        "label" => "View #{String.downcase(humanize(name))}",
        "action" => "context_select",
        "context" =>
          %{
            "context" => to_string(name),
            "value" => %{"path" => "id"},
            "component" => to_string(table.name)
          }
          |> put_query_binding(view)
          |> put_contexts_binding(view)
      }
    ]
  end

  defp admin_row_envelope(label, action, table) do
    %{
      "label" => label,
      "action" => action,
      "context" => %{
        "recordId" => %{"path" => "id"},
        "component" => to_string(table.name)
      }
    }
  end

  defp put_admin_prompt_values(context, %{prompt_fields: [_ | _], name: name}) do
    Map.put(context, "values", %{"path" => "/prompt/values/#{name}"})
  end

  defp put_admin_prompt_values(context, _setting), do: context

  defp maybe_destructive(envelope, resource, action) do
    case ResourceInfo.action(resource, action) do
      %Ash.Resource.Actions.Destroy{} -> Map.put(envelope, "destructive", true)
      _other -> envelope
    end
  end

  defp admin_empty_state(sfx) do
    %{
      "id" => "empty_state#{sfx}",
      "component" => "emptyState",
      "message" => %{"path" => "_empty_message#{sfx}"},
      "children" => []
    }
  end

  # The pagination component binds PLAIN values — the query state's
  # boolean keys (no zero-or-one sentinel lists). prev/next dispatch the
  # existing query envelope with pageDelta -1/+1 (unchanged handler
  # contract); the context shape matches the basic prev/next buttons.
  defp admin_pagination_components(_view, %{query: nil}, _sfx), do: []

  defp admin_pagination_components(view, table, sfx) do
    query_path = table.query_path

    [
      %{
        "id" => "pagination#{sfx}",
        "component" => "pagination",
        "page" => %{"path" => "#{query_path}/page"},
        "pageSize" => %{"path" => "#{query_path}/pageSize"},
        "total" => %{"path" => "#{query_path}/totalCount"},
        "hasNext" => %{"path" => "#{query_path}/hasMore"},
        "visible" => %{"path" => "#{query_path}/paginationVisible"},
        "previousVisible" => %{"path" => "#{query_path}/previousVisible"},
        "nextVisible" => %{"path" => "#{query_path}/nextVisible"},
        "rangeText" => %{"path" => "#{query_path}/_range_text"},
        "previousAction" => admin_page_action(table, -1, view),
        "nextAction" => admin_page_action(table, 1, view)
      }
    ]
  end

  defp admin_page_action(table, page_delta, view) do
    %{
      "name" => "query",
      "context" =>
        %{"query" => %{"path" => table.query_path}, "pageDelta" => page_delta}
        |> Map.put("component", to_string(table.name))
        |> put_contexts_binding(view)
    }
  end

  defp admin_record_panel(form) do
    %{
      "id" => "record_panel",
      "component" => "recordPanel",
      "mode" => %{"path" => "/ui/panel/mode"},
      "title" => %{"path" => "/ui/panel/title"},
      "recordId" => %{"path" => "/ui/panel/record_id"},
      "children" =>
        Enum.map(form.fields, &"field_display_#{&1}") ++ ["form_section", "action_bar"]
    }
  end

  defp admin_panel_descendants(view, form, options) do
    field_displays = Enum.map(form.fields, &admin_field_display(view, &1))

    form_section = %{
      "id" => "form_section",
      "component" => "formSection",
      "children" => form_field_children(view, form)
    }

    inputs =
      Enum.map(form.fields, fn field ->
        if searchable_select?(view, field) do
          searchable_select_components(view, field)
        else
          form_input(view, field, options)
        end
      end)

    errors = Enum.map(form.fields, &form_error/1)

    action_bar = %{
      "id" => "action_bar",
      "component" => "actionBar",
      "primaryLabel" => %{"path" => "/ui/panel/primary_label"},
      "busy" => false,
      "action" => %{"event" => submit_event(view)},
      "children" => ["form_cancel_button"]
    }

    field_displays ++
      [form_section | List.flatten(inputs) ++ errors ++ group_components(view, form)] ++
      [action_bar | cancel_components()]
  end

  defp admin_field_display(view, field) do
    display = %{
      "id" => "field_display_#{field}",
      "component" => "fieldDisplay",
      "label" => view.fields[field].label,
      # the view task's read-only display values (view_record writes them;
      # /form is the edit buffer and stays untouched in view mode)
      "value" => %{"path" => "/ui/panel/record/#{field}"}
    }

    display
    |> maybe_put("format", admin_display_format(view, field))
    |> put_link_binding(view, field, "/ui/panel/record/_links/#{field}")
  end

  # The optional format hint: boolean/datetime from the resolved widget,
  # number from the field type; text (the default) is omitted.
  defp admin_display_format(view, field), do: display_format(view, view.resource, field)

  # The FieldDisplay/column `format` of a field on `resource` (the surface's
  # resource for grids and panels, the context's for details).
  @datetime_types [
    Ash.Type.Date,
    Ash.Type.UtcDatetime,
    Ash.Type.UtcDatetimeUsec,
    Ash.Type.NaiveDatetime,
    Ash.Type.DateTime
  ]

  defp display_format(view, resource, field) do
    declared = view.fields[field]

    cond do
      AshA2ui.Links.link_field?(declared) and not resource_field?(resource, field) -> nil
      declared && declared.widget == :check_box -> "boolean"
      declared && declared.widget == :date_time_input -> "datetime"
      true -> type_format(attribute_type(resource, field))
    end
  end

  defp type_format(type) when type in @numeric_types, do: "number"
  defp type_format(type) when type in @datetime_types, do: "datetime"
  defp type_format(Ash.Type.Boolean), do: "boolean"
  defp type_format(_type), do: nil

  defp resource_field?(resource, field) do
    not is_nil(ResourceInfo.attribute(resource, field)) or
      not is_nil(ResourceInfo.calculation(resource, field)) or
      not is_nil(ResourceInfo.aggregate(resource, field))
  end

  # Admin details: the same Card/Column/heading shell as the basic
  # composition, with each field a FieldDisplay — typed formatting,
  # link-aware (`link` binds `/detail/<context>/_links/<field>`), and
  # list-aware (multi-line / bulleted text renders as a list).
  defp admin_detail_components(view, detail) do
    base = "detail_#{detail.name}"
    resource = view.contexts[detail.context].resource

    fields =
      Enum.map(detail.fields, fn field ->
        %{
          "id" => "#{base}_field_#{field}",
          "component" => "fieldDisplay",
          "label" => detail_field_label(view, field),
          "value" => %{"path" => "/detail/#{detail.context}/#{field}"}
        }
        |> maybe_put("format", display_format(view, resource, field))
        |> put_link_binding(view, field, "/detail/#{detail.context}/_links/#{field}")
      end)

    [
      %{"id" => base, "component" => "Card", "child" => "#{base}_body"},
      %{
        "id" => "#{base}_body",
        "component" => "Column",
        "children" => ["#{base}_heading" | Enum.map(detail.fields, &"#{base}_field_#{&1}")]
      },
      %{
        "id" => "#{base}_heading",
        "component" => "Text",
        "text" => humanize(detail.name),
        "variant" => "h3"
      }
      | fields
    ]
  end

  defp table_suffix(view, table) do
    if ResolvedView.multi_table?(view), do: "_#{table.name}", else: ""
  end

  # Root order: under experience v2 the optional surface title
  # (`surface_title`, emitted only when the declaration carries one) leads,
  # then the record-task panel (`form_slot`) — opening a create/view/edit
  # task puts the form front-and-center instead of below every table (the
  # visibility gate keeps it out of the browse layout, so the position only
  # matters when a task is open) — and the feedback region (`status_text`,
  # the single authoritative outcome line bound to /ui/feedback/message)
  # follows: a near-action home, above the tables, so an invoke success or
  # refusal is on screen without scrolling to the page bottom (the audit's
  # offscreen-feedback finding; the panel-first ordering carries it into
  # view when a task is
  # open). Tables/details follow. The v1 experience keeps the frozen
  # pre-v2 root order with the always-rendered form and status last.
  defp root_children(view, form) do
    context_children =
      for name <- view.context_order, view.contexts[name].picker, do: "context_#{name}"

    component_children = Enum.flat_map(view.components, &component_root_children(view, &1))

    form_child = if form, do: [form_root_child()], else: []

    if AshA2ui.Experience.v2?() do
      title_child(view) ++
        form_child ++
        ["status_text"] ++ context_children ++ component_children ++ ["action_result_panel"]
    else
      context_children ++
        component_children ++ form_child ++ ["status_text", "action_result_panel"]
    end
  end

  # The v2 title child — present exactly when surface_title_components/1
  # emits the component (the same guard, so the two can never disagree).
  defp title_child(view) do
    if is_binary(view.title) and view.title != "", do: ["surface_title"], else: []
  end

  # v2 roots the form at the form_slot visibility gate (the List templated
  # over /ui/panel/visible); v1 keeps the bare form Column id.
  defp form_root_child do
    if AshA2ui.Experience.v2?(), do: "form_slot", else: "form"
  end

  # A board's lanes share one root child, the board container, placed at
  # its first lane.
  defp component_root_children(view, %{name: :table, display: :board} = component) do
    table = Enum.find(view.tables, &(&1.component == component))

    case AshA2ui.Board.template_lanes(view.tables, table.section.template) do
      [^table | _rest] -> [board_id(table)]
      _later_lane -> []
    end
  end

  defp component_root_children(view, %{name: :table} = component) do
    table = Enum.find(view.tables, &(&1.component == component))
    sfx = table_suffix(view, table)

    ["table_heading#{sfx}"] ++
      ((table.query && ["query#{sfx}_controls"]) || []) ++
      create_button_ids(view, table, sfx) ++
      ((AshA2ui.Bulk.enabled?(table) && [AshA2ui.Bulk.toolbar_id(sfx)]) || []) ++
      ["records_list#{sfx}"] ++
      empty_state_ids(view, table, sfx) ++
      ((table.query && ["query#{sfx}_pagination"]) || []) ++
      ((table.export && ["export#{sfx}_controls"]) || [])
  end

  defp component_root_children(_view, %{name: :detail} = component),
    do: ["detail_#{AshA2ui.Component.key(component)}"]

  defp component_root_children(_view, %{name: :report} = component),
    do: ["report_#{AshA2ui.Component.key(component)}"]

  defp component_root_children(_view, _form), do: []

  # The result panel displays map-returning generic action results: a Column
  # wrapping a Text bound to the reserved /ui/action_result_text path (see
  # topics/data-model-conventions). Empty text renders nothing.
  defp action_result_components do
    [
      %{
        "id" => "action_result_panel",
        "component" => "Column",
        "children" => ["action_result_text"]
      },
      %{
        "id" => "action_result_text",
        "component" => "Text",
        "text" => %{"path" => "/ui/action_result_text"}
      }
    ]
  end

  # --- experience v2 affordances ---

  # The create affordance (v2 only, and only when the view declares a create
  # action): a Button dispatching `start_create`, placed right after the
  # query controls. Under v1 no create affordance is emitted.
  defp create_button_ids(view, _table, sfx) do
    if AshA2ui.Experience.v2?() and view.create_action, do: ["create#{sfx}_button"], else: []
  end

  defp create_button_components(view, _table, sfx) do
    if AshA2ui.Experience.v2?() and view.create_action do
      [
        %{
          "id" => "create#{sfx}_button",
          "component" => "Button",
          "variant" => "primary",
          "child" => "create#{sfx}_text",
          "action" => %{"event" => %{"name" => "start_create", "context" => %{}}}
        },
        %{
          "id" => "create#{sfx}_text",
          "component" => "Text",
          "text" => AshA2ui.Experience.create_label(view)
        }
      ]
    else
      []
    end
  end

  # The per-table empty state (v2 only): a zero-or-one List over the root
  # `_empty_visible` sentinel (see AshA2ui.Experience) rendering the
  # "No <resource> records yet." Text — toggled by every records rewrite.
  defp empty_state_ids(_view, _table, sfx) do
    if AshA2ui.Experience.v2?(), do: ["empty_state#{sfx}"], else: []
  end

  defp empty_state_components(view, table, sfx) do
    if AshA2ui.Experience.v2?() do
      [
        %{
          "id" => "empty_state#{sfx}",
          "component" => "List",
          "children" => %{
            "componentId" => "empty_state#{sfx}_text",
            "path" => AshA2ui.Experience.empty_visible_path(view, table)
          }
        },
        %{
          "id" => "empty_state#{sfx}_text",
          "component" => "Text",
          "text" => %{"path" => "_empty_message#{sfx}"}
        }
      ]
    else
      []
    end
  end

  # Single-table headings show the humanized resource name (frozen); each
  # multi-table section is headed by its humanized component name — except
  # the expanded tables of a dynamic table set, which are headed by their
  # section record's label (see AshA2ui.Sections).
  defp table_components(view, table, sfx) do
    heading =
      case Map.get(table, :section) do
        %{label: label} ->
          label

        _not_a_section ->
          if ResolvedView.multi_table?(view),
            do: humanize(table.name),
            else: humanize_resource(view.resource)
      end

    [
      %{
        "id" => "table_heading#{sfx}",
        "component" => "Text",
        "text" => heading,
        "variant" => "h2"
      },
      %{
        "id" => "records_list#{sfx}",
        "component" => "List",
        "children" => %{"componentId" => "record_row#{sfx}", "path" => table.records_path}
      }
    ] ++ bulk_toolbar_components(view, table, sfx)
  end

  # The bulk-action toolbar above the list (tables with bulk_actions only;
  # see AshA2ui.Bulk). Its action contexts carry the usual query/contexts
  # bindings, like row-action invokes.
  defp bulk_toolbar_components(view, table, sfx) do
    if AshA2ui.Bulk.enabled?(table) do
      AshA2ui.Bulk.toolbar_components(table, sfx, fn context ->
        context |> put_query_binding(view) |> put_contexts_binding(view)
      end)
    else
      []
    end
  end

  # --- boards (display :board) ---

  # A board renders its template's lanes side by side: the container Column
  # (`board_<template>`: an h2 heading, the v2 create affordance, and a
  # horizontal List of lane Columns — a List, not a Row, because the basic
  # Row cannot wrap or scroll). Each lane Column (`lane<sfx>`) holds a
  # header Row (the lane heading Text plus its total, bound to
  # `/_lane_total_<lane>`), the lane's query controls when its query
  # declares any, the card list, the v2 empty state, the pagination and the
  # export controls. Card rows, row actions, visibility slots and the query
  # buttons are the list composition's, under the lane's runtime suffix.
  defp board_components(view) do
    view.tables
    |> Enum.filter(&AshA2ui.Board.lane?/1)
    |> Enum.flat_map(&board_lane_components(view, &1))
  end

  defp board_lane_components(view, table) do
    sfx = table_suffix(view, table)
    controls? = lane_controls?(table)

    lane = %{
      "id" => "lane#{sfx}",
      "component" => "Column",
      "children" => lane_children(view, table, sfx, controls?)
    }

    header = [
      %{
        "id" => "lane#{sfx}_header",
        "component" => "Row",
        "align" => "center",
        "children" => ["table_heading#{sfx}", "lane#{sfx}_total"]
      },
      %{
        "id" => "table_heading#{sfx}",
        "component" => "Text",
        "text" => table.section.label,
        "variant" => "h3"
      },
      %{
        "id" => "lane#{sfx}_total",
        "component" => "Text",
        "text" => %{"path" => AshA2ui.Board.total_path(table)},
        "variant" => "caption"
      },
      %{
        "id" => "records_list#{sfx}",
        "component" => "List",
        "children" => %{"componentId" => "record_row#{sfx}", "path" => table.records_path}
      }
    ]

    controls = if controls?, do: query_control_components(view, table, sfx), else: []

    board_container_components(view, table) ++
      [lane | header] ++
      controls ++
      pagination_components(view, table, sfx) ++
      table_export_components(view, table, sfx) ++
      table_descendants(view, table, sfx) ++
      empty_state_components(view, table, sfx)
  end

  # The container is emitted once, with the template's first lane.
  defp board_container_components(view, table) do
    case AshA2ui.Board.template_lanes(view.tables, table.section.template) do
      [^table | _rest] = lanes ->
        template = table.section.template
        board = board_id(table)

        [
          %{
            "id" => board,
            "component" => "Column",
            "children" =>
              ["#{board}_heading"] ++
                create_button_ids(view, table, "_#{template}") ++ ["#{board}_lanes"]
          },
          %{
            "id" => "#{board}_heading",
            "component" => "Text",
            "text" => humanize(template),
            "variant" => "h2"
          },
          %{
            "id" => "#{board}_lanes",
            "component" => "List",
            "direction" => "horizontal",
            "align" => "start",
            "children" => Enum.map(lanes, &"lane#{table_suffix(view, &1)}")
          }
        ] ++ create_button_components(view, table, "_#{template}")

      _later_lane ->
        []
    end
  end

  defp board_id(table), do: "board_#{table.section.template}"

  defp lane_children(view, table, sfx, controls?) do
    ["lane#{sfx}_header"] ++
      ((controls? && ["query#{sfx}_controls"]) || []) ++
      ["records_list#{sfx}"] ++
      empty_state_ids(view, table, sfx) ++
      ((table.query && ["query#{sfx}_pagination"]) || []) ++
      ((table.export && ["export#{sfx}_controls"]) || [])
  end

  # Lanes show query controls only when there is something to control: a
  # query used for page size or default sort alone adds no per-lane Card.
  defp lane_controls?(%{query: nil}), do: false

  defp lane_controls?(%{query: query}) do
    query.search_fields != [] or query.presets != [] or query.filters != [] or
      query.range_filters != []
  end

  # --- query controls (search / filters / pagination) ---

  # The `"query"` action wire contract: every control sends
  # `{"query": {"path": <the table's query path>}}` — the current query
  # state — plus the source `"component"` and either a literal page reset
  # (`"page" => 1`, Apply) or a relative page change (`"pageDelta" => -1 | 1`,
  # prev/next). The server validates everything against the declared
  # allowlist (`AshA2ui.QueryRunner`).
  defp query_components(view, table, sfx) do
    query_control_components(view, table, sfx) ++
      pagination_components(view, table, sfx)
  end

  # The search/preset/filter/range controls plus the Apply button — the
  # query section MINUS pagination (the admin emission composes its own
  # semantic pagination, so it consumes this variant directly).
  defp query_control_components(_view, %{query: nil}, _sfx), do: []

  defp query_control_components(view, table, sfx) do
    query = table.query
    search = (query.search_fields != [] && [search_input(table, sfx)]) || []
    presets = (query.presets != [] && [preset_picker(query, table, sfx)]) || []
    filters = Enum.map(query.filters, &filter_picker(view.resource, table, &1, sfx))
    ranges = Enum.flat_map(query.range_filters, &range_inputs(table, &1, sfx))

    # Query controls render as a Card (`query<sfx>_controls`, the id root
    # children reference) over a `_body` Row — section chrome on every
    # renderer, same shape as form groups and the context/detail sections.
    card = %{
      "id" => "query#{sfx}_controls",
      "component" => "Card",
      "child" => "query#{sfx}_controls_body"
    }

    controls = %{
      "id" => "query#{sfx}_controls_body",
      "component" => "Row",
      "children" =>
        Enum.map(search ++ presets ++ filters ++ ranges, & &1["id"]) ++
          ["query#{sfx}_apply_button"]
    }

    [card, controls | search ++ presets ++ filters ++ ranges] ++
      apply_button(view, table, sfx)
  end

  defp search_input(table, sfx) do
    %{
      "id" => "query#{sfx}_search_input",
      "component" => "TextField",
      "label" => "Search",
      "value" => %{"path" => "#{table.query_path}/search"}
    }
  end

  # The preset picker sends only the preset NAME over the wire — the
  # predicates live server-side. With a default_preset the option set is
  # closed (no "" escape back to the unscoped base read); without one an
  # "All" option ("" = no preset) comes first, mirroring the filter pickers.
  defp preset_picker(query, table, sfx) do
    preset_options =
      Enum.map(query.presets, &%{"label" => humanize(&1.name), "value" => to_string(&1.name)})

    options =
      if query.default_preset do
        preset_options
      else
        [%{"label" => "All", "value" => ""} | preset_options]
      end

    %{
      "id" => "query#{sfx}_preset_picker",
      "component" => "ChoicePicker",
      "label" => "View",
      "variant" => "mutuallyExclusive",
      "value" => %{"path" => "#{table.query_path}/preset"},
      "options" => options
    }
  end

  defp filter_picker(resource, table, field, sfx) do
    %{
      "id" => "query#{sfx}_filter_#{field}",
      "component" => "ChoicePicker",
      "label" => humanize(field),
      "variant" => "mutuallyExclusive",
      "value" => %{"path" => "#{table.query_path}/filters/#{field}"},
      "options" => [%{"label" => "All", "value" => ""} | filter_options(resource, field)]
    }
  end

  defp filter_options(resource, field) do
    if attribute_type(resource, field) == Ash.Type.Boolean do
      [%{"label" => "True", "value" => "true"}, %{"label" => "False", "value" => "false"}]
    else
      choice_options(resource, field)
    end
  end

  # Each range_filters field emits a from/to TextField pair bound to the
  # frozen /query/ranges/<field>/from|to paths; the shared Apply button
  # submits them with the rest of the query state.
  defp range_inputs(table, field, sfx) do
    Enum.map(["from", "to"], fn side ->
      %{
        "id" => "query#{sfx}_range_#{field}_#{side}",
        "component" => "TextField",
        "label" => "#{humanize(field)} #{side}",
        "value" => %{"path" => "#{table.query_path}/ranges/#{field}/#{side}"}
      }
    end)
  end

  defp apply_button(view, table, sfx) do
    [
      query_button("query#{sfx}_apply", table, %{"page" => 1}, view),
      %{"id" => "query#{sfx}_apply_text", "component" => "Text", "text" => "Apply"}
    ]
  end

  defp pagination_components(_view, %{query: nil}, _sfx), do: []

  defp pagination_components(view, table, sfx) do
    if AshA2ui.Experience.v2?() do
      experience_pagination_components(view, table, sfx)
    else
      [
        %{
          "id" => "query#{sfx}_pagination",
          "component" => "Row",
          "children" => [
            "query#{sfx}_prev_button",
            "query#{sfx}_page_text",
            "query#{sfx}_next_button"
          ]
        },
        query_button("query#{sfx}_prev", table, %{"pageDelta" => -1}, view),
        %{"id" => "query#{sfx}_prev_text", "component" => "Text", "text" => "Previous"},
        %{
          "id" => "query#{sfx}_page_text",
          "component" => "Text",
          "text" => %{"path" => "#{table.query_path}/page"}
        },
        query_button("query#{sfx}_next", table, %{"pageDelta" => 1}, view),
        %{"id" => "query#{sfx}_next_text", "component" => "Text", "text" => "Next"}
      ]
    end
  end

  # v2 pagination: the row hides behind the `_pagination_visible` sentinel
  # (a zero-or-one List, same technique as the row-action visibility slots —
  # see AshA2ui.Experience), the prev/next buttons each hide behind their
  # own sentinel, and the page number becomes the result-range text. The
  # Button ids are unchanged so themes keep working; the slot paths are
  # absolute because the sentinels live on the /query state itself, not on
  # the template item.
  defp experience_pagination_components(view, table, sfx) do
    query_path = table.query_path

    [
      %{
        "id" => "query#{sfx}_pagination",
        "component" => "List",
        "children" => %{
          "componentId" => "query#{sfx}_pagination_row",
          "path" => "#{query_path}/_pagination_visible"
        }
      },
      %{
        "id" => "query#{sfx}_pagination_row",
        "component" => "Row",
        "children" => [
          "query#{sfx}_prev_slot",
          "query#{sfx}_page_text",
          "query#{sfx}_next_slot"
        ]
      },
      %{
        "id" => "query#{sfx}_prev_slot",
        "component" => "List",
        "children" => %{
          "componentId" => "query#{sfx}_prev_button",
          "path" => "#{query_path}/_previous_visible"
        }
      },
      query_button("query#{sfx}_prev", table, %{"pageDelta" => -1}, view),
      %{"id" => "query#{sfx}_prev_text", "component" => "Text", "text" => "Previous"},
      %{
        "id" => "query#{sfx}_page_text",
        "component" => "Text",
        "text" => %{"path" => "#{query_path}/_range_text"}
      },
      %{
        "id" => "query#{sfx}_next_slot",
        "component" => "List",
        "children" => %{
          "componentId" => "query#{sfx}_next_button",
          "path" => "#{query_path}/_next_visible"
        }
      },
      query_button("query#{sfx}_next", table, %{"pageDelta" => 1}, view),
      %{"id" => "query#{sfx}_next_text", "component" => "Text", "text" => "Next"}
    ]
  end

  defp query_button(id_prefix, table, context, view) do
    context =
      context
      |> Map.put("query", %{"path" => table.query_path})
      |> Map.put("component", to_string(table.name))
      |> put_contexts_binding(view)

    %{
      "id" => "#{id_prefix}_button",
      "component" => "Button",
      "child" => "#{id_prefix}_text",
      "action" => %{"event" => %{"name" => "query", "context" => context}}
    }
  end

  # Write-action contexts carry the current /query (on multi-table surfaces:
  # the whole per-table state map) so success refreshes can re-read with the
  # client's active search/filters/sort/page.
  defp put_query_binding(context, view) do
    if Enum.any?(view.tables, & &1.query) do
      Map.put(context, "query", %{"path" => "/query"})
    else
      context
    end
  end

  # Action contexts on context-enabled surfaces carry the current /context
  # map, so server reads (refreshes, query, context cascades) run under the
  # client's active selections. Context-less surfaces are unchanged (frozen
  # contract).
  defp put_contexts_binding(context, view) do
    if ResolvedView.contexts?(view) do
      Map.put(context, "contexts", %{"path" => "/context"})
    else
      context
    end
  end

  defp table_descendants(view, table, sfx) do
    {action_ids, action_components} =
      table.row_actions
      |> Enum.map(&row_action_components(view, table, &1, sfx))
      |> Enum.unzip()

    # The context-select button (master/detail hook) rides along with the
    # row-action anchors in either layout, as do the row controls — Select
    # under v1 (form surfaces only); View/Edit under v2.
    {context_select_ids, context_select_components} = context_select_button(view, table, sfx)
    {control_ids, control_components} = row_controls(view, table, sfx)

    action_ids = action_ids ++ context_select_ids ++ control_ids

    row_components =
      case table.component.row_layout do
        nil -> flat_row_components(view, table, action_ids, sfx)
        layout -> card_row_components(view, layout, action_ids, sfx)
      end

    # Bulk tables add the row CheckBox (no-op otherwise).
    row_components = AshA2ui.Bulk.with_row_checkbox(row_components, table, sfx)

    row_components ++
      List.flatten(action_components) ++ context_select_components ++ control_components
  end

  # The row controls tail: v2 replaces the frozen v1 Select with View —
  # only when a form panel exists to show the record in (a View button on
  # a formless surface is dead wire weight — the audit's 7 dead buttons) —
  # plus Edit when the view declares an update action. v1 keeps the frozen
  # Select button (form surfaces only — see select_button/2).
  defp row_controls(view, table, sfx) do
    cond do
      not AshA2ui.Experience.v2?() -> v1_select_control(view, table, sfx)
      form_target?(view) -> view_edit_controls(view, table, sfx)
      true -> {[], []}
    end
  end

  defp view_edit_controls(view, table, sfx) do
    {view_id, view_components} =
      record_control(table, "view#{sfx}_button", "view_record", "View")

    {edit_ids, edit_components} =
      if view.update_action do
        {id, components} = record_control(table, "edit#{sfx}_button", "start_edit", "Edit")
        {[id], components}
      else
        {[], []}
      end

    {[view_id | edit_ids], view_components ++ edit_components}
  end

  defp v1_select_control(view, table, sfx) do
    components =
      if Enum.any?(view.components, &(&1.name == :form)),
        do: select_button(table, sfx),
        else: []

    {Enum.map(Enum.take(components, 1), & &1["id"]), components}
  end

  # Whether the surface has a record-task panel for view_record to open:
  # the form component's panel is the only view target.
  defp form_target?(view) do
    Enum.any?(view.components, &(&1.name == :form))
  end

  # One v2 record control: a Button dispatching `event` with the row's
  # recordId binding, plus its label Text (mirrors select_button/2).
  defp record_control(table, id, event, label) do
    components = [
      %{
        "id" => id,
        "component" => "Button",
        "child" => "#{id}_text",
        "action" => %{
          "event" => %{
            "name" => event,
            "context" => %{
              "recordId" => %{"path" => "id"},
              "component" => to_string(table.name)
            }
          }
        }
      },
      %{"id" => "#{id}_text", "component" => "Text", "text" => label}
    ]

    {id, components}
  end

  # Each record renders as a Card (chrome themed via --a2ui-card-*)
  # wrapping the actual Row of labeled cells; the List template still points
  # at record_row, so this stays invisible to the data model and actions.
  defp flat_row_components(view, table, action_ids, sfx) do
    fields = table.component.fields
    cell_ids = Enum.map(fields, &"table_cell#{sfx}_#{&1}")

    card = %{
      "id" => "record_row#{sfx}",
      "component" => "Card",
      "child" => "record_row#{sfx}_content"
    }

    row = %{
      "id" => "record_row#{sfx}_content",
      "component" => "Row",
      "children" => cell_ids ++ action_ids
    }

    [card, row | Enum.flat_map(fields, &cell(view, table, &1, sfx))]
  end

  # Card-style rows (row_layout): the templated record_row becomes a Card
  # whose Column body holds a header Row — the title Text (weight 1) and a
  # right-hand Row of the badge Text (when declared) plus the row's action
  # anchors and select button — above the meta grid (see grid_components/4:
  # Rows of equal-weight Columns, each a caption label over the bound value).
  defp card_row_components(view, layout, action_ids, sfx) do
    base = "record_row#{sfx}"

    badge =
      if layout.badge do
        [
          %{
            "id" => "#{base}_badge",
            "component" => "Text",
            "text" => %{"path" => "_badge_#{layout.badge}"},
            "variant" => "caption"
          }
        ]
      else
        []
      end

    {meta_row_ids, meta_components} =
      grid_components("#{base}_meta", layout.columns, layout.meta, fn field ->
        {["#{base}_meta_label_#{field}", "#{base}_meta_value_#{field}"],
         [
           %{
             "id" => "#{base}_meta_label_#{field}",
             "component" => "Text",
             "text" => view.fields[field].label,
             "variant" => "caption"
           },
           %{
             "id" => "#{base}_meta_value_#{field}",
             "component" => "Text",
             "text" => cell_text(view.fields[field])
           }
         ]}
      end)

    [
      %{"id" => base, "component" => "Card", "child" => "#{base}_body"},
      %{
        "id" => "#{base}_body",
        "component" => "Column",
        "children" => ["#{base}_header" | meta_row_ids]
      },
      %{
        "id" => "#{base}_header",
        "component" => "Row",
        "justify" => "spaceBetween",
        "align" => "center",
        "children" => ["#{base}_title", "#{base}_header_right"]
      },
      %{
        "id" => "#{base}_title",
        "component" => "Text",
        "text" => cell_text(view.fields[layout.title]),
        "variant" => "h4",
        "weight" => 1
      },
      %{
        "id" => "#{base}_header_right",
        "component" => "Row",
        "align" => "center",
        "children" => Enum.map(badge, & &1["id"]) ++ action_ids
      }
    ] ++ badge ++ meta_components
  end

  # An N-column grid: items chunked into Rows of `columns` equal-weight cell
  # Columns (each holding the ids `cell_fun` returns for its item), the last
  # row padded with empty spacer Columns so cells stay aligned.
  defp grid_components(base, columns, items, cell_fun) do
    items
    |> Enum.chunk_every(columns)
    |> Enum.with_index()
    |> Enum.map(fn {row_items, index} ->
      cells =
        Enum.map(row_items, fn item ->
          {children, components} = cell_fun.(item)

          {"#{base}_cell_#{item}",
           [
             %{
               "id" => "#{base}_cell_#{item}",
               "component" => "Column",
               "weight" => 1,
               "children" => children
             }
             | components
           ]}
        end)

      spacers =
        for spacer <- length(row_items)..(columns - 1)//1 do
          {"#{base}_spacer_#{index}_#{spacer}",
           [
             %{
               "id" => "#{base}_spacer_#{index}_#{spacer}",
               "component" => "Column",
               "weight" => 1,
               "children" => []
             }
           ]}
        end

      {cell_ids, cell_components} = Enum.unzip(cells ++ spacers)

      {"#{base}_row_#{index}",
       [
         %{
           "id" => "#{base}_row_#{index}",
           "component" => "Row",
           "children" => cell_ids
         }
         | List.flatten(cell_components)
       ]}
    end)
    |> Enum.unzip()
    |> then(fn {row_ids, components} -> {row_ids, List.flatten(components)} end)
  end

  # Only emitted on surfaces with a :form component — select_row's single
  # purpose is populating /form for editing, so a formless surface gets no
  # Select button (see table_descendants/3).
  defp select_button(table, sfx) do
    [
      %{
        "id" => "row_select#{sfx}_button",
        "component" => "Button",
        "child" => "row_select#{sfx}_text",
        "action" => %{
          "event" => %{
            "name" => "select_row",
            "context" => %{
              "recordId" => %{"path" => "id"},
              "component" => to_string(table.name)
            }
          }
        }
      },
      %{"id" => "row_select#{sfx}_text", "component" => "Text", "text" => "Select"}
    ]
  end

  # A table with `select_context` gets a per-row Button dispatching
  # `context_select` for the named context with the row's id — the
  # master/detail hook: the row's record becomes the context's selection,
  # cascading like a picker selection would.
  defp context_select_button(_view, %{select_context: nil}, _sfx), do: {[], []}

  defp context_select_button(view, table, sfx) do
    name = table.select_context
    base = "row_context#{sfx}_button"

    components = [
      %{
        "id" => base,
        "component" => "Button",
        "child" => "row_context#{sfx}_text",
        "action" => %{
          "event" => %{
            "name" => "context_select",
            "context" =>
              %{
                "context" => to_string(name),
                "value" => %{"path" => "id"}
              }
              |> put_query_binding(view)
              |> put_contexts_binding(view)
          }
        }
      },
      %{
        "id" => "row_context#{sfx}_text",
        "component" => "Text",
        "text" => "View #{String.downcase(humanize(name))}"
      }
    ]

    {[base], components}
  end

  # A cell is a labeled pair: a caption Text with the humanized field name
  # and a body Text bound to the field value — so generated rows read
  # "Name: Fido" instead of a bare value soup. Fields listed in the table's
  # `editable` config render as editable cells instead (see
  # editable_cell/4).
  defp cell(view, table, field_name, sfx) do
    if field_name in editable_fields(table) do
      editable_cell(view, table, field_name, sfx)
    else
      field = view.fields[field_name]
      base = "table_cell#{sfx}_#{field_name}"

      [
        %{
          "id" => base,
          "component" => "Row",
          "children" => ["#{base}_label", "#{base}_value"]
        },
        %{
          "id" => "#{base}_label",
          "component" => "Text",
          "text" => humanize(field_name),
          "variant" => "caption"
        },
        %{
          "id" => "#{base}_value",
          "component" => "Text",
          "text" => cell_text(field)
        }
      ]
    end
  end

  defp editable_fields(table) do
    case Map.get(table, :editable) do
      %{fields: fields} -> fields
      _not_editable -> []
    end
  end

  # An editable cell (inline cell editing): a TextField bound to the
  # template-relative field path — edits stay in the client row until
  # committed — a Save Button dispatching `edit_cell` with the row's id and
  # this field's current value, and an error Text bound to the row's
  # reserved `_error_<field>` mirror (written by the handler when the
  # commit's validation fails; empty otherwise). On v1.0 surfaces the
  # Save button's actionResponse handshake drives per-cell pending→settled
  # feedback.
  defp editable_cell(view, table, field_name, sfx) do
    field = view.fields[field_name]
    base = "table_cell#{sfx}_#{field_name}"

    [
      %{
        "id" => base,
        "component" => "Row",
        "align" => "center",
        "children" => ["#{base}_input", "#{base}_save_button", "#{base}_error"]
      },
      %{
        "id" => "#{base}_input",
        "component" => "TextField",
        "label" => field.label,
        "value" => %{"path" => to_string(field_name)}
      },
      %{
        "id" => "#{base}_save_button",
        "component" => "Button",
        "child" => "#{base}_save_text",
        "action" => %{
          "event" => %{
            "name" => "edit_cell",
            "context" =>
              %{
                "recordId" => %{"path" => "id"},
                "component" => to_string(table.name),
                "field" => to_string(field_name),
                "value" => %{"path" => to_string(field_name)}
              }
              |> put_query_binding(view)
              |> put_contexts_binding(view)
          }
        }
      },
      %{"id" => "#{base}_save_text", "component" => "Text", "text" => "Save"},
      %{
        "id" => "#{base}_error",
        "component" => "Text",
        "text" => %{"path" => "_error_#{field_name}"},
        "variant" => "caption"
      }
    ]
  end

  # Template-relative binding: paths inside a List item template resolve
  # against the item object, so plain "<field>" (no leading /).
  defp cell_text(%{format: :date} = field) do
    %{
      "call" => "formatDate",
      "args" => %{
        "value" => %{"path" => to_string(field.name)},
        "format" => "MMM d, yyyy"
      },
      "returnType" => "string"
    }
  end

  defp cell_text(field), do: %{"path" => to_string(field.name)}

  # One row action's components plus the id placed in the row's children:
  # a plain invoke Button by default; a Modal (trigger button + prompt
  # content) when the action declares prompt_fields; either wrapped in a
  # visibility slot (a List templated over the row-relative
  # `_visible_<action>` path) when the action declares visible_when.
  defp row_action_components(view, table, action, sfx) do
    setting = Map.get(view.actions, action)
    prompt? = match?(%{prompt_fields: [_ | _]}, setting)
    conditional? = match?(%{visible_when: [_ | _]}, setting)
    base = "row_action#{sfx}_#{action}"

    inner_id = if prompt?, do: "#{base}_modal", else: "#{base}_button"
    anchor_id = if conditional?, do: "#{base}_slot", else: inner_id

    button =
      if prompt? do
        prompt_trigger_button(table, action, base) ++
          prompt_components(view, table, action, base, setting)
      else
        invoke_button(view, table, action, base)
      end

    slot = if conditional?, do: [visibility_slot(base, inner_id, action)], else: []

    {anchor_id, button ++ slot}
  end

  defp invoke_button(view, table, action, base) do
    [
      %{
        "id" => "#{base}_button",
        "component" => "Button",
        "child" => "#{base}_text",
        "action" => %{
          "event" => %{
            "name" => "invoke",
            "context" =>
              %{
                "action" => to_string(action),
                "recordId" => %{"path" => "id"},
                "component" => to_string(table.name)
              }
              |> put_query_binding(view)
              |> put_contexts_binding(view)
          }
        }
      },
      %{
        "id" => "#{base}_text",
        "component" => "Text",
        "text" => humanize(action)
      }
    ]
  end

  # The Modal's trigger: opening is client-side (interacting with the
  # trigger), while the `prompt` event lets the server pre-fill
  # /prompt/values/<action> and clear stale /errors.
  defp prompt_trigger_button(table, action, base) do
    [
      %{
        "id" => "#{base}_button",
        "component" => "Button",
        "child" => "#{base}_text",
        "action" => %{
          "event" => %{
            "name" => "prompt",
            "context" => %{
              "action" => to_string(action),
              "recordId" => %{"path" => "id"},
              "component" => to_string(table.name)
            }
          }
        }
      },
      %{
        "id" => "#{base}_text",
        "component" => "Text",
        "text" => humanize(action)
      }
    ]
  end

  # The Modal and its content: a title, one TextField per prompt field bound
  # to the absolute /prompt/values/<action>/<field> path (template-relative
  # paths cannot reach the shared prompt state), a per-field error Text, and
  # the confirm Button whose invoke context carries the "values" binding.
  defp prompt_components(view, table, action, base, setting) do
    title = setting.prompt_title || humanize(action)

    field_children =
      Enum.flat_map(setting.prompt_fields, fn field ->
        ["#{base}_prompt_input_#{field}", "#{base}_prompt_error_#{field}"]
      end)

    inputs =
      Enum.map(setting.prompt_fields, fn field ->
        %{
          "id" => "#{base}_prompt_input_#{field}",
          "component" => "TextField",
          "label" => prompt_label(view, field),
          "value" => %{"path" => "/prompt/values/#{action}/#{field}"}
        }
      end)

    errors =
      Enum.map(setting.prompt_fields, fn field ->
        %{
          "id" => "#{base}_prompt_error_#{field}",
          "component" => "Text",
          "text" => %{"path" => "/errors/#{field}"},
          "variant" => "caption"
        }
      end)

    [
      %{
        "id" => "#{base}_modal",
        "component" => "Modal",
        "trigger" => "#{base}_button",
        "content" => "#{base}_prompt"
      },
      %{
        "id" => "#{base}_prompt",
        "component" => "Column",
        "children" => ["#{base}_prompt_title" | field_children] ++ ["#{base}_confirm_button"]
      },
      %{
        "id" => "#{base}_prompt_title",
        "component" => "Text",
        "text" => title,
        "variant" => "h3"
      }
    ] ++
      inputs ++
      errors ++
      [
        %{
          "id" => "#{base}_confirm_button",
          "component" => "Button",
          "variant" => "primary",
          "child" => "#{base}_confirm_text",
          "action" => %{
            "event" => %{
              "name" => "invoke",
              "context" =>
                %{
                  "action" => to_string(action),
                  "recordId" => %{"path" => "id"},
                  "component" => to_string(table.name),
                  "values" => %{"path" => "/prompt/values/#{action}"}
                }
                |> put_query_binding(view)
                |> put_contexts_binding(view)
            }
          }
        },
        %{"id" => "#{base}_confirm_text", "component" => "Text", "text" => "Confirm"}
      ]
  end

  defp prompt_label(view, field) do
    case view.fields[field] do
      %{label: label} when is_binary(label) -> label
      _undeclared -> humanize(field)
    end
  end

  # Zero-or-one nested template: `_visible_<action>` on the row is either
  # [] or [%{"id" => id}], so the slot renders the action only when the
  # server computed it visible (and the item's "id" keeps the
  # template-relative recordId binding working).
  defp visibility_slot(base, inner_id, action) do
    %{
      "id" => "#{base}_slot",
      "component" => "List",
      "children" => %{"componentId" => inner_id, "path" => "_visible_#{action}"}
    }
  end

  defp form_components(view, form) do
    field_children = form_field_children(view, form)
    nested_children = Enum.map(form.nested_forms, &"nested_#{&1.name}")

    # v2 splits the panel's content by task mode: the editable form fields
    # live behind the /ui/panel/form_visible gate (create/edit), the
    # read-only record display behind /ui/panel/view_visible (view) — so a
    # view task renders the derived display, never an empty editable form.
    #
    # v2 also cards the panel: the form is the heaviest task surface on
    # the page and floated uncared on the page background (the CLIN-10
    # audit's finding #3) while the group sections 30 lines below already
    # had the Card anatomy. The `form` id is kept (the hook's panel-reveal
    # PANEL_IDS contract) — it becomes the Card, its content moves under a
    # `form_body` Column, and the submit/cancel pair gains a footer zone
    # (Divider + `form_footer` Column) so the card closes like the digest's
    # CardFooter instead of trailing loose buttons.
    {form_root, body_children, footer_components} =
      if AshA2ui.Experience.v2?() do
        body = [
          "form_title",
          "panel_view_slot",
          "form_fields_slot",
          "form_footer_divider",
          "form_footer"
        ]

        footer = [
          %{"id" => "form_footer_divider", "component" => "Divider"},
          %{
            "id" => "form_footer",
            "component" => "Column",
            "children" => ["form_submit_slot", "form_cancel_button"]
          }
        ]

        {%{"id" => "form", "component" => "Card", "child" => "form_body"}, body, footer}
      else
        children = field_children ++ nested_children ++ [AshA2ui.Wizard.submit_child(form)]

        {%{"id" => "form", "component" => "Column", "children" => children}, children, []}
      end

    # v1 keeps the always-rendered form.
    if AshA2ui.Experience.v2?() do
      [
        %{
          "id" => "form_slot",
          "component" => "List",
          "children" => %{"componentId" => "form", "path" => "/ui/panel/visible"}
        },
        form_root,
        %{
          "id" => "form_body",
          "component" => "Column",
          "children" => body_children
        }
        | footer_components ++ panel_mode_slots(view, form, field_children, nested_children)
      ] ++ group_components(view, form) ++ wizard_components(view, form)
    else
      [form_root] ++ group_components(view, form) ++ wizard_components(view, form)
    end
  end

  # The v2 mode-gated panel content: the read-only record display (view
  # task) and the editable form fields (create/edit tasks), each behind its
  # zero-or-one sentinel — exactly one of them renders at a time. The
  # submit/cancel pair keeps its own gating (submit_visible / the open
  # panel), so view offers Cancel alone while edit offers the pair.
  defp panel_mode_slots(view, form, field_children, nested_children) do
    List.flatten([
      %{
        "id" => "panel_view_slot",
        "component" => "List",
        "children" => %{"componentId" => "panel_view", "path" => "/ui/panel/view_visible"}
      },
      panel_view(view, form),
      %{
        "id" => "form_fields_slot",
        "component" => "List",
        "children" => %{"componentId" => "form_fields", "path" => "/ui/panel/form_visible"}
      },
      %{
        "id" => "form_fields",
        "component" => "Column",
        "children" => field_children ++ nested_children
      }
    ])
  end

  # The view task's derived display: one caption/value pair per form field,
  # bound to the `/ui/panel/record` values the handler writes on
  # view_record — the same values the form would have shown, but as bound
  # Texts (nothing editable). Nested-form rows are edit machinery and stay
  # out of the display.
  defp panel_view(view, form) do
    rows =
      Enum.flat_map(form.fields, fn field ->
        [
          %{
            "id" => "panel_view_#{field}",
            "component" => "Row",
            "children" => ["panel_view_#{field}_label", "panel_view_#{field}_value"]
          },
          %{
            "id" => "panel_view_#{field}_label",
            "component" => "Text",
            "text" => view.fields[field].label,
            "variant" => "caption"
          },
          %{
            "id" => "panel_view_#{field}_value",
            "component" => "Text",
            "text" => %{"path" => "/ui/panel/record/#{field}"}
          }
        ]
      end)

    [
      %{
        "id" => "panel_view",
        "component" => "Column",
        "children" => Enum.map(form.fields, &"panel_view_#{&1}")
      }
      | rows
    ]
  end

  defp field_anchor_ids(view, field) do
    anchor =
      if searchable_select?(view, field),
        do: "form_select_#{field}",
        else: "form_input_#{field}"

    [anchor, "form_error_#{field}"]
  end

  # A stepped form's fields render inside its wizard pages.
  defp form_field_children(_view, %{steps: [_ | _]}), do: AshA2ui.Wizard.field_children()

  # The ordering contract with groups: walking the form's effective field
  # order, an ungrouped field renders its input/error pair in place, and a
  # group renders (whole, in the group's own field order) at the position of
  # its first member — later members are already covered by the group.
  defp form_field_children(view, %{groups: []} = form) do
    Enum.flat_map(form.fields, &field_anchor_ids(view, &1))
  end

  defp form_field_children(view, form) do
    form.fields
    |> Enum.flat_map_reduce(MapSet.new(), fn field, seen ->
      case Enum.find(form.groups, &(field in &1.fields)) do
        nil -> {field_anchor_ids(view, field), seen}
        %{name: name} -> group_anchor(name, seen)
      end
    end)
    |> elem(0)
  end

  # The group anchor appears once — at its first member's position.
  defp group_anchor(name, seen) do
    if MapSet.member?(seen, name) do
      {[], seen}
    else
      {["form_group_#{name}"], MapSet.put(seen, name)}
    end
  end

  # One Card-wrapped section per group: a heading Text (h3) over the fields.
  # Single-column groups hold the input/error pairs directly; multi-column
  # groups lay them out in the shared grid shape (see grid_components/4).
  defp group_components(view, form) do
    Enum.flat_map(form.groups, &group_section(view, &1))
  end

  defp group_section(view, group) do
    base = "form_group_#{group.name}"
    {grid_children, grid_components} = group_grid(view, group, base)

    [
      %{"id" => base, "component" => "Card", "child" => "#{base}_body"},
      %{
        "id" => "#{base}_body",
        "component" => "Column",
        "children" => ["#{base}_heading" | grid_children]
      },
      %{
        "id" => "#{base}_heading",
        "component" => "Text",
        "text" => group.label,
        "variant" => "h3"
      }
    ] ++ grid_components
  end

  defp group_grid(view, %{columns: 1} = group, _base) do
    {Enum.flat_map(group.fields, &field_anchor_ids(view, &1)), []}
  end

  defp group_grid(view, group, base) do
    grid_components(base, group.columns, group.fields, fn field ->
      {field_anchor_ids(view, field), []}
    end)
  end

  # Stepped forms (see AshA2ui.Wizard): the wizard Column, its step pages
  # and Back/Next controls. Inputs stay the encoder's own field anchors.
  defp wizard_components(view, form),
    do: AshA2ui.Wizard.components(view, form, &field_anchor_ids(view, &1))

  defp searchable_select?(view, field_name) do
    match?(%{search_fields: [_ | _]}, view.selects[field_name])
  end

  defp form_descendants(_view, nil, _options), do: []

  defp form_descendants(view, form, options) do
    inputs =
      Enum.map(form.fields, fn field ->
        if searchable_select?(view, field) do
          searchable_select_components(view, field)
        else
          form_input(view, field, options)
        end
      end)

    nested =
      Enum.flat_map(form.nested_forms, fn entity ->
        nested_form_components(view, view.nested_forms[entity.name], options)
      end)

    errors = Enum.map(form.fields, &form_error/1)

    List.flatten(inputs) ++ nested ++ errors ++ form_task_descendants(view)
  end

  # The form's task affordances: v1 keeps the frozen always-visible "Save"
  # submit. v2 adds the panel heading (bound to /ui/panel/title), gates the
  # submit behind the /ui/panel/submit_visible sentinel with its label bound
  # to /ui/panel/primary_label (so it disappears in view mode), and emits
  # the Cancel button dispatching `cancel_record_task`.
  defp form_task_descendants(view) do
    if AshA2ui.Experience.v2?() do
      [
        %{
          "id" => "form_title",
          "component" => "Text",
          "text" => %{"path" => "/ui/panel/title"},
          "variant" => "h3"
        },
        %{
          "id" => "form_submit_slot",
          "component" => "List",
          "children" => %{
            "componentId" => "form_submit_button",
            "path" => "/ui/panel/submit_visible"
          }
        }
      ] ++
        submit_button(view, %{"path" => "/ui/panel/primary_label"}) ++
        cancel_components()
    else
      submit_button(view, "Save")
    end
  end

  # The Cancel button (v2 basic form and the admin ActionBar secondary):
  # dispatches the existing cancel_record_task envelope.
  defp cancel_components do
    [
      %{
        "id" => "form_cancel_button",
        "component" => "Button",
        "child" => "form_cancel_text",
        "action" => %{"event" => %{"name" => "cancel_record_task", "context" => %{}}}
      },
      %{"id" => "form_cancel_text", "component" => "Text", "text" => "Cancel"}
    ]
  end

  defp submit_button(view, label) do
    [
      %{
        "id" => "form_submit_button",
        "component" => "Button",
        "variant" => "primary",
        "child" => "form_submit_text",
        "action" => %{"event" => submit_event(view)}
      },
      %{"id" => "form_submit_text", "component" => "Text", "text" => label}
    ]
  end

  # The frozen submit_form event envelope, shared by the basic submit
  # button and the admin ActionBar's primary action.
  defp submit_event(view) do
    %{
      "name" => "submit_form",
      "context" =>
        %{
          "values" => %{"path" => "/form"},
          "recordId" => %{"path" => "/form/id"}
        }
        |> put_query_binding(view)
        |> put_contexts_binding(view)
    }
  end

  # --- searchable selects ---

  # A relationship select with `option_search` renders as a composite instead
  # of a static ChoicePicker: the current selection's label (bound to
  # /select/<field>/label), a search TextField (bound to
  # /select/<field>/search) with a Button dispatching `option_search`, and a
  # result List templated over /options/<field> whose per-option Button
  # dispatches `option_select` with the template-relative option "value".
  # Selection round-trips through the server, which validates the value
  # against the destination (authorized read) and writes /form/<field> plus
  # the resolved label — labels never come from the client.
  defp searchable_select_components(view, field_name) do
    base = "form_select_#{field_name}"
    field = view.fields[field_name]

    [
      %{
        "id" => base,
        "component" => "Column",
        "children" => [
          "#{base}_label",
          "#{base}_selected",
          "#{base}_controls",
          "#{base}_options"
        ]
      },
      %{"id" => "#{base}_label", "component" => "Text", "text" => field.label, "variant" => "h4"},
      %{
        "id" => "#{base}_selected",
        "component" => "Text",
        "text" => %{"path" => "/select/#{field_name}/label"}
      },
      %{
        "id" => "#{base}_controls",
        "component" => "Row",
        "children" => ["#{base}_search_input", "#{base}_search_button"]
      }
    ] ++
      search_controls(base, to_string(field_name)) ++
      option_list(base, "/options/#{field_name}", %{
        "name" => "option_select",
        "context" => %{
          "field" => to_string(field_name),
          "value" => %{"path" => "value"}
        }
      })
  end

  # The shared search input + button pair: the button's `option_search`
  # context carries the current search text via a data binding and the
  # select/picker name as "field".
  defp search_controls(base, name) do
    [
      %{
        "id" => "#{base}_search_input",
        "component" => "TextField",
        "label" => "Search",
        "value" => %{"path" => "/select/#{name}/search"}
      },
      %{
        "id" => "#{base}_search_button",
        "component" => "Button",
        "child" => "#{base}_search_text",
        "action" => %{
          "event" => %{
            "name" => "option_search",
            "context" => %{
              "field" => name,
              "search" => %{"path" => "/select/#{name}/search"}
            }
          }
        }
      },
      %{"id" => "#{base}_search_text", "component" => "Text", "text" => "Search"}
    ]
  end

  # The option result List: templated over the options path, one Button per
  # option whose child Text binds the template-relative "label" and whose
  # event context carries the template-relative "value".
  defp option_list(base, options_path, event) do
    [
      %{
        "id" => "#{base}_options",
        "component" => "List",
        "children" => %{"componentId" => "#{base}_option_button", "path" => options_path}
      },
      %{
        "id" => "#{base}_option_button",
        "component" => "Button",
        "variant" => "borderless",
        "child" => "#{base}_option_text",
        "action" => %{"event" => event}
      },
      %{
        "id" => "#{base}_option_text",
        "component" => "Text",
        "text" => %{"path" => "label"}
      }
    ]
  end

  # --- contexts and details ---

  # A picker context renders as a surface-level composite mirroring the
  # searchable-select pattern: a Card (`context_<name>`, the root child)
  # over a `_body` Column holding a label, the current selection (bound to
  # /context/<name>/label) with a Clear button (`context_clear`), a search
  # TextField (bound to /context/<name>/search) with a Button dispatching
  # `context_search` when the context declares option_search, and a result
  # List templated over /options/<name> whose per-option Button dispatches
  # `context_select` with the template-relative option "value". Every
  # context action carries the current /context map (and /query state on
  # query-enabled surfaces) so the server cascades under the client's
  # active state. Pickerless contexts (`picker false`) emit nothing — they
  # are selected through a table's `select_context` button.
  defp context_picker_components(_view, %{picker: false}), do: []

  defp context_picker_components(view, context) do
    base = "context_#{context.name}"
    name = to_string(context.name)
    searchable? = context.search_fields != []

    # The section renders as a Card (keeping the frozen `context_<name>` id
    # root children reference) over a `_body` Column holding the composite —
    # card chrome for every renderer; enhanced catalogs (see
    # priv/js/ash_a2ui_catalog.js) upgrade the body to a combobox.
    card = %{
      "id" => base,
      "component" => "Card",
      "child" => "#{base}_body"
    }

    section = %{
      "id" => "#{base}_body",
      "component" => "Column",
      "children" =>
        ["#{base}_label", "#{base}_selected_row"] ++
          ((searchable? && ["#{base}_controls"]) || []) ++ ["#{base}_options"]
    }

    header = [
      card,
      section,
      %{
        "id" => "#{base}_label",
        "component" => "Text",
        "text" => context.label,
        "variant" => "h3"
      },
      %{
        "id" => "#{base}_selected_row",
        "component" => "Row",
        "children" => ["#{base}_selected", "#{base}_clear_button"]
      },
      %{
        "id" => "#{base}_selected",
        "component" => "Text",
        "text" => %{"path" => "/context/#{name}/label"}
      },
      %{
        "id" => "#{base}_clear_button",
        "component" => "Button",
        "variant" => "borderless",
        "child" => "#{base}_clear_text",
        "action" => %{
          "event" => %{
            "name" => "context_clear",
            "context" =>
              %{"context" => name}
              |> put_query_binding(view)
              |> put_contexts_binding(view)
          }
        }
      },
      %{"id" => "#{base}_clear_text", "component" => "Text", "text" => "Clear"}
    ]

    controls =
      if searchable? do
        [
          %{
            "id" => "#{base}_controls",
            "component" => "Row",
            "children" => ["#{base}_search_input", "#{base}_search_button"]
          },
          %{
            "id" => "#{base}_search_input",
            "component" => "TextField",
            "label" => "Search",
            "value" => %{"path" => "/context/#{name}/search"}
          },
          %{
            "id" => "#{base}_search_button",
            "component" => "Button",
            "child" => "#{base}_search_text",
            "action" => %{
              "event" => %{
                "name" => "context_search",
                "context" =>
                  %{
                    "context" => name,
                    "search" => %{"path" => "/context/#{name}/search"}
                  }
                  |> put_contexts_binding(view)
              }
            }
          },
          %{"id" => "#{base}_search_text", "component" => "Text", "text" => "Search"}
        ]
      else
        []
      end

    options =
      option_list(base, "/options/#{name}", %{
        "name" => "context_select",
        "context" =>
          %{
            "context" => name,
            "value" => %{"path" => "value"}
          }
          |> put_query_binding(view)
          |> put_contexts_binding(view)
      })

    header ++ controls ++ options
  end

  # A :detail component renders its context's selected record: a heading
  # and one label/value Row per field, each value Text bound to the
  # absolute /detail/<context>/<field> path (an unselected context renders
  # empty values — the server writes %{}).
  defp detail_components(view, detail) do
    base = "detail_#{detail.name}"

    field_rows =
      Enum.flat_map(detail.fields, fn field ->
        [
          %{
            "id" => "#{base}_field_#{field}",
            "component" => "Row",
            "children" => ["#{base}_label_#{field}", "#{base}_value_#{field}"]
          },
          %{
            "id" => "#{base}_label_#{field}",
            "component" => "Text",
            "text" => detail_field_label(view, field),
            "variant" => "h5"
          },
          %{
            "id" => "#{base}_value_#{field}",
            "component" => "Text",
            "text" => %{"path" => "/detail/#{detail.context}/#{field}"}
          }
        ]
      end)

    [
      %{
        "id" => base,
        "component" => "Card",
        "child" => "#{base}_body"
      },
      %{
        "id" => "#{base}_body",
        "component" => "Column",
        "children" => ["#{base}_heading" | Enum.map(detail.fields, &"#{base}_field_#{&1}")]
      },
      %{
        "id" => "#{base}_heading",
        "component" => "Text",
        "text" => humanize(detail.name),
        "variant" => "h3"
      }
      | field_rows
    ]
  end

  defp detail_field_label(view, field) do
    case view.fields[field] do
      %{label: label} when is_binary(label) -> label
      _undeclared -> humanize(field)
    end
  end

  # --- reports ---

  # A :report component renders as a Card (`report_<name>`, the root child)
  # over a Column: a heading, one TextField per param (bound to the reserved
  # /report/<name>/params/<param> path), a Run Button dispatching the
  # `"report"` action with the current params, and a result List templated
  # over /report/<name>/rows — each row a Row of caption-labeled cells, one
  # per declared field, bound template-relative to the row map's keys.
  defp report_components(view, report) do
    base = "report_#{report.name}"

    param_inputs =
      Enum.map(report.params, fn param ->
        %{
          "id" => "#{base}_param_#{param}",
          "component" => "TextField",
          "label" => report_field_label(view, param),
          "value" => %{"path" => "#{report.path}/params/#{param}"}
        }
      end)

    cells =
      Enum.flat_map(report.fields, fn field ->
        cell_base = "#{base}_cell_#{field}"

        [
          %{
            "id" => cell_base,
            "component" => "Row",
            "children" => ["#{cell_base}_label", "#{cell_base}_value"]
          },
          %{
            "id" => "#{cell_base}_label",
            "component" => "Text",
            "text" => report_field_label(view, field),
            "variant" => "caption"
          },
          %{
            "id" => "#{cell_base}_value",
            "component" => "Text",
            "text" => %{"path" => to_string(field)}
          }
        ]
      end)

    export_section =
      if report.export do
        export_components(view, report, "#{base}_export", %{
          "component" => to_string(report.name),
          "params" => %{"path" => "#{report.path}/params"}
        })
      else
        []
      end

    [
      %{"id" => base, "component" => "Card", "child" => "#{base}_body"},
      %{
        "id" => "#{base}_body",
        "component" => "Column",
        "children" =>
          ["#{base}_heading"] ++
            Enum.map(report.params, &"#{base}_param_#{&1}") ++
            ["#{base}_run_button", "#{base}_list"] ++
            ((report.export && ["#{base}_export_controls"]) || [])
      },
      %{
        "id" => "#{base}_heading",
        "component" => "Text",
        "text" => humanize(report.name),
        "variant" => "h3"
      },
      %{
        "id" => "#{base}_run_button",
        "component" => "Button",
        "child" => "#{base}_run_text",
        "action" => %{
          "event" => %{
            "name" => "report",
            "context" => %{
              "component" => to_string(report.name),
              "params" => %{"path" => "#{report.path}/params"}
            }
          }
        }
      },
      %{"id" => "#{base}_run_text", "component" => "Text", "text" => "Run"},
      %{
        "id" => "#{base}_list",
        "component" => "List",
        "children" => %{"componentId" => "#{base}_row", "path" => "#{report.path}/rows"}
      },
      %{
        "id" => "#{base}_row",
        "component" => "Card",
        "child" => "#{base}_row_content"
      },
      %{
        "id" => "#{base}_row_content",
        "component" => "Row",
        "children" => Enum.map(report.fields, &"#{base}_cell_#{&1}")
      }
    ] ++ param_inputs ++ cells ++ export_section
  end

  defp report_field_label(view, field) do
    case view.fields[field] do
      %{label: label} when is_binary(label) -> label
      _undeclared -> humanize(field)
    end
  end

  # --- CSV export (v1.0-only; see AshA2ui.Export) ---

  # A table's export controls: the section-level Row referenced from the
  # root children ("export<sfx>_controls"). The action context carries the
  # source component plus the table conventions (current query state,
  # active contexts) so the export honors what the user sees.
  defp table_export_components(_view, %{export: nil}, _sfx), do: []

  defp table_export_components(view, table, sfx) do
    context =
      %{"component" => to_string(table.name)}
      |> put_query_binding(view)
      |> put_contexts_binding(view)

    export_components(view, table, "export#{sfx}", context)
  end

  # The shared export chrome of a table or report: an optional CheckBox per
  # exportable column (bound to the reserved /export/<name>/columns/<field>
  # paths — the frozen column-selection state) and the Export CSV Button
  # dispatching the "export" client action. A successful export answers
  # with the frozen `downloadFile` callFunction (see AshA2ui.Export).
  defp export_components(view, component, base, context) do
    export = component.export

    checkboxes =
      if export.column_select do
        Enum.map(export.columns, fn column ->
          %{
            "id" => "#{base}_column_#{column}",
            "component" => "CheckBox",
            "label" => report_field_label(view, column),
            "value" => %{"path" => "/export/#{component.name}/columns/#{column}"}
          }
        end)
      else
        []
      end

    context =
      if export.column_select do
        Map.put(context, "columns", %{"path" => "/export/#{component.name}/columns"})
      else
        context
      end

    [
      %{
        "id" => "#{base}_controls",
        "component" => "Row",
        "align" => "center",
        "children" => Enum.map(checkboxes, & &1["id"]) ++ ["#{base}_button"]
      },
      %{
        "id" => "#{base}_button",
        "component" => "Button",
        "child" => "#{base}_button_text",
        "action" => %{"event" => %{"name" => "export", "context" => context}}
      },
      %{"id" => "#{base}_button_text", "component" => "Text", "text" => "Export CSV"}
    ] ++ checkboxes
  end

  # --- nested forms ---

  # One nested-form section per `nested_form` entity: a heading, the current
  # rows (a List templated over /form/<argument> — every row map carries the
  # server-generated "_row" key the remove button's context binds), and the
  # mode-specific add mechanism. All row mutations round-trip through the
  # stateless `nested_add` / `nested_remove` actions, whose contexts carry
  # the current rows via a {"path": "/form/<argument>"} binding; the server
  # rewrites the array wholesale.
  defp nested_form_components(view, nested, options) do
    base = "nested_#{nested.argument}"

    header = [
      %{
        "id" => "#{base}_heading",
        "component" => "Text",
        "text" => nested.label,
        "variant" => "h3"
      }
    ]

    case nested.mode do
      :create_inline ->
        [nested_section(base, ["#{base}_heading", "#{base}_rows", "#{base}_add_button"])] ++
          header ++
          nested_rows(base, nested, create_inline_row(view, nested, base)) ++
          nested_add_button(base, nested, %{
            "argument" => to_string(nested.argument),
            "rows" => %{"path" => "/form/#{nested.argument}"}
          })

      :pick_existing ->
        picker = pick_existing_picker(view, nested, base, options)

        [nested_section(base, ["#{base}_heading", "#{base}_rows" | picker.children])] ++
          header ++ nested_rows(base, nested, pick_existing_row(base)) ++ picker.components
    end
  end

  defp nested_section(base, children) do
    %{"id" => base, "component" => "Column", "children" => children}
  end

  defp nested_rows(base, nested, {row_children, row_components}) do
    [
      %{
        "id" => "#{base}_rows",
        "component" => "List",
        "children" => %{"componentId" => "#{base}_row", "path" => "/form/#{nested.argument}"}
      },
      %{"id" => "#{base}_row", "component" => "Row", "children" => row_children}
    ] ++ row_components ++ nested_remove_button(base, nested)
  end

  # create_inline rows: one widget-mapped input per nested field bound to the
  # template-relative field path (conforming renderers resolve it to the
  # index-addressed /form/<argument>/<index>/<field> for two-way binding),
  # plus a per-field error Text bound to the row's "_error_<field>" mirror.
  defp create_inline_row(_view, nested, base) do
    children =
      Enum.flat_map(nested.fields, fn field ->
        ["#{base}_input_#{field}", "#{base}_row_error_#{field}"]
      end) ++ ["#{base}_remove_button"]

    inputs = Enum.map(nested.fields, &nested_input(nested, base, &1))

    errors =
      Enum.map(nested.fields, fn field ->
        %{
          "id" => "#{base}_row_error_#{field}",
          "component" => "Text",
          "text" => %{"path" => "_error_#{field}"},
          "variant" => "caption"
        }
      end)

    {children, inputs ++ errors}
  end

  defp pick_existing_row(base) do
    {
      ["#{base}_row_label", "#{base}_remove_button"],
      [
        %{
          "id" => "#{base}_row_label",
          "component" => "Text",
          "text" => %{"path" => "label"}
        }
      ]
    }
  end

  # The pick_existing add mechanism: with option_search a search input +
  # result List whose option Buttons dispatch `nested_add` directly with the
  # template-relative option "value"; without one a ChoicePicker of the
  # loaded options (inline, limit-capped — the v0.9.1 constraint) bound to
  # /select/<argument>/picked plus an Add button carrying that binding.
  defp pick_existing_picker(_view, %{search_fields: [_ | _]} = nested, base, _options) do
    name = to_string(nested.argument)

    %{
      children: ["#{base}_controls", "#{base}_options"],
      components:
        [
          %{
            "id" => "#{base}_controls",
            "component" => "Row",
            "children" => ["#{base}_search_input", "#{base}_search_button"]
          }
        ] ++
          search_controls(base, name) ++
          option_list(base, "/options/#{nested.argument}", %{
            "name" => "nested_add",
            "context" => %{
              "argument" => name,
              "value" => %{"path" => "value"},
              "rows" => %{"path" => "/form/#{nested.argument}"}
            }
          })
    }
  end

  defp pick_existing_picker(_view, nested, base, options) do
    picker = %{
      "id" => "#{base}_picker",
      "component" => "ChoicePicker",
      "label" => "Add",
      "variant" => "mutuallyExclusive",
      "value" => %{"path" => "/select/#{nested.argument}/picked"},
      "options" => Map.fetch!(options, nested.argument)
    }

    %{
      children: ["#{base}_picker", "#{base}_add_button"],
      components:
        [picker] ++
          nested_add_button(base, nested, %{
            "argument" => to_string(nested.argument),
            "value" => %{"path" => "/select/#{nested.argument}/picked"},
            "rows" => %{"path" => "/form/#{nested.argument}"}
          })
    }
  end

  defp nested_add_button(base, _nested, context) do
    [
      %{
        "id" => "#{base}_add_button",
        "component" => "Button",
        "child" => "#{base}_add_text",
        "action" => %{"event" => %{"name" => "nested_add", "context" => context}}
      },
      %{"id" => "#{base}_add_text", "component" => "Text", "text" => "Add"}
    ]
  end

  defp nested_remove_button(base, nested) do
    [
      %{
        "id" => "#{base}_remove_button",
        "component" => "Button",
        "child" => "#{base}_remove_text",
        "action" => %{
          "event" => %{
            "name" => "nested_remove",
            "context" => %{
              "argument" => to_string(nested.argument),
              "row" => %{"path" => "_row"},
              "rows" => %{"path" => "/form/#{nested.argument}"}
            }
          }
        }
      },
      %{"id" => "#{base}_remove_text", "component" => "Text", "text" => "Remove"}
    ]
  end

  # Nested inputs widget-map against the *destination* resource's attribute
  # types (the parent surface's field entities don't apply inside rows).
  defp nested_input(nested, base, field) do
    binding = %{"path" => to_string(field)}
    label = humanize(field)
    id = "#{base}_input_#{field}"
    base_props = %{"id" => id, "label" => label, "value" => binding}

    type = attribute_type(nested.destination, field)
    constraints = attribute_constraints(nested.destination, field)

    case AshA2ui.TypeMapper.widget_for(type || Ash.Type.String, constraints) do
      :check_box ->
        Map.put(base_props, "component", "CheckBox")

      :choice_picker ->
        base_props
        |> Map.put("component", "ChoicePicker")
        |> Map.put("variant", "mutuallyExclusive")
        |> Map.put("options", choice_options(nested.destination, field))

      :date_time_input ->
        base_props
        |> Map.put("component", "DateTimeInput")
        |> Map.put("enableDate", true)
        |> Map.put("enableTime", not date_only?(nested.destination, field))

      _text_field ->
        text_field = Map.put(base_props, "component", "TextField")

        if numeric?(nested.destination, field) do
          Map.put(text_field, "variant", "number")
        else
          text_field
        end
    end
  end

  defp form_input(view, field_name, options) do
    field = view.fields[field_name]
    binding = %{"path" => "/form/#{field_name}"}

    base = %{"id" => "form_input_#{field_name}", "label" => field.label, "value" => binding}

    case field.widget do
      :check_box ->
        Map.put(base, "component", "CheckBox")

      :choice_picker ->
        base
        |> Map.put("component", "ChoicePicker")
        |> Map.put("variant", "mutuallyExclusive")
        |> Map.put("options", picker_options(view, field_name, options))

      :date_time_input ->
        base
        |> Map.put("component", "DateTimeInput")
        |> Map.put("enableDate", true)
        |> Map.put("enableTime", not date_only?(view.resource, field_name))

      _text_field ->
        text_field = Map.put(base, "component", "TextField")

        if numeric?(view.resource, field_name) do
          Map.put(text_field, "variant", "number")
        else
          text_field
        end
    end
  end

  defp form_error(field_name) do
    %{
      "id" => "form_error_#{field_name}",
      "component" => "Text",
      "text" => %{"path" => "/errors/#{field_name}"},
      "variant" => "caption"
    }
  end

  # Relationship selects use the loaded option list; enum-constrained
  # attributes keep their static `one_of` options. The v0.9.1 basic-catalog
  # ChoicePicker only accepts a literal options array (each option's `value`
  # is a plain string, no data binding), so loaded options are emitted inline
  # here and mirrored at /options/<field> in the data model.
  defp picker_options(view, field_name, options) do
    if Map.has_key?(view.selects, field_name) do
      Map.fetch!(options, field_name)
    else
      choice_options(view.resource, field_name)
    end
  end

  defp choice_options(resource, field_name) do
    resource
    |> AshA2ui.TypeMapper.choices(field_name)
    |> Enum.map(fn {value, label} -> %{"label" => label, "value" => to_string(value)} end)
  end

  defp numeric?(resource, field_name),
    do: attribute_type(resource, field_name) in @numeric_types

  defp date_only?(resource, field_name),
    do: attribute_type(resource, field_name) == Ash.Type.Date

  # Filterable fields may be attributes or (expression-backed) calculations;
  # both carry a type + constraints for picker options and variants.
  defp attribute_type(resource, field_name) do
    case ResourceInfo.attribute(resource, field_name) ||
           ResourceInfo.calculation(resource, field_name) do
      %{type: type} -> Ash.Type.get_type(type)
      nil -> nil
    end
  end

  defp attribute_constraints(resource, field_name) do
    case ResourceInfo.attribute(resource, field_name) ||
           ResourceInfo.calculation(resource, field_name) do
      %{constraints: constraints} when is_list(constraints) -> constraints
      _ -> []
    end
  end

  # --- /query state ---

  # The initial data model carries the query state under "query": the single
  # table's state map, or (multi-table) an object keyed by table component
  # name covering every query-attached table. Callers that ran the queries
  # (AshA2ui.Info) pass the real state via `:query_state`; direct encoder
  # calls fall back to the declared defaults with counts derived from the
  # records at hand. Omitted entirely when no table declares a query.
  defp put_query_state(value, view, opts) do
    query_tables = Enum.filter(view.tables, & &1.query)

    cond do
      query_tables == [] ->
        value

      ResolvedView.multi_table?(view) ->
        states = Keyword.get(opts, :query_state) || %{}

        Map.put(
          value,
          "query",
          Map.new(query_tables, fn table ->
            rows = value["records"][to_string(table.name)] || []
            {to_string(table.name), Map.get(states, table.name) || default_state(table, rows)}
          end)
        )

      true ->
        state =
          Keyword.get(opts, :query_state) || default_state(hd(query_tables), value["records"])

        Map.put(value, "query", state)
    end
  end

  defp default_state(table, records) do
    AshA2ui.QueryRunner.state(
      table.query,
      AshA2ui.QueryRunner.default_params(table.query),
      length(records),
      false
    )
  end

  # The reserved /prompt state: one empty values map per prompt-enabled row
  # action, so the Modal inputs always have a bindable path. Omitted
  # entirely on surfaces without prompts (frozen shape unchanged).
  defp put_prompt_state(value, view) do
    prompt_values =
      for {name, %{prompt_fields: [_ | _] = fields}} <- view.actions, into: %{} do
        {to_string(name), Map.new(fields, &{to_string(&1), ""})}
      end

    if prompt_values == %{} do
      value
    else
      Map.put(value, "prompt", %{"values" => prompt_values})
    end
  end

  # The reserved /ui/wizard state (step 0) — only on surfaces whose form
  # declares steps (frozen shape unchanged everywhere else).
  defp put_wizard_state(value, view) do
    if AshA2ui.Wizard.stepped?(view) do
      Map.update!(value, "ui", &Map.put(&1, "wizard", AshA2ui.Wizard.state(view, 0)))
    else
      value
    end
  end

  # --- experience v2 state ---

  # The experience v2 additions to the initial data model (a no-op under v1
  # — the frozen shape is untouched): the `/ui` task-mode region (intent /
  # panel / feedback, see AshA2ui.Experience), per-table empty-state
  # sentinels, and the pagination sentinels on every query state. Sentinels
  # are re-derived from the rows at hand, so explicit `:query_state` opts
  # (states carried from the client) are adorned the same way.
  defp put_experience_state(value, view) do
    if AshA2ui.Experience.v2?() do
      value
      |> Map.update!("ui", &Map.merge(&1, AshA2ui.Experience.ui_data(view)))
      |> put_empty_state(view)
      |> put_pagination_sentinels(view)
    else
      value
    end
  end

  defp put_empty_state(value, view) do
    Enum.reduce(view.tables, value, fn table, acc ->
      sfx = table_suffix(view, table)
      rows = rows_at(value, view, table)

      acc
      |> Map.put("_empty_visible#{sfx}", AshA2ui.Experience.sentinel(rows == []))
      |> Map.put("_empty_message#{sfx}", AshA2ui.Experience.empty_message(view, table))
    end)
  end

  defp put_pagination_sentinels(value, view) do
    query_tables = Enum.filter(view.tables, & &1.query)

    cond do
      query_tables == [] ->
        value

      ResolvedView.multi_table?(view) ->
        Map.update!(value, "query", fn states ->
          Map.new(states, &adorned_table_state(&1, value, view, query_tables))
        end)

      true ->
        [single] = query_tables

        Map.update!(
          value,
          "query",
          &adorned_query_state(&1, value |> rows_at(view, single) |> length())
        )
    end
  end

  # The v2 sentinels plus — when the admin emission is effective — the
  # plain boolean pagination props the semantic Pagination component binds.
  # Both adornments are gated no-ops outside their mode, so v1 and v2-basic
  # query states are unchanged.
  defp adorned_query_state(state, count) do
    state
    |> AshA2ui.Experience.with_pagination_sentinels(count)
    |> AshA2ui.Experience.with_admin_pagination_booleans(count)
  end

  defp adorned_table_state({name, state}, value, view, query_tables) do
    table = Enum.find(query_tables, &(to_string(&1.name) == name))
    count = value |> rows_at(view, table) |> length()

    {name, adorned_query_state(state, count)}
  end

  defp rows_at(value, view, table) do
    if ResolvedView.multi_table?(view) do
      value["records"][to_string(table.name)] || []
    else
      value["records"] || []
    end
  end

  # Board lanes carry their total at the reserved /_lane_total_<lane> path
  # (see AshA2ui.Board); a no-op on surfaces without boards.
  defp put_lane_totals(value, view) do
    view.tables
    |> Enum.filter(&AshA2ui.Board.lane?/1)
    |> Enum.reduce(value, fn table, acc ->
      rows = rows_at(value, view, table)
      state = table.query && get_in(value, ["query", to_string(table.name)])

      Map.put(acc, "_lane_total_#{table.name}", AshA2ui.Board.total_text(length(rows), state))
    end)
  end

  # --- record serialization ---

  defp serialize_record(view, table, record, links) do
    field_names =
      case table do
        %{component: %{fields: fields}} -> fields
        nil -> view.fields |> Map.values() |> Enum.reject(& &1.hidden) |> Enum.map(& &1.name)
      end

    row =
      [:id | field_names]
      |> Enum.uniq()
      |> Map.new(fn name -> {to_string(name), field_value(view, record, name)} end)

    row
    |> Map.merge((table && AshA2ui.Conditions.row_visibility(view, table, record)) || %{})
    |> Map.merge(AshA2ui.RowLayout.badge_data(table && table.component.row_layout, record))
    |> Map.merge(AshA2ui.Links.row_data(links, record, row))
    |> Map.merge(AshA2ui.Bulk.row_data(table))
  end

  # `source` columns read through the loaded relationship path (nil-safe: a
  # nil or unloaded relationship serializes to ""); plain fields read the
  # record key directly.
  defp field_value(view, record, name) do
    case view.fields[name] do
      %{source: [_ | _] = source} ->
        record |> walk_source(source) |> source_safe()

      field ->
        case AshA2ui.Links.virtual_value(field, record) do
          {:ok, value} ->
            value

          :not_virtual ->
            # The record's own resource: a related table's rows are not the surface's.
            record |> Map.get(name) |> json_safe() |> humanize_choice(record.__struct__, name)
        end
    end
  end

  # An enum reaches the wire as its bare atom name, so a grid cell read
  # `direct_user_and_team` while the form picker for the SAME field, on the same
  # surface, read "Direct user and team" -- `choice_options/2` has always
  # labelled these. This is that treatment on the display side: one vocabulary
  # per field rather than two.
  #
  # `Ash.Type.Enum.label/1` first, so an enum that declares its own words keeps
  # them; humanized underscores otherwise. Only values the field actually
  # declares are rewritten, so anything unrecognised passes through untouched
  # rather than being mangled by a guess.
  defp humanize_choice(value, resource, name) when is_binary(value) do
    case choice_labels(resource, name) do
      %{^value => label} -> label
      _ -> value
    end
  end

  defp humanize_choice(value, _resource, _name), do: value

  defp choice_labels(resource, name) do
    resource
    |> AshA2ui.TypeMapper.choices(name)
    |> Map.new(fn {value, label} -> {to_string(value), label} end)
  end

  defp walk_source(record, [attribute]), do: Map.get(record, attribute)

  defp walk_source(record, [relationship | rest]) do
    case Map.get(record, relationship) do
      %Ash.NotLoaded{} -> nil
      nil -> nil
      related -> walk_source(related, rest)
    end
  end

  defp source_safe(nil), do: ""
  defp source_safe(value), do: json_safe(value)

  # A calculation/aggregate that slipped past `loads` must not leak an
  # inspect()-ed struct onto the wire.
  defp json_safe(%Ash.NotLoaded{}), do: nil
  defp json_safe(%Ash.CiString{} = ci), do: to_string(ci)
  defp json_safe(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  defp json_safe(%Date{} = date), do: Date.to_iso8601(date)
  defp json_safe(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp json_safe(%NaiveDateTime{} = naive), do: NaiveDateTime.to_iso8601(naive)
  defp json_safe(%Time{} = time), do: Time.to_iso8601(time)

  defp json_safe(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: to_string(value)

  # A struct whose type has no Jason implementation (a MapSet from a custom
  # Ash type, a value type a host lib introduced...) and any tuple (an
  # Ash.Type.Tuple value) cannot reach the JSON wire. Rather than crashing
  # the transport with a Jason.EncodeError — or silently vanishing — render
  # a readable placeholder naming the type, so the surface author can pick a
  # renderable field or add a Jason implementation. (Jason's fallback Any
  # implementation is exactly the one that raises for unimplemented structs,
  # so an explicit implementation — derived or hand-written — is honored.)
  # Nested positions inside maps/lists are not walked: those shapes are the
  # reserved-path contract.
  defp json_safe(value) when is_struct(value) do
    if Jason.Encoder.impl_for(value) == Jason.Encoder.Any do
      unsupported_type(value)
    else
      value
    end
  end

  defp json_safe(value) when is_tuple(value), do: unsupported_type(value)

  defp json_safe(value), do: value

  defp unsupported_type(value) when is_struct(value),
    do: "unsupported type: #{value.__struct__ |> Module.split() |> List.last()}"

  defp unsupported_type(_value), do: "unsupported type: tuple"

  defp humanize_resource(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> humanize()
  end

  defp humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
