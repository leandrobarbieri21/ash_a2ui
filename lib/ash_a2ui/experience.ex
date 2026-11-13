defmodule AshA2ui.Experience do
  @moduledoc """
  The experience layer: explicit task modes (browse / create / view / edit),
  conditional pagination, semantic action labels, typed feedback, and
  data-driven empty states. This is how every ash_a2ui surface composes; there
  is no version switch.

  ## The /ui reserved state

  The initial data model's `"ui"` region holds:

    * `"intent"` — the client-facing task intent: `"browse"`, `"create"`,
      `"view"`, or `"edit"`.
    * `"panel"` — the record task panel: `"visible"`, `"submit_visible"`,
      `"form_visible"` and `"view_visible"` are zero-or-one visibility
      sentinels (`[]` hidden, one item visible — the exact technique the
      row-action `visible_when` slots use, see `AshA2ui.Conditions`),
      plus `"mode"`, `"title"`, `"primary_label"`, and `"record_id"`.
    * `"feedback"` — the outcome of the last action, one map written whole
      (see `feedback/3`): `"kind"`, `"message"`, `"code"`,
      `"functionCallId"`, `"result"` and `"resultText"`.
    * `"feedback_text"` — the words a renderer writes into `"feedback"`
      itself, in the surface's language: `"pending"` (shown the moment an
      `ashAction` call goes out) and `"slow"` (shown when the call has not
      been answered in time; the call is still pending).

  ## The task state machine

  The panel is a three-mode machine over the record buffer:

    * **browse** (the start state) — the panel is closed, `/form` is empty,
      no population happens. Nothing about a row is rendered into the panel.
    * **create** (`"start_create"`, gated on a declared create action) —
      the panel opens over a fresh `/form`; the editable form shows
      (`form_visible`), the submit (create label) and Cancel show.
    * **view** (`"view_record"`) — READ-ONLY: the record is rendered as a
      derived display bound to `/ui/panel/record/<field>` (`view_visible`),
      **`/form` is never written**, no submit is offered, and Cancel is the
      exit. Viewing no longer means "edit minus the save button".
    * **edit** (`"start_edit"`, gated on a **declared** `update_action`) —
      the explicit transition onto the form buffer: `/form` is populated,
      the editable form shows, and the save/cancel pair appears together
      (`submit_visible` + Cancel). The handler rejects `start_edit` on
      surfaces with no declared update action (the encoder never offers the
      affordance there either).
    * **save/cancel pair, mode-gated** — the submit and Cancel appear
      together only in create/edit; view offers only Cancel; browse
      neither (the panel itself is hidden).

  `"cancel_record_task"` returns to browse from any mode: panel closed,
  `/form` and `/errors` reset, feedback cleared.

  ## Query-state sentinels

  Every `/query` state (initial and refreshed) carries
  `"_pagination_visible"`, `"_previous_visible"`, `"_next_visible"` (the
  zero-or-one sentinels the pagination row and its prev/next buttons are
  templated over) and `"_range_text"` (the result-range text, e.g.
  `"1–5 of 42"` / `"Showing 1–5"`). See `pagination_state/2`.

  ## Per-table empty-state sentinels

  The data model carries `"_empty_visible"` (`"_empty_visible_<table>"` on
  multi-table surfaces) — the same sentinel shape, `[]` while records exist —
  and `"_empty_message"` with the humanized "No <resource> records yet."
  text. Every records rewrite refreshes the sentinel, so the empty state
  toggles with the data.

  ## Task-panel client actions

    * `"start_create"` — open the panel in create mode over a fresh `/form`.
    * `"view_record"` — authorized read rendered into the read-only
      `/ui/panel/record` display (no submit offered, `/form` untouched).
    * `"start_edit"` — authorized read + `/form` population in edit mode
      ("Save changes" submit).
    * `"cancel_record_task"` — back to browse, form reset, feedback cleared.
  """

  import AshA2ui.Gettext, only: [msg: 1]

  alias AshA2ui.L10n
  alias AshA2ui.Label
  alias AshA2ui.ResolvedView

  @typedoc "The record task panel modes (`:hidden` for the closed state)."
  @type mode :: :create | :view | :edit | :hidden

  @admin_catalog_id "https://github.com/lukegalea/ash_a2ui/catalogs/admin/v2"
  @feedback_kinds ["", "pending", "success", "warning", "error"]

  @doc """
  The configured component catalog: `:basic` (default) or `:admin_v1`
  (the semantic admin catalog, see `priv/a2ui/admin_v1/catalog.json` and
  `notes/2026-09-07-admin-catalog-contract.md`).
  """
  @spec catalog() :: :basic | :admin_v1
  def catalog, do: Application.get_env(:ash_a2ui, :catalog, :basic)

  @doc """
  Whether the admin catalog is selected — the admin emission is active
  exactly when this is true (a surface the admin composition cannot carry
  still falls back to basic per component; see the contract note).
  """
  @spec admin?() :: boolean
  def admin?, do: catalog() == :admin_v1

  @doc """
  Whether `view` is encoded with the admin catalog: the catalog its resolve
  chose (the `:catalog` build option), else the configured `catalog/0`.
  """
  @spec admin?(ResolvedView.t()) :: boolean
  def admin?(%ResolvedView{catalog: nil}), do: admin?()
  def admin?(%ResolvedView{catalog: catalog}), do: catalog == :admin_v1

  @doc """
  The catalog to build a surface with for a renderer that sent its A2UI
  renderer capabilities (the `priv/a2ui/v1_0/json/renderer_capabilities.json`
  shape, `%{"1.0" => %{"supportedCatalogIds" => [...]}}`): pass the result
  as the `:catalog` option of `AshA2ui.Info.build_surface/2`,
  `AshA2ui.Dynamic.build_surface/2` and `AshA2ui.ActionHandler.handle/3`.

  Every surface needs the basic catalog and the ash_a2ui catalog
  (`AshA2ui.Encoder.ash_catalog_id/0`, which declares the `ashAction`
  function every server-handled action calls); an admin surface needs the
  admin catalog too.

    * `{:ok, :admin_v1}` — the configured catalog is `:admin_v1` and the
      renderer lists the basic, ash_a2ui and admin catalog ids.
    * `{:ok, :basic}` — otherwise, when the renderer lists the basic and
      ash_a2ui catalog ids. This is the fallback for a renderer without
      the admin catalog.
    * `{:error, :no_common_catalog}` — the renderer lacks the basic or the
      ash_a2ui catalog, or sent capabilities without a `supportedCatalogIds`
      list. No surface this library builds can be rendered there; what the
      renderer gets instead is the host's choice (text, a link).

  `nil` (the client sent no capabilities: no negotiation took place) is the
  configured `catalog/0`, so hosts that never pass capabilities see no
  change. Inline catalogs are not accepted.
  """
  @spec catalog_for(map | nil) :: {:ok, :basic | :admin_v1} | {:error, :no_common_catalog}
  def catalog_for(nil), do: {:ok, catalog()}

  def catalog_for(%{"1.0" => %{"supportedCatalogIds" => ids}}) when is_list(ids) do
    base? = AshA2ui.Encoder.basic_catalog_id() in ids and AshA2ui.Encoder.ash_catalog_id() in ids

    cond do
      base? and catalog() == :admin_v1 and @admin_catalog_id in ids -> {:ok, :admin_v1}
      base? -> {:ok, :basic}
      true -> {:error, :no_common_catalog}
    end
  end

  def catalog_for(_other), do: {:error, :no_common_catalog}

  @doc false
  # The admin catalog id emitted on createSurface when the admin emission
  # is active (see notes/2026-09-07-admin-catalog-contract.md).
  def admin_catalog_id, do: @admin_catalog_id

  @doc """
  The admin catalog contract version (`metadata.extensions.ash_a2ui.version`
  in `priv/a2ui/admin_v1/catalog.json`). 2.0 is the A2UI 1.0 wire: the new
  `admin_catalog_id/0`, `@path`/`@call` bindings, envelopes sent as
  `ashAction`, and the `filterPicker` component. Minor versions are additive
  within one catalog id — 1.1 added the column presentation hints
  (format/align/mono/badge/link), `rowClick`, FieldDisplay `link` and the
  `openSurface` client function; 1.2 added the `rowActions` entries'
  `visiblePath` (per-row `visible_when`) and `prompt` (prompt dialogs);
  1.7 added sortable headers (column `sortable`, the dataGrid's `sort`);
  1.10 added column `help` and `sortField`, the detail line's `helpPath`,
  pagination page sizes and the extended ChoicePicker/TextField keys;
  1.13 added plain links (`{href, label}` with no surface); 1.14 added
  grouped list rows (column placements `group`/`groupSubtitle`, the
  dataGrid's `groupIcon`, column `emptyText`); 1.15 added document rows
  (the `leading` placement) and table footers (`footerNote`, `footerLink`);
  1.16 added card rows (`layout: "cards"`), the `expandLabel` disclosure
  label and labeled `pairs` columns; 1.17 added the fieldDisplay `steps`
  stepper; 1.18 added a table card's own `heading` and `description`. 2.0
  includes every 1.x addition.
  """
  @spec admin_catalog_version() :: String.t()
  def admin_catalog_version, do: "2.0.0"

  @doc """
  The zero-or-one visibility sentinel value: `[]` (hidden) or a one-item
  list (visible) — the exact shape the row-action `visible_when` slots bind
  (see `AshA2ui.Conditions.row_visibility/3`).
  """
  @spec sentinel(boolean) :: list
  def sentinel(true), do: [%{"id" => "on"}]
  def sentinel(false), do: []

  @doc """
  The initial `/ui/*` state as a flat `%{path => value}` map (paths keyed
  exactly like the `updateDataModel` writes the action handler emits).
  `/ui/panel/visible` and every mode sentinel hold the hidden value — a
  fresh surface is in browse mode with the record panel closed.
  """
  @spec initial_ui_state(ResolvedView.t()) :: %{String.t() => term}
  def initial_ui_state(view) do
    %{
      "/ui/intent" => "browse",
      "/ui/panel/visible" => sentinel(false),
      "/ui/panel/mode" => nil,
      "/ui/panel/title" => "",
      "/ui/panel/primary_label" => "",
      "/ui/panel/record_id" => nil,
      "/ui/panel/submit_visible" => sentinel(false),
      "/ui/panel/form_visible" => sentinel(false),
      "/ui/panel/view_visible" => sentinel(false),
      "/ui/feedback" => clear_feedback(),
      "/ui/feedback_text/pending" => L10n.t(view.l10n, msg("Working…")),
      "/ui/feedback_text/slow" =>
        L10n.t(view.l10n, msg("This is taking longer than usual. Still working…"))
    }
  end

  @doc false
  # The initial state nested under the data model's `"ui"` key (the flat
  # `initial_ui_state/1` map is the single source of truth).
  def ui_data(view) do
    Enum.reduce(initial_ui_state(view), %{}, fn {path, value}, acc ->
      ["ui" | segments] = path |> String.trim_leading("/") |> String.split("/")
      put_in_segments(acc, segments, value)
    end)
  end

  defp put_in_segments(map, [key], value), do: Map.put(map, key, value)

  defp put_in_segments(map, [key | rest], value) do
    Map.update(map, key, put_in_segments(%{}, rest, value), &put_in_segments(&1, rest, value))
  end

  @doc """
  The create affordance / create-task label: `"Create " <> humanized
  resource name` (e.g. `"Create Appointment"`).
  """
  @spec create_label(ResolvedView.t()) :: String.t()
  def create_label(view),
    do: L10n.t(view.l10n, msg("Create %{resource}"), resource: resource_label(view))

  @doc """
  The edit-task primary button label, translated with `l10n` (see
  `AshA2ui.L10n`).
  """
  @spec save_changes_label(L10n.t()) :: String.t()
  def save_changes_label(l10n \\ nil), do: L10n.t(l10n, msg("Save changes"))

  @doc """
  The panel heading for `mode` (`:create` / `:view` / `:edit`), e.g.
  `"Edit Appointment"`.
  """
  @spec panel_title(:create | :view | :edit, ResolvedView.t()) :: String.t()
  def panel_title(:create, view), do: create_label(view)

  def panel_title(:view, view),
    do: L10n.t(view.l10n, msg("View %{resource}"), resource: resource_label(view))

  def panel_title(:edit, view),
    do: L10n.t(view.l10n, msg("Edit %{resource}"), resource: resource_label(view))

  @doc """
  The surface's heading — what the page is a page *of*.

  The view's declared `title` when it has one, and otherwise the derived
  resource label. The distinction matters because the derived name is the
  module's, not the reader's: a surface over `Legacy.User` is a list of users
  belonging to another application's estate, and heading it "User" is both
  singular and wrong about whose users they are. Hosts usually already have the
  right words in their own navigation; `title` is how they say so.
  """
  @spec surface_title(ResolvedView.t()) :: String.t()
  def surface_title(%{title: title} = view) when is_binary(title) and title != "",
    do: Label.translate(view.l10n, title)

  def surface_title(view), do: resource_label(view)

  @doc """
  The singular noun for one record, used by the derived task labels.

  The view's declared `record_label` when it has one, else the humanized
  resource short name (e.g. `"Appointment"`).
  """
  @spec resource_label(ResolvedView.t()) :: String.t()
  def resource_label(%{record_label: label} = view) when is_binary(label) and label != "",
    do: Label.translate(view.l10n, label)

  def resource_label(view), do: Label.translate(view.l10n, Label.resource_name(view.resource))

  @doc """
  The per-table empty-state text (e.g. `"No Appointment records yet."`).
  """
  @spec empty_message(ResolvedView.t(), ResolvedView.table()) :: String.t()
  def empty_message(view, table) do
    # A section (a board lane or a sectioned table) is headed by its value
    # already; its empty state names the records ("No Task records yet."),
    # not the runtime section name ("By status archived").
    resource =
      if Map.get(table, :section),
        do: resource_label(view),
        else: collection_label(view, table)

    L10n.t(view.l10n, msg("No %{resource} records yet."), resource: resource)
  end

  @doc false
  # The humanized collection name for a table: the resource label on
  # single-table surfaces, the humanized table component name on
  # multi-table surfaces (same scheme as the section headings).
  @spec collection_label(ResolvedView.t(), ResolvedView.table()) :: String.t()
  def collection_label(view, table) do
    cond do
      ResolvedView.multi_table?(view) -> component_label(view, table.component, table.name)
      # A declared label heads a lone table too; without one it keeps the
      # resource name (frozen).
      table.component.label -> component_label(view, table.component, table.name)
      true -> resource_label(view)
    end
  end

  @doc false
  # A section's heading: the component's declared `label`, else its humanized
  # name (`name` is the table's or card's runtime key), translated in the
  # metadata domain either way.
  def component_label(view, component, name),
    do: Label.resolve(view.l10n, component && component.label, name)

  @doc false
  # The root data-model path of a table's `_empty_visible` sentinel
  # (unsuffixed on single-table surfaces, `_<table>`-suffixed on
  # multi-table surfaces — the same scheme as the component ids).
  def empty_visible_path(view, table) do
    if ResolvedView.multi_table?(view) do
      "/_empty_visible_#{table.name}"
    else
      "/_empty_visible"
    end
  end

  @doc """
  The `/ui/panel` value for the task panel in `mode`:

    * `:hidden` — the closed state (empty sentinels, everything blank).
    * `:create` — visible, editable form showing (`form_visible`), primary
      label = `create_label/1`.
    * `:view` — visible, the read-only record display showing
      (`view_visible`), no primary label, no submit — Cancel is the exit.
    * `:edit` — visible, editable form showing, primary label =
      `save_changes_label/0` — the save/cancel pair together.

  Only `form_visible`/`view_visible` ever differ from the submit gate: the
  panel content is either the editable form (create/edit) or the derived
  read-only display (view), never both.

  On a stepped form (see `AshA2ui.Wizard`) `step_index` is the current step:
  before the last step the create/edit primary label reads `"Next"` and the
  submit stays hidden (the wizard's Next button binds the label); on the
  last step both are the usual create/edit values. Without steps
  `step_index` is ignored.
  """
  @spec panel_state(mode, ResolvedView.t(), term, non_neg_integer) :: map
  def panel_state(:hidden) do
    %{
      "visible" => sentinel(false),
      "mode" => nil,
      "title" => "",
      "primary_label" => "",
      "record_id" => nil,
      "submit_visible" => sentinel(false),
      "form_visible" => sentinel(false),
      "view_visible" => sentinel(false)
    }
  end

  def panel_state(mode, view, record_id, step_index \\ 0)
      when mode in [:create, :view, :edit] do
    next_step? = mode != :view and AshA2ui.Wizard.before_last_step?(view, step_index)

    primary_label =
      case mode do
        _form_mode when next_step? -> AshA2ui.Wizard.next_label(view.l10n)
        :create -> create_label(view)
        :edit -> save_changes_label(view.l10n)
        :view -> ""
      end

    %{
      "visible" => sentinel(true),
      "mode" => to_string(mode),
      "title" => panel_title(mode, view),
      "primary_label" => primary_label,
      "record_id" => (record_id && to_string(record_id)) || nil,
      "submit_visible" => sentinel(primary_label != "" and not next_step?),
      "form_visible" => sentinel(mode in [:create, :edit]),
      "view_visible" => sentinel(mode == :view)
    }
  end

  @doc """
  The `/ui/feedback` value: the outcome of the last action, always written
  whole so no field of an earlier outcome survives.

      %{
        "kind" => kind,
        "message" => message,
        "code" => "",
        "functionCallId" => "",
        "result" => %{},
        "resultText" => ""
      }

  `kind` is `""` (idle), `"pending"` (written by the renderer while an
  `ashAction` call is in flight; with `"code" => "TIMEOUT"` once the call
  has gone unanswered past the renderer's watchdog), `"success"`, `"warning"` (a bulk run that
  partly succeeded) or `"error"`. `extra` sets any of the other keys:
  `"code"` (the error code, `""` otherwise), `"functionCallId"` (the
  `ashAction` call the outcome answers), `"result"` and `"resultText"` (a
  map-returning generic action's result and its display text).
  """
  @spec feedback(String.t(), String.t(), map) :: map
  def feedback(kind, message \\ "", extra \\ %{})
      when kind in @feedback_kinds and is_binary(message) and is_map(extra) do
    extra = Map.take(extra, ["code", "functionCallId", "result", "resultText"])

    %{
      "kind" => kind,
      "message" => message,
      "code" => "",
      "functionCallId" => "",
      "result" => %{},
      "resultText" => ""
    }
    |> Map.merge(extra)
  end

  @doc "The idle `/ui/feedback` value (see `feedback/3`)."
  @spec clear_feedback() :: map
  def clear_feedback, do: feedback("")

  @doc """
  The pagination visibility/range state derived from a `/query` state map
  (string-keyed, as built by `AshA2ui.QueryRunner.state/4`):

    * `visible?` — the pagination row shows when paging back is possible
      (`page > 1`) or there are further records (`hasMore`).
    * `previous?` / `next?` — the individual affordances.
    * `range_text` — with a `totalCount` present: `"<first>–<last> of
      <total>"`; otherwise `"Showing <first>–<last>"`. `record_count` (the
      rows on the current page, when the caller has them) sharpens the last
      entry on a sparse final page. Empty result sets render `""`.

  `record_count` defaults to `nil` (upper-bound estimate from page/pageSize).
  `l10n` translates the range text (see `AshA2ui.L10n`).
  """
  @spec pagination_state(map, non_neg_integer | nil, L10n.t()) :: %{
          visible?: boolean,
          previous?: boolean,
          next?: boolean,
          range_text: String.t()
        }
  def pagination_state(query_state, record_count \\ nil, l10n \\ nil) when is_map(query_state) do
    page = integer_value(query_state["page"], 1)
    page_size = integer_value(query_state["pageSize"], 10)
    has_more = query_state["hasMore"] == true
    total = query_state["totalCount"]
    first = (page - 1) * page_size + 1
    last = last_entry(first, page * page_size, total, has_more, record_count)

    # A query with page_size_options (its state carries `appliedPageSize`)
    # keeps the pager whenever there are rows: its size select must stay
    # reachable after a larger size fits everything on one page.
    sizable? = Map.has_key?(query_state, "appliedPageSize")

    has_rows? =
      (is_integer(total) and total > 0) or (is_integer(record_count) and record_count > 0)

    %{
      visible?: page > 1 or has_more or (sizable? and has_rows?),
      previous?: page > 1,
      next?: has_more,
      range_text: range_text(first, last, total, l10n)
    }
  end

  # A known total caps the range; the probe (`hasMore`) extends it; on the
  # final page the actual row count settles it.
  defp last_entry(_first, upper, total, _has_more, _count) when is_integer(total),
    do: min(upper, total)

  defp last_entry(_first, upper, _total, true, _count), do: upper

  defp last_entry(first, _upper, _total, false, count) when is_integer(count),
    do: first + count - 1

  defp last_entry(_first, upper, _total, false, _count), do: upper

  defp range_text(_first, last, _total, _l10n) when last < 1, do: ""

  defp range_text(first, last, total, l10n) when is_integer(total),
    do: L10n.t(l10n, msg("%{first}–%{last} of %{total}"), first: first, last: last, total: total)

  defp range_text(first, last, _total, l10n),
    do: L10n.t(l10n, msg("Showing %{first}–%{last}"), first: first, last: last)

  @doc false
  # Adorns a `/query` state map with the pagination sentinel keys.
  # Idempotent, so callers that already-adorned states pass through
  # unchanged in value.
  def with_pagination_sentinels(query_state, record_count, l10n \\ nil) do
    if is_map(query_state) do
      state = pagination_state(query_state, record_count, l10n)

      Map.merge(query_state, %{
        "_pagination_visible" => sentinel(state.visible?),
        "_previous_visible" => sentinel(state.previous?),
        "_next_visible" => sentinel(state.next?),
        "_range_text" => state.range_text
      })
    else
      query_state
    end
  end

  @doc false
  # Adorns a `/query` state map with the admin catalog's plain boolean
  # pagination props (`paginationVisible`/`previousVisible`/`nextVisible`)
  # — a no-op unless the admin catalog is selected. The sentinels stay
  # (basic renderers keep working); the admin Pagination component binds
  # these plain booleans instead.
  def with_admin_pagination_booleans(query_state, record_count, view) do
    if admin?(view) and is_map(query_state) do
      state = pagination_state(query_state, record_count)

      Map.merge(query_state, %{
        "paginationVisible" => state.visible?,
        "previousVisible" => state.previous?,
        "nextVisible" => state.next?
      })
    else
      query_state
    end
  end

  defp integer_value(value, _default) when is_integer(value), do: value

  defp integer_value(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _unparsable -> default
    end
  end

  defp integer_value(_value, default), do: default
end
