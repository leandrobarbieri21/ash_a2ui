defmodule AshA2ui.SectionsHeadingTest do
  @moduledoc """
  Catalog 1.12 record page sections: consecutive components naming the same
  `section` share one headed wrapper (`section_<first key>`), a card in a
  section without a label of its own draws no heading, and a field's `note`.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.{OwnerOverviewUI, SchemaHelper, Surface}

  setup do
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
  end

  defp surface(catalog) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    OwnerOverviewUI
    |> AshA2ui.Info.build_surface(authorize?: false)
    |> Surface.components_by_id()
    |> Surface.unqualified()
  end

  for catalog <- [:admin_v1, :basic] do
    test "#{catalog}: a section wraps its run of components under one heading" do
      components = surface(unquote(catalog))
      root = components["root"]["children"]

      assert "section_details" in root
      assert "section_visits" in root
      refute "detail_details" in root

      assert components["section_details"]["children"] ==
               ["section_details_heading", "detail_details", "detail_contact"]

      assert components["section_details_heading"] ==
               %{
                 "id" => "section_details_heading",
                 "component" => "Text",
                 "text" => "## Overview"
               }

      assert components["section_visits_heading"]["text"] == "## Visits"
    end

    test "#{catalog}: a labelled card keeps its heading, an unlabelled one has none" do
      components = surface(unquote(catalog))

      assert components["detail_details_heading"]["text"] == "### Details"
      refute Map.has_key?(components, "detail_contact_heading")
      refute "detail_contact_heading" in components["detail_contact_body"]["children"]
    end
  end

  test "the sectioned surfaces validate against their catalogs" do
    for {catalog, catalogs} <- [admin_v1: SchemaHelper.admin_catalogs(), basic: nil] do
      Application.put_env(:ash_a2ui, :catalog, catalog)
      opts = if catalogs, do: [catalogs: catalogs], else: []

      OwnerOverviewUI
      |> AshA2ui.Info.build_surface(authorize?: false)
      |> SchemaHelper.assert_valid_agent_messages(opts)
    end
  end

  test "the admin fieldDisplay carries the note" do
    components = surface(:admin_v1)
    assert components["detail_contact_field_email"]["note"] == "From sign-up"
    refute Map.has_key?(components["detail_details_field_name"], "note")
  end

  test "surfaces without sections encode no wrappers" do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    ids =
      AshA2ui.Test.RecordPageUI
      |> AshA2ui.Info.build_surface(authorize?: false)
      |> Surface.components()
      |> Enum.map(& &1["id"])

    refute Enum.any?(ids, &String.starts_with?(&1, "section_"))
  end

  test "dynamic specs carry the section and the note" do
    {:ok, spec, _rejections} = Importer.import(OwnerOverviewUI)

    sections = Map.new(spec["components"], &{&1["name"], &1["section"]})
    assert sections == %{"details" => "Overview", "contact" => "Overview", "visits" => "Visits"}

    assert %{"note" => "From sign-up"} = Enum.find(spec["fields"], &(&1["name"] == "email"))
  end
end
