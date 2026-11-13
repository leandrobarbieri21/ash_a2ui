defmodule AshA2ui.V10ConformanceTest do
  @moduledoc """
  The upstream A2UI 1.0 schema conformance corpus, run through
  `AshA2ui.Test.SchemaHelper` with no exceptions.

  It mirrors the reference runner (`specification/v1_0/test/run_tests.py`,
  ajv in draft 2020-12 mode with formats) step for step, over the files
  vendored in `priv/a2ui/v1_0` (see its NOTES.md):

    1. every case of every suite in `test/cases/*.json` validates or fails
       exactly as labelled, with the suite's `"catalog"` alias applied;
    2. every line of `contact_form_example.jsonl` is a valid message;
    3. the basic catalog and the testing catalog are valid catalogs
       (structure, UAX #31 identifiers, restricted `$ref` targets);
    4. `sample.json` and the capability, data-model and list-wrapper schemas
       accept the runner's own minimal payloads.

  A case that fails here is a bug in the helper or the vendored copy, never
  a known gap.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Test.SchemaHelper
  alias AshA2ui.Test.SchemaHelper.Resolver

  @cases_dir Path.join(Resolver.dir(), "test/cases")
  @basic_catalog_id "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"

  for file <-
        @cases_dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".json")) |> Enum.sort() do
    suite = @cases_dir |> Path.join(file) |> File.read!() |> Jason.decode!()
    schema_file = Map.get(suite, "schema", "agent_to_renderer.json")
    catalog = suite |> Map.get("catalog") |> then(&(&1 && Path.join("test", &1)))

    describe "upstream suite #{file}" do
      for {test_case, index} <- suite |> Map.fetch!("tests") |> Enum.with_index(1) do
        description = Map.get(test_case, "description", "case #{index}")
        valid? = Map.get(test_case, "valid", true)

        @tag :v1_0_conformance
        test "##{index} [#{if valid?, do: "valid", else: "invalid"}] #{description}" do
          schema = SchemaHelper.spec_schema(unquote(schema_file), catalogs: unquote(catalog))
          result = SchemaHelper.validate(schema, unquote(Macro.escape(test_case["data"])))

          if unquote(valid?) do
            assert result == :ok, "upstream-valid case failed validation: #{inspect(result)}"
          else
            assert {:error, [_ | _]} = result, "upstream-invalid case validated"
          end
        end
      end
    end
  end

  describe "upstream contact_form_example.jsonl" do
    test "every line is a valid agent-to-renderer message" do
      lines =
        @cases_dir
        |> Path.join("contact_form_example.jsonl")
        |> File.read!()
        |> String.split("\n", trim: true)

      assert lines != []

      for line <- lines, do: line |> Jason.decode!() |> SchemaHelper.assert_valid_agent_message()
    end
  end

  describe "upstream catalogs" do
    for catalog <- ["catalogs/basic/v1/catalog.json", "test/testing_catalog.json"] do
      test "#{catalog} is a valid catalog" do
        unquote(catalog) |> Resolver.read!() |> SchemaHelper.assert_valid_catalog()
      end
    end

    test "the catalog rules reject what the upstream runner rejects" do
      basic = Resolver.read!("catalogs/basic/v1/catalog.json")

      bad_name = put_in(basic, ["components", "Bad-Name"], basic["components"]["Text"])
      assert {:error, errors} = SchemaHelper.validate_catalog(bad_name)
      assert "invalid component name: \"Bad-Name\"" in errors

      bad_ref =
        put_in(basic, ["components", "Text", "properties", "text"], %{
          "$ref" => "common_types.json#/$defs/ComponentCommon"
        })

      assert {:error, errors} = SchemaHelper.validate_catalog(bad_ref)

      assert "disallowed external $ref target: \"common_types.json#/$defs/ComponentCommon\"" in errors

      any =
        put_in(basic, ["components", "Text", "properties", "text"], %{
          "$ref" => "#/$defs/anyComponent"
        })

      assert {:error, errors} = SchemaHelper.validate_catalog(any)
      assert "disallowed $ref target: \"#/$defs/anyComponent\"" in errors
    end
  end

  describe "upstream schema integrity payloads" do
    @create %{
      "version" => "1.0",
      "createSurface" => %{"surfaceId" => "test_surface", "catalogId" => @basic_catalog_id}
    }

    @action %{
      "version" => "1.0",
      "action" => %{
        "name" => "click_button",
        "surfaceId" => "test_surface",
        "sourceComponentId" => "btn_1",
        "timestamp" => "2026-06-22T17:00:00Z",
        "context" => %{}
      }
    }

    test "sample.json" do
      payload = %{
        "name" => "Test Sample",
        "description" => "A minimal sample for testing schema integrity",
        "messages" => [@create]
      }

      assert SchemaHelper.validate(SchemaHelper.spec_schema("sample.json"), payload) == :ok
    end

    test "capabilities, data model and list wrappers" do
      for {file, payload} <- [
            {"renderer_capabilities.json",
             %{"1.0" => %{"supportedCatalogIds" => [@basic_catalog_id], "inlineCatalogs" => []}}},
            {"agent_capabilities.json",
             %{
               "1.0" => %{
                 "supportedCatalogIds" => [@basic_catalog_id],
                 "acceptsInlineCatalogs" => true
               }
             }},
            {"renderer_data_model.json",
             %{
               "version" => "1.0",
               "surfaces" => %{"surface_123" => %{"user" => %{"name" => "Alice"}}}
             }},
            {"agent_to_renderer_list_wrapper.json", %{"messages" => [@create]}},
            {"renderer_to_agent_list_wrapper.json", %{"messages" => [@action]}}
          ] do
        assert SchemaHelper.validate(SchemaHelper.spec_schema(file), payload) == :ok, file
      end
    end
  end
end
