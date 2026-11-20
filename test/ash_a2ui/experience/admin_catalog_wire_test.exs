defmodule AshA2ui.Experience.AdminCatalogWireTest do
  @moduledoc """
  A2UI-101B/AC-10: an admin surface on the 1.0 wire — the admin catalogId,
  the admin kinds and their bindings, the basic kinds the admin catalog
  renders itself unqualified, every other basic component qualified with the
  basic catalog, and the A2UI-101 ui state.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Experience
  alias AshA2ui.Test.Experience.Task

  setup do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
    end)

    :ok
  end

  @tag ac: "A2UI-101B/AC-10"
  test "an admin surface keeps its kinds, bindings and ui state" do
    [surface] = AshA2ui.Info.build_surface(Task)

    assert %{"version" => "1.0", "createSurface" => create} = surface

    # the admin catalog is the surface's catalog
    assert create["catalogId"] == Experience.admin_catalog_id()

    comps = Map.new(create["components"], &{&1["id"], &1})

    # the admin kinds carry no @catalogId: they are the surface's own
    assert comps["root"]["component"] == "entityPage"
    assert comps["data_grid"]["component"] == "dataGrid"
    assert comps["record_panel"]["component"] == "recordPanel"
    assert comps["status_banner"]["component"] == "statusBanner"
    assert comps["pagination"]["component"] == "pagination"
    refute Map.has_key?(comps["root"], "@catalogId")

    # a basic component on the admin surface names the basic catalog
    assert comps["action_result_text"]["@catalogId"] == AshA2ui.Encoder.basic_catalog_id()

    # the basic kinds the admin catalog renders itself (its accessible inputs
    # and the prompt Modal) name no catalog: they resolve from the admin
    # catalog, the surface's own; every other basic kind names the basic one
    owned = Experience.admin_basic_kinds()
    admin_kinds = Map.keys(admin_catalog()["components"]) -- owned

    for %{"component" => kind} = component <- create["components"] do
      cond do
        kind in owned -> refute Map.has_key?(component, "@catalogId"), kind
        kind in admin_kinds -> refute Map.has_key?(component, "@catalogId"), kind
        true -> assert component["@catalogId"] == AshA2ui.Encoder.basic_catalog_id(), kind
      end
    end

    assert %{"component" => "TextField"} = text_field = comps["form_input_name"]
    refute Map.has_key?(text_field, "@catalogId")

    # bindings are @path bindings into the data model
    assert comps["status_banner"]["kind"] == %{"@path" => "/ui/feedback/kind"}
    assert comps["status_banner"]["message"] == %{"@path" => "/ui/feedback/message"}
    assert comps["record_panel"]["mode"] == %{"@path" => "/ui/panel/mode"}
    assert comps["action_bar"]["primaryLabel"] == %{"@path" => "/ui/panel/primary_label"}
    assert comps["pagination"]["visible"] == %{"@path" => "/query/paginationVisible"}

    # row action envelopes pass through with their row-relative bindings
    [view_action | _rest] = comps["data_grid"]["rowActions"]
    assert view_action["action"] == "view_record"
    assert view_action["context"]["recordId"] == %{"@path" => "id"}
    assert view_action["context"]["component"] == "table"

    # the ActionBar's action is an ashAction call, while the pagination
    # envelopes stay bare (the admin renderer dispatches them itself)
    assert comps["action_bar"]["action"]["functionCall"]["args"]["name"] == "submit_form"
    assert comps["action_bar"]["action"]["functionCall"]["@call"] == "ashAction"

    assert comps["pagination"]["nextAction"] == %{
             "name" => "query",
             "context" => %{
               "query" => %{"@path" => "/query"},
               "pageDelta" => 1,
               "component" => "table"
             }
           }

    # the A2UI-101 experience state: intent, panel and the one feedback map
    ui = create["dataModel"]["ui"]

    assert ui["intent"] == "browse"
    assert ui["panel"]["visible"] == []
    assert ui["feedback"] == AshA2ui.Experience.clear_feedback()

    for retired <- ["status", "response", "action_result", "action_result_text"],
        do: refute(Map.has_key?(ui, retired))
  end

  test "every input kind and the prompt Modal resolve from the admin catalog" do
    owned = Experience.admin_basic_kinds()

    found =
      for module <- surface_modules(),
          [surface] = AshA2ui.Info.build_surface(module, authorize?: false, catalog: :admin_v1),
          %{"component" => kind} = component <- surface["createSurface"]["components"],
          kind in owned do
        refute Map.has_key?(component, "@catalogId"),
               "#{inspect(module)} #{component["id"]} (#{kind}) names a catalog"

        kind
      end

    # the test support's admin surfaces draw every one of them (and each
    # surface validates with the admin catalog as its own: see
    # AshA2ui.SurfaceConformanceTest)
    assert Enum.sort(Enum.uniq(found)) == Enum.sort(owned)
  end

  test "a basic function inside an admin-owned kind names the basic catalog" do
    admin = Experience.admin_catalog_id()
    basic = AshA2ui.Encoder.basic_catalog_id()

    field = %{
      "id" => "form_title",
      "component" => "TextField",
      "label" => %{"@call" => "formatString", "args" => %{"value" => "${/form/title}"}},
      "value" => %{"@path" => "/form/title"}
    }

    qualified = AshA2ui.Encoder.with_catalog(field, admin)
    refute Map.has_key?(qualified, "@catalogId")
    assert qualified["label"]["catalogId"] == basic

    # on a basic surface nothing is qualified
    assert AshA2ui.Encoder.with_catalog(field, basic) == field

    # openSurface is the admin catalog's: unqualified on an admin surface
    open = %{"@call" => "openSurface", "args" => %{"surface" => "tasks"}}

    button = %{
      "id" => "b",
      "component" => "Button",
      "child" => "t",
      "action" => %{"functionCall" => open}
    }

    qualified = AshA2ui.Encoder.with_catalog(button, admin)
    assert qualified["@catalogId"] == basic
    assert qualified["action"]["functionCall"] == open
  end

  # Every AshA2ui surface module the test support compiles.
  defp surface_modules do
    {:ok, modules} = :application.get_key(:ash_a2ui, :modules)

    Enum.filter(modules, fn module ->
      String.starts_with?(inspect(module), "AshA2ui.Test.") and
        Code.ensure_loaded?(module) and
        function_exported?(module, :spark_dsl_config, 0) and
        AshA2ui in Spark.extensions(module) and
        AshA2ui.Info.components(module) != []
    end)
  end

  defp admin_catalog,
    do: "priv/a2ui/admin_v1/catalog.json" |> File.read!() |> Jason.decode!()
end
