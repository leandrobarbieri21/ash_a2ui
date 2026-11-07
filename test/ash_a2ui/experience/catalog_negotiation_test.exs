defmodule AshA2ui.Experience.CatalogNegotiationTest do
  @moduledoc """
  The per-build `:catalog` option and `AshA2ui.Experience.catalog_for/1`,
  which reads a client's A2UI client capabilities (`supportedCatalogIds`).
  A client without the admin catalog gets the basic composition; a client
  that lists no catalog this library emits is told so, never handed a
  surface it cannot render.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Experience
  alias AshA2ui.Test.Experience.Task

  @admin "https://ash-a2ui.dev/catalogs/admin/v1"
  @basic_v1_0 "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
  @basic_v0_9 "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"

  setup do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
    :ok
  end

  defp caps(version \\ "v1.0", ids), do: %{version => %{"supportedCatalogIds" => ids}}

  defp components_by_id(components_message) do
    Map.new(components_message["updateComponents"]["components"], &{&1["id"], &1})
  end

  describe "catalog_for/1" do
    test "a client listing the admin catalog gets it when it is configured" do
      assert Experience.catalog_for(caps([@admin, @basic_v1_0])) == {:ok, :admin_v1}
    end

    test "a client without the admin catalog falls back to basic" do
      assert Experience.catalog_for(caps([@basic_v1_0])) == {:ok, :basic}
      assert Experience.catalog_for(caps("v0.9", [@basic_v0_9])) == {:ok, :basic}
    end

    test "the admin catalog is never chosen when the host configured basic" do
      Application.put_env(:ash_a2ui, :catalog, :basic)

      assert Experience.catalog_for(caps([@admin, @basic_v1_0])) == {:ok, :basic}
      assert Experience.catalog_for(caps([@admin])) == {:error, :no_common_catalog}
    end

    test "no capabilities sent is the configured catalog" do
      assert Experience.catalog_for(nil) == {:ok, :admin_v1}
    end

    test "capabilities naming no catalog this library emits are not a fallback to basic" do
      for capabilities <- [
            caps([]),
            caps(["https://example.com/catalogs/other.json"]),
            %{"v1.0" => %{}},
            %{"v1.0" => %{"supportedCatalogIds" => "not a list"}},
            %{"v1.0" => %{"supportedCatalogIds" => [nil, 3]}},
            %{"v2.0" => %{"supportedCatalogIds" => [@basic_v1_0]}},
            %{},
            "v1.0"
          ] do
        assert Experience.catalog_for(capabilities) == {:error, :no_common_catalog},
               "#{inspect(capabilities)} was read as a supported catalog"
      end
    end
  end

  describe "the :catalog build option" do
    test "basic for one build under a configured admin catalog" do
      [create, components, _data] = built = AshA2ui.Info.build_surface(Task, catalog: :basic)

      assert create["createSurface"]["catalogId"] == @basic_v0_9
      assert components_by_id(components)["root"]["component"] == "Column"

      Application.put_env(:ash_a2ui, :catalog, :basic)
      assert built == AshA2ui.Info.build_surface(Task, [])
      Enum.each(built, &assert_valid_server_message/1)
    end

    test "the v1.0 createSurface names the basic catalog" do
      [%{"createSurface" => create}] =
        AshA2ui.Info.build_surface(Task, catalog: :basic, spec_version: "1.0")

      assert create["catalogId"] == @basic_v1_0
      refute Map.has_key?(create["dataModel"]["query"], "paginationVisible")
    end

    test "admin for one build under a configured basic catalog" do
      Application.put_env(:ash_a2ui, :catalog, :basic)

      [create, components, _data] = AshA2ui.Info.build_surface(Task, catalog: :admin_v1)

      assert create["createSurface"]["catalogId"] == @admin
      assert components_by_id(components)["root"]["component"] == "entityPage"
    end

    test "omitted, the configured catalog is used" do
      [create, _components, _data] = AshA2ui.Info.build_surface(Task, [])
      assert create["createSurface"]["catalogId"] == @admin
    end

    test "an unknown catalog is refused" do
      assert_raise ArgumentError, ~r/catalog must be/, fn ->
        AshA2ui.Info.build_surface(Task, catalog: :fancy)
      end
    end

    test "the action handler's refresh follows the build's catalog" do
      envelope = %{
        "version" => "v0.9.1",
        "action" => %{
          "name" => "query",
          "surfaceId" => "experience_task",
          "sourceComponentId" => "query_apply_button",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
          "context" => %{"query" => %{}, "page" => 1}
        }
      }

      query_state = fn messages ->
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/query", "value" => value}} -> value
          _other -> nil
        end)
      end

      {:ok, basic} = ActionHandler.handle(Task, envelope, catalog: :basic)
      {:ok, admin} = ActionHandler.handle(Task, envelope, [])

      refute Map.has_key?(query_state.(basic), "paginationVisible")
      assert Map.has_key?(query_state.(admin), "paginationVisible")
    end
  end
end
