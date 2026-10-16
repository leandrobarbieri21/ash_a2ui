defmodule AshA2ui.ReportTest do
  @moduledoc """
  Aggregate/report queries: `:report` components declare a generic Ash
  action whose computed row maps render as a table-like section with param
  inputs and a Run button — data under the reserved `/report/<name>` paths,
  the `"report"` client action invoking the allowlisted action actor-scoped.
  Schema-validated on both v0.9.1 and v1.0.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.BucketWord
  alias AshA2ui.Test.WordReportUI
  alias AshA2ui.Test.WordReportV1UI

  defp envelope(name, context, surface \\ "word_report") do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => surface,
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _ -> nil
    end)
  end

  defp create_word!(word) do
    Ash.create!(BucketWord, %{word: word}, authorize?: false)
  end

  describe "resolution" do
    test "a :report component resolves with params defaulted from the action" do
      view = ResolvedView.resolve(WordReportUI)

      assert [report] = view.reports

      assert report.name == :lengths
      assert report.action == :length_report
      assert report.params == [:min_length]
      assert report.fields == [:word, :length, :state]
      assert report.path == "/report/lengths"
    end

    test "omitted params default to all of the action's arguments" do
      defmodule DefaultParamsUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.BucketWord
          surface_id "default_params"

          component :report do
            action :length_report
            fields [:word]
          end
        end
      end

      view = ResolvedView.resolve(DefaultParamsUI)
      assert [%{name: :report, params: [:min_length]}] = view.reports
    end

    test "report state seeds empty params and rows" do
      view = ResolvedView.resolve(WordReportUI)

      assert ResolvedView.report_state(view) == %{
               "lengths" => %{"params" => %{"min_length" => ""}, "rows" => []}
             }
    end
  end

  describe "encoder (v0.9.1)" do
    setup do
      messages = AshA2ui.Info.build_surface(WordReportUI, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      components =
        messages
        |> Enum.find_value(& &1["updateComponents"])
        |> Map.fetch!("components")
        |> Map.new(&{&1["id"], &1})

      data_model =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
          _ -> nil
        end)

      %{components: components, data_model: data_model}
    end

    test "the report section renders heading, params, run button and list", %{
      components: components
    } do
      assert "report_lengths" in components["root"]["children"]

      assert components["report_lengths_body"]["children"] == [
               "report_lengths_heading",
               "report_lengths_param_min_length",
               "report_lengths_run_button",
               "report_lengths_list"
             ]

      param = components["report_lengths_param_min_length"]
      assert param["component"] == "TextField"
      assert param["value"] == %{"path" => "/report/lengths/params/min_length"}

      event = components["report_lengths_run_button"]["action"]["event"]
      assert event["name"] == "report"

      assert event["context"] == %{
               "component" => "lengths",
               "params" => %{"path" => "/report/lengths/params"}
             }

      assert components["report_lengths_list"]["children"] == %{
               "componentId" => "report_lengths_row",
               "path" => "/report/lengths/rows"
             }

      assert components["report_lengths_row_content"]["children"] == [
               "report_lengths_cell_word",
               "report_lengths_cell_length",
               "report_lengths_cell_state"
             ]

      assert components["report_lengths_cell_length_value"]["text"] == %{"path" => "length"}
    end

    test "the initial data model carries the reserved /report region", %{
      data_model: data_model
    } do
      assert data_model["report"] == %{
               "lengths" => %{"params" => %{"min_length" => ""}, "rows" => []}
             }
    end
  end

  describe "action handler" do
    setup do
      create_word!("ab")
      create_word!("abcdef")
      :ok
    end

    test ~s(the "report" action runs the declared generic action with cast params) do
      message = envelope("report", %{"params" => %{"min_length" => "3"}})

      assert {:ok, messages} = ActionHandler.handle(WordReportUI, message, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      assert value_at(messages, "/report/lengths/rows") == [
               %{"word" => "abcdef", "length" => 6, "state" => "new"}
             ]

      assert value_at(messages, "/ui/feedback")["message"] == "Report complete: 1 row."
    end

    test "missing params run the action with defaults" do
      message = envelope("report", %{"params" => %{}})

      assert {:ok, messages} = ActionHandler.handle(WordReportUI, message, authorize?: false)
      assert length(value_at(messages, "/report/lengths/rows")) == 2
    end

    test "rows are trimmed to the declared field allowlist" do
      message = envelope("report", %{"params" => %{"min_length" => ""}})

      assert {:ok, messages} = ActionHandler.handle(WordReportUI, message, authorize?: false)

      for row <- value_at(messages, "/report/lengths/rows") do
        assert Map.keys(row) |> Enum.sort() == ["length", "state", "word"]
      end
    end

    test "params outside the declared allowlist are dropped before the cast" do
      message =
        envelope("report", %{"params" => %{"min_length" => "3", "bogus" => "x"}})

      assert {:ok, _messages} = ActionHandler.handle(WordReportUI, message, authorize?: false)
    end

    test "a failing report action maps onto the standard error messages" do
      defmodule BrokenReportUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.BucketWord
          surface_id "broken_report"

          component :report do
            action :broken_report
            fields [:word]
          end
        end
      end

      message = envelope("report", %{"params" => %{}}, "broken_report")

      assert {:error, messages} = ActionHandler.handle(BrokenReportUI, message, authorize?: false)
      assert value_at(messages, "/ui/feedback")["message"] =~ "Request failed"
    end

    test "a surface without reports rejects the action" do
      message = envelope("report", %{"params" => %{}}, "editable_words")

      assert {:error, messages} =
               ActionHandler.handle(AshA2ui.Test.EditableWordsUI, message, authorize?: false)

      assert value_at(messages, "/ui/feedback")["message"] =~ "declares no :report components"
    end
  end

  describe "v1.0" do
    setup do
      create_word!("abcdef")
      :ok
    end

    test "the surface bootstraps as one schema-valid inline createSurface" do
      assert [message] = AshA2ui.Info.build_surface(WordReportV1UI, authorize?: false)
      assert_valid_server_message(message, :v1_0)

      assert message["createSurface"]["dataModel"]["report"] == %{
               "lengths" => %{"params" => %{"min_length" => ""}, "rows" => []}
             }

      run =
        Enum.find(
          message["createSurface"]["components"],
          &(&1["id"] == "report_lengths_run_button")
        )

      assert run["action"]["event"]["wantResponse"] == true
    end

    test "a report run answers its actionId with the structured result" do
      message = %{
        "version" => "v1.0",
        "action" => %{
          "name" => "report",
          "surfaceId" => "word_report_v1",
          "actionId" => "run_1",
          "context" => %{"params" => %{"min_length" => "1"}}
        }
      }

      assert {:ok, [response | followups]} =
               ActionHandler.handle(WordReportV1UI, message, authorize?: false)

      assert response["actionId"] == "run_1"

      assert %{"value" => %{"status" => "ok", "result" => %{"count" => 1}}} =
               response["actionResponse"]

      assert_valid_server_message(response, :v1_0)
      Enum.each(followups, &assert_valid_server_message(&1, :v1_0))

      assert [%{"word" => "abcdef"}] = value_at(followups, "/report/lengths/rows")

      # the status Text binds /ui/feedback/message on v1.0 too
      assert value_at(followups, "/ui/feedback") == %{
               "kind" => "success",
               "message" => "Report complete: 1 row."
             }
    end
  end
end

defmodule AshA2ui.ReportVerifierTest do
  @moduledoc """
  Compile-time failure tests for `AshA2ui.Verifiers.VerifyReports`.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "a report without an action does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule NoAction do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :report do
              fields [:word]
            end
          end
        end
      end)

    assert result =~ ~r/must declare the generic `action` it runs/
  end

  test "a report without fields does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule NoFields do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :report do
              action :length_report
            end
          end
        end
      end)

    assert result =~ ~r/must declare its `fields`/
  end

  test "a report action that is not generic does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule NotGeneric do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :report do
              action :approve
              fields [:word]
            end
          end
        end
      end)

    assert result =~ ~r/is not a generic \(action-type\) action/
  end

  test "report params outside the action's arguments do not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule BadParams do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :report do
              action :length_report
              params([:nope])
              fields [:word]
            end
          end
        end
      end)

    assert result =~ ~r/report param :nope is not an argument of action/
  end

  test "action/params on a non-report component do not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule ActionOnTable do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :table do
              fields [:word]
              action :length_report
            end
          end
        end
      end)

    assert result =~ ~r/cannot declare `action`\/`params`/
  end

  test "a report with table options does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule ReportWithQuery do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            query :q do
              search_fields [:word]
            end

            component :report do
              action :length_report
              fields [:word]
              query :q
            end
          end
        end
      end)

    assert result =~ ~r/cannot declare :query/
  end
end
