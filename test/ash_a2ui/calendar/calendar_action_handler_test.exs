defmodule AshA2ui.Calendar.CalendarActionHandlerTest do
  @moduledoc """
  Calendar behavior through `AshA2ui.ActionHandler` (AST-173): moving the
  window and picking a day are `"query"` actions the server re-reads as the
  actor (reads, marks and refreshes alike), a picked day narrows the read,
  a row action's refresh keeps the window, and malformed window input is
  rejected before any read.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Calendar.{Event, MonthUI}

  @red %{team: "red"}
  @blue %{team: "blue"}

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "calendar_month",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp titles(messages), do: messages |> value_at("/records") |> Enum.map(& &1["title"])
  defp window(messages), do: value_at(messages, "/query")["window"]
  defp mark_dates(messages), do: Enum.map(window(messages)["marks"], & &1["date"])

  defp event!(title, team, starts_on, ends_on \\ nil) do
    Ash.create!(Event, %{title: title, team: team, starts_on: starts_on, ends_on: ends_on},
      authorize?: false
    )
  end

  defp seed do
    event!("Red Oct 3", "red", ~D[2026-10-03])
    event!("Red Oct 16", "red", ~D[2026-10-16], ~D[2026-10-17])
    event!("Red Oct 16 b", "red", ~D[2026-10-16])
    event!("Red Nov 2", "red", ~D[2026-11-02])
    event!("Blue Oct 3", "blue", ~D[2026-10-03])
    event!("Blue Nov 9", "blue", ~D[2026-11-09])
  end

  # The /query state a client carries back: the October window on page 2.
  defp october_state(extra \\ %{}) do
    Map.merge(
      %{
        "page" => 2,
        "pageSize" => 10,
        "filters" => %{"status" => ""},
        "window" => %{"anchor" => "2026-10-01", "selected" => ""}
      },
      extra
    )
  end

  defp query(context, actor) do
    message = envelope("query", Map.merge(%{"component" => "schedule"}, context))

    assert {:ok, messages} =
             ActionHandler.handle(MonthUI, message, actor: actor, authorize?: false)

    Enum.each(messages, &assert_valid_server_message/1)
    messages
  end

  @tag ac: "AST-173/AC-5"
  test "window actions re-query as the actor" do
    seed()

    # Next month, relative to the carried anchor: only the actor's November
    # events, the page back to 1.
    next = query(%{"query" => october_state(), "windowDelta" => 1}, @red)
    assert titles(next) == ["Red Nov 2"]
    assert window(next)["anchor"] == "2026-11-01"
    assert window(next)["to"] == "2026-11-30"
    assert mark_dates(next) == ["2026-11-02"]
    assert value_at(next, "/query")["page"] == 1

    # The same move as another actor reads that actor's events only.
    blue = query(%{"query" => october_state(), "windowDelta" => 1}, @blue)
    assert titles(blue) == ["Blue Nov 9"]
    assert mark_dates(blue) == ["2026-11-09"]

    # An absolute anchor (what the admin calendar sends) wins over the
    # carried one; the window snaps to its month.
    december = query(%{"query" => october_state(), "anchor" => "2026-12-15"}, @red)
    assert titles(december) == []
    assert window(december)["anchor"] == "2026-12-01"
    assert window(december)["marks"] == []

    # Picking a day narrows the records to it; the marks still cover the
    # whole window, and only the actor's days.
    picked = query(%{"query" => october_state(), "date" => "2026-10-16"}, @red)
    assert Enum.sort(titles(picked)) == ["Red Oct 16", "Red Oct 16 b"]
    assert window(picked)["selected"] == "2026-10-16"
    assert window(picked)["scopeLabel"] == "2026-10-16"
    assert mark_dates(picked) == ["2026-10-03", "2026-10-16", "2026-10-17"]
    assert Enum.find(window(picked)["marks"], &(&1["date"] == "2026-10-16"))["count"] == 2
    assert value_at(picked, "/query")["totalCount"] == 2

    # A multi-day event shows on its later days too.
    seventeenth = query(%{"query" => october_state(), "date" => "2026-10-17"}, @red)
    assert titles(seventeenth) == ["Red Oct 16"]

    # Clearing the pick reads the whole window again.
    cleared =
      query(
        %{
          "query" =>
            october_state(%{"window" => %{"anchor" => "2026-10-01", "selected" => "2026-10-16"}}),
          "date" => ""
        },
        @red
      )

    # Date order (same-day events tie-break on the primary key).
    assert ["Red Oct 3" | same_day] = titles(cleared)
    assert Enum.sort(same_day) == ["Red Oct 16", "Red Oct 16 b"]
    assert window(cleared)["selected"] == ""

    # Moving the window drops a pick that is no longer inside it.
    moved =
      query(
        %{
          "query" =>
            october_state(%{"window" => %{"anchor" => "2026-10-01", "selected" => "2026-10-16"}}),
          "windowDelta" => -1
        },
        @red
      )

    assert window(moved)["anchor"] == "2026-09-01"
    assert window(moved)["selected"] == ""

    # A carried state that changes nothing keeps its page.
    same = query(%{"query" => october_state()}, @red)
    assert value_at(same, "/query")["page"] == 2
  end

  @tag ac: "AST-173/AC-5"
  test "a row action's refresh keeps the window and the pick" do
    seed()

    [target] =
      Ash.read!(Event, actor: @red, authorize?: false)
      |> Enum.filter(&(&1.title == "Red Oct 16 b"))

    state =
      october_state(%{
        "page" => 1,
        "window" => %{"anchor" => "2026-10-01", "selected" => "2026-10-16"}
      })

    message =
      envelope("invoke", %{
        "action" => "confirm",
        "recordId" => target.id,
        "component" => "schedule",
        "query" => state
      })

    assert {:ok, messages} =
             ActionHandler.handle(MonthUI, message, actor: @red, authorize?: false)

    Enum.each(messages, &assert_valid_server_message/1)

    assert Ash.get!(Event, target.id, authorize?: false).status == :confirmed

    assert Enum.sort(titles(messages)) == ["Red Oct 16", "Red Oct 16 b"]
    assert window(messages)["selected"] == "2026-10-16"
    assert window(messages)["anchor"] == "2026-10-01"
    confirmed = Enum.find(value_at(messages, "/records"), &(&1["title"] == "Red Oct 16 b"))
    assert confirmed["_calendar_when"] == "2026-10-16"
    assert confirmed["_visible_confirm"] == []
  end

  @tag ac: "AST-173/AC-6"
  test "rejects malformed windows" do
    seed()

    for context <- [
          %{"query" => october_state(), "anchor" => "next tuesday"},
          %{"query" => october_state(), "anchor" => 20_261_001},
          %{"query" => october_state(), "windowDelta" => "1"},
          %{"query" => october_state(), "windowDelta" => 100_000},
          %{"query" => october_state(), "date" => "2026-13-01"},
          %{"query" => october_state(%{"window" => %{"anchor" => "October"}})}
        ] do
      message = envelope("query", Map.put(context, "component", "schedule"))

      assert {:error, messages} =
               ActionHandler.handle(MonthUI, message, actor: @red, authorize?: false)

      assert value_at(messages, "/records") == nil, "no read for #{inspect(context)}"
      assert value_at(messages, "/ui/feedback")["kind"] == "error"
      assert value_at(messages, "/ui/feedback")["message"] =~ "Malformed query action"
    end
  end
end
