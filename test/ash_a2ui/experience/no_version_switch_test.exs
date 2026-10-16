defmodule AshA2ui.Experience.NoVersionSwitchTest do
  @moduledoc """
  The experience layer is the only composition: there is no version switch to
  pin, and the catalog selection alone decides basic vs admin.

  These tests carry the retired criteria A2UI-101/AC-17 (byte-compatibility
  under `experience_version: 1`) and A2UI-101B/AC-9 (admin ignored under
  experience v1): what they now check is that the removal is complete — a
  leftover `experience_version` setting changes nothing, and the legacy
  `select_row` action is gone.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Experience
  alias AshA2ui.Test.Paginated

  setup do
    on_exit(fn ->
      Application.delete_env(:ash_a2ui, :experience_version)
      Application.put_env(:ash_a2ui, :catalog, :basic)
    end)

    :ok
  end

  defp components_by_id([_create, components, _data]) do
    Map.new(components["updateComponents"]["components"], &{&1["id"], &1})
  end

  @tag ac: "A2UI-101/AC-17"
  test "a leftover experience_version setting is inert" do
    refute function_exported?(Experience, :version, 0)
    refute function_exported?(Experience, :v2?, 0)
    refute function_exported?(Experience, :effective_admin?, 0)

    Application.delete_env(:ash_a2ui, :experience_version)
    default_surface = AshA2ui.Info.build_surface(Paginated, actor: nil)

    for pinned <- [1, 2] do
      Application.put_env(:ash_a2ui, :experience_version, pinned)
      assert AshA2ui.Info.build_surface(Paginated, actor: nil) == default_surface
    end

    Enum.each(default_surface, &assert_valid_server_message/1)
    comps = components_by_id(default_surface)

    # the experience layer's shapes, not the removed v1 ones
    assert comps["form_slot"]["children"] == %{
             "componentId" => "form",
             "path" => "/ui/panel/visible"
           }

    assert comps["form"]["component"] == "Card"
    assert comps["view_button"]["action"]["event"]["name"] == "view_record"
    assert comps["edit_button"]["action"]["event"]["name"] == "start_edit"
    assert comps["create_button"]["action"]["event"]["name"] == "start_create"
    assert comps["status_text"]["text"] == %{"path" => "/ui/feedback/message"}
    refute Map.has_key?(comps, "row_select_button")
    refute Map.has_key?(comps, "row_select_text")
  end

  @tag ac: "A2UI-101B/AC-9"
  test "the admin catalog selection alone activates the admin emission" do
    Application.put_env(:ash_a2ui, :experience_version, 1)
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    assert Experience.admin?()

    # (admin payloads use the admin catalog's components, so they are not
    # basic-catalog schema messages)
    [create, _components, _data] = surface = AshA2ui.Info.build_surface(Paginated, actor: nil)

    assert create["createSurface"]["catalogId"] == Experience.admin_catalog_id()

    comps = components_by_id(surface)
    assert comps["root"]["component"] == "entityPage"
    assert comps["data_grid"]["component"] == "dataGrid"
    assert comps["status_banner"]["message"] == %{"path" => "/ui/feedback/message"}
  end

  @tag ac: "A2UI-101/AC-17"
  test "select_row is an unknown action" do
    record = Ash.create!(Paginated, %{name: "Pick"}, authorize?: false)

    envelope = %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "select_row",
        "surfaceId" => "paginated",
        "sourceComponentId" => "row_select_button",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => %{"recordId" => record.id}
      }
    }

    assert {:error, [message]} = ActionHandler.handle(Paginated, envelope)
    assert_valid_server_message(message)

    assert %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => feedback}} = message
    assert feedback == %{"kind" => "error", "message" => ~s(Unknown action "select_row".)}
  end
end
