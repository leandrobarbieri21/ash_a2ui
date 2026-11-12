defmodule AshA2ui.GroupedRowsTest do
  @moduledoc """
  Catalog 1.14 grouped list rows: a row layout's `group_by`, `group_subtitle`
  and `group_icon`, and a component's `section_note` under its section's
  heading.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.{Appointment, Clinic, GroupedVisitsUI, Owner}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      for resource <- [Appointment, Clinic, Owner], do: Ets.stop(resource)
    end)

    owner = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
    clinic = Ash.create!(Clinic, %{name: "North"}, authorize?: false)

    Ash.create!(Appointment, %{title: "Checkup", owner_id: owner.id, clinic_id: clinic.id},
      authorize?: false
    )

    %{owner: owner}
  end

  defp build(catalog, opts \\ []) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [_create, components, data] =
      AshA2ui.Info.build_surface(GroupedVisitsUI, [authorize?: false] ++ opts)

    {Map.new(components["updateComponents"]["components"], &{&1["id"], &1}),
     data["updateDataModel"]["value"]}
  end

  defp selected(owner),
    do: [context_state: %{"owner" => %{"search" => "", "value" => owner.id, "label" => "x"}}]

  test "the admin grid places the group's columns and carries the icon" do
    {components, _data} = build(:admin_v1)
    grid = components["data_grid"]

    assert grid["groupIcon"] == "home"

    placements = Map.new(grid["columns"], &{&1["path"], &1["placement"]})

    assert placements == %{
             "title" => nil,
             "scheduled_for" => "trailing",
             "clinic_id" => "group",
             "status" => "groupSubtitle"
           }
  end

  test "a column carries its field's empty text" do
    {components, _data} = build(:admin_v1)
    title = Enum.find(components["data_grid"]["columns"], &(&1["path"] == "title"))
    assert title["emptyText"] == "Untitled"
  end

  test "the default meta leaves the group's fields out" do
    view = AshA2ui.ResolvedView.resolve(GroupedVisitsUI)
    [%{component: %{row_layout: layout}}] = view.tables

    assert layout.meta == []
    assert layout.group_by == :clinic_id
    assert layout.group_subtitle == :status
  end

  test "the basic card shows the group's fields in its metadata grid" do
    {components, _data} = build(:basic)
    ids = Map.keys(components)

    assert Enum.any?(ids, &String.ends_with?(&1, "_meta_cell_clinic_id"))
    assert Enum.any?(ids, &String.ends_with?(&1, "_meta_cell_status"))
  end

  test "the section's note sits under its heading, read with the context's record", %{
    owner: owner
  } do
    {components, data} = build(:admin_v1, selected(owner))

    assert ["section_visits_heading", "section_visits_note" | _tables] =
             components["section_visits"]["children"]

    assert components["section_visits_note"]["text"] == %{"path" => "/detail/owner/name"}
    assert components["section_visits_note"]["variant"] == "caption"
    assert data["detail"]["owner"]["name"] == "Ada"
  end

  test "the note updates when the context changes", %{owner: owner} do
    view = AshA2ui.ResolvedView.resolve(GroupedVisitsUI)
    assert [%{context: :owner, fields: [:name]}] = view.section_notes

    {_components, data} = build(:admin_v1)
    assert data["detail"]["owner"] == %{}

    {_components, data} = build(:admin_v1, selected(owner))
    assert data["detail"]["owner"]["name"] == "Ada"
  end

  test "dynamic specs carry the group and the note" do
    {:ok, spec, _rejections} = Importer.import(GroupedVisitsUI)
    [visits] = spec["components"]

    assert visits["section_note"] == "name"
    assert visits["row_layout"]["group_by"] == "clinic_id"
    assert visits["row_layout"]["group_subtitle"] == "status"
    assert visits["row_layout"]["group_icon"] == "home"
  end

  test "imported specs with list rows, groups, notes and plain links resolve again" do
    allow = AshA2ui.Dynamic.allowlist([Owner, Appointment, Clinic])

    for ui <- [GroupedVisitsUI, AshA2ui.Test.OwnerVisitsUI, AshA2ui.Test.LinkedVisitsUI] do
      {:ok, spec, _rejections} = Importer.import(ui)
      assert {:ok, %AshA2ui.Dynamic.Surface{}} = AshA2ui.Dynamic.resolve(spec, allowlist: allow)
    end
  end

  describe "compile-time checks" do
    test "a group subtitle without a group" do
      assert capture_io(:stderr, fn ->
               defmodule SubtitleWithoutGroup do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   component :table do
                     fields [:title, :status]

                     row_layout do
                       title :title
                       group_subtitle :status
                     end
                   end
                 end
               end
             end) =~ ~r/group_subtitle without a group_by/
    end

    test "a section note without a section" do
      assert capture_io(:stderr, fn ->
               defmodule NoteWithoutSection do
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
                     section_note :name
                   end
                 end
               end
             end) =~ ~r/needs a section/
    end

    test "a section note the context's resource does not have" do
      assert capture_io(:stderr, fn ->
               defmodule NoteUnknown do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Owner

                   context :owner do
                     resource AshA2ui.Test.Owner
                     picker false
                   end

                   component :detail, :card do
                     section "Owner"
                     context :owner
                     fields [:email]
                     section_note :nickname
                   end
                 end
               end
             end) =~ ~r/:nickname is not a public attribute/
    end
  end
end
