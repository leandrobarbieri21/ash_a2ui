defmodule AshA2ui.QueryPresetPickerTest do
  @moduledoc """
  `preset_picker false` leaves the preset picker out of a query's controls
  when the page selects the preset itself. The presets still apply: the
  query action accepts them and the default preset still scopes the read.
  The option round-trips through dynamic specs.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.{BulkPresetsUI, TabbedPresetsUI}

  defp components(ui) do
    [_create, components, _data] = AshA2ui.Info.build_surface(ui, authorize?: false)
    Map.new(components["updateComponents"]["components"], &{&1["id"], &1})
  end

  test "the picker is emitted by default" do
    components = components(BulkPresetsUI)

    assert %{"component" => "ChoicePicker"} = components["query_preset_picker"]
  end

  test "preset_picker false leaves the picker out of the controls, and only the picker" do
    components = components(TabbedPresetsUI)

    refute Map.has_key?(components, "query_preset_picker")

    assert components["query_controls_body"]["children"] == [
             "query_search_input",
             "query_apply_button"
           ]
  end

  test "the presets still apply without the picker" do
    [query] = AshA2ui.Info.queries(TabbedPresetsUI)

    assert query.preset_picker == false
    assert Enum.map(query.presets, & &1.name) == [:archived, :approved]
    assert query.default_preset == :archived
  end

  test "the option round-trips through a dynamic spec" do
    {:ok, spec, _rejections} = Importer.import(TabbedPresetsUI)
    assert [%{"preset_picker" => false}] = spec["queries"]

    {:ok, default_spec, _rejections} = Importer.import(BulkPresetsUI)
    [default_query] = default_spec["queries"]
    refute Map.has_key?(default_query, "preset_picker")

    allowlist = Dynamic.allowlist([AshA2ui.Test.BulkTask])
    {:ok, surface} = Dynamic.resolve(spec, allowlist: allowlist)
    [_create, message, _data] = Dynamic.build_surface(surface, authorize?: false)
    ids = Enum.map(message["updateComponents"]["components"], & &1["id"])

    assert "query_search_input" in ids
    refute "query_preset_picker" in ids
  end
end
