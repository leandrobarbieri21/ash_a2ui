defmodule AshA2ui.Board.BoardSwimlanesVerifierTest do
  @moduledoc """
  Compile-time rules for board swimlanes (A2UI-105B): `swimlanes_by` only
  on a source-less `display :board`, on an enumerable public attribute
  other than `scope_by`; swimlane values, labels and tones naming its
  values; tones from the `badge_tones` vocabulary; no runtime-name
  collisions; and the `swimlane_*` options only with `swimlanes_by`. Uses
  the `capture_io(:stderr)` + regex pattern of the board verifier suite.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  defp compile_ui(body) do
    name = "AshA2ui.Board.BoardSwimlanesVerifierTest.Ui#{System.unique_integer([:positive])}"

    capture_io(:stderr, fn ->
      Code.compile_string("""
      defmodule #{name} do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.BoardTask
      #{body}
        end
      end
      """)
    end)
  end

  defp board(sections, opts \\ []) do
    """
        component :table, :board do
          fields [:name, :status]
          display #{Keyword.get(opts, :display, ":board")}

          row_layout do
            title :name
          end

          sections do
    #{sections}
          end
        end
    """
  end

  defp swimlanes(extra), do: board("scope_by :status\nvalues [:open, :claimed]\n#{extra}")

  @tag ac: "A2UI-105B/AC-5"
  test "rejects invalid swimlanes" do
    # A well-formed swimlaned board compiles cleanly.
    assert compile_ui(
             swimlanes("""
             swimlanes_by :severity
             swimlane_values [:very_high, :low]
             swimlane_labels very_high: "Critical"
             swimlane_tones very_high: :danger, low: :success
             """)
           ) == ""

    # A one_of attribute works as well as an Ash.Type.Enum.
    assert compile_ui(swimlanes("swimlanes_by :priority")) == ""

    # Only on boards.
    assert compile_ui(board("scope_by :status\nswimlanes_by :severity", display: ":list")) =~
             ~r/swimlanes_by splits a board into rows: table :board needs display :board/

    # Only without a source.
    assert compile_ui(
             board("source AshA2ui.Test.Bucket\nscope_by :name\nswimlanes_by :severity",
               display: ":list"
             )
           ) =~ ~r/swimlanes_by requires sections without a source/

    # A second attribute, not the lane attribute.
    assert compile_ui(swimlanes("swimlanes_by :status")) =~
             ~r/swimlanes_by :status is the lane attribute \(scope_by\)/

    # A public attribute or calculation, with enumerable values.
    assert compile_ui(swimlanes("swimlanes_by :bogus")) =~
             ~r/swimlanes_by :bogus is not a public attribute or calculation/

    assert compile_ui(swimlanes("swimlanes_by :name")) =~
             ~r/swimlanes need enumerable values: swimlanes_by :name/

    # Values, labels and tones name enumerated values.
    assert compile_ui(swimlanes("swimlanes_by :severity\nswimlane_values [:low, :bogus]")) =~
             ~r/swimlane_values entry :bogus is not an enumerated value of swimlanes_by/

    assert compile_ui(swimlanes("swimlanes_by :severity\nswimlane_labels bogus: \"Nope\"")) =~
             ~r/swimlane_labels entry :bogus is not an enumerated value of swimlanes_by/

    assert compile_ui(swimlanes("swimlanes_by :severity\nswimlane_tones bogus: :danger")) =~
             ~r/swimlane_tones entry :bogus is not an enumerated value of swimlanes_by/

    # Tones come from the badge_tones vocabulary.
    assert compile_ui(swimlanes("swimlanes_by :severity\nswimlane_tones low: :red")) =~
             ~r/swimlane_tones for :low must be one of :neutral, :info, :success, :warning, :danger, :accent, got: :red/

    # No two swimlanes share a runtime name.
    assert compile_ui(swimlanes("swimlanes_by :severity\nswimlane_values [:low, \"low\"]")) =~
             ~r/swimlane_values lists :low more than once/

    assert compile_ui(swimlanes("swimlanes_by :stage")) =~
             ~r/swimlane values :"in-progress" and :in_progress collide on the runtime name board__in_progress/

    assert compile_ui(swimlanes("swimlanes_by :stage\nswimlane_values [:in_progress, :done]")) ==
             ""

    # The swimlane options require swimlanes_by.
    for option <- [
          "swimlane_values [:low]",
          "swimlane_labels low: \"Low\"",
          "swimlane_tones low: :info"
        ] do
      [name | _rest] = String.split(option)

      assert compile_ui(swimlanes(option)) =~
               ~r/sections option #{name} requires swimlanes_by/
    end
  end

  @tag ac: "A2UI-105B/AC-5"
  test "rejects swimlaned boards whose ids or data paths would collide, or that show nothing" do
    # Swimlane values that extend one another at an underscore build the
    # same component ids (swimlane_board__high's total vs the
    # :high_total swimlane's Column).
    assert compile_ui(swimlanes("swimlanes_by :tier\nswimlane_values [:high, :high_total]")) =~
             ~r/runtime names board__high and board__high_total can produce the same component id/

    assert compile_ui(swimlanes("swimlanes_by :tier\nswimlane_values [:high, :high_cells]")) =~
             ~r/runtime names board__high and board__high_cells/

    assert compile_ui(swimlanes("swimlanes_by :tier\nswimlane_values [:high, :low]")) == ""

    # Lanes too (a lane-only board, and a swimlaned board's stages).
    assert compile_ui(board("scope_by :tier\nvalues [:high, :high_total]")) =~
             ~r/runtime names board_high and board_high_total can produce the same component id/

    assert compile_ui(
             board("scope_by :tier\nvalues [:high, :high_total]\nswimlanes_by :severity")
           ) =~ ~r/runtime names board_high and board_high_total/

    # A cell may not take another table's key (they would share
    # /records/<name>).
    assert compile_ui(
             swimlanes("swimlanes_by :severity\nswimlane_values [:low]") <>
               """
                   component :table, :board_open__low do
                     fields [:name]
                   end
               """
           ) =~ ~r/board :board expands into a table named board_open__low, which is also the key/

    assert compile_ui(
             board("scope_by :status\nvalues [:open]") <>
               """
                   component :table, :board_open do
                     fields [:name]
                   end
               """
           ) =~ ~r/expands into a table named board_open/

    # Empty value lists would render no board at all.
    assert compile_ui(swimlanes("swimlanes_by :severity\nswimlane_values []")) =~
             ~r/swimlane_values \[\] leaves the board with nothing to show/

    assert compile_ui(board("scope_by :status\nvalues []")) =~
             ~r/values \[\] leaves the board with nothing to show/

    # limit caps the cells: 2 lanes x 2 swimlanes is 4 cells.
    assert compile_ui(
             swimlanes("swimlanes_by :severity\nswimlane_values [:very_high, :low]\nlimit 3")
           ) =~ ~r/limit 3 is below the 4 cells \(2 lanes x 2 swimlanes\)/

    assert compile_ui(
             swimlanes("swimlanes_by :severity\nswimlane_values [:very_high, :low]\nlimit 4")
           ) == ""
  end
end
