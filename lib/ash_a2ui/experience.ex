defmodule AshA2ui.Experience do
  @moduledoc """
  The experience layer: explicit task modes (browse / create / view / edit),
  conditional pagination, semantic action labels, typed feedback, and
  data-driven empty states. This is how every ash_a2ui surface composes; there
  is no version switch.

  ## The /ui reserved state

  The initial data model's `"ui"` region holds (alongside the
  `"action_result"` / `"action_result_text"` entries):

    * `"intent"` — the client-facing task intent: `"browse"`, `"create"`,
      `"view"`, or `"edit"`.
    * `"panel"` — the record task panel: `"visible"`, `"submit_visible"`,
      `"form_visible"` and `"view_visible"` are zero-or-one visibility
      sentinels (`[]` hidden, one item visible — the exact technique the
      row-action `visible_when` slots use, see `AshA2ui.Conditions`),
      plus `"mode"`, `"title"`, `"primary_label"`, and `"record_id"`.
    * `"feedback"` — the last action outcome: `"kind"` (`nil`, `"success"`,
      `"warning"`, or `"error"`) and `"message"`.

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

  alias AshA2ui.ResolvedView

  @typedoc "The record task panel modes (`:hidden` for the closed state)."
  @type mode :: :create | :view | :edit | :hidden

  @admin_catalog_id "https://ash-a2ui.dev/catalogs/admin/v1"

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

  @doc false
  # The admin catalog id emitted on createSurface when the admin emission
  # is active (see notes/2026-09-07-admin-catalog-contract.md).
  def admin_catalog_id, do: @admin_catalog_id

  @doc """
  The admin catalog contract version (`"version"` in
  `priv/a2ui/admin_v1/catalog.json`). Minor versions are additive within the
  unchanged `admin_catalog_id/0` — 1.1 added the column presentation hints
  (format/align/mono/badge/link), `rowClick`, FieldDisplay `link` and the
  `openSurface` client function; 1.2 added the `rowActions` entries'
  `visiblePath` (per-row `visible_when`) and `prompt` (prompt dialogs).
  """
  @spec admin_catalog_version() :: String.t()
  def admin_catalog_version, do: "1.6.0"

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
  def initial_ui_state(_view) do
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
      "/ui/feedback/kind" => nil,
      "/ui/feedback/message" => ""
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
  def create_label(view), do: "Create #{resource_label(view)}"

  @doc """
  The edit-task primary button label.
  """
  @spec save_changes_label() :: String.t()
  def save_changes_label, do: "Save changes"

  @doc """
  The panel heading for `mode` (`:create` / `:view` / `:edit`), e.g.
  `"Edit Appointment"`.
  """
  @spec panel_title(:create | :view | :edit, ResolvedView.t()) :: String.t()
  def panel_title(:create, view), do: create_label(view)
  def panel_title(:view, view), do: "View #{resource_label(view)}"
  def panel_title(:edit, view), do: "Edit #{resource_label(view)}"

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
  def surface_title(%{title: title}) when is_binary(title) and title != "", do: title
  def surface_title(view), do: resource_label(view)

  @doc """
  The singular noun for one record, used by the derived task labels.

  The view's declared `record_label` when it has one, else the humanized
  resource short name (e.g. `"Appointment"`).
  """
  @spec resource_label(ResolvedView.t()) :: String.t()
  def resource_label(%{record_label: label}) when is_binary(label) and label != "", do: label

  def resource_label(view) do
    view.resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> humanize()
  end

  @doc """
  The per-table empty-state text (e.g. `"No Appointment records yet."`).
  """
  @spec empty_message(ResolvedView.t(), ResolvedView.table()) :: String.t()
  def empty_message(view, table) do
    # A board lane is headed by its value already; its empty state names
    # the records ("No Task records yet."), not the runtime lane name.
    if AshA2ui.Board.lane?(table),
      do: "No #{resource_label(view)} records yet.",
      else: "No #{collection_label(view, table)} records yet."
  end

  @doc false
  # The humanized collection name for a table: the resource label on
  # single-table surfaces, the humanized table component name on
  # multi-table surfaces (same scheme as the section headings).
  @spec collection_label(ResolvedView.t(), ResolvedView.table()) :: String.t()
  def collection_label(view, table) do
    if ResolvedView.multi_table?(view) do
      table.name |> to_string() |> humanize()
    else
      resource_label(view)
    end
  end

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
        _form_mode when next_step? -> AshA2ui.Wizard.next_label()
        :create -> create_label(view)
        :edit -> save_changes_label()
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
  A typed feedback value: `%{"kind" => kind, "message" => message}` where
  `kind` is `"success"` / `"warning"` (a bulk run that partly succeeded) /
  `"error"` / `nil`.
  """
  @spec feedback(String.t() | nil, String.t()) :: map
  def feedback(kind, message \\ "")
  def feedback(kind, message) when is_binary(message), do: %{"kind" => kind, "message" => message}

  @doc """
  The cleared feedback value (`nil` kind, empty message).
  """
  @spec clear_feedback() :: map
  def clear_feedback, do: feedback(nil, "")

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
  """
  @spec pagination_state(map, non_neg_integer | nil) :: %{
          visible?: boolean,
          previous?: boolean,
          next?: boolean,
          range_text: String.t()
        }
  def pagination_state(query_state, record_count \\ nil) when is_map(query_state) do
    page = integer_value(query_state["page"], 1)
    page_size = integer_value(query_state["pageSize"], 10)
    has_more = query_state["hasMore"] == true
    total = query_state["totalCount"]
    first = (page - 1) * page_size + 1
    last = last_entry(first, page * page_size, total, has_more, record_count)

    %{
      visible?: page > 1 or has_more,
      previous?: page > 1,
      next?: has_more,
      range_text: range_text(first, last, total)
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

  defp range_text(_first, last, _total) when last < 1, do: ""
  defp range_text(first, last, total) when is_integer(total), do: "#{first}–#{last} of #{total}"
  defp range_text(first, last, _total), do: "Showing #{first}–#{last}"

  @doc false
  # Adorns a `/query` state map with the pagination sentinel keys.
  # Idempotent, so callers that already-adorned states pass through
  # unchanged in value.
  def with_pagination_sentinels(query_state, record_count) do
    if is_map(query_state) do
      state = pagination_state(query_state, record_count)

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
  def with_admin_pagination_booleans(query_state, record_count) do
    if admin?() and is_map(query_state) do
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

  defp humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
