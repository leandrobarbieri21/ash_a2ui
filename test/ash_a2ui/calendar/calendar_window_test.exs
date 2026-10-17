defmodule AshA2ui.Calendar.CalendarWindowTest do
  @moduledoc """
  The window arithmetic and request precedence of `AshA2ui.Calendar`
  (A2UI-107): month, week and day ranges, shifting across year ends, the
  absolute anchor over the delta, and picks on day calendars.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Calendar

  defp config(granularity),
    do: %{
      date_field: :starts_on,
      end_date_field: nil,
      granularity: granularity,
      start_kind: :date,
      end_kind: nil
    }

  @tag ac: "A2UI-107/AC-7"
  test "ranges and shifts" do
    assert Calendar.range(:month, ~D[2026-02-14]) == {~D[2026-02-01], ~D[2026-02-28]}
    # 2026-10-18 is a Sunday: its week starts on Monday the 12th.
    assert Calendar.range(:week, ~D[2026-10-18]) == {~D[2026-10-12], ~D[2026-10-18]}
    assert Calendar.range(:week, ~D[2026-10-12]) == {~D[2026-10-12], ~D[2026-10-18]}
    assert Calendar.range(:day, ~D[2026-10-18]) == {~D[2026-10-18], ~D[2026-10-18]}

    assert Calendar.shift(:month, ~D[2026-12-01], 1) == ~D[2027-01-01]
    assert Calendar.shift(:month, ~D[2026-01-01], -1) == ~D[2025-12-01]
    assert Calendar.shift(:month, ~D[2026-01-01], -13) == ~D[2024-12-01]
    assert Calendar.shift(:week, ~D[2026-12-28], 1) == ~D[2027-01-04]
    assert Calendar.shift(:day, ~D[2026-12-31], 1) == ~D[2027-01-01]
  end

  @tag ac: "A2UI-107/AC-7"
  test "request precedence" do
    state = %{"window" => %{"anchor" => "2026-10-01", "selected" => "2026-10-16"}}

    # Nothing requested: the carried window, unchanged.
    assert {:ok, window, false} = Calendar.parse_window(config(:month), state, %{})
    assert window.anchor == ~D[2026-10-01]
    assert window.selected == ~D[2026-10-16]

    # The absolute anchor wins over a delta.
    assert {:ok, window, true} =
             Calendar.parse_window(config(:month), state, %{
               "anchor" => "2027-03-09",
               "windowDelta" => 1
             })

    assert window.anchor == ~D[2027-03-01]
    assert window.selected == nil

    # A pick inside the moved window survives the move.
    assert {:ok, window, true} =
             Calendar.parse_window(config(:month), state, %{
               "windowDelta" => 1,
               "date" => "2026-11-05"
             })

    assert {window.anchor, window.selected} == {~D[2026-11-01], ~D[2026-11-05]}

    # On a day calendar a pick moves the window; there is no selection.
    assert {:ok, window, true} =
             Calendar.parse_window(config(:day), %{"window" => %{"anchor" => "2026-10-01"}}, %{
               "date" => "2026-10-20"
             })

    assert {window.anchor, window.selected, window.from, window.to} ==
             {~D[2026-10-20], nil, ~D[2026-10-20], ~D[2026-10-20]}

    # A carried pick outside the window is dropped (and counts as a change).
    assert {:ok, window, true} =
             Calendar.parse_window(
               config(:week),
               %{"window" => %{"anchor" => "2026-10-12", "selected" => "2026-10-30"}},
               %{}
             )

    assert window.selected == nil
  end
end
