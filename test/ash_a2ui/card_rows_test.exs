defmodule AshA2ui.CardRowsTest do
  @moduledoc """
  Catalog 1.16 card rows: `display :cards`, a row layout's `expand_label`, a
  field's `pairs`, and a badge that is already words.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.{Appointment, CardVisitsUI, Clinic, Owner}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      for resource <- [Appointment, Clinic, Owner], do: Ets.stop(resource)
    end)

    owner = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
    clinic = Ash.create!(Clinic, %{name: "North"}, authorize?: false)

    visit =
      Ash.create!(
        Appointment,
        %{title: "Checkup", status: :completed, owner_id: owner.id, clinic_id: clinic.id},
        authorize?: false
      )

    %{owner: owner, visit: visit}
  end

  defp build(catalog, owner) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [_create, components, data] =
      AshA2ui.Info.build_surface(CardVisitsUI,
        authorize?: false,
        context_state: %{"owner" => %{"search" => "", "value" => owner.id, "label" => "x"}}
      )

    {Map.new(components["updateComponents"]["components"], &{&1["id"], &1}),
     data["updateDataModel"]["value"]}
  end

  test "the admin grid asks for cards, names the disclosure and marks the pairs", %{owner: owner} do
    {components, _data} = build(:admin_v1, owner)
    grid = components["data_grid"]

    assert grid["layout"] == "cards"
    assert grid["expandLabel"] == "Show clinic"

    columns = Map.new(grid["columns"], &{&1["path"], &1})
    assert columns["details"]["pairs"] == true
    refute Map.has_key?(columns["title"], "pairs")
    assert columns["clinic_id"]["placement"] == "expand"
  end

  test "a row carries its pairs as a list of term and value", %{owner: owner} do
    {_components, data} = build(:admin_v1, owner)
    [row] = data["records"]

    assert row["details"] == [
             %{"term" => "Title", "value" => "Checkup"},
             %{"term" => "Status", "value" => "completed"}
           ]
  end

  test "a badge already in words is shown as written", %{owner: owner} do
    {_components, data} = build(:admin_v1, owner)
    [row] = data["records"]

    assert row["_badge_seen_by"] == "Seen by Dr. Checkup"
  end

  test "an identifier-like string badge is still humanized" do
    layout = %AshA2ui.RowLayout{title: :title, badge: :title}
    record = struct(Appointment, title: "in_review")

    assert AshA2ui.RowLayout.badge_data(layout, record)["_badge_title"] == "In review"
  end

  test "the basic card keeps the expand field in its metadata", %{owner: owner} do
    {components, _data} = build(:basic, owner)
    ids = Map.keys(components)

    assert Enum.any?(ids, &String.ends_with?(&1, "_meta_cell_clinic_id"))
    assert Enum.any?(ids, &String.ends_with?(&1, "_meta_cell_details"))
  end

  test "dynamic specs carry the display, the label and the pairs" do
    {:ok, spec, _rejections} = Importer.import(CardVisitsUI)
    [visits] = spec["components"]

    assert visits["display"] == "cards"
    assert visits["row_layout"]["expand_label"] == "Show clinic"
    assert Enum.find(spec["fields"], &(&1["name"] == "details"))["pairs"] == true

    allow = AshA2ui.Dynamic.allowlist([Owner, Appointment, Clinic])
    assert {:ok, %AshA2ui.Dynamic.Surface{}} = AshA2ui.Dynamic.resolve(spec, allowlist: allow)
  end

  describe "compile-time checks" do
    test "display :cards without a row layout" do
      assert capture_io(:stderr, fn ->
               defmodule CardsWithoutLayout do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   component :table do
                     display :cards
                     fields [:title]
                   end
                 end
               end
             end) =~ ~r/display :cards requires a row_layout/
    end

    test "an expand label without expand fields" do
      assert capture_io(:stderr, fn ->
               defmodule LabelWithoutExpand do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   component :table do
                     fields [:title]

                     row_layout do
                       title :title
                       expand_label("Show more")
                     end
                   end
                 end
               end
             end) =~ ~r/expand_label without expand fields/
    end
  end
end
