defmodule AshA2ui.LinkUrlTest do
  @moduledoc """
  Catalog 1.13 plain links: a field's `link_url` names the field holding a
  page or address; rows and detail records carry `_links/<field>` as
  `{href, label}` with no surface, and none when the URL is empty.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.{Appointment, Clinic, LinkedVisitsUI, Owner}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      for resource <- [Appointment, Clinic, Owner], do: Ets.stop(resource)
    end)

    owner = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
    clinic = Ash.create!(Clinic, %{name: "North"}, authorize?: false)

    create =
      &Ash.create!(Appointment, Map.merge(%{owner_id: owner.id, clinic_id: clinic.id}, &1),
        authorize?: false
      )

    %{
      open: create.(%{title: "Checkup"}),
      done: create.(%{title: "Follow-up", status: :completed})
    }
  end

  defp build(opts \\ []) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    [_create, components, data] =
      AshA2ui.Info.build_surface(LinkedVisitsUI, [authorize?: false] ++ opts)

    {Map.new(components["updateComponents"]["components"], &{&1["id"], &1}),
     data["updateDataModel"]["value"]}
  end

  test "a row links its title to the page, and a row without a URL carries no link", %{
    open: open,
    done: done
  } do
    {_components, data} = build()
    rows = Map.new(data["records"], &{&1["id"], &1})

    assert rows[open.id]["_links"]["title"] == %{
             "href" => "/visits/#{open.id}",
             "label" => "Checkup"
           }

    refute Map.has_key?(rows[done.id]["_links"], "title")
  end

  test "a detail card links the same way, and its fieldDisplay binds the link", %{open: open} do
    {components, data} =
      build(context_state: %{"visit" => %{"search" => "", "value" => open.id, "label" => "x"}})

    assert data["detail"]["visit"]["_links"]["title"] == %{
             "href" => "/visits/#{open.id}",
             "label" => "Checkup"
           }

    assert components["detail_visit_card_field_title"]["link"] == %{
             "path" => "/detail/visit/_links/title"
           }
  end

  test "the grid column binds the link" do
    {components, _data} = build()
    title = Enum.find(components["data_grid"]["columns"], &(&1["path"] == "title"))
    assert title["link"] == %{"path" => "_links/title"}
  end

  test "dynamic specs carry it" do
    {:ok, spec, _rejections} = Importer.import(LinkedVisitsUI)
    assert %{"link_url" => "page_url"} = Enum.find(spec["fields"], &(&1["name"] == "title"))
  end

  describe "compile-time checks" do
    test "link_url with another kind of link" do
      assert capture_io(:stderr, fn ->
               defmodule UrlAndLink do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   component :table do
                     fields [:title, :owner_id]
                   end

                   field :owner_id do
                     link :owner
                     link_url(:page_url)
                   end
                 end
               end
             end) =~ ~r/link_url cannot be combined with link, links or source/
    end

    test "link_url naming no field" do
      assert capture_io(:stderr, fn ->
               defmodule UrlUnknown do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   component :table do
                     fields [:title]
                   end

                   field :title do
                     link_url(:nowhere)
                   end
                 end
               end
             end) =~ ~r/link_url names :nowhere/
    end
  end
end
