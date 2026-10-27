defmodule AshA2ui.QueryApplyOnChangeTest do
  @moduledoc """
  `apply_on_change true` puts `autoApply` in the query's `/query` state, so
  a renderer can send the Apply envelope as the controls change. The Apply
  button stays in the tree for renderers that don't. The option
  round-trips through dynamic specs. Separately, a query with nothing to
  pick gets no controls card at all.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.{BulkPresetsUI, LiveFiltersUI, SortOnlyUI}

  setup do
    previous = Application.get_env(:ash_a2ui, :catalog)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, previous) end)
  end

  defp build(ui) do
    [_create, components, data] = AshA2ui.Info.build_surface(ui, authorize?: false)
    {Map.new(components["updateComponents"]["components"], &{&1["id"], &1}), data}
  end

  defp referenced_ids(components) do
    components
    |> Map.values()
    |> Enum.flat_map(fn component ->
      List.wrap(component["child"]) ++
        case component["children"] do
          children when is_list(children) -> children
          _template -> []
        end
    end)
  end

  test "without the option the query state has no autoApply" do
    {components, data} = build(BulkPresetsUI)

    refute Map.has_key?(data["updateDataModel"]["value"]["query"], "autoApply")
    assert %{"component" => "Button"} = components["query_apply_button"]
  end

  test "apply_on_change puts autoApply in the query state and keeps Apply in the tree" do
    {components, data} = build(LiveFiltersUI)

    assert data["updateDataModel"]["value"]["query"]["autoApply"] == %{"debounceMs" => 300}

    assert %{"action" => %{"event" => %{"name" => "query", "context" => %{"page" => 1}}}} =
             components["query_apply_button"]

    assert "query_apply_button" in components["query_controls_body"]["children"]
  end

  test "a query refresh keeps autoApply" do
    envelope = %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "query",
        "context" => %{"query" => %{"filters" => %{"status" => "approved"}}, "page" => 1}
      }
    }

    assert {:ok, messages} = AshA2ui.ActionHandler.handle(LiveFiltersUI, envelope, actor: nil)

    assert %{"updateDataModel" => %{"value" => %{"autoApply" => %{"debounceMs" => 300}}}} =
             Enum.find(messages, &match?(%{"updateDataModel" => %{"path" => "/query"}}, &1))
  end

  test "the option round-trips through a dynamic spec" do
    {:ok, spec, _rejections} = Importer.import(LiveFiltersUI)
    assert [%{"apply_on_change" => true}] = spec["queries"]

    {:ok, default_spec, _rejections} = Importer.import(BulkPresetsUI)
    [default_query] = default_spec["queries"]
    refute Map.has_key?(default_query, "apply_on_change")

    allowlist = Dynamic.allowlist([AshA2ui.Test.BulkTask])
    {:ok, surface} = Dynamic.resolve(spec, allowlist: allowlist)
    [_create, _components, data] = Dynamic.build_surface(surface, authorize?: false)

    assert data["updateDataModel"]["value"]["query"]["autoApply"] == %{"debounceMs" => 300}
  end

  for catalog <- [:basic, :admin_v1] do
    test "a query with nothing to pick gets no controls card (#{catalog})" do
      Application.put_env(:ash_a2ui, :catalog, unquote(catalog))
      {components, _data} = build(SortOnlyUI)

      refute Map.has_key?(components, "query_controls")
      refute Map.has_key?(components, "query_apply_button")
      refute "query_controls" in referenced_ids(components)
      assert Enum.any?(Map.keys(components), &String.contains?(&1, "pagination"))
    end
  end
end
