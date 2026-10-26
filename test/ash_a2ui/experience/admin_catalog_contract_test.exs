defmodule AshA2ui.Experience.AdminCatalogContractTest do
  @moduledoc """
  A2UI-101B/AC-1 + AC-12: the admin catalog definition declares the full
  ten-component contract vocabulary with the pinned property names, and the
  renderer asset in priv/js registers the same vocabulary — structurally
  (the visual/accessibility evidence is the host-app Playwright tier).
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Experience

  @admin_catalog_path "priv/a2ui/admin_v1/catalog.json"
  @renderer_asset_path "priv/js/ash_admin_catalog.js"

  # The ten contract kinds in contract order
  # (notes/2026-09-07-admin-catalog-contract.md).
  @kinds ~w(entityPage dataGrid emptyState pagination recordPanel fieldDisplay formSection actionBar statusBanner confirmDialog)

  # Kinds added after 1.0, each additive within the catalog id.
  @additive_kinds ~w(calendarView liveDiagram)

  # The pinned property names per kind, straight from the contract.
  @pinned_props %{
    "entityPage" => ~w(title description children),
    "dataGrid" => ~w(columns rows rowId label rowActions children),
    "emptyState" => ~w(message children),
    "pagination" => ~w(page pageSize total hasNext visible previousVisible nextVisible rangeText),
    "recordPanel" => ~w(mode title recordId children),
    "fieldDisplay" => ~w(label value format),
    "formSection" => ~w(title columns children),
    "actionBar" => ~w(primaryLabel busy destructive action children),
    "statusBanner" => ~w(kind message),
    "confirmDialog" => ~w(title body confirmLabel destructive)
  }

  @tag ac: "A2UI-101B/AC-1"
  test "catalog declares the full component vocabulary" do
    assert {:ok, catalog} =
             @admin_catalog_path |> File.read!() |> Jason.decode()

    assert catalog["catalogId"] == Experience.admin_catalog_id()
    assert Map.keys(catalog["components"]) |> Enum.sort() == Enum.sort(@kinds ++ @additive_kinds)

    Enum.each(@kinds, fn kind ->
      component = catalog["components"][kind]
      assert is_map(component), "catalog component #{kind} is missing"

      declared = MapSet.new(Map.keys(component["properties"] || %{}))

      Enum.each(@pinned_props[kind], fn prop ->
        assert MapSet.member?(declared, prop),
               "catalog component #{kind} does not declare pinned property #{prop}"
      end)

      assert component["properties"]["component"]["const"] == kind
    end)
  end

  test "catalog 1.1 is additive: version, column hints, rowClick, field links, openSurface" do
    catalog = @admin_catalog_path |> File.read!() |> Jason.decode!()

    assert catalog["version"] == Experience.admin_catalog_version()
    assert catalog["catalogId"] == Experience.admin_catalog_id()

    grid = catalog["components"]["dataGrid"]
    column = grid["properties"]["columns"]["items"]
    assert column["required"] == ["label", "path"]

    for hint <- ~w(format align mono badge link) do
      assert Map.has_key?(column["properties"], hint), "column hint #{hint} missing"
    end

    refute "rowClick" in grid["required"]
    assert Map.has_key?(grid["properties"], "rowClick")
    assert Map.has_key?(catalog["components"]["fieldDisplay"]["properties"], "link")

    open_surface = catalog["functions"]["openSurface"]
    assert open_surface["properties"]["call"]["const"] == "openSurface"
    assert open_surface["properties"]["args"]["required"] == ["surface"]

    source = File.read!(@renderer_asset_path)

    assert source =~
             ~s(export const ADMIN_CATALOG_VERSION = "#{Experience.admin_catalog_version()}")

    assert source =~ ~s(name: "openSurface")
  end

  @tag ac: "A2UI-107/AC-4"
  test "catalog 1.3 is additive: calendarView" do
    catalog = @admin_catalog_path |> File.read!() |> Jason.decode!()

    assert catalog["catalogId"] == Experience.admin_catalog_id()

    calendar = catalog["components"]["calendarView"]
    assert calendar["properties"]["component"]["const"] == "calendarView"

    assert calendar["required"] ==
             ["component", "granularity", "window", "windowAction", "children"]

    assert calendar["properties"]["granularity"]["enum"] == ["day", "week", "month"]
    assert Map.has_key?(catalog["x-changelog"], "1.3.0")
  end

  test "catalog 1.6 is additive: entityPage headerVisible" do
    catalog = @admin_catalog_path |> File.read!() |> Jason.decode!()

    assert catalog["version"] == "1.6.0"
    assert Experience.admin_catalog_version() == "1.6.0"
    assert Map.has_key?(catalog["x-changelog"], "1.6.0")

    page = catalog["components"]["entityPage"]
    assert page["properties"]["headerVisible"]["type"] == "boolean"
    assert page["required"] == ["component", "title", "children"]
  end

  test "catalog 1.5 is additive: calendarView granularities" do
    catalog = @admin_catalog_path |> File.read!() |> Jason.decode!()

    assert Map.has_key?(catalog["x-changelog"], "1.5.0")

    sizes = catalog["components"]["calendarView"]["properties"]["granularities"]
    assert sizes["items"]["enum"] == ["day", "week", "month"]
  end

  @tag ac: "A2UI-108/AC-4"
  test "catalog 1.4 is additive: liveDiagram" do
    catalog = @admin_catalog_path |> File.read!() |> Jason.decode!()

    assert catalog["catalogId"] == Experience.admin_catalog_id()

    diagram = catalog["components"]["liveDiagram"]
    assert diagram["properties"]["component"]["const"] == "liveDiagram"
    assert diagram["required"] == ["component", "source", "markers"]
    assert Map.has_key?(catalog["x-changelog"], "1.4.0")
  end

  @tag ac: "A2UI-101B/AC-12"
  test "renderer asset declares the component vocabulary" do
    assert File.exists?(@renderer_asset_path),
           "renderer asset #{@renderer_asset_path} is missing"

    source = File.read!(@renderer_asset_path)

    # the public surface: createAshAdminCatalog/1 (+ default export)
    assert source =~ "export function createAshAdminCatalog"
    assert source =~ "export default createAshAdminCatalog"

    # the admin catalog id the encoder emits on createSurface
    assert source =~ Experience.admin_catalog_id()

    # all ten contract kinds (and the additive ones) registered under their
    # ash-admin-* tags
    Enum.each(@kinds ++ @additive_kinds, fn kind ->
      assert Regex.match?(~r/#{kind}:\s*"ash-admin-/, source),
             "renderer asset does not register #{kind}"
    end)
  end
end
