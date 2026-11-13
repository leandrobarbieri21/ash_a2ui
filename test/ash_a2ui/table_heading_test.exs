defmodule AshA2ui.TableHeadingTest do
  @moduledoc """
  Catalog 1.18 table card headers: a table's `heading` and `description`,
  the header of its own card and the caption under it, above its rows.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.{Appointment, Clinic, HeadedVisitsUI, Owner, RecordPageUI, SchemaHelper}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      for resource <- [Appointment, Clinic, Owner], do: Ets.stop(resource)
    end)

    owner = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
    %{owner: owner}
  end

  defp build(ui, catalog, owner) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(ui,
        authorize?: false,
        context_state: %{"owner" => %{"search" => "", "value" => owner.id, "label" => "x"}}
      )

    catalogs = if catalog == :admin_v1, do: SchemaHelper.admin_catalogs()
    SchemaHelper.assert_valid_agent_message(message, catalogs: catalogs)

    Map.new(surface["components"], &{&1["id"], &1})
  end

  test "a declared heading and description ride on the grid, empty or not", %{owner: owner} do
    components = build(HeadedVisitsUI, :admin_v1, owner)

    visits = components["data_grid_visits"]
    assert visits["heading"] == "Visit history"
    assert visits["description"] == "Each visit for this owner. Details come from the latest."

    schedule = components["data_grid_schedule"]
    assert schedule["layout"] == "rows"
    assert schedule["heading"] == "Schedule"
    refute Map.has_key?(schedule, "description")

    # Both tables share the section's one heading.
    assert components["section_visits"]["children"] ==
             ["section_visits_heading", "data_grid_visits", "data_grid_schedule"]
  end

  test "a label is not a heading: no declared heading, no heading key", %{owner: owner} do
    all = build(HeadedVisitsUI, :admin_v1, owner)["data_grid_all_visits"]
    assert all["label"] == "All visits"
    refute Map.has_key?(all, "heading")
    refute Map.has_key?(all, "description")

    page = build(RecordPageUI, :admin_v1, owner)
    refute Enum.any?(Map.values(page), &Map.has_key?(&1, "heading"))
  end

  test "the basic catalog draws them as Texts just before the table", %{owner: owner} do
    components = build(HeadedVisitsUI, :basic, owner)

    assert components["table_visits_card_heading"] == %{
             "id" => "table_visits_card_heading",
             "component" => "Text",
             "text" => "### Visit history"
           }

    assert components["table_visits_card_description"]["text"] ==
             "Each visit for this owner. Details come from the latest."

    assert components["table_visits_card_description"]["variant"] == "caption"

    children = components["section_visits"]["children"]

    assert Enum.drop_while(children, &(&1 != "table_visits_card_heading")) |> Enum.take(3) ==
             ["table_visits_card_heading", "table_visits_card_description", "records_list_visits"]

    assert "table_schedule_card_heading" in children
    refute Map.has_key?(components, "table_schedule_card_description")
    refute Map.has_key?(components, "table_all_visits_card_heading")
  end

  test "dynamic specs carry them, and resolve again" do
    {:ok, spec, _rejections} = Importer.import(HeadedVisitsUI)
    visits = Enum.find(spec["components"], &(&1["name"] == "visits"))

    assert visits["heading"] == "Visit history"
    assert visits["description"] == "Each visit for this owner. Details come from the latest."

    allow = AshA2ui.Dynamic.allowlist([Owner, Appointment, Clinic])
    assert {:ok, %AshA2ui.Dynamic.Surface{}} = AshA2ui.Dynamic.resolve(spec, allowlist: allow)
  end

  describe "compile-time checks" do
    test "a heading on a detail card" do
      assert capture_io(:stderr, fn ->
               defmodule HeadingOnDetail do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Owner

                   context :owner do
                     resource AshA2ui.Test.Owner
                     picker false
                   end

                   component :detail, :card do
                     context :owner
                     fields [:email]
                     heading("Contact")
                   end
                 end
               end
             end) =~ ~r/heading is for tables/
    end

    test "a description on a board" do
      assert capture_io(:stderr, fn ->
               defmodule DescriptionOnBoard do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.BoardTask

                   component :table, :board do
                     fields [:name, :status]
                     display :board
                     description("Open work first.")

                     row_layout do
                       title :name
                     end

                     sections do
                       scope_by :status
                       values [:open, :claimed]
                     end
                   end
                 end
               end
             end) =~ ~r/description is not drawn on a board lane/
    end
  end
end
