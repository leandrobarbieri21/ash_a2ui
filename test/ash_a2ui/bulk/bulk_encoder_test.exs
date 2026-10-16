defmodule AshA2ui.Bulk.BulkEncoderTest do
  @moduledoc """
  A2UI-104: the encoded selection state and toolbar of a table with
  `bulk_actions`, on both spec versions and both row shapes.
  """

  # Shared ETS fixtures and the experience/catalog application env.
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper
  import AshA2ui.Test.BulkHelpers

  alias AshA2ui.Test.{BulkCardsUI, BulkTasksUI}

  setup do
    reset!()
    project = project!("Apollo")
    task!("Alpha", %{project_id: project.id})
    task!("Bravo", %{project_id: project.id})
    %{project: project}
  end

  defp by_id(components), do: Map.new(components, &{&1["id"], &1})

  @tag ac: "A2UI-104/AC-1"
  test "encodes selection and toolbar for both versions" do
    # v0.9.1: the createSurface -> updateComponents -> updateDataModel triple
    [_create, components_message, data_message] =
      messages = AshA2ui.Info.build_surface(BulkTasksUI, actor: actor())

    Enum.each(messages, &assert_valid_server_message/1)

    components = by_id(components_message["updateComponents"]["components"])
    data = data_message["updateDataModel"]["value"]

    assert_bulk_flat_table(components)

    # every row carries "_selected": false; the result state starts at zero
    assert [_, _] = data["records"]
    assert Enum.all?(data["records"], &(&1["_selected"] == false))

    assert data["bulk"] == %{
             "table" => %{
               "result" => %{
                 "ok" => 0,
                 "failed" => 0,
                 "refused" => 0,
                 "skipped" => 0,
                 "errors" => []
               }
             }
           }

    # v1.0: one inline createSurface with the same composition
    [create] = AshA2ui.Info.build_surface(BulkTasksUI, actor: actor(), spec_version: "1.0")
    assert_valid_server_message(create, :v1_0)

    v1_components = by_id(create["createSurface"]["components"])
    assert_bulk_flat_table(v1_components)

    assert v1_components["bulk_action_approve_button"]["action"]["event"]["wantResponse"] == true
    assert Enum.all?(create["createSurface"]["dataModel"]["records"], &(&1["_selected"] == false))

    # card rows: the CheckBox leads the card header; a table without bulk
    # actions keeps its rows and components unchanged
    for {version, schema} <- [{"0.9.1", :v0_9_1}, {"1.0", :v1_0}] do
      {components, data} =
        case AshA2ui.Info.build_surface(BulkCardsUI, actor: actor(), spec_version: version) do
          [create] ->
            assert_valid_server_message(create, schema)

            {by_id(create["createSurface"]["components"]), create["createSurface"]["dataModel"]}

          [_create, components_message, data_message] = triple ->
            Enum.each(triple, &assert_valid_server_message(&1, schema))

            {by_id(components_message["updateComponents"]["components"]),
             data_message["updateDataModel"]["value"]}
        end

      assert ["record_row_inbox_selected" | _rest] =
               components["record_row_inbox_header"]["children"]

      assert components["record_row_inbox_selected"]["value"] == %{"path" => "_selected"}

      assert components["bulk_inbox_toolbar"]["children"] == [
               "bulk_inbox_action_reject_button",
               "bulk_inbox_select_page_button",
               "bulk_inbox_clear_button"
             ]

      refute Map.has_key?(components, "bulk_everything_toolbar")
      refute Map.has_key?(components, "record_row_everything_selected")

      assert Enum.all?(data["records"]["inbox"], &(&1["_selected"] == false))
      refute Enum.any?(data["records"]["everything"], &Map.has_key?(&1, "_selected"))
      assert Map.keys(data["bulk"]) == ["inbox"]
    end
  end

  test "the admin catalog keeps a bulk table basic composed" do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
    end)

    [_create, components_message, _data] =
      AshA2ui.Info.build_surface(BulkTasksUI, actor: actor())

    components = by_id(components_message["updateComponents"]["components"])

    assert components["root"]["component"] == "entityPage"
    refute Map.has_key?(components, "data_grid")
    assert "bulk_toolbar" in components["root"]["children"]
    assert_bulk_flat_table(components)
  end

  # The flat-row composition: the CheckBox first in the row's cell Row, the
  # toolbar above the list with one bulk_invoke Button per bulk action plus
  # Select page / Clear, every context carrying the records, query and
  # contexts bindings.
  defp assert_bulk_flat_table(components) do
    assert ["record_row_selected" | _cells] = components["record_row_content"]["children"]

    assert %{
             "component" => "CheckBox",
             "label" => "Select",
             "value" => %{"path" => "_selected"}
           } = components["record_row_selected"]

    root_children = components["root"]["children"]
    toolbar_at = Enum.find_index(root_children, &(&1 == "bulk_toolbar"))
    assert toolbar_at
    assert Enum.at(root_children, toolbar_at + 1) == "records_list"

    assert components["bulk_toolbar"]["children"] == [
             "bulk_action_approve_button",
             "bulk_action_reject_button",
             "bulk_action_destroy_button",
             "bulk_select_page_button",
             "bulk_clear_button"
           ]

    approve = components["bulk_action_approve_button"]["action"]["event"]
    assert approve["name"] == "bulk_invoke"

    assert %{
             "action" => "approve",
             "component" => "table",
             "records" => %{"path" => "/records"},
             "query" => %{"path" => "/query"},
             "contexts" => %{"path" => "/context"}
           } = approve["context"]

    assert components["bulk_action_approve_text"]["text"] == "Approve"

    for {id, selected} <- [{"bulk_select_page_button", true}, {"bulk_clear_button", false}] do
      event = components[id]["action"]["event"]
      assert event["name"] == "bulk_select"

      assert %{
               "component" => "table",
               "selected" => ^selected,
               "records" => %{"path" => "/records"}
             } = event["context"]
    end
  end

  test "a bulk action named like a fixed control gets its own component ids" do
    defmodule BulkClearUI do
      @moduledoc false
      use AshA2ui.Standalone

      a2ui do
        for_resource AshA2ui.Test.BulkTask
        surface_id "bulk_clear"

        component :table do
          fields [:title]
          bulk_actions [:clear]
        end
      end
    end

    [_create, components_message, _data] = AshA2ui.Info.build_surface(BulkClearUI, actor: actor())
    components = components_message["updateComponents"]["components"]
    ids = Enum.map(components, & &1["id"])

    assert ids == Enum.uniq(ids)

    by_id = by_id(components)
    assert by_id["bulk_action_clear_button"]["action"]["event"]["name"] == "bulk_invoke"
    assert by_id["bulk_clear_button"]["action"]["event"]["name"] == "bulk_select"
  end
end
