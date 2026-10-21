defmodule AshA2ui.Calendar.CalendarDslTest do
  @moduledoc """
  `display :calendar` on `:table` (A2UI-107): the DSL options, their
  resolution onto the table scope, and the compile-time rules. Verifier
  cases use the `capture_io(:stderr)` + regex pattern of the other verifier
  suites.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Calendar.{DayUI, MonthUI, WeekUI}

  @tag ac: "A2UI-107/AC-1"
  test "declares a calendar table" do
    [month] = ResolvedView.resolve(MonthUI).tables

    assert month.component.display == :calendar

    assert month.calendar == %{
             date_field: :starts_on,
             end_date_field: :ends_on,
             granularity: :month,
             granularities: [:month],
             start_kind: :date,
             end_kind: :date
           }

    week = Enum.find(ResolvedView.resolve(WeekUI).tables, &(&1.name == :week))

    assert week.calendar == %{
             date_field: :starts_at,
             end_date_field: nil,
             granularity: :week,
             granularities: [:week],
             start_kind: :datetime,
             end_kind: nil
           }

    # The plain table beside it is not a calendar.
    all = Enum.find(ResolvedView.resolve(WeekUI).tables, &(&1.name == :all))
    assert all.calendar == nil

    [day] = ResolvedView.resolve(DayUI).tables
    assert day.calendar.granularity == :day
    assert day.calendar.end_kind == :datetime
  end

  test "granularity defaults to month" do
    name = "AshA2ui.Calendar.CalendarDslTest.Default#{System.unique_integer([:positive])}"

    [{module, _binary}] =
      Code.compile_string("""
      defmodule #{name} do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Calendar.Event

          query :q do
          end

          component :table do
            fields [:title, :starts_on]
            display :calendar
            date_field :starts_on
            query :q
          end
        end
      end
      """)

    [table] = ResolvedView.resolve(module).tables
    assert table.calendar.granularity == :month
  end

  # --- verifier -------------------------------------------------------------

  defp compile_ui(body) do
    name = "AshA2ui.Calendar.CalendarDslTest.Ui#{System.unique_integer([:positive])}"

    capture_io(:stderr, fn ->
      try do
        Code.compile_string("""
        defmodule #{name} do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Calendar.Event

            query :q do
            end

        #{body}
          end
        end
        """)
      rescue
        error -> IO.puts(:stderr, Exception.message(error))
      end
    end)
  end

  defp calendar(options) do
    """
        component :table do
          fields [:title, :status, :starts_on, :ends_on]
    #{options}
        end
    """
  end

  @tag ac: "A2UI-107/AC-2"
  test "rejects invalid calendars" do
    cases = [
      {calendar("display :calendar\nquery :q"), ~r/needs a date_field/},
      {calendar("display :calendar\ndate_field :starts_on"), ~r/needs a query/},
      {calendar("display :calendar\ndate_field :title\nquery :q"),
       ~r/date_field :title must be a public :date or datetime attribute/},
      {calendar("display :calendar\ndate_field :nope\nquery :q"),
       ~r/date_field :nope must be a public :date or datetime attribute/},
      {calendar("display :calendar\ndate_field :starts_on\nend_date_field :status\nquery :q"),
       ~r/end_date_field :status must be a public :date or datetime attribute/},
      {calendar("display :calendar\ndate_field :starts_on\nend_date_field :starts_on\nquery :q"),
       ~r/end_date_field must differ from date_field/},
      {calendar("date_field :starts_on"),
       ~r/date_field is only supported with display :calendar/},
      {calendar("granularity :week"), ~r/granularity is only supported with display :calendar/},
      {calendar("display :calendar\ndate_field :starts_on\nquery :q\nbulk_actions [:confirm]"),
       ~r/cannot declare bulk_actions/},
      {calendar("""
       display :calendar
       date_field :starts_on
       query :q

       sections do
         scope_by :status
       end
       """), ~r/cannot declare a sections block/},
      {"""
           component :detail do
             context :event
             display :calendar
             date_field :starts_on
           end

           context :event do
             resource AshA2ui.Test.Calendar.Event
           end
       """, ~r/only supported on :table components/}
    ]

    for {body, pattern} <- cases do
      output = compile_ui(body)
      assert output =~ pattern, "expected #{inspect(pattern)} for:\n#{body}\ngot:\n#{output}"
    end
  end

  @tag ac: "A2UI-107/AC-2"
  test "granularity is a closed set" do
    output =
      compile_ui(
        calendar("display :calendar\ndate_field :starts_on\nquery :q\ngranularity :year")
      )

    assert output =~ ~r/granularity/
    assert output =~ ~r/:day, :week, :month|one of/
  end

  test "a valid calendar compiles without diagnostics" do
    output =
      compile_ui(
        calendar(
          "display :calendar\ndate_field :starts_on\nend_date_field :ends_on\ngranularity :week\nquery :q"
        )
      )

    refute output =~ ~r/error|warning/i
  end
end
