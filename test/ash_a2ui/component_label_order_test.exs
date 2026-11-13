defmodule AshA2ui.ComponentLabelOrderTest do
  @moduledoc """
  A component's `label` heads its section, and `component_order :declared`
  lays the admin catalog's sections out in declaration order (a record page
  interleaving detail cards and related tables). Without either, headings
  are the humanized component names and tables lead (frozen).
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.{AppointmentsUI, RecordPageUI, Surface}

  defp surface(ui, catalog) do
    Application.put_env(:ash_a2ui, :catalog, catalog)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
    ui |> AshA2ui.Info.build_surface(authorize?: false) |> Surface.components_by_id()
  end

  defp sections(components) do
    Enum.filter(
      components["root"]["children"],
      &String.starts_with?(&1, ["detail_", "data_grid", "records_list", "table_heading"])
    )
  end

  describe "admin catalog" do
    test "labels head the cards and the related table" do
      components = surface(RecordPageUI, :admin_v1)

      assert components["detail_summary_heading"]["text"] == "### At a glance"
      assert components["data_grid"]["label"] == "Visits & follow-ups"
      # No label: the humanized component name, as before.
      assert components["detail_contact_heading"]["text"] == "### Contact"
    end

    test ":declared keeps the cards where they were declared" do
      assert RecordPageUI |> surface(:admin_v1) |> sections() ==
               ["detail_summary", "data_grid", "detail_contact"]
    end

    test ":kind (the default) still places tables first" do
      assert AppointmentsUI |> surface(:admin_v1) |> sections() ==
               ["data_grid", "detail_owner_card", "detail_appointment_detail"]
    end
  end

  describe "basic catalog" do
    test "labels head the cards and the related table; declaration order as always" do
      components = surface(RecordPageUI, :basic)

      assert components["detail_summary_heading"]["text"] == "### At a glance"
      assert components["table_heading"]["text"] == "## Visits & follow-ups"

      assert components |> sections() |> Enum.take(2) ==
               ["detail_summary", "table_heading"]

      assert List.last(sections(components)) == "detail_contact"
    end
  end

  describe "dynamic specs" do
    test "a label imports into the spec; component_order is a visible rejection" do
      {:ok, spec, rejections} = Importer.import(RecordPageUI)

      labels = Map.new(spec["components"], &{&1["name"], &1["label"]})
      assert labels["summary"] == "At a glance"
      assert labels["visits"] == "Visits & follow-ups"
      refute Map.has_key?(labels, nil)

      assert Enum.any?(rejections, &(&1.feature == "component_order"))
    end
  end
end
