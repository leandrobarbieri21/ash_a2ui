defmodule AshA2ui.DocumentRowsTest do
  @moduledoc """
  Catalog 1.15 document rows and table footers: a row layout's `leading`
  field, a plain link that downloads (`download`), and a table's
  `footer_note` and `footer_link` under its rows.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.{Appointment, Clinic, DocumentVisitsUI, Owner}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      for resource <- [Appointment, Clinic, Owner], do: Ets.stop(resource)
    end)

    owner = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
    clinic = Ash.create!(Clinic, %{name: "North"}, authorize?: false)

    visit =
      Ash.create!(Appointment, %{title: "Checkup", owner_id: owner.id, clinic_id: clinic.id},
        authorize?: false
      )

    %{owner: owner, visit: visit}
  end

  defp build(catalog, owner) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [_create, components, data] =
      AshA2ui.Info.build_surface(DocumentVisitsUI,
        authorize?: false,
        context_state: %{"owner" => %{"search" => "", "value" => owner.id, "label" => "x"}}
      )

    {Map.new(components["updateComponents"]["components"], &{&1["id"], &1}),
     data["updateDataModel"]["value"]}
  end

  test "the leading field is placed, and leaves the default meta", %{owner: owner} do
    {components, _data} = build(:admin_v1, owner)
    placements = Map.new(components["data_grid"]["columns"], &{&1["path"], &1["placement"]})

    assert placements["status"] == "leading"
    assert placements["title"] == nil

    [%{component: %{row_layout: layout}}] = AshA2ui.ResolvedView.resolve(DocumentVisitsUI).tables
    assert layout.leading == :status
    refute :status in layout.meta
  end

  test "a download link says so", %{owner: owner, visit: visit} do
    {_components, data} = build(:admin_v1, owner)
    [row] = data["records"]

    assert row["_links"]["title"] == %{
             "href" => "/visits/#{visit.id}",
             "label" => "Checkup",
             "download" => true
           }
  end

  test "the footer note and link ride on the grid, read with the context's record", %{
    owner: owner
  } do
    {components, data} = build(:admin_v1, owner)
    grid = components["data_grid"]

    assert grid["footerNote"] == %{"path" => "/detail/owner/name"}
    assert grid["footerLink"] == %{"href" => "#all", "label" => "All visits"}
    assert data["detail"]["owner"]["name"] == "Ada"
  end

  test "the basic catalog leaves the footer out and keeps the leading field in the card", %{
    owner: owner
  } do
    {components, _data} = build(:basic, owner)

    refute Enum.any?(Map.values(components), &Map.has_key?(&1, "footerNote"))
    assert Enum.any?(Map.keys(components), &String.ends_with?(&1, "_meta_cell_status"))
  end

  test "dynamic specs carry them, and resolve again" do
    {:ok, spec, _rejections} = Importer.import(DocumentVisitsUI)
    [visits] = spec["components"]

    assert visits["row_layout"]["leading"] == "status"
    assert visits["footer_note"] == "name"
    assert visits["footer_link"] == %{"href" => "#all", "label" => "All visits"}
    assert Enum.find(spec["fields"], &(&1["name"] == "title"))["download"] == true

    allow = AshA2ui.Dynamic.allowlist([Owner, Appointment, Clinic])
    assert {:ok, %AshA2ui.Dynamic.Surface{}} = AshA2ui.Dynamic.resolve(spec, allowlist: allow)
  end

  describe "compile-time checks" do
    test "download without a link_url" do
      assert capture_io(:stderr, fn ->
               defmodule DownloadWithoutUrl do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   component :table do
                     fields [:title]
                   end

                   field :title do
                     download(true)
                   end
                 end
               end
             end) =~ ~r/download needs a link_url/
    end

    test "a footer on a detail card" do
      assert capture_io(:stderr, fn ->
               defmodule FooterOnDetail do
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
                     footer_note(:name)
                   end
                 end
               end
             end) =~ ~r/is for tables/
    end

    test "a footer note the context's resource does not have" do
      assert capture_io(:stderr, fn ->
               defmodule FooterUnknown do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Owner

                   context :owner do
                     resource AshA2ui.Test.Owner
                     picker false
                   end

                   component :table, :visits do
                     resource AshA2ui.Test.Appointment
                     fields [:title]
                     context_filter owner_id: :owner
                     footer_note(:nickname)
                   end
                 end
               end
             end) =~ ~r/:nickname is not a public attribute/
    end
  end
end
