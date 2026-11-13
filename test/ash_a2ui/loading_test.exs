defmodule AshA2ui.LoadingTest do
  use ExUnit.Case, async: true

  alias AshA2ui.Loading
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.SchemaHelper

  defp writes(messages),
    do: Map.new(messages, &{&1["updateDataModel"]["path"], &1["updateDataModel"]["value"]})

  test "the flag lives at a reserved ui path" do
    assert Loading.path() == "/ui/loading"
  end

  test "sets the flag and its zero-or-one list as A2UI 1.0 data-model writes" do
    view = %ResolvedView{surface_id: "s1"}

    on = Loading.messages(view, true)
    SchemaHelper.assert_valid_agent_messages(on)
    assert Enum.all?(on, &(&1["version"] == "1.0" and &1["updateDataModel"]["surfaceId"] == "s1"))
    assert writes(on) == %{"/ui/loading" => true, "/ui/loading_visible" => [%{"id" => "on"}]}

    off = Loading.messages(view, false)
    SchemaHelper.assert_valid_agent_messages(off)
    assert writes(off) == %{"/ui/loading" => false, "/ui/loading_visible" => []}
  end

  test "resolves a surface module" do
    messages = Loading.messages(AshA2ui.Test.Diagram.FlowUI, true)

    assert [_, _] = messages
    assert writes(messages)["/ui/loading"] == true
  end
end
