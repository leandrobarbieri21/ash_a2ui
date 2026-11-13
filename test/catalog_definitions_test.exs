defmodule AshA2ui.CatalogDefinitionsTest do
  @moduledoc """
  The two catalogs ash_a2ui ships beside the basic catalog are valid A2UI
  1.0 catalog definitions: their structure validates against the vendored
  `catalog_definition.json`, every entity and property name is a UAX #31
  identifier, and every `$ref` is local or one of the `common_types.json`
  targets the catalog rules allow (`SchemaHelper.validate_catalog/1`).
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Test.SchemaHelper

  @ash_catalog "priv/a2ui/v1_0/catalogs/ash_a2ui/catalog.json"
  @admin_catalog "priv/a2ui/admin_v1/catalog.json"

  defp read(path), do: path |> File.read!() |> Jason.decode!()

  for path <- [@ash_catalog, @admin_catalog] do
    test "#{path} is a valid 1.0 catalog definition" do
      catalog = read(unquote(path))

      assert SchemaHelper.validate_catalog(catalog) == :ok
      assert catalog["protocolVersion"] == "1.0"
      assert catalog["$id"] == catalog["catalogId"]
    end

    # a2ui_protocol.md, "Extensions": a third-party extension key MUST carry
    # an organization or product prefix separated by an underscore, and the
    # a2ui_ prefix is reserved for official extensions.
    test "#{path} prefixes its metadata extensions" do
      extensions = get_in(read(unquote(path)), ["metadata", "extensions"]) || %{}

      for key <- Map.keys(extensions) do
        assert key =~ ~r/\A[^_]+_./u, "extension #{inspect(key)} has no prefix"
        refute String.starts_with?(key, "a2ui_"), "extension #{inspect(key)} is reserved"
      end
    end

    test "#{path} names functions with @call and leaves the envelope to ComponentCommon" do
      catalog = read(unquote(path))

      for {name, function} <- catalog["functions"] do
        assert function["properties"]["@call"] == %{"const" => name}
        assert function["required"] == ["@call", "args"]
        refute Map.has_key?(function["properties"], "returnType")
      end

      for {_name, component} <- catalog["components"],
          key <- ~w(id @accessibility @checks @catalogId @metadata) do
        refute Map.has_key?(component["properties"] || %{}, key)
        refute Map.has_key?(component, "unevaluatedProperties")
      end
    end
  end

  describe "the ash_a2ui catalog" do
    setup do
      %{catalog: read(@ash_catalog)}
    end

    test "is not under the a2ui.org specification namespace", %{catalog: catalog} do
      refute catalog["catalogId"] =~ "a2ui.org"
    end

    test "declares no components, so it never matches one in a mixed oneOf", %{catalog: catalog} do
      assert catalog["components"] == %{}
      assert catalog["$defs"]["anyComponent"] == %{"not" => %{}}
    end

    test "ashAction is a renderer-called function that needs a user gesture", %{
      catalog: catalog
    } do
      ash_action = catalog["functions"]["ashAction"]

      assert ash_action["requiresUserActivation"] == true
      assert Map.get(ash_action, "allowedCallers", "rendererOnly") == "rendererOnly"
      assert ash_action["properties"]["args"]["required"] == ["name"]
    end

    test "downloadFile is agent-only", %{catalog: catalog} do
      assert catalog["functions"]["downloadFile"]["allowedCallers"] == "agentOnly"
    end

    test "anyFunction lists every function", %{catalog: catalog} do
      refs = Enum.map(catalog["$defs"]["anyFunction"]["oneOf"], & &1["$ref"])

      assert Enum.sort(refs) ==
               Enum.map(Enum.sort(Map.keys(catalog["functions"])), &"#/functions/#{&1}")
    end
  end

  describe "the admin catalog" do
    setup do
      %{catalog: read(@admin_catalog)}
    end

    test "openSurface runs only from a user gesture in the renderer", %{catalog: catalog} do
      open_surface = catalog["functions"]["openSurface"]

      assert open_surface["requiresUserActivation"] == true
      assert Map.get(open_surface, "allowedCallers", "rendererOnly") == "rendererOnly"
    end

    test "anyComponent and anyFunction list every entry", %{catalog: catalog} do
      for {section, def_name} <- [{"components", "anyComponent"}, {"functions", "anyFunction"}] do
        refs = Enum.map(catalog["$defs"][def_name]["oneOf"], & &1["$ref"])

        assert Enum.sort(refs) ==
                 Enum.map(Enum.sort(Map.keys(catalog[section])), &"#/#{section}/#{&1}")
      end
    end

    test "every $ref is relative", %{catalog: catalog} do
      refs = catalog |> Jason.encode!() |> then(&Regex.scan(~r/"\$ref":"([^"]+)"/, &1))

      for [_, ref] <- refs do
        assert String.starts_with?(ref, "#/") or String.starts_with?(ref, "common_types.json#"),
               "absolute $ref #{ref}"
      end
    end
  end
end
