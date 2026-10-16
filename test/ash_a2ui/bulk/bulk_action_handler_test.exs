defmodule AshA2ui.Bulk.BulkActionHandlerTest do
  @moduledoc """
  A2UI-104: `bulk_invoke` runs the action once per selected record through
  the single-row dispatch, reports the outcome at `/bulk/<table>/result`
  and refreshes once; `bulk_select` rewrites the page's selection from an
  authorized re-read.
  """

  # Shared ETS fixtures and the experience application env.
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper
  import AshA2ui.Test.BulkHelpers

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{BulkCardsUI, BulkPresetsUI, BulkTasksUI}

  setup do
    reset!()
    %{project: project!("Apollo")}
  end

  defp bulk_invoke(action, rows, project) do
    ActionHandler.handle(
      BulkTasksUI,
      envelope("bulk_invoke", %{
        "action" => action,
        "component" => "table",
        "records" => rows,
        "contexts" => contexts(project)
      }),
      actor: actor()
    )
  end

  @tag ac: "A2UI-104/AC-2"
  test "runs the action on every selected record", %{project: project} do
    [a, b, c, d] =
      for title <- ["Alpha", "Bravo", "Charlie", "Delta"],
          do: task!(title, %{project_id: project.id})

    assert {:ok, messages} = bulk_invoke("approve", rows([a, b, c, d], [a, b, c]), project)
    Enum.each(messages, &assert_valid_server_message/1)

    # each selected record went through the action as the actor
    assert Enum.map([a, b, c, d], &reload!(&1).status) == [:approved, :approved, :approved, :open]

    assert value_at(messages, "/bulk/table/result") == %{
             "ok" => 3,
             "failed" => 0,
             "refused" => 0,
             "skipped" => 0,
             "errors" => []
           }

    # the target table is refreshed exactly once, every row deselected
    assert Enum.count(paths(messages), &(&1 == "/records")) == 1
    records = value_at(messages, "/records")
    assert length(records) == 4
    assert Enum.all?(records, &(&1["_selected"] == false))

    assert value_at(messages, "/ui/feedback")["message"] ==
             "Approve: 3 of 3 selected records done."

    assert value_at(messages, "/ui/feedback")["kind"] == "success"
  end

  @tag ac: "A2UI-104/AC-5"
  test "visible_when skips records per record", %{project: project} do
    open_one = task!("Alpha", %{project_id: project.id})
    open_two = task!("Bravo", %{project_id: project.id})
    rejected = task!("Charlie", %{project_id: project.id, status: :rejected})

    tasks = [open_one, open_two, rejected]
    assert {:ok, messages} = bulk_invoke("approve", rows(tasks, tasks), project)

    # approve is visible_when status: :open — the same predicate the
    # single-row invoke enforces
    assert reload!(open_one).status == :approved
    assert reload!(open_two).status == :approved
    assert reload!(rejected).status == :rejected

    assert %{"ok" => 2, "skipped" => 1, "refused" => 0, "failed" => 0} =
             value_at(messages, "/bulk/table/result")

    assert value_at(messages, "/ui/feedback")["message"] ==
             "Approve: 2 of 3 selected records done; 1 skipped."

    assert value_at(messages, "/ui/feedback")["kind"] == "warning"

    # the single-row invoke refuses the same record
    assert {:error, _messages} =
             ActionHandler.handle(
               BulkTasksUI,
               envelope("invoke", %{"action" => "approve", "recordId" => rejected.id}),
               actor: actor()
             )
  end

  @tag ac: "A2UI-104/AC-6"
  test "partial failure is reported not rolled back", %{project: project} do
    good_one = task!("Alpha", %{project_id: project.id})
    bad = task!("Bravo", %{project_id: project.id, score: -1})
    good_two = task!("Charlie", %{project_id: project.id})

    tasks = [good_one, bad, good_two]
    assert {:ok, messages} = bulk_invoke("approve", rows(tasks, tasks), project)
    Enum.each(messages, &assert_valid_server_message/1)

    assert reload!(good_one).status == :approved
    assert reload!(good_two).status == :approved
    assert reload!(bad).status == :open

    assert %{
             "ok" => 2,
             "failed" => 1,
             "refused" => 0,
             "skipped" => 0,
             "errors" => [%{"id" => bad_id, "message" => message}]
           } = value_at(messages, "/bulk/table/result")

    assert bad_id == bad.id
    assert message =~ ~r/^score: must be greater than or equal to 0/

    assert value_at(messages, "/ui/feedback")["message"] ==
             "Approve: 2 of 3 selected records done; 1 failed."

    assert value_at(messages, "/ui/feedback") == %{
             "kind" => "warning",
             "message" => "Approve: 2 of 3 selected records done; 1 failed."
           }
  end

  test "a run that writes nothing is an error and refreshes nothing", %{project: project} do
    bad = task!("Bravo", %{project_id: project.id, score: -1})

    assert {:error, messages} = bulk_invoke("approve", rows([bad], [bad]), project)

    assert %{"ok" => 0, "failed" => 1} = value_at(messages, "/bulk/table/result")
    refute "/records" in paths(messages)
    assert value_at(messages, "/ui/feedback")["kind"] == "error"
  end

  test "a v1.0 run answers with the result in the action response", %{project: project} do
    a = task!("Alpha", %{project_id: project.id})

    message =
      envelope("bulk_invoke", %{
        "action" => "reject",
        "component" => "table",
        "records" => rows([a], [a])
      })
      |> put_in(["action", "actionId"], "act-1")

    assert {:ok, [response | messages]} =
             ActionHandler.handle(BulkTasksUI, message, actor: actor(), spec_version: "1.0")

    Enum.each([response | messages], &assert_valid_server_message(&1, :v1_0))

    assert %{"value" => %{"status" => "ok", "result" => %{"ok" => 1}}} =
             response["actionResponse"]

    assert reload!(a).status == :rejected
  end

  @tag ac: "A2UI-104/AC-9"
  test "select page and clear rewrite selection", %{project: project} do
    visible = for title <- ["Alpha", "Bravo"], do: task!(title, %{project_id: project.id})
    _secret = task!("Charlie", %{project_id: project.id, secret: true})

    select = fn selected ->
      ActionHandler.handle(
        BulkTasksUI,
        envelope("bulk_select", %{
          "component" => "table",
          "selected" => selected,
          # the carried rows are never echoed back: a forged row is ignored
          "records" => [%{"id" => "forged", "title" => "Forged", "_selected" => true}],
          "contexts" => contexts(project)
        }),
        actor: actor()
      )
    end

    assert {:ok, messages} = select.(true)
    Enum.each(messages, &assert_valid_server_message/1)

    records = value_at(messages, "/records")

    assert Enum.map(records, & &1["id"]) |> Enum.sort() ==
             Enum.map(visible, & &1.id) |> Enum.sort()

    assert Enum.all?(records, &(&1["_selected"] == true))

    assert {:ok, messages} = select.(false)
    records = value_at(messages, "/records")
    assert length(records) == 2
    assert Enum.all?(records, &(&1["_selected"] == false))

    # nothing was written
    assert Enum.all?(visible, &(reload!(&1).status == :open))
  end

  test "a generic bulk action runs once per record with its record_id" do
    [a, b, c] = for title <- ["A", "B", "C"], do: task!(title, %{archived: true})

    assert {:ok, messages} =
             ActionHandler.handle(
               BulkPresetsUI,
               envelope("bulk_invoke", %{
                 "action" => "stamp",
                 "component" => "table",
                 "records" => rows([a, b, c], [a, c])
               }),
               actor: actor()
             )

    Enum.each(messages, &assert_valid_server_message/1)

    # :stamp sets the score of the record its :record_id names: each call
    # got its own record, the unselected one was not touched
    assert Enum.map([a, b, c], &reload!(&1).score) == [7, 0, 7]
    assert %{"ok" => 2, "refused" => 0} = value_at(messages, "/bulk/table/result")
  end

  describe "a table without a query" do
    defp inbox_table do
      BulkCardsUI
      |> AshA2ui.ResolvedView.resolve()
      |> Map.fetch!(:tables)
      |> Enum.find(&(&1.name == :inbox))
    end

    defp inbox_rows(messages) do
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => path, "value" => rows}}
        when is_list(rows) and path != "/records" ->
          if String.contains?(path, "inbox"), do: rows

        _other ->
          nil
      end)
    end

    test "select page marks at most the bulk cap and the run is accepted" do
      # the inbox reads through BulkTask's default :read, whose pagination
      # max_page_size (Ash's default, 250) is the bulk cap: one row more
      cap = AshA2ui.Bulk.cap(inbox_table())
      assert cap == 250

      for n <- 1..(cap + 1), do: task!("Task #{String.pad_leading(to_string(n), 3, "0")}")

      assert {:ok, messages} =
               ActionHandler.handle(
                 BulkCardsUI,
                 envelope("bulk_select", %{"component" => "inbox", "selected" => true}),
                 actor: actor()
               )

      Enum.each(messages, &assert_valid_server_message/1)

      rows = inbox_rows(messages)
      assert length(rows) == cap + 1
      assert Enum.count(rows, & &1["_selected"]) == cap
      assert rows |> Enum.take(cap) |> Enum.all?(& &1["_selected"])

      assert value_at(messages, "/ui/feedback")["message"] ==
               "Selected the first 250 of 251 records: a bulk action runs on at most 250 records."

      # the selection the page now holds is one a bulk run accepts
      assert {:ok, messages} =
               ActionHandler.handle(
                 BulkCardsUI,
                 envelope("bulk_invoke", %{
                   "action" => "reject",
                   "component" => "inbox",
                   "records" => rows
                 }),
                 actor: actor()
               )

      assert %{"ok" => 250, "refused" => 0} = value_at(messages, "/bulk/inbox/result")
    end

    test "on v1.0 the capped-selection notice answers ok, with a warning feedback" do
      cap = AshA2ui.Bulk.cap(inbox_table())
      for n <- 1..(cap + 1), do: task!("Task #{String.pad_leading(to_string(n), 3, "0")}")

      message = %{
        "version" => "v1.0",
        "action" => %{
          "name" => "bulk_select",
          "surfaceId" => "bulk_cards",
          "actionId" => "sel_1",
          "context" => %{"component" => "inbox", "selected" => true}
        }
      }

      assert {:ok, [response | followups]} =
               ActionHandler.handle(BulkCardsUI, message, actor: actor(), spec_version: "1.0")

      text = "Selected the first 250 of 251 records: a bulk action runs on at most 250 records."

      assert response["actionId"] == "sel_1"
      assert %{"value" => %{"status" => "ok", "message" => ^text}} = response["actionResponse"]
      assert %{"status" => "ok", "message" => ^text} = value_at(followups, "/ui/response")
      assert value_at(followups, "/ui/feedback") == %{"kind" => "warning", "message" => text}
    end
  end
end
