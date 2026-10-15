defmodule AshA2ui.Board.BoardVerifierTest do
  @moduledoc """
  Compile-time rules for boards (A2UI-105): source-less sections need an
  enumerable `scope_by`, `values`/`labels` must name enumerated values, no
  two lanes may share a runtime name, `limit` may not drop lanes,
  `label`/`value`/`sort`/`read_action` require a source (and
  `values`/`labels` its absence), and `display :board` needs a `:table`
  with `sections` and a `row_layout`. Uses the `capture_io(:stderr)` +
  regex pattern of the existing verifier suites.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  # Compiles one standalone UI module over AshA2ui.Test.BoardTask whose
  # `a2ui` body is `body`, returning the compile diagnostics.
  defp compile_ui(body) do
    name = "AshA2ui.Board.BoardVerifierTest.Ui#{System.unique_integer([:positive])}"

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
    row_layout =
      if Keyword.get(opts, :row_layout, true) do
        """
              row_layout do
                title :name
              end
        """
      else
        ""
      end

    sections_block =
      if sections do
        """
              sections do
        #{sections}
              end
        """
      else
        ""
      end

    """
        component :table, :board do
          fields [:name, :status]
          display #{Keyword.get(opts, :display, ":board")}
    #{row_layout}#{sections_block}
        end
    """
  end

  @tag ac: "A2UI-105/AC-7"
  test "rejects invalid boards" do
    # A well-formed board compiles cleanly (the baseline for every case).
    assert compile_ui(board("scope_by :status\nvalues [:open, :claimed]\nlabels open: \"To do\"")) ==
             ""

    # Without a source, scope_by needs enumerable values.
    assert compile_ui(board("scope_by :name")) =~
             ~r/sections without a source need enumerable values: scope_by :name/

    # values outside the enumeration.
    assert compile_ui(board("scope_by :status\nvalues [:open, :bogus]")) =~
             ~r/values entry :bogus is not an enumerated value of scope_by/

    # A value listed twice — also by string form — would render two lanes
    # with the same component ids and data-model paths.
    assert compile_ui(board("scope_by :status\nvalues [:open, :open, :claimed]")) =~
             ~r/values lists :open more than once/

    assert compile_ui(board("scope_by :status\nvalues [:open, \"open\", :claimed]")) =~
             ~r/values lists :open more than once/

    # Two enumerated values that sanitize to the same lane name, whether
    # enumerated in full or listed in values.
    assert compile_ui(board("scope_by :stage")) =~
             ~r/lane values :"in-progress" and :in_progress collide on the runtime name board_in_progress/

    assert compile_ui(board("scope_by :stage\nvalues [:in_progress, :\"in-progress\"]")) =~
             ~r/lane values :in_progress and :"in-progress" collide/

    assert compile_ui(board("scope_by :stage\nvalues [:in_progress, :done]")) == ""

    # Without a source, limit caps lanes: a limit below the lane count
    # would drop lanes silently.
    assert compile_ui(board("scope_by :status\nvalues [:open, :claimed, :completed]\nlimit 2")) =~
             ~r/limit 2 is below the 3 lanes \(:open, :claimed, :completed\)/

    assert compile_ui(board("scope_by :status\nlimit 3")) =~
             ~r/limit 3 is below the 4 lanes/

    assert compile_ui(board("scope_by :status\nvalues [:open, :claimed]\nlimit 2")) == ""

    # labels keys outside the enumeration.
    assert compile_ui(board("scope_by :status\nlabels bogus: \"Nope\"")) =~
             ~r/labels entry :bogus is not an enumerated value of scope_by/

    # label / sort / value / read_action require a source.
    for option <- ["label :name", "sort :name", "value :id", "read_action :read"] do
      [name | _rest] = String.split(option)

      assert compile_ui(board("scope_by :status\n#{option}")) =~
               ~r/sections option #{name} requires a source/
    end

    # values / labels shape source-less sections only.
    assert compile_ui(
             board("source AshA2ui.Test.Bucket\nscope_by :name\nvalues [:open]",
               display: ":list"
             )
           ) =~ ~r/sections option values applies only to sections without a source/

    assert compile_ui(
             board("source AshA2ui.Test.Bucket\nscope_by :name\nlabels open: \"To do\"",
               display: ":list"
             )
           ) =~ ~r/labels shape source-less sections only/

    # display :board without sections, or without a row_layout.
    assert compile_ui(board(nil)) =~
             ~r/declares display :board: a board needs a :table component with a sections block and a row_layout/

    assert compile_ui(board("scope_by :status", row_layout: false)) =~
             ~r/declares display :board: a board needs a :table component with a sections block and a row_layout/

    # display :board on a non-table component.
    assert compile_ui("""
               component :form do
                 fields [:name]
                 create_action :create
                 display :board
               end
           """) =~ ~r/component :form declares display :board/

    # Source-less sections render as a list without display :board.
    assert compile_ui(board("scope_by :status", display: ":list", row_layout: false)) == ""
  end
end
