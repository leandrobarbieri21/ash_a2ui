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
  alias AshA2ui.Experience
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.BucketWord
  alias AshA2ui.Test.ExportWordsV1UI
  alias AshA2ui.Test.Messages
  alias AshA2ui.Test.WordReportV1UI

  defp envelope(name, context, surface) do
    Messages.call(name, surface, context, id: "call-1")
  end

  defp create_word!(word, replacement \\ nil) do
    Ash.create!(BucketWord, %{word: word, replacement: replacement}, authorize?: false)
  end

  defp download(messages) do
    Enum.find_value(messages, fn
      %{"callRendererFunction" => %{"callFunction" => %{"@call" => "downloadFile"} = call}} ->
        call["args"]

      _ ->
        nil
    end)
  end

  # downloadFile is declared by the shipped ash_a2ui catalog, not the basic
  # catalog, so the follow-ups validate against both.
  defp assert_valid_export_messages(messages),
    do: assert_valid_agent_messages(messages, catalogs: Messages.catalogs())

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
               limit: 100,
               loads: []
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
      assert_valid_agent_message(message)

      components = Map.new(message["createSurface"]["components"], &{&1["id"], &1})

      assert "export_controls" in components["root"]["children"]
      assert components["export_controls"]["children"] == ["export_button"]

      event = components["export_button"]["action"]["functionCall"]["args"]
      assert event["name"] == "export"

      assert event["context"] == %{
               "component" => "table",
               "query" => %{"@path" => "/query"}
             }
    end

    test "a column-selectable report export renders checkboxes bound to /export paths" do
      assert [message] = AshA2ui.Info.build_surface(WordReportV1UI, authorize?: false)
      assert_valid_agent_message(message)

      components = Map.new(message["createSurface"]["components"], &{&1["id"], &1})

      assert components["report_lengths_export_controls"]["children"] == [
               "report_lengths_export_column_word",
               "report_lengths_export_column_length",
               "report_lengths_export_column_state",
               "report_lengths_export_button"
             ]

      checkbox = components["report_lengths_export_column_length"]
      assert checkbox["component"] == "CheckBox"
      assert checkbox["value"] == %{"@path" => "/export/lengths/columns/length"}

      event = components["report_lengths_export_button"]["action"]["functionCall"]["args"]

      assert event["context"] == %{
               "component" => "lengths",
               "params" => %{"@path" => "/report/lengths/params"},
               "columns" => %{"@path" => "/export/lengths/columns"}
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

    test "an export called as ashAction pushes the download, then answers the call" do
      message = Messages.call("export", "export_words_v1", %{}, id: "ex_1")

      assert {:ok, messages} = ActionHandler.handle(ExportWordsV1UI, message, authorize?: false)
      assert_valid_export_messages(messages)

      assert [%{"callRendererFunction" => _download} | _rest] = messages

      assert %{"agentFunctionResponse" => %{"functionCallId" => "ex_1", "value" => value}} =
               List.last(messages)

      assert %{"kind" => "success", "result" => %{"filename" => "table.csv", "rows" => 3}} =
               value
    end

    test "a successful export reports a success /ui/feedback for the status Text" do
      message = envelope("export", %{}, "export_words_v1")

      assert {:ok, messages} = ActionHandler.handle(ExportWordsV1UI, message, authorize?: false)

      assert Enum.find_value(messages, fn
               %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => value}} -> value
               _other -> nil
             end) ==
               Experience.feedback("success", "Exported table.csv (3 rows).", %{
                 "result" => %{"filename" => "table.csv", "rows" => 3},
                 "functionCallId" => "call-1"
               })
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

  describe "table export of columns the table does not show" do
    alias AshA2ui.Test.ExportContract
    alias AshA2ui.Test.ExportContractLine
    alias AshA2ui.Test.ExportContractsUI

    @header "Name,Contract value,Status,Currency,Priced name,Line count,Margin"

    setup do
      acme = contract!("Acme", value: "1200.50", currency: "CAD", status: :active, margin: "9")
      contract!("Beta", value: "80", currency: "USD", margin: "4")
      contract!("Hidden", value: "1", currency: "CAD", secret: true)
      contract!("Old", value: "2", currency: "USD", archived: true)

      for _line <- 1..2 do
        Ash.create!(ExportContractLine, %{contract_id: acme.id}, authorize?: false)
      end

      :ok
    end

    defp contract!(name, attrs) do
      Ash.create!(ExportContract, Map.new([{:name, name} | attrs]), authorize?: false)
    end

    defp export_csv(context, opts) do
      message = envelope("export", context, "export_contracts")
      assert {:ok, messages} = ActionHandler.handle(ExportContractsUI, message, opts)
      assert_valid_export_messages(messages)
      csv_of(download(messages))
    end

    test "the resolved export loads only the calculation and aggregate it adds" do
      [table] = ResolvedView.resolve(ExportContractsUI).tables

      assert table.export.loads == [:priced_name, :line_count]
      refute :priced_name in table.loads
      refute :line_count in table.loads
      assert table.component.fields == [:name, :status]
    end

    test "the surface the browser gets carries none of the export-only columns" do
      Ash.create!(ExportContract, %{name: "Zed", value: "5", currency: "EUR"}, authorize?: false)

      assert [message] =
               AshA2ui.Info.build_surface(ExportContractsUI, actor: %{role: :admin})

      rows = message["createSurface"]["dataModel"]["records"]
      assert [_ | _] = rows

      for row <- rows do
        refute Map.has_key?(row, "value")
        refute Map.has_key?(row, "priced_name")
        refute Map.has_key?(row, "line_count")
        refute Map.has_key?(row, "margin")
      end
    end

    test "exports the extra attribute, hidden field, calculation and aggregate" do
      csv = export_csv(%{}, actor: %{role: :admin})

      assert csv ==
               @header <>
                 "\r\nAcme,1200.50,active,CAD,Acme (CAD),2,9" <>
                 "\r\nBeta,80,draft,USD,Beta (USD),0,4\r\n"
    end

    test "the carried search and filters still narrow the export" do
      assert export_csv(%{"query" => %{"search" => "bet"}}, actor: %{role: :admin}) ==
               @header <> "\r\nBeta,80,draft,USD,Beta (USD),0,4\r\n"

      assert export_csv(%{"query" => %{"filters" => %{"status" => "active"}}},
               actor: %{role: :admin}
             ) ==
               @header <> "\r\nAcme,1200.50,active,CAD,Acme (CAD),2,9\r\n"
    end

    test "a column the actor's field policies forbid exports empty" do
      assert export_csv(%{}, actor: %{role: :viewer}) ==
               @header <>
                 "\r\nAcme,1200.50,active,CAD,Acme (CAD),2," <>
                 "\r\nBeta,80,draft,USD,Beta (USD),0,\r\n"
    end

    test "a forbidden table cell renders the masked text, not the inspected placeholder" do
      assert [message] =
               AshA2ui.Info.build_surface(AshA2ui.Test.ExportContractMarginsUI,
                 actor: %{role: :viewer}
               )

      rows = message["createSurface"]["dataModel"]["records"]
      assert [_ | _] = rows

      for row <- rows do
        assert row["margin"] == "Hidden"
        assert row["_masked"] == %{"margin" => "You do not have access to this value."}
      end
    end

    test "the column selection may pick an export-only column" do
      assert export_csv(%{"columns" => %{"value" => true}}, actor: %{role: :admin}) =~
               "Contract value"
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

      feedback =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => value}} -> value
          _ -> nil
        end)

      assert %{"kind" => "error", "code" => "INVALID_ACTION"} = feedback
      assert feedback["message"] =~ "at least one column"
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

  test "an export on a form component does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule ExportOnForm do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

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

    assert result =~
             ~r/nor a public attribute, calculation or aggregate of AshA2ui.Test.BucketWord/
  end

  test "export columns may name a hidden field, attribute, calculation or aggregate" do
    result =
      capture_io(:stderr, fn ->
        defmodule ExportResourceColumns do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.ExportContract

            component :table do
              fields [:name, :currency]

              export do
                columns [:name, :currency, :value, :priced_name, :line_count]
              end
            end

            field :currency do
              hidden true
            end
          end
        end
      end)

    refute result =~ "export column"
  end

  test "a related table's export columns are checked against its own resource" do
    result =
      capture_io(:stderr, fn ->
        defmodule ExportRelatedColumns do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :table, :contracts do
              resource AshA2ui.Test.ExportContract
              fields [:name]

              export do
                columns [:name, :value, :word]
              end
            end
          end
        end
      end)

    assert result =~ ~r/export column :word is not one of component :contracts/
    assert result =~ ~r/of AshA2ui.Test.ExportContract/
  end

  test "a relationship is not an exportable column" do
    result =
      capture_io(:stderr, fn ->
        defmodule ExportRelationshipColumn do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.ExportContract

            component :table do
              fields [:name]

              export do
                columns [:name, :lines]
              end
            end
          end
        end
      end)

    assert result =~ ~r/export column :lines is not one of component :table/
  end
end
