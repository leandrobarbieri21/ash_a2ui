defmodule AshA2ui.TableDisplays.MatrixTest do
  @moduledoc """
  `display :matrix`: the server-built grid at `/_matrix_<table>` (rows and
  columns from the data or an enumerated column, the first record per cell,
  a missing value never shown as one), its basic composition under both
  catalogs, its refresh beside the records, and the DSL and composed-surface
  rules.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper
  import ExUnit.CaptureIO

  alias AshA2ui.ActionHandler
  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Error
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Messages
  alias AshA2ui.Test.Surface
  alias AshA2ui.Test.TableDisplays.{ArmMatrixUI, MatrixUI, Result}

  @allowlist Dynamic.allowlist([Result])

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :catalog) end)
    :ok
  end

  defp result!(rank, case_name, candidate, outcome, arm \\ nil) do
    Ash.create!(
      Result,
      %{rank: rank, case_name: case_name, candidate: candidate, outcome: outcome, arm: arm},
      authorize?: false
    )
  end

  defp seed do
    result!(1, "dosage check", "v1", :improved, :baseline)
    result!(2, "dosage check", "v2", :degraded, :candidate)
    result!(3, "allergy flag", "v1", :failed, :baseline)
    # A result with no outcome: the cell is not recorded.
    result!(4, "allergy flag", "v2", nil, :candidate)
    # A second result at a filled cell: the first read wins.
    result!(5, "dosage check", "v1", :skipped, :baseline)
    # Only v2 ran this case: its v1 cell has no record at all.
    result!(6, "triage note", "v2", :unmeasured, :candidate)
  end

  defp components_by_id(components), do: Map.new(components, &{&1["id"], &1})

  defp parts(ui) do
    messages = AshA2ui.Info.build_surface(ui, authorize?: false)
    Enum.each(messages, &assert_valid_agent_message/1)

    components =
      Surface.components(messages)

    value =
      Enum.find_value(messages, fn
        %{"createSurface" => %{"dataModel" => value}} -> value
        %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
        _other -> nil
      end)

    {components_by_id(components), value}
  end

  defp texts(cells), do: Enum.map(cells, & &1["text"])

  defp grid_rows(grid) do
    Enum.map(grid["rows"], fn row -> Enum.map(row["cells"], &{&1["text"], &1["recorded"]}) end)
  end

  describe "the grid" do
    test "rows in read order, columns from the data, one value per cell" do
      seed()
      {_components, value} = parts(MatrixUI)
      grid = value["_matrix_results"]

      assert texts(grid["columns"]) == ["Case name", "v1", "v2"]

      assert grid_rows(grid) == [
               [{"dosage check", true}, {"Improved", true}, {"Degraded", true}],
               [{"allergy flag", true}, {"Failed", true}, {"Not recorded", false}],
               [{"triage note", true}, {"Not recorded", false}, {"Unmeasured", true}]
             ]
    end

    test "a missing or empty cell is never recorded, and never an empty value" do
      result!(1, "allergy flag", "v1", nil)
      result!(2, "triage note", "v2", :failed)
      {_components, value} = parts(MatrixUI)

      cells = Enum.flat_map(value["_matrix_results"]["rows"], &tl(&1["cells"]))

      assert Enum.count(cells, &(&1["recorded"] == false)) == 3
      refute Enum.any?(cells, &(&1["text"] in ["", nil]))

      for %{"recorded" => false} = cell <- cells do
        assert cell["text"] == "Not recorded"
      end
    end

    test "no records is an empty grid, not a grid of values" do
      {_components, value} = parts(MatrixUI)

      assert value["_matrix_results"] == %{
               "columns" => [%{"text" => "Case name"}],
               "rows" => []
             }
    end

    test "an enumerated column keeps every declared value, empty ones too" do
      seed()

      assert [message] = AshA2ui.Info.build_surface(ArmMatrixUI, authorize?: false)
      assert_valid_agent_message(message)

      grid = message["createSurface"]["dataModel"]["_matrix_results"]
      assert texts(grid["columns"]) == ["Case name", "Baseline", "Candidate", "Shadow"]

      assert grid_rows(grid) |> hd() ==
               [
                 {"dosage check", true},
                 {"Improved", true},
                 {"Degraded", true},
                 {"Not recorded", false}
               ]
    end
  end

  describe "the composition" do
    test "a Column of a header Row and a List of Rows, basic catalog only" do
      seed()
      {components, _value} = parts(MatrixUI)

      assert "matrix" in components["root"]["children"]
      refute Map.has_key?(components, "records_list")
      refute Map.has_key?(components, "record_row")

      assert components["matrix"]["children"] == ["matrix_head", "matrix_body"]

      assert components["matrix_head"]["children"] ==
               %{"componentId" => "matrix_heading", "path" => "/_matrix_results/columns"}

      assert components["matrix_body"]["children"] ==
               %{"componentId" => "matrix_row", "path" => "/_matrix_results/rows"}

      assert components["matrix_row"]["children"] ==
               %{"componentId" => "matrix_cell", "path" => "cells"}

      assert components["matrix_cell"]["text"] == %{"@path" => "text"}

      basic =
        "priv/a2ui/v1_0/catalogs/basic/v1/catalog.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("components")
        |> Map.keys()
        |> MapSet.new()

      kinds = components |> Map.values() |> MapSet.new(& &1["component"])
      assert MapSet.subset?(kinds, basic), inspect(MapSet.difference(kinds, basic))
    end

    test "keeps the basic composition under the admin catalog" do
      seed()
      Application.put_env(:ash_a2ui, :catalog, :admin_v1)

      by_id =
        MatrixUI
        |> AshA2ui.Info.build_surface(authorize?: false)
        |> Surface.components()
        |> components_by_id()

      refute Enum.any?(Map.values(by_id), &(&1["component"] == "dataGrid"))
      assert by_id["matrix"]["component"] == "Column"
    end
  end

  describe "refreshing" do
    test "a query action rewrites the grid beside the records" do
      seed()
      {_components, value} = parts(MatrixUI)

      envelope =
        Messages.call("query", "result_matrix", %{
          "component" => "results",
          "query" => Map.put(value["query"], "search", "allergy")
        })

      assert {:ok, messages} = ActionHandler.handle(MatrixUI, envelope, authorize?: false)
      Enum.each(messages, &assert_valid_agent_message/1)

      grid =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/_matrix_results", "value" => grid}} -> grid
          _other -> nil
        end)

      assert grid, "expected a /_matrix_results update in #{inspect(messages)}"
      assert Enum.map(grid["rows"], &hd(&1["cells"])["text"]) == ["allergy flag"]
    end
  end

  describe "rules" do
    defp compile_ui(body) do
      name = "AshA2ui.TableDisplays.MatrixTest.Ui#{System.unique_integer([:positive])}"

      capture_io(:stderr, fn ->
        try do
          Code.compile_string("""
          defmodule #{name} do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.TableDisplays.Result

              query :q do
              end

          #{body}
            end
          end
          """)
        rescue
          error -> IO.puts(:stderr, Exception.message(error))
        end
      end)
    end

    defp table(options, fields \\ "[:case_name, :candidate, :outcome, :rank]") do
      """
          component :table do
            fields #{fields}
      #{options}
          end
      """
    end

    @grid "display :matrix\nrow_field :case_name\ncolumn_field :candidate\ncell_field :outcome"

    test "the DSL rejects an invalid matrix" do
      cases = [
        {table("display :matrix\nrow_field :case_name\ncolumn_field :candidate"),
         ~r/display :matrix needs cell_field/},
        {table("display :matrix"), ~r/display :matrix needs row_field/},
        {table(
           "display :matrix\nrow_field :case_name\ncolumn_field :case_name\ncell_field :outcome"
         ), ~r/must be distinct/},
        {table("display :matrix\nrow_field :case_name\ncolumn_field :nope\ncell_field :outcome"),
         ~r/column_field :nope must be a public attribute/},
        {table(@grid, "[:case_name, :outcome]"),
         ~r/column_field :candidate must be one of the table's fields/},
        {table(@grid <> "\nrow_actions [:destroy]"), ~r/cannot declare row_actions/},
        {table(@grid <> "\nbulk_actions [:destroy]"), ~r/cannot declare bulk_actions/},
        {table("row_field :case_name"), ~r/row_field is only supported with display :matrix/},
        {table("display :list\ncell_field :outcome"),
         ~r/cell_field is only supported with display :matrix/},
        {table("""
         #{@grid}

         sections do
           scope_by :outcome
         end
         """), ~r/cannot declare a sections block/}
      ]

      for {body, pattern} <- cases do
        output = compile_ui(body)
        assert output =~ pattern, "expected #{inspect(pattern)} for:\n#{body}\ngot:\n#{output}"
      end
    end

    test "a valid matrix compiles, with or without declared fields" do
      assert compile_ui(table(@grid <> "\nquery :q")) == ""

      assert compile_ui("""
                 component :table do
             #{@grid}
                 end
             """) == ""
    end

    test "a declared matrix exports to a spec that resolves back" do
      {:ok, spec, _rejections} = Importer.import(MatrixUI)
      [table] = spec["components"]

      assert Map.take(table, ~w(display row_field column_field cell_field)) == %{
               "display" => "matrix",
               "row_field" => "case_name",
               "column_field" => "candidate",
               "cell_field" => "outcome"
             }

      assert {:ok, surface} = Dynamic.resolve(spec, allowlist: @allowlist)

      assert [%{matrix: %{row_field: :case_name}}] =
               ResolvedView.resolve(surface.dsl_state).tables
    end

    test "a composed surface resolves, and rejects what the DSL rejects" do
      spec = fn overrides ->
        %{
          "resource" => "Result",
          "queries" => [%{"name" => "results", "page_size" => 50}],
          "components" => [
            Map.merge(
              %{
                "kind" => "table",
                "name" => "results",
                "display" => "matrix",
                "row_field" => "case_name",
                "column_field" => "candidate",
                "cell_field" => "outcome",
                "query" => "results"
              },
              overrides
            )
          ]
        }
      end

      seed()
      assert {:ok, surface} = Dynamic.resolve(spec.(%{}), allowlist: @allowlist)

      assert [%{matrix: %{row_field: :case_name, column_field: :candidate, cell_field: :outcome}}] =
               ResolvedView.resolve(surface.dsl_state).tables

      messages = Dynamic.build_surface(surface, authorize?: false)
      Enum.each(messages, &assert_valid_agent_message/1)
      value = Surface.data_model(messages)
      assert length(value["_matrix_results"]["rows"]) == 3

      without_cell =
        update_in(spec.(%{}), ["components", Access.at(0)], &Map.delete(&1, "cell_field"))

      for {input, pattern} <- [
            {without_cell, ~r/display :matrix needs cell_field/},
            {spec.(%{"cell_field" => "case_name"}), ~r/must be distinct/},
            {spec.(%{"display" => "list"}), ~r/only supported with display :matrix/},
            {spec.(%{"row_field" => "zz_not_an_attribute_9f3"}),
             ~r/row_field "zz_not_an_attribute_9f3" is not an attribute of the resource/}
          ] do
        assert {:error, errors} = Dynamic.resolve(input, allowlist: @allowlist)
        assert errors |> Error.messages() |> Enum.join("\n") =~ pattern
      end
    end
  end
end
