defmodule AshA2ui.Board.BoardSectionsTest do
  @moduledoc """
  Source-less sections (A2UI-105): the sections of a `:table` template come
  from the enumerated values of `scope_by` — a `one_of` constraint or an
  `Ash.Type.Enum` — narrowed and ordered by `values`, headed per `labels`,
  with no read issued to enumerate them; empty lanes are kept.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ResolvedView
  alias AshA2ui.Sections
  alias AshA2ui.Test.BoardTask
  alias AshA2ui.Test.BoardTaskUI
  alias AshA2ui.Test.SeveritySectionsUI
  alias AshA2ui.Test.StatusSectionsUI

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :experience_version) end)
    :ok
  end

  defp create_task!(name, attrs) do
    Ash.create!(BoardTask, Map.put(attrs, :name, name), authorize?: false)
  end

  # Counts the Ash reads issued while `fun` runs, by resource.
  defp count_reads(fun) do
    handler_id = "board-sections-reads-#{System.unique_integer([:positive])}"
    parent = self()

    domain = Ash.Domain.Info.short_name(AshA2ui.Test.Domain)

    # Telemetry handlers run in the emitting process: only this test's reads.
    :telemetry.attach(
      handler_id,
      [:ash, domain, :read, :start],
      fn _event, _measurements, metadata, _config ->
        if self() == parent, do: send(parent, {:ash_read, metadata[:resource_short_name]})
      end,
      nil
    )

    try do
      result = fun.()
      {result, collect_reads([])}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp collect_reads(acc) do
    receive do
      {:ash_read, resource} -> collect_reads([resource | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp lanes(ui) do
    {:ok, expanded} = ui |> ResolvedView.resolve() |> Sections.expand(authorize?: false)
    expanded
  end

  @tag ac: "A2UI-105/AC-1"
  test "lanes come from enumerated values" do
    # one_of on an :atom attribute: every value, in declaration order.
    {status_view, reads} = count_reads(fn -> lanes(StatusSectionsUI) end)

    assert Enum.map(status_view.tables, & &1.name) == [
             "by_status_open",
             "by_status_claimed",
             "by_status_completed",
             "by_status_archived"
           ]

    assert Enum.map(status_view.tables, & &1.section.filter) == [
             {:status, :open},
             {:status, :claimed},
             {:status, :completed},
             {:status, :archived}
           ]

    assert Enum.map(status_view.tables, & &1.section.label) ==
             ["Open", "Claimed", "Completed", "Archived"]

    assert Enum.map(status_view.tables, & &1.records_path) ==
             Enum.map(status_view.tables, &"/records/#{&1.name}")

    # No read enumerates the lanes (expansion only).
    assert reads == []

    # An Ash.Type.Enum: every value of AshA2ui.Test.Severity, in order.
    {severity_view, reads} = count_reads(fn -> lanes(SeveritySectionsUI) end)

    assert Enum.map(severity_view.tables, & &1.name) == [
             "by_severity_low",
             "by_severity_medium",
             "by_severity_very_high"
           ]

    assert Enum.map(severity_view.tables, & &1.section.filter) ==
             [{:severity, :low}, {:severity, :medium}, {:severity, :very_high}]

    assert Enum.map(severity_view.tables, & &1.section.label) == ["Low", "Medium", "Very high"]
    assert reads == []

    # Each lane's reads are scoped to its value: building the surface reads
    # the table resource once per lane and never anything else.
    create_task!("one", %{status: :open, severity: :low})
    create_task!("two", %{status: :archived, severity: :very_high})

    {messages, reads} =
      count_reads(fn -> AshA2ui.Info.build_surface(StatusSectionsUI, authorize?: false) end)

    Enum.each(messages, &assert_valid_server_message/1)
    assert Enum.uniq(reads) == [:board_task]

    records =
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value["records"]
        _other -> nil
      end)

    assert [%{"name" => "one"}] = records["by_status_open"]
    assert [%{"name" => "two"}] = records["by_status_archived"]
    assert records["by_status_claimed"] == []
  end

  @tag ac: "A2UI-105/AC-2"
  test "values and labels shape the lanes" do
    view = lanes(BoardTaskUI)

    # values [:open, :claimed, :completed] drops :archived; labels overrides
    # :open only — the others keep their humanized value.
    assert Enum.map(view.tables, & &1.name) == ["board_open", "board_claimed", "board_completed"]
    assert Enum.map(view.tables, & &1.section.label) == ["To do", "Claimed", "Completed"]
    assert Enum.map(view.tables, & &1.section.template) == [:board, :board, :board]

    # The template key fans out to every lane on refresh.
    assert view.refreshes == %{
             claim: ["board_open", "board_claimed", "board_completed"],
             complete: ["board_open", "board_claimed", "board_completed"]
           }

    # A custom order is honored as declared.
    reordered =
      AshA2ui.Board.lanes(BoardTask, %{
        scope_by: :status,
        values: [:archived, "open"],
        labels: [archived: "Done and dusted"]
      })

    assert reordered == [
             %{value: :archived, label: "Done and dusted"},
             %{value: :open, label: "Open"}
           ]

    # Runtime guard behind the verifier: a repeated value (by string form)
    # and values whose lane names collide keep their first occurrence, so
    # lane component ids and data-model paths stay unique.
    assert AshA2ui.Board.lanes(BoardTask, %{scope_by: :status, values: [:open, "open", :claimed]}) ==
             [%{value: :open, label: "Open"}, %{value: :claimed, label: "Claimed"}]

    assert AshA2ui.Board.lanes(BoardTask, %{scope_by: :stage, values: nil}) ==
             [%{value: :"in-progress", label: "In-progress"}, %{value: :done, label: "Done"}]
  end

  @tag ac: "A2UI-105/AC-3"
  test "empty lanes are kept" do
    create_task!("only", %{status: :open})

    messages = AshA2ui.Info.build_surface(BoardTaskUI, authorize?: false)
    Enum.each(messages, &assert_valid_server_message/1)

    components =
      messages
      |> Enum.find_value(& &1["updateComponents"])
      |> Map.fetch!("components")
      |> Map.new(&{&1["id"], &1})

    value =
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
        _other -> nil
      end)

    # Every lane is on the board, the empty ones included.
    assert components["board_board_lanes"]["children"] ==
             ["lane_board_open", "lane_board_claimed", "lane_board_completed"]

    for lane <- ["board_claimed", "board_completed"] do
      assert value["records"][lane] == []
      assert value["_lane_total_#{lane}"] == "0"
      # The v2 empty state shows (a non-empty sentinel) with its text.
      assert value["_empty_visible_#{lane}"] == [%{"id" => "on"}]
      assert value["_empty_message_#{lane}"] == "No Board task records yet."
      assert "empty_state_#{lane}" in components["lane_#{lane}"]["children"]
      assert components["empty_state_#{lane}"]["component"] == "List"
    end

    assert [%{"name" => "only"}] = value["records"]["board_open"]
    assert value["_empty_visible_board_open"] == []
  end
end
