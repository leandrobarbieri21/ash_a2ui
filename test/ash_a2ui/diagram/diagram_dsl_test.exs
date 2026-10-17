defmodule AshA2ui.Diagram.DiagramDslTest do
  @moduledoc """
  The `diagram` entity (A2UI-108): resolution onto the view, and the
  compile-time rules. Verifier cases use the `capture_io(:stderr)` + regex
  pattern of the other verifier suites.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Diagram.{Flow, FlowUI, FlowV1UI}

  @tag ac: "A2UI-108/AC-1"
  test "declares diagrams" do
    assert [flow] = ResolvedView.resolve(FlowUI).diagrams
    assert flow.name == :flow
    assert flow.label == "Visits in flight"
    assert flow.description == "Where every visit is right now."
    assert flow.source == Flow
    assert AshA2ui.Diagram.label(flow) == "Visits in flight"

    assert [mfa, offline] = ResolvedView.resolve(FlowV1UI).diagrams
    assert mfa.source == {Flow, :diagram_for, [:v1]}
    assert AshA2ui.Diagram.label(mfa) == "Flow"
    assert offline.name == :offline

    # Surfaces without diagrams resolve none.
    assert ResolvedView.resolve(AshA2ui.Test.MinimalUI).diagrams == []
  end

  defp compile_ui(body) do
    name = "AshA2ui.Diagram.DiagramDslTest.Ui#{System.unique_integer([:positive])}"

    capture_io(:stderr, fn ->
      try do
        Code.compile_string("""
        defmodule #{name} do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Diagram.Visit
        #{body}
          end
        end
        """)
      rescue
        error -> IO.puts(:stderr, Exception.message(error))
      end
    end)
  end

  @tag ac: "A2UI-108/AC-2"
  test "rejects invalid diagrams" do
    cases = [
      {"""
       diagram :flow do
         source AshA2ui.Test.Diagram.Flow
       end

       diagram :flow do
         source AshA2ui.Test.Diagram.Flow
       end
       """, ~r/duplicate diagram :flow/},
      {"""
       diagram :Flow do
         source AshA2ui.Test.Diagram.Flow
       end
       """, ~r/must be a lowercase identifier/},
      {"""
       diagram :flow do
         source AshA2ui.Test.Diagram.Visit
       end
       """, ~r/does not export diagram\/1/},
      {"""
       diagram :flow do
         source {AshA2ui.Test.Diagram.Flow, :diagram_for, []}
       end
       """, ~r/diagram_for\/1 is not exported/},
      {"""
       diagram :flow do
         label "No source"
       end
       """, ~r/source/}
    ]

    for {body, pattern} <- cases do
      output = compile_ui(body)
      assert output =~ pattern, "expected #{inspect(pattern)} for:\n#{body}\ngot:\n#{output}"
    end
  end

  test "a valid diagram compiles without diagnostics" do
    output =
      compile_ui("""
      diagram :flow do
        source {AshA2ui.Test.Diagram.Flow, :diagram_for, [:v1]}
      end
      """)

    refute output =~ ~r/error|warning/i
  end
end
