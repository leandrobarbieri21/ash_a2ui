defmodule AshA2ui.Experience.AdminCatalogWireTest do
  @moduledoc """
  A2UI-101B/AC-10: an admin surface on the 1.0 wire — the admin catalogId,
  the admin kinds and their bindings, the basic components qualified with
  their own catalog, and the A2UI-101 ui state.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Experience
  alias AshA2ui.Test.Experience.Task

  setup do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
    end)

    :ok
  end

  @tag ac: "A2UI-101B/AC-10"
  test "an admin surface keeps its kinds, bindings and ui state" do
    [surface] = AshA2ui.Info.build_surface(Task)

    assert %{"version" => "1.0", "createSurface" => create} = surface

    # the admin catalog is the surface's catalog
    assert create["catalogId"] == Experience.admin_catalog_id()

    comps = Map.new(create["components"], &{&1["id"], &1})

    # the admin kinds carry no @catalogId: they are the surface's own
    assert comps["root"]["component"] == "entityPage"
    assert comps["data_grid"]["component"] == "dataGrid"
    assert comps["record_panel"]["component"] == "recordPanel"
    assert comps["status_banner"]["component"] == "statusBanner"
    assert comps["pagination"]["component"] == "pagination"
    refute Map.has_key?(comps["root"], "@catalogId")

    # a basic component on the admin surface names the basic catalog
    assert comps["action_result_text"]["@catalogId"] == AshA2ui.Encoder.basic_catalog_id()

    # bindings are @path bindings into the data model
    assert comps["status_banner"]["kind"] == %{"@path" => "/ui/feedback/kind"}
    assert comps["status_banner"]["message"] == %{"@path" => "/ui/feedback/message"}
    assert comps["record_panel"]["mode"] == %{"@path" => "/ui/panel/mode"}
    assert comps["action_bar"]["primaryLabel"] == %{"@path" => "/ui/panel/primary_label"}
    assert comps["pagination"]["visible"] == %{"@path" => "/query/paginationVisible"}

    # row action envelopes pass through with their row-relative bindings
    [view_action | _rest] = comps["data_grid"]["rowActions"]
    assert view_action["action"] == "view_record"
    assert view_action["context"]["recordId"] == %{"@path" => "id"}
    assert view_action["context"]["component"] == "table"

    # the ActionBar's action is an ashAction call, while the pagination
    # envelopes stay bare (the admin renderer dispatches them itself)
    assert comps["action_bar"]["action"]["functionCall"]["args"]["name"] == "submit_form"
    assert comps["action_bar"]["action"]["functionCall"]["@call"] == "ashAction"

    assert comps["pagination"]["nextAction"] == %{
             "name" => "query",
             "context" => %{
               "query" => %{"@path" => "/query"},
               "pageDelta" => 1,
               "component" => "table"
             }
           }

    # the A2UI-101 experience state: intent, panel and the one feedback map
    ui = create["dataModel"]["ui"]

    assert ui["intent"] == "browse"
    assert ui["panel"]["visible"] == []
    assert ui["feedback"] == AshA2ui.Experience.clear_feedback()

    for retired <- ["status", "response", "action_result", "action_result_text"],
        do: refute(Map.has_key?(ui, retired))
  end
end
