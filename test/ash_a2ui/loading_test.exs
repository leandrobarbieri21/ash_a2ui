defmodule AshA2ui.LoadingTest do
  use ExUnit.Case, async: true

  alias AshA2ui.Loading
  alias AshA2ui.ResolvedView

  defp writes(messages),
    do: Map.new(messages, &{&1["updateDataModel"]["path"], &1["updateDataModel"]["value"]})

  test "the flag lives at a reserved ui path" do
    assert Loading.path() == "/ui/loading"
  end

  test "sets the flag and its zero-or-one list in the surface's own protocol version" do
    v1 = %ResolvedView{surface_id: "s1", spec_version: :v1_0}
    v09 = %ResolvedView{surface_id: "s2", spec_version: :v0_9_1}

    on = Loading.messages(v1, true)

    assert Enum.all?(
             on,
             &(&1["version"] == "v1.0" and &1["updateDataModel"]["surfaceId"] == "s1")
           )

    assert writes(on) == %{"/ui/loading" => true, "/ui/loading_visible" => [%{"id" => "on"}]}

    off = Loading.messages(v09, false)
    assert Enum.all?(off, &(&1["version"] == "v0.9.1"))
    assert writes(off) == %{"/ui/loading" => false, "/ui/loading_visible" => []}
  end

  test "resolves a surface module" do
    messages = Loading.messages(AshA2ui.Test.Diagram.FlowV1UI, true)

    assert [_, _] = messages
    assert writes(messages)["/ui/loading"] == true
  end
end
