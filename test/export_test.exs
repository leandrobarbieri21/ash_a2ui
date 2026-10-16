defmodule AshA2ui.ExportTest do
  @moduledoc """
  CSV file export (v1.0-only): `export` blocks on `:table` / `:report`
  components render an Export CSV button dispatching the `"export"` client
  action; the server re-runs the component's data and answers with the
  frozen `downloadFile` callFunction carrying a base64 `text/csv` data URL.
  Column selection rides the reserved `/export/<name>/columns` paths.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Csv
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.BucketWord
  alias AshA2ui.Test.ExportWordsV1UI
  alias AshA2ui.Test.SchemaHelper
  alias AshA2ui.Test.WordReportV1UI

  defp envelope(name, context, surface) do
    %{
      "version" => "v1.0",
      "action" => %{
        "name" => name,
        "surfaceId" => surface,
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp create_word!(word, replacement \\ nil) do
    Ash.create!(BucketWord, %{word: word, replacement: replacement}, authorize?: false)
  end

  defp download(messages) do
    Enum.find_value(messages, fn
      %{"callFunction" => %{"call" => "downloadFile", "args" => args}} -> args
      _ -> nil
    end)
  end

  # downloadFile is declared by the shipped AshA2ui extension catalog (not
  # the basic catalog), so callFunction messages validate against it; every
  # other message validates against the plain v1.0 schemas.
  defp assert_valid_export_messages(messages) do
    extension_schema =
      SchemaHelper.resolved_schema(:v1_0, "server_to_client.json",
        catalog: "catalogs/ash_a2ui/catalog.json"
      )

    Enum.each(messages, fn
      %{"callFunction" => _call} = message ->
        assert :ok = SchemaHelper.validate(extension_schema, message)

      message ->
        assert_valid_server_message(message, :v1_0)
    end)
  end

  defp csv_of(args) do
    ["data:text/csv;base64," <> base64] = [args["dataUrl"]]
    Base.decode64!(base64)
  end

  describe "AshA2ui.Csv" do
    test "encodes headers + rows CRLF-separated with RFC-4180 quoting" do
      csv = Csv.encode(["Word", "Note"], [["teh", ~s(a "quoted", note)], ["adn", nil]])

      assert csv == "Word,Note\r\nteh,\"a \"\"quoted\"\", note\"\r\nadn,\r\n"
    end

    test "data_url/1 wraps the binary as a base64 text/csv data URL" do
      assert Csv.data_url("a,b\r\n") == "data:text/csv;base64," <> Base.encode64("a,b\r\n")
    end
  end

  describe "resolution" do
    test "a table export resolves with the filename and columns defaulted" do
      view = ResolvedView.resolve(ExportWordsV1UI)

      assert [%{export: export}] = view.tables

      assert export == %{
               filename: "table.csv",
               columns: [:word, :replacement],
               column_select: false,
               limit: 100
             }
    end

    test "a report export resolves onto the report with column_select state seeded" do
      view = ResolvedView.resolve(WordReportV1UI)

      assert [%{export: export}] = view.reports
      assert export.filename == "word_lengths.csv"
      assert export.columns == [:word, :length, :state]
      assert export.column_select

      assert ResolvedView.export_state(view) == %{
               "lengths" => %{
                 "columns" => %{"word" => true, "length" => true, "state" => true}
               }
             }
    end

    test "surfaces without column-selectable exports carry no /export state" do
      assert ResolvedView.export_state(ResolvedView.resolve(ExportWordsV1UI)) == %{}
    end
  end

  describe "encoder" do
    test "a table export renders the Export CSV button with the table conventions" do
      assert [message] = AshA2ui.Info.build_surface(ExportWordsV1UI, authorize?: false)
      assert_valid_server_message(message, :v1_0)

      components = Map.new(message["createSurface"]["components"], &{&1["id"], &1})

      assert "export_controls" in components["root"]["children"]
      assert components["export_controls"]["children"] == ["export_button"]

      event = components["export_button"]["action"]["event"]
      assert event["name"] == "export"
      assert event["wantResponse"] == true

      assert event["context"] == %{
               "component" => "table",
               "query" => %{"path" => "/query"}
             }
    end

    test "a column-selectable report export renders checkboxes bound to /export paths" do
      assert [message] = AshA2ui.Info.build_surface(WordReportV1UI, authorize?: false)
      assert_valid_server_message(message, :v1_0)

      components = Map.new(message["createSurface"]["components"], &{&1["id"], &1})

      assert components["report_lengths_export_controls"]["children"] == [
               "report_lengths_export_column_word",
               "report_lengths_export_column_length",
               "report_lengths_export_column_state",
               "report_lengths_export_button"
             ]

      checkbox = components["report_lengths_export_column_length"]
      assert checkbox["component"] == "CheckBox"
      assert checkbox["value"] == %{"path" => "/export/lengths/columns/length"}

      event = components["report_lengths_export_button"]["action"]["event"]

      assert event["context"] == %{
               "component" => "lengths",
               "params" => %{"path" => "/report/lengths/params"},
               "columns" => %{"path" => "/export/lengths/columns"}
             }

      assert message["createSurface"]["dataModel"]["export"] == %{
               "lengths" => %{
                 "columns" => %{"word" => true, "length" => true, "state" => true}
               }
             }
    end
  end

  describe "table export" do
    setup do
      create_word!("teh", "the")
      create_word!("adn", "and")
      create_word!("wrold", "world")
      :ok
    end

    test "exports the full filtered set as a downloadFile callFunction" do
      message = envelope("export", %{}, "export_words_v1")

      assert {:ok, messages} = ActionHandler.handle(ExportWordsV1UI, message, authorize?: false)
      assert_valid_export_messages(messages)

      args = download(messages)
      assert args["filename"] == "table.csv"
      assert args["mimeType"] == "text/csv"

      # page_size is 2, but the export ignores pagination: all 3 rows
      [header | rows] = csv_of(args) |> String.trim_trailing() |> String.split("\r\n")
      assert header == "Word,Replacement"
      assert Enum.sort(rows) == ["adn,and", "teh,the", "wrold,world"]
    end

    test "the export honors the carried query search" do
      message =
        envelope("export", %{"query" => %{"search" => "teh", "page" => 2}}, "export_words_v1")

      assert {:ok, messages} = ActionHandler.handle(ExportWordsV1UI, message, authorize?: false)

      assert csv_of(download(messages)) == "Word,Replacement\r\nteh,the\r\n"
    end

    test "a successful export answers the actionId with the structured result" do
      message = %{
        "version" => "v1.0",
        "action" => %{
          "name" => "export",
          "surfaceId" => "export_words_v1",
          "actionId" => "ex_1",
          "context" => %{}
        }
      }

      assert {:ok, [response | _followups]} =
               ActionHandler.handle(ExportWordsV1UI, message, authorize?: false)

      assert response["actionId"] == "ex_1"

      assert %{"value" => %{"status" => "ok", "result" => %{"rows" => 3}}} =
               response["actionResponse"]
    end

    test "a successful export reports a success /ui/feedback for the status Text" do
      message = envelope("export", %{}, "export_words_v1")

      assert {:ok, messages} = ActionHandler.handle(ExportWordsV1UI, message, authorize?: false)

      assert Enum.find_value(messages, fn
               %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => value}} -> value
               _other -> nil
             end) == %{"kind" => "success", "message" => "Exported table.csv (3 rows)."}
    end
  end

  describe "table export of an enum column" do
    test "cells carry the stored enum value, not the table's display label" do
      Ash.create!(AshA2ui.Test.Appointment, %{title: "Checkup", status: :completed},
        authorize?: false
      )

      message = envelope("export", %{}, "export_appointments_v1")

      assert {:ok, messages} =
               ActionHandler.handle(AshA2ui.Test.ExportAppointmentsV1UI, message,
                 authorize?: false
               )

      assert csv_of(download(messages)) == "Title,Status\r\nCheckup,completed\r\n"
    end
  end

  describe "report export" do
    setup do
      create_word!("ab")
      create_word!("abcdef")
      :ok
    end

    test "re-runs the report with the carried params and exports its rows" do
      message =
        envelope(
          "export",
          %{"params" => %{"min_length" => "3"}, "columns" => %{"word" => true, "length" => true}},
          "word_report_v1"
        )

      assert {:ok, messages} = ActionHandler.handle(WordReportV1UI, message, authorize?: false)

      args = download(messages)
      assert args["filename"] == "word_lengths.csv"
      assert csv_of(args) == "Word,Length\r\nabcdef,6\r\n"
    end

    test "the column selection narrows and orders by the declared columns" do
      message =
        envelope(
          "export",
          %{"params" => %{}, "columns" => %{"state" => true, "word" => false, "length" => false}},
          "word_report_v1"
        )

      assert {:ok, messages} = ActionHandler.handle(WordReportV1UI, message, authorize?: false)

      assert csv_of(download(messages)) == "State\r\nnew\r\nnew\r\n"
    end

    test "an every-column-unchecked selection is rejected" do
      message =
        envelope(
          "export",
          %{
            "params" => %{},
            "columns" => %{"word" => false, "length" => false, "state" => false}
          },
          "word_report_v1"
        )

      assert {:error, messages} =
               ActionHandler.handle(WordReportV1UI, message, authorize?: false)

      response =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/ui/response", "value" => value}} -> value
          _ -> nil
        end)

      assert response["message"] =~ "at least one column"
    end
  end
end

defmodule AshA2ui.ExportVerifierTest do
  @moduledoc """
  Compile-time failure tests for `AshA2ui.Verifiers.VerifyExport`.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "an export on a 0.9.1 surface does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule ExportOn091 do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :table do
              fields [:word]

              export do
                filename "words.csv"
              end
            end
          end
        end
      end)

    assert result =~ ~r/export is v1\.0-only/
  end

  test "an export on a form component does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule ExportOnForm do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord
            spec_version("1.0")

            component :form do
              fields [:word]

              export do
                filename "words.csv"
              end
            end
          end
        end
      end)

    assert result =~ ~r/only supported on :table and :report components/
  end

  test "export columns outside the component's fields do not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule ExportUnknownColumn do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord
            spec_version("1.0")

            component :table do
              fields [:word]

              export do
                columns [:word, :nope]
              end
            end
          end
        end
      end)

    assert result =~ ~r/export column :nope is not one of component/
  end
end
