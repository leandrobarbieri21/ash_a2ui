defmodule AshA2ui.Experience.AdminCatalogUpgradeTest do
  @moduledoc """
  A2UI-101B/AC-10: the v1.0 upgrade pass — custom admin kinds and their
  bindings go through untouched, and the /ui/response collapse preserves
  the A2UI-101 behavior.
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
  test "v1_0 upgrade passes custom kinds through" do
    [surface] = AshA2ui.Info.build_surface(Task, spec_version: "1.0")

    assert %{"version" => "v1.0", "createSurface" => create} = surface

    # the admin catalog id survives the inline createSurface
    assert create["catalogId"] == Experience.admin_catalog_id()

    comps = Map.new(create["components"], &{&1["id"], &1})

    # custom kinds pass through untouched
    assert comps["root"]["component"] == "entityPage"
    assert comps["data_grid"]["component"] == "dataGrid"
    assert comps["record_panel"]["component"] == "recordPanel"
    assert comps["status_banner"]["component"] == "statusBanner"
    assert comps["pagination"]["component"] == "pagination"

    # bindings are not rewritten (only the /ui/action_result family is)
    assert comps["status_banner"]["kind"] == %{"path" => "/ui/feedback/kind"}
    assert comps["status_banner"]["message"] == %{"path" => "/ui/feedback/message"}
    assert comps["record_panel"]["mode"] == %{"path" => "/ui/panel/mode"}
    assert comps["action_bar"]["primaryLabel"] == %{"path" => "/ui/panel/primary_label"}
    assert comps["pagination"]["visible"] == %{"path" => "/query/paginationVisible"}

    # row action envelopes pass through with their row-relative bindings
    [view_action | _rest] = comps["data_grid"]["rowActions"]
    assert view_action["action"] == "view_record"
    assert view_action["context"]["recordId"] == %{"path" => "id"}
    assert view_action["context"]["component"] == "table"

    # v1.0 wire contract: emitted action events gain wantResponse — the
    # event-wrapped ActionBar action gets it, while the bare pagination
    # envelopes pass through untouched (the renderer dispatches them
    # directly)
    assert comps["action_bar"]["action"]["event"]["name"] == "submit_form"
    assert comps["action_bar"]["action"]["event"]["wantResponse"] == true

    assert comps["pagination"]["nextAction"] == %{
             "name" => "query",
             "context" => %{
               "query" => %{"path" => "/query"},
               "pageDelta" => 1,
               "component" => "table"
             }
           }

    # the /ui/response collapse preserves the A2UI-101 state: the
    # structured response replaces the status trio, the experience state
    # (intent/panel/feedback) survives alongside it
    ui = create["dataModel"]["ui"]

    assert %{"status" => "", "message" => "", "result" => %{}, "resultText" => ""} =
             ui["response"]

    assert ui["intent"] == "browse"
    assert ui["panel"]["visible"] == []
    assert ui["feedback"] == %{"kind" => nil, "message" => ""}
    refute Map.has_key?(ui, "status")
  end
end
