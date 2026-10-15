defmodule AshA2ui.Bulk.BulkSecurityTest do
  @moduledoc """
  A2UI-104: the server-side checks of `bulk_invoke` — the bulk_actions
  allowlist, the authorized and scoped re-read of the carried ids, and the
  selection bounds. Every refusal leaves the data untouched.
  """

  # Shared ETS fixtures.
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper
  import AshA2ui.Test.BulkHelpers

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{BulkPresetsUI, BulkTasksUI}

  setup do
    reset!()
    %{project: project!("Apollo"), other: project!("Zephyr")}
  end

  defp bulk_invoke(context) do
    ActionHandler.handle(BulkTasksUI, envelope("bulk_invoke", context), actor: actor())
  end

  defp statuses(tasks), do: Enum.map(tasks, &reload!(&1).status)

  @tag ac: "A2UI-104/AC-3"
  test "refuses actions outside bulk actions", %{project: project} do
    tasks = for title <- ["Alpha", "Bravo"], do: task!(title, %{project_id: project.id})

    # :flag is a row action but not a bulk action; :update is declared nowhere
    for action <- ["flag", "update", "no_such_action"] do
      assert {:error, messages} =
               bulk_invoke(%{
                 "action" => action,
                 "component" => "table",
                 "records" => rows(tasks, tasks)
               })

      Enum.each(messages, &assert_valid_server_message/1)

      assert value_at(messages, "/ui/status") ==
               "Action #{inspect(action)} is not allowed: it is not listed in the view's " <>
                 "bulk_actions."

      # refused before any read: no records, no result, no refresh
      refute Enum.any?(paths(messages), &String.starts_with?(&1, "/records"))
      refute Enum.any?(paths(messages), &String.starts_with?(&1, "/bulk"))
    end

    assert statuses(tasks) == [:open, :open]
  end

  @tag ac: "A2UI-104/AC-4"
  test "forged and out of scope ids are refused", %{project: project, other: other} do
    allowed = task!("Alpha", %{project_id: project.id})
    secret = task!("Bravo", %{project_id: project.id, secret: true})
    out_of_scope = task!("Charlie", %{project_id: other.id})

    forged_rows = [
      %{"id" => Ash.UUID.generate(), "_selected" => true},
      %{"id" => "not-a-uuid", "_selected" => true}
    ]

    assert {:ok, messages} =
             bulk_invoke(%{
               "action" => "reject",
               "component" => "table",
               "records" =>
                 rows([allowed, secret, out_of_scope], [allowed, secret, out_of_scope]) ++
                   forged_rows,
               "contexts" => contexts(project)
             })

    Enum.each(messages, &assert_valid_server_message/1)

    # only the id the authorized, scoped re-read returned was written
    assert reload!(allowed).status == :rejected
    assert reload!(secret).status == :open
    assert reload!(out_of_scope).status == :open

    assert %{"ok" => 1, "refused" => 4, "failed" => 0, "skipped" => 0} =
             value_at(messages, "/bulk/table/result")

    assert value_at(messages, "/ui/status") ==
             "Reject: 1 of 5 selected records done; 4 refused."
  end

  @tag ac: "A2UI-104/AC-7"
  test "empty and oversized selections are refused", %{project: project} do
    tasks =
      for title <- ["A", "B", "C", "D", "E", "F"],
          do: task!(title, %{project_id: project.id})

    # nothing selected
    assert {:error, empty_messages} =
             bulk_invoke(%{
               "action" => "reject",
               "component" => "table",
               "records" => rows(tasks, [])
             })

    assert value_at(empty_messages, "/ui/status") == "Select at least one record first."

    # six selected on a table whose query caps pages at five
    assert {:error, oversized_messages} =
             bulk_invoke(%{
               "action" => "reject",
               "component" => "table",
               "records" => rows(tasks, tasks)
             })

    assert value_at(oversized_messages, "/ui/status") =~ ~r/^Too many records selected \(6\)/

    for messages <- [empty_messages, oversized_messages] do
      Enum.each(messages, &assert_valid_server_message/1)
      refute Enum.any?(paths(messages), &String.starts_with?(&1, "/records"))
      refute Enum.any?(paths(messages), &String.starts_with?(&1, "/bulk"))
    end

    assert Enum.all?(statuses(tasks), &(&1 == :open))
  end

  describe "under query presets" do
    defp preset_invoke(action, rows, query) do
      context =
        %{"action" => action, "component" => "table", "records" => rows}
        |> then(&if(query, do: Map.put(&1, "query", query), else: &1))

      ActionHandler.handle(BulkPresetsUI, envelope("bulk_invoke", context), actor: actor())
    end

    test "the re-read uses the default preset's read action" do
      archived = for title <- ["A", "B"], do: task!(title, %{archived: true})
      active = task!("C")
      selection = archived ++ [active]

      # no carried query state: the default preset (:archived) applies, so
      # the archived rows the table shows are written and the active one,
      # which that view never showed, is refused
      assert {:ok, messages} = preset_invoke("reject", rows(selection, selection), nil)
      Enum.each(messages, &assert_valid_server_message/1)

      assert statuses(archived) == [:rejected, :rejected]
      assert statuses([active]) == [:open]

      assert %{"ok" => 2, "refused" => 1} = value_at(messages, "/bulk/table/result")
    end

    test "the re-read follows the carried preset, filter included" do
      approved = task!("A", %{status: :approved})
      open = task!("B")
      archived = task!("C", %{archived: true, status: :approved})
      selection = [approved, open, archived]

      # :approved reads through the table's :active and ANDs status ==
      # :approved: only the approved active row is re-read
      assert {:ok, messages} =
               preset_invoke("reject", rows(selection, selection), %{"preset" => "approved"})

      assert statuses(selection) == [:rejected, :open, :approved]
      assert %{"ok" => 1, "refused" => 2} = value_at(messages, "/bulk/table/result")

      # an explicit ["archived"] (the ChoicePicker's list form) re-reads
      # through :archived
      assert {:ok, _messages} =
               preset_invoke("reject", rows(selection, selection), %{"preset" => ["archived"]})

      assert statuses(selection) == [:rejected, :open, :rejected]
    end

    test "an unknown carried preset falls back to the default preset" do
      archived = task!("A", %{archived: true})
      active = task!("B")

      assert {:ok, messages} =
               preset_invoke("reject", rows([archived, active], [archived, active]), %{
                 "preset" => "no_such_preset"
               })

      assert statuses([archived, active]) == [:rejected, :open]
      assert %{"ok" => 1, "refused" => 1} = value_at(messages, "/bulk/table/result")
    end
  end
end
