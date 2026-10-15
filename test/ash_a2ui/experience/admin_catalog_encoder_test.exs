defmodule AshA2ui.Experience.AdminCatalogEncoderTest do
  @moduledoc """
  A2UI-101B/AC-2..AC-6 + AC-11: the admin emission — semantic components
  (EntityPage / DataGrid / RecordPanel / StatusBanner / Pagination /
  EmptyState), derived columns and row actions, plain-boolean pagination
  props, mode-bound panel children — and the zero-new-handler-contract
  guarantee.
  """

  use ExUnit.Case, async: false

  require Ash.Query

  alias AshA2ui.ActionHandler
  alias AshA2ui.Experience
  alias AshA2ui.Test.Experience.{ReadOnly, Task}
  alias AshA2ui.Test.KitchenSink

  setup do
    Application.put_env(:ash_a2ui, :experience_version, 2)
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    on_exit(fn ->
      Application.delete_env(:ash_a2ui, :experience_version)
      Application.put_env(:ash_a2ui, :catalog, :basic)
    end)

    :ok
  end

  defp envelope(name, context \\ %{}) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "experience_task",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp components_by_id(components_message) do
    Map.new(components_message["updateComponents"]["components"], &{&1["id"], &1})
  end

  describe "semantic core subtree" do
    @tag ac: "A2UI-101B/AC-2"
    test "admin surface uses semantic components" do
      [create, components, _data] = AshA2ui.Info.build_surface(Task, actor: nil)

      assert create["createSurface"]["catalogId"] == Experience.admin_catalog_id()

      comps = components_by_id(components)

      assert comps["root"]["component"] == "entityPage"
      assert comps["root"]["title"] == "Task"

      # zero jank: the record-task panel is the FIRST root child — an open
      # create/view/edit task is front-and-center, not below the tables —
      # and the typed-feedback banner sits right below it (near-action home,
      # above the collections)
      assert comps["root"]["children"] == [
               "record_panel",
               "status_banner",
               "query_controls",
               "create_button",
               "data_grid",
               "action_result_panel"
             ]

      assert comps["data_grid"]["component"] == "dataGrid"
      assert comps["record_panel"]["component"] == "recordPanel"
      assert comps["status_banner"]["component"] == "statusBanner"

      # no basic-v2 core composition anywhere: no form-slot List, no
      # sentinel-bound pagination row, no standalone view/edit buttons,
      # no "Save" submit, no status Text
      refute Map.has_key?(comps, "form_slot")
      refute Map.has_key?(comps, "form")
      refute Map.has_key?(comps, "query_pagination")
      refute Map.has_key?(comps, "view_button")
      refute Map.has_key?(comps, "edit_button")
      refute Map.has_key?(comps, "row_select_button")
      refute Map.has_key?(comps, "form_submit_button")
      refute Map.has_key?(comps, "status_text")
    end
  end

  describe "DataGrid derivation" do
    @tag ac: "A2UI-101B/AC-3"
    test "data grid derives columns and row actions" do
      [_create, components, _data] = AshA2ui.Info.build_surface(KitchenSink, actor: nil)
      grid = components_by_id(components)["data_grid"]

      # one column per visible field, in the resolved field order (the same
      # derivation the basic Row/Card composition uses for cells — the
      # kitchen-sink surface declares field `order`s), with resolved labels
      # and row-relative cell paths
      assert %{"columns" => columns} = grid

      # — plus the additive per-type presentation hints (format; numbers
      # end-aligned)
      assert columns == [
               %{"label" => "Active", "path" => "active", "format" => "boolean"},
               %{"label" => "Count", "path" => "count", "format" => "number", "align" => "end"},
               %{"label" => "Price", "path" => "price", "format" => "number", "align" => "end"},
               %{"label" => "Birthday", "path" => "birthday", "format" => "datetime"},
               %{"label" => "Scheduled at", "path" => "scheduled_at", "format" => "datetime"},
               %{"label" => "Status", "path" => "status"},
               %{"label" => "Name", "path" => "name"},
               %{"label" => "Created", "path" => "inserted_at", "format" => "datetime"}
             ]

      # rows/rowId/label bindings
      assert grid["rows"] == %{"path" => "/records"}
      assert grid["rowId"] == "id"
      assert grid["label"] == "Kitchen sink"

      # row actions: View always, Edit (update action exists), then the
      # declared row actions as their existing invoke envelopes — the
      # destroy marked destructive
      actions = grid["rowActions"]

      assert [
               %{"label" => "View", "action" => "view_record"},
               %{"label" => "Edit", "action" => "start_edit"},
               %{"label" => "Update", "action" => "invoke"},
               %{"label" => "Destroy", "action" => "invoke", "destructive" => true}
             ] = actions

      # the view/edit envelopes carry the exact recordId path binding the
      # basic-v2 record controls emit
      assert %{
               "context" => %{
                 "recordId" => %{"path" => "id"},
                 "component" => "table"
               }
             } = hd(actions)

      # the destroy envelope is the existing invoke context (+ query
      # binding — the kitchen-sink table has none — and destructive flag)
      assert %{
               "context" => %{
                 "action" => "destroy",
                 "recordId" => %{"path" => "id"},
                 "component" => "table"
               },
               "destructive" => true
             } = Enum.at(actions, 3)

      refute Map.has_key?(Enum.at(actions, 2), "destructive")

      # formless read-only surface variant: no row actions at all — View
      # needs a record panel to open, and ReadOnly has no form component
      # (the audit's dead-button finding)
      [_create, components, _data] = AshA2ui.Info.build_surface(ReadOnly, actor: nil)
      grid = components_by_id(components)["data_grid"]

      assert grid["rowActions"] == []
    end
  end

  describe "master/detail on admin grids" do
    test "a select_context table carries the context_select row action" do
      [_create, components, _data] =
        AshA2ui.Info.build_surface(AshA2ui.Test.AppointmentsUI, actor: nil)

      grid = components_by_id(components)["data_grid"]

      assert [
               %{
                 "label" => "View appointment",
                 "action" => "context_select",
                 "context" => %{
                   "context" => "appointment",
                   "value" => %{"path" => "id"},
                   "component" => "table",
                   "contexts" => %{"path" => "/context"}
                 }
               }
             ] = grid["rowActions"]
    end

    test "the dispatched envelope selects the row into the context" do
      [_create, components, _data] =
        AshA2ui.Info.build_surface(AshA2ui.Test.AppointmentsUI, actor: nil)

      [%{"action" => name, "context" => context}] =
        components_by_id(components)["data_grid"]["rowActions"]

      # the handler resolves the envelope exactly as it does the basic
      # button's: an unknown id is rejected by the authorized read, never
      # trusted — proving the admin entry routes through `context_select`
      resolved = Map.put(context, "value", Ash.UUID.generate())

      assert {:error, messages} =
               ActionHandler.handle(AshA2ui.Test.AppointmentsUI, envelope(name, resolved),
                 actor: nil
               )

      assert Enum.any?(messages, &match?(%{"updateDataModel" => _}, &1))
    end
  end

  describe "Pagination props" do
    @tag ac: "A2UI-101B/AC-4"
    test "pagination component receives boolean props" do
      for i <- 1..3, do: Ash.create!(Task, %{name: "Item #{i}"}, authorize?: false)

      [_create, components, data] = AshA2ui.Info.build_surface(Task, actor: nil)
      pagination = components_by_id(components)["pagination"]

      assert pagination["component"] == "pagination"

      # plain bindings to the boolean query-state keys
      assert pagination["visible"] == %{"path" => "/query/paginationVisible"}
      assert pagination["previousVisible"] == %{"path" => "/query/previousVisible"}
      assert pagination["nextVisible"] == %{"path" => "/query/nextVisible"}

      assert pagination["page"] == %{"path" => "/query/page"}
      assert pagination["pageSize"] == %{"path" => "/query/pageSize"}
      assert pagination["total"] == %{"path" => "/query/totalCount"}
      assert pagination["hasNext"] == %{"path" => "/query/hasMore"}
      assert pagination["rangeText"] == %{"path" => "/query/_range_text"}

      # prev/next dispatch the existing query envelope (pageDelta -1/+1)
      assert pagination["previousAction"]["name"] == "query"
      assert pagination["previousAction"]["context"]["pageDelta"] == -1
      assert pagination["previousAction"]["context"]["query"] == %{"path" => "/query"}
      assert pagination["nextAction"]["name"] == "query"
      assert pagination["nextAction"]["context"]["pageDelta"] == 1

      # no zero-or-one sentinel lists anywhere in the admin pagination props
      refute Enum.any?(Map.values(pagination), &is_list(&1))

      refute Enum.any?(Map.values(pagination), fn
               %{"path" => path} -> path =~ "_visible"
               _other -> false
             end)

      # the data model carries the plain booleans alongside the v2 sentinels
      %{"updateDataModel" => %{"value" => model}} = data
      query = model["query"]

      assert query["paginationVisible"] == true
      assert query["previousVisible"] == false
      assert query["nextVisible"] == true
      assert query["_pagination_visible"] != []
      assert query["_next_visible"] != []
    end
  end

  describe "RecordPanel" do
    @tag ac: "A2UI-101B/AC-5"
    test "record panel binds mode and declares mode children" do
      [_create, components, _data] = AshA2ui.Info.build_surface(Task, actor: nil)
      comps = components_by_id(components)

      panel = comps["record_panel"]

      assert panel["mode"] == %{"path" => "/ui/panel/mode"}
      assert panel["title"] == %{"path" => "/ui/panel/title"}
      assert panel["recordId"] == %{"path" => "/ui/panel/record_id"}

      # view-mode children (field displays) plus create/edit children
      # (FormSection + ActionBar)
      assert panel["children"] == ["field_display_name", "form_section", "action_bar"]

      assert %{
               "component" => "fieldDisplay",
               "label" => "Name",
               # the view task's read-only display values — /form is the edit
               # buffer and is never written in view mode
               "value" => %{"path" => "/ui/panel/record/name"}
             } = comps["field_display_name"]

      assert %{"children" => form_children} = comps["form_section"]
      assert "form_input_name" in form_children
      assert "form_error_name" in form_children

      # the input inside FormSection keeps the exact basic binding
      assert comps["form_input_name"]["value"] == %{"path" => "/form/name"}
      assert comps["form_error_name"]["text"] == %{"path" => "/errors/name"}

      # ActionBar: primary label bound (empty = hidden), reserved busy,
      # existing submit_form envelope, Cancel as a secondary basic button
      action_bar = comps["action_bar"]

      assert action_bar["primaryLabel"] == %{"path" => "/ui/panel/primary_label"}
      assert action_bar["busy"] == false
      assert action_bar["action"]["event"]["name"] == "submit_form"
      assert action_bar["action"]["event"]["context"]["values"] == %{"path" => "/form"}
      assert action_bar["action"]["event"]["context"]["recordId"] == %{"path" => "/form/id"}
      assert action_bar["children"] == ["form_cancel_button"]

      assert comps["form_cancel_button"]["action"]["event"]["name"] == "cancel_record_task"
    end
  end

  describe "StatusBanner" do
    @tag ac: "A2UI-101B/AC-6"
    test "status banner binds typed feedback" do
      [_create, components, _data] = AshA2ui.Info.build_surface(Task, actor: nil)
      banner = components_by_id(components)["status_banner"]

      assert banner["component"] == "statusBanner"
      assert banner["kind"] == %{"path" => "/ui/feedback/kind"}
      assert banner["message"] == %{"path" => "/ui/feedback/message"}
    end
  end

  describe "handler contract" do
    @dispatch_names [
      "submit_form",
      "invoke",
      "prompt",
      "report",
      "export",
      "edit_cell",
      "select_row",
      "query",
      "context_search",
      "context_select",
      "context_clear",
      "option_search",
      "option_select",
      "nested_add",
      "nested_remove",
      "start_create",
      "view_record",
      "start_edit",
      "cancel_record_task",
      # A2UI-104 bulk actions (not catalog-driven: the admin catalog keeps
      # bulk tables basic-composed)
      "bulk_invoke",
      "bulk_select"
    ]

    @tag ac: "A2UI-101B/AC-11"
    test "semantic components reuse existing action envelopes" do
      # structural: the handler grew no new action names for the catalog
      source = File.read!("lib/ash_a2ui/action_handler.ex")
      names = Regex.scan(~r/defp dispatch\("([a-z_]+)"/, source) |> Enum.map(&Enum.at(&1, 1))

      assert Enum.sort(names) == Enum.sort(@dispatch_names)

      # behavioral: every event produces the same contract-relevant writes
      # under admin and basic-v2 (admin /query additionally carries the
      # plain boolean props)
      record = Ash.create!(Task, %{name: "Target"}, authorize?: false)

      events = [
        {"start_create", envelope("start_create")},
        {"view_record", envelope("view_record", %{"recordId" => record.id})},
        {"start_edit", envelope("start_edit", %{"recordId" => record.id})},
        {"cancel_record_task", envelope("cancel_record_task")},
        {"query", envelope("query", %{"query" => %{"page" => 1}, "pageDelta" => 1})},
        {"submit_form", envelope("submit_form", %{"values" => %{"name" => "Created"}})}
      ]

      admin_results =
        Map.new(events, fn {name, env} ->
          {:ok, messages} = ActionHandler.handle(Task, env, actor: nil)
          result = {name, contract_writes(messages)}
          cleanup_created!()
          result
        end)

      Application.put_env(:ash_a2ui, :catalog, :basic)

      basic_results =
        Map.new(events, fn {name, env} ->
          {:ok, messages} = ActionHandler.handle(Task, env, actor: nil)
          result = {name, contract_writes(messages)}
          cleanup_created!()
          result
        end)

      Enum.each(events, fn {name, _env} ->
        admin = Map.fetch!(admin_results, name)
        basic = Map.fetch!(basic_results, name)

        # the same reserved-path write set (the /records content itself may
        # differ — each submit_form run created its own record)
        assert MapSet.new(Map.keys(admin)) == MapSet.new(Map.keys(basic)),
               "#{name}: write paths diverged between admin and basic"

        # every shared write is byte-equal after dropping the admin-only
        # boolean query props
        Enum.each(admin, fn {path, value} ->
          if path == "/records" do
            assert is_list(value)
          else
            assert value == Map.fetch!(basic, path), "#{name}: #{path} diverged"
          end
        end)
      end)
    end

    # The reserved-path writes, minus the admin-only plain boolean
    # pagination props (the only intended catalog delta — everything else
    # must be byte-identical between the two emissions).
    defp contract_writes(messages) do
      messages
      |> Enum.filter(&Map.has_key?(&1, "updateDataModel"))
      |> Map.new(fn message ->
        %{"updateDataModel" => %{"path" => path, "value" => value}} = message
        {path, drop_admin_query_props(path, value)}
      end)
    end

    defp drop_admin_query_props("/query", value) when is_map(value),
      do: Map.drop(value, ["paginationVisible", "previousVisible", "nextVisible"])

    defp drop_admin_query_props(_path, value), do: value

    # Each submit_form run creates its own record; removing it keeps both
    # runs' reads (refresh rows, query totals) comparable.
    defp cleanup_created! do
      Task
      |> Ash.Query.filter(name == "Created")
      |> Ash.read!(authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    end
  end
end
