defmodule AshA2ui.Experience.SurfaceHeaderTest do
  @moduledoc """
  `header: false` leaves the surface's own heading out, for a host page that
  already renders one: a second `<h1>` is a duplicate and an outline error.

  Basic catalog: the `surface_title` Text and its root child are not emitted.
  Admin catalog: the `entityPage` keeps its required title and carries
  `headerVisible: false` (catalog 1.6), so the renderer skips its header.
  Without the option both outputs are exactly as before.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Test.Experience.EstateUser
  alias AshA2ui.Test.SchemaHelper

  setup do
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
    :ok
  end

  defp components(opts) do
    [_create, components, _data] = AshA2ui.Info.build_surface(EstateUser, [actor: nil] ++ opts)
    components["updateComponents"]["components"]
  end

  defp by_id(components), do: Map.new(components, &{&1["id"], &1})

  describe "basic catalog" do
    test "the surface title is the root's first child by default" do
      components = by_id(components([]))

      assert %{"component" => "Text", "variant" => "h1"} = components["surface_title"]
      assert "surface_title" in components["root"]["children"]
    end

    test "header: false leaves the title out, and the root does not reference it" do
      components = components(header: false)
      ids = by_id(components)

      refute Map.has_key?(ids, "surface_title")
      refute "surface_title" in ids["root"]["children"]

      [_create, message, _data] =
        AshA2ui.Info.build_surface(EstateUser, actor: nil, header: false)

      SchemaHelper.assert_valid_server_message(message)
    end

    test "header: false changes nothing else" do
      default = components([])
      without = components(header: false)

      expected =
        default
        |> Enum.reject(&(&1["id"] == "surface_title"))
        |> Enum.map(fn
          %{"id" => "root"} = root ->
            Map.update!(root, "children", &List.delete(&1, "surface_title"))

          component ->
            component
        end)

      assert without == expected
    end
  end

  describe "admin catalog" do
    setup do
      Application.put_env(:ash_a2ui, :catalog, :admin_v1)
      :ok
    end

    defp entity_page(opts), do: Enum.find(components(opts), &(&1["component"] == "entityPage"))

    test "the entityPage carries no headerVisible by default" do
      refute Map.has_key?(entity_page([]), "headerVisible")
    end

    test "header: false keeps the title and marks the header hidden, as catalog 1.6 declares" do
      default = entity_page([])
      page = entity_page(header: false)

      assert page["title"] == default["title"]
      assert page["headerVisible"] == false

      catalog = "priv/a2ui/admin_v1/catalog.json" |> File.read!() |> Jason.decode!()

      schema =
        catalog["components"]["entityPage"]
        |> Map.put("$defs", catalog["$defs"] || %{})
        |> ExJsonSchema.Schema.resolve()

      # headerVisible adds no schema error. (The literal string title is
      # reported against the catalog's object-typed title on the default
      # page too; that predates this option.)
      assert ExJsonSchema.Validator.validate(schema, page) ==
               ExJsonSchema.Validator.validate(schema, default)
    end

    test "header: false changes nothing but the entityPage" do
      default = components([])
      without = components(header: false)

      assert Enum.reject(without, &(&1["component"] == "entityPage")) ==
               Enum.reject(default, &(&1["component"] == "entityPage"))
    end
  end
end
