defmodule AshA2ui.Experience.CatalogNegotiationTest do
  @moduledoc """
  The per-build `:catalog` option and `AshA2ui.Experience.catalog_for/1`,
  which reads a client's A2UI 1.0 renderer capabilities
  (`supportedCatalogIds`). Every surface calls the ash_a2ui catalog's
  `ashAction`, so a client must list it beside the basic catalog. A client
  without the admin catalog gets the basic composition; a client that lists
  no catalog set this library emits is told so, never handed a surface it
  cannot render.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Experience
  alias AshA2ui.Test.Experience.Task
  alias AshA2ui.Test.Messages
  alias AshA2ui.Test.Surface

  @admin "https://github.com/lukegalea/ash_a2ui/catalogs/admin/v2"
  @basic "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
  @ash "https://github.com/lukegalea/ash_a2ui/catalogs/ash_a2ui/v1"

  setup do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
    :ok
  end

  defp caps(ids), do: %{"1.0" => %{"supportedCatalogIds" => ids}}

  defp components_by_id(components_message) do
    Surface.components_by_id(components_message)
  end

  describe "catalog_for/1" do
    test "a client listing the admin catalog gets it when it is configured" do
      assert Experience.catalog_for(caps([@admin, @basic, @ash])) == {:ok, :admin_v1}
    end

    test "a client without the admin catalog falls back to basic" do
      assert Experience.catalog_for(caps([@basic, @ash])) == {:ok, :basic}
    end

    test "a client without the ash_a2ui catalog cannot run the surface's actions" do
      assert Experience.catalog_for(caps([@basic])) == {:error, :no_common_catalog}
      assert Experience.catalog_for(caps([@admin, @basic])) == {:error, :no_common_catalog}
    end

    test "the admin catalog is never chosen when the host configured basic" do
      Application.put_env(:ash_a2ui, :catalog, :basic)

      assert Experience.catalog_for(caps([@admin, @basic, @ash])) == {:ok, :basic}
      assert Experience.catalog_for(caps([@admin, @ash])) == {:error, :no_common_catalog}
    end

    test "no capabilities sent is the configured catalog" do
      assert Experience.catalog_for(nil) == {:ok, :admin_v1}
    end

    test "capabilities naming no catalog this library emits are not a fallback to basic" do
      for capabilities <- [
            caps([]),
            caps(["https://example.com/catalogs/other.json"]),
            %{"1.0" => %{}},
            %{"1.0" => %{"supportedCatalogIds" => "not a list"}},
            %{"1.0" => %{"supportedCatalogIds" => [nil, 3]}},
            %{"v1.0" => %{"supportedCatalogIds" => [@basic, @ash]}},
            %{"v0.9" => %{"supportedCatalogIds" => [@basic, @ash]}},
            %{"2.0" => %{"supportedCatalogIds" => [@basic, @ash]}},
            %{},
            "1.0"
          ] do
        assert Experience.catalog_for(capabilities) == {:error, :no_common_catalog},
               "#{inspect(capabilities)} was read as a supported catalog"
      end
    end
  end

  describe "the :catalog build option" do
    test "basic for one build under a configured admin catalog" do
      [%{"createSurface" => %{"components" => components, "dataModel" => _data}} = create] =
        built = AshA2ui.Info.build_surface(Task, catalog: :basic)

      assert create["createSurface"]["catalogId"] == @basic
      assert components_by_id(components)["root"]["component"] == "Column"

      Application.put_env(:ash_a2ui, :catalog, :basic)
      assert built == AshA2ui.Info.build_surface(Task, [])
      Enum.each(built, &assert_valid_agent_message/1)
    end

    test "the basic createSurface leaves the admin pagination booleans out" do
      [%{"createSurface" => create}] =
        AshA2ui.Info.build_surface(Task, catalog: :basic)

      refute Map.has_key?(create["dataModel"]["query"], "paginationVisible")
    end

    test "admin for one build under a configured basic catalog" do
      Application.put_env(:ash_a2ui, :catalog, :basic)

      [%{"createSurface" => %{"components" => components, "dataModel" => _data}} = create] =
        AshA2ui.Info.build_surface(Task, catalog: :admin_v1)

      assert create["createSurface"]["catalogId"] == @admin
      assert components_by_id(components)["root"]["component"] == "entityPage"
    end

    test "omitted, the configured catalog is used" do
      [%{"createSurface" => %{"components" => _components, "dataModel" => _data}} = create] =
        AshA2ui.Info.build_surface(Task, [])

      assert create["createSurface"]["catalogId"] == @admin
    end

    test "an unknown catalog is refused" do
      assert_raise ArgumentError, ~r/catalog must be/, fn ->
        AshA2ui.Info.build_surface(Task, catalog: :fancy)
      end
    end

    test "the action handler's refresh follows the build's catalog" do
      envelope =
        Messages.call("query", "experience_task", %{"query" => %{}, "page" => 1},
          source: "query_apply_button"
        )

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
