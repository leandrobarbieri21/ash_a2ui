defmodule AshA2ui.ReportParamPlaceholdersTest do
  @moduledoc """
  `param_placeholders` on a `:report` component: the admin catalog's param
  TextFields carry the placeholder (and keep their label); the basic catalog's
  take none; a placeholder for a param the report does not have is a
  compile-time error.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshA2ui.Test.WordReportPlaceholderUI

  defp components(catalog) do
    Application.put_env(:ash_a2ui, :catalog, catalog)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)

    WordReportPlaceholderUI
    |> AshA2ui.Info.build_surface(authorize?: false)
    |> Enum.find_value(& &1["updateComponents"])
    |> Map.fetch!("components")
    |> Map.new(&{&1["id"], &1})
  end

  test "the admin param input carries the placeholder and keeps its label" do
    input = components(:admin_v1)["report_lengths_param_min_length"]

    assert input["placeholder"] == "Shortest word to list"
    assert input["label"] == "Min length"
  end

  test "the basic param input takes no placeholder" do
    input = components(:basic)["report_lengths_param_min_length"]

    refute Map.has_key?(input, "placeholder")
  end

  test "a placeholder for a param the report does not have does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule BadPlaceholder do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :report do
              action :length_report
              params [:min_length]
              param_placeholders(nope: "x")
              fields [:word]
            end
          end
        end
      end)

    assert result =~ ~r/param_placeholders names :nope/
  end
end
