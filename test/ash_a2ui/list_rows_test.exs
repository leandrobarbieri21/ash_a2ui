defmodule AshA2ui.ListRowsTest do
  @moduledoc """
  Catalog 1.12 list rows: `display :rows` and a row layout's `trailing` and
  `expand` fields, on the admin dataGrid and in the basic card fallback.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.OwnerVisitsUI

  setup do
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
  end

  defp surface(catalog) do
    Application.put_env(:ash_a2ui, :catalog, catalog)
    [_create, components, _data] = AshA2ui.Info.build_surface(OwnerVisitsUI, authorize?: false)
    Map.new(components["updateComponents"]["components"], &{&1["id"], &1})
  end

  test "the admin grid asks for rows and places the trailing and expand columns" do
    grid = surface(:admin_v1)["data_grid"]

    assert grid["layout"] == "rows"

    placements = Map.new(grid["columns"], &{&1["path"], &1["placement"]})

    assert placements == %{
             "title" => nil,
             "status" => nil,
             "scheduled_for" => "trailing",
             "clinic_id" => "expand"
           }
  end

  test "the default meta leaves the trailing and expand fields out" do
    view = AshA2ui.ResolvedView.resolve(OwnerVisitsUI)
    [%{component: %{row_layout: layout}}] = view.tables

    assert layout.meta == []
    assert layout.trailing == [:scheduled_for]
    assert layout.expand == [:clinic_id]
  end

  test "the basic card shows them in its metadata grid" do
    components = surface(:basic)
    ids = Map.keys(components)

    assert Enum.any?(ids, &String.ends_with?(&1, "_meta_cell_scheduled_for"))
    assert Enum.any?(ids, &String.ends_with?(&1, "_meta_cell_clinic_id"))
  end

  test "a plain list keeps its grid" do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    [_create, components, _data] =
      AshA2ui.Info.build_surface(AshA2ui.Test.RecordPageUI, authorize?: false)

    grid = Enum.find(components["updateComponents"]["components"], &(&1["id"] == "data_grid"))
    refute Map.has_key?(grid, "layout")
  end

  test "dynamic specs carry the display and the fields" do
    {:ok, spec, _rejections} = Importer.import(OwnerVisitsUI)
    [visits] = spec["components"]

    assert visits["display"] == "rows"
    assert visits["row_layout"]["trailing"] == ["scheduled_for"]
    assert visits["row_layout"]["expand"] == ["clinic_id"]
  end

  describe "compile-time checks" do
    test "display :rows without a row layout" do
      assert capture_io(:stderr, fn ->
               defmodule RowsWithoutLayout do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   component :table do
                     display :rows
                     fields [:title]
                   end
                 end
               end
             end) =~ ~r/display :rows requires a row_layout/
    end

    test "a trailing field the table does not show" do
      assert capture_io(:stderr, fn ->
               defmodule TrailingUnknown do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   component :table do
                     fields [:title]

                     row_layout do
                       title :title
                       trailing([:scheduled_for])
                     end
                   end
                 end
               end
             end) =~ ~r/scheduled_for/
    end
  end
end
