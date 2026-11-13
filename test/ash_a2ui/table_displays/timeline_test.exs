defmodule AshA2ui.TableDisplays.TimelineTest do
  @moduledoc """
  `display :timeline`: a table read oldest first over its `date_field`, each
  row led by its moment, in the basic composition under both catalogs; the
  DSL and composed-surface rules; and a requested sort still winning.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper
  import ExUnit.CaptureIO

  alias AshA2ui.ActionHandler
  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Error
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Messages
  alias AshA2ui.Test.Surface
  alias AshA2ui.Test.TableDisplays.{TimelineUI, Visit}

  @allowlist Dynamic.allowlist([Visit])

  defp spec(overrides) do
    %{
      "resource" => "Visit",
      "queries" => [%{"name" => "history", "page_size" => 20}],
      "components" => [
        Map.merge(
          %{
            "kind" => "table",
            "name" => "history",
            "fields" => ["summary", "seen_at"],
            "display" => "timeline",
            "date_field" => "seen_at",
            "query" => "history"
          },
          overrides
        )
      ]
    }
  end

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :catalog) end)
    :ok
  end

  defp visit!(summary, seen_at) do
    Ash.create!(Visit, %{summary: summary, seen_at: seen_at}, authorize?: false)
  end

  defp seed do
    visit!("Follow-up", ~U[2026-10-20 14:05:00Z])
    visit!("Intake", ~U[2026-10-01 08:30:00Z])
    visit!("Not yet seen", nil)
    visit!("Check-in", ~U[2026-10-07 09:00:00Z])
  end

  defp components_by_id(components), do: Map.new(components, &{&1["id"], &1})

  defp parts(ui, opts \\ []) do
    messages = AshA2ui.Info.build_surface(ui, [authorize?: false] ++ opts)
    Enum.each(messages, &assert_valid_agent_message/1)

    components =
      Surface.components(messages)

    value =
      Enum.find_value(messages, fn
        %{"createSurface" => %{"dataModel" => value}} -> value
        %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
        _other -> nil
      end)

    {components_by_id(components), value}
  end

  defp envelope(context) do
    Messages.call("query", "visit_timeline", context)
  end

  describe "encoding" do
    test "reads oldest first, each row led by its moment" do
      seed()
      {components, value} = parts(TimelineUI)

      summaries = Enum.map(value["records"], & &1["summary"])
      assert Enum.take(summaries, 3) == ["Intake", "Check-in", "Follow-up"]
      assert "Not yet seen" in summaries

      intake = hd(value["records"])
      assert intake["_timeline_at"] == "2026-10-01T08:30:00Z"
      assert intake["_timeline_when"] == "2026-10-01 08:30"

      # A record without a moment carries empty strings, never a date.
      undated = Enum.find(value["records"], &(&1["summary"] == "Not yet seen"))
      assert undated["_timeline_at"] == ""
      assert undated["_timeline_when"] == ""

      # The leading caption, bound to the moment.
      assert hd(components["record_row_content"]["children"]) == "record_row_when"

      assert components["record_row_when"] == %{
               "id" => "record_row_when",
               "component" => "Text",
               "text" => %{"@path" => "_timeline_when"},
               "variant" => "caption"
             }
    end

    test "is basic catalog only" do
      seed()
      {components, _value} = parts(TimelineUI)

      basic =
        "priv/a2ui/v1_0/catalogs/basic/v1/catalog.json"
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("components")
        |> Map.keys()
        |> MapSet.new()

      kinds = components |> Map.values() |> MapSet.new(& &1["component"])
      assert MapSet.subset?(kinds, basic), inspect(MapSet.difference(kinds, basic))

      assert {:ok, v1} =
               Dynamic.resolve(spec(%{}), allowlist: @allowlist)

      assert [message] = Dynamic.build_surface(v1, authorize?: false)
      assert_valid_agent_message(message)

      record = hd(message["createSurface"]["dataModel"]["records"])
      assert record["_timeline_when"] == "2026-10-01 08:30"
    end

    test "keeps the basic composition under the admin catalog" do
      seed()
      Application.put_env(:ash_a2ui, :catalog, :admin_v1)

      messages = AshA2ui.Info.build_surface(TimelineUI, authorize?: false)

      by_id =
        messages
        |> Surface.components()
        |> components_by_id()

      refute Enum.any?(Map.values(by_id), &(&1["component"] == "dataGrid"))
      assert by_id["record_row_when"]["text"] == %{"@path" => "_timeline_when"}
    end
  end

  describe "querying" do
    test "a requested sort wins over time order, and its absence restores it" do
      seed()
      {_components, value} = parts(TimelineUI)

      assert {:ok, sorted} =
               ActionHandler.handle(
                 TimelineUI,
                 envelope(%{
                   "component" => "history",
                   "query" =>
                     Map.put(value["query"], "sort", %{"field" => "summary", "dir" => "desc"})
                 }),
                 authorize?: false
               )

      records = records(sorted)

      assert Enum.map(records, & &1["summary"]) ==
               ["Not yet seen", "Intake", "Follow-up", "Check-in"]

      assert {:ok, unsorted} =
               ActionHandler.handle(
                 TimelineUI,
                 envelope(%{
                   "component" => "history",
                   "query" => Map.put(value["query"], "sort", nil)
                 }),
                 authorize?: false
               )

      records = records(unsorted)

      assert records |> Enum.map(& &1["summary"]) |> Enum.take(3) == [
               "Intake",
               "Check-in",
               "Follow-up"
             ]

      assert Enum.all?(records, &Map.has_key?(&1, "_timeline_when"))
    end
  end

  defp records(messages) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => "/records", "value" => records}} -> records
      _other -> nil
    end)
  end

  describe "rules" do
    defp compile_ui(body) do
      name = "AshA2ui.TableDisplays.TimelineTest.Ui#{System.unique_integer([:positive])}"

      capture_io(:stderr, fn ->
        try do
          Code.compile_string("""
          defmodule #{name} do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.TableDisplays.Visit

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

    defp table(options) do
      """
          component :table do
            fields [:summary, :seen_at, :seen_on, :note]
      #{options}
          end
      """
    end

    test "the DSL rejects an invalid timeline" do
      cases = [
        {table("display :timeline"), ~r/display :timeline needs a date_field/},
        {table("display :timeline\ndate_field :note"),
         ~r/date_field :note must be a public :date or datetime attribute/},
        {table("display :timeline\ndate_field :nope"),
         ~r/date_field :nope must be a public :date or datetime attribute/},
        {table("display :timeline\ndate_field :seen_at\ngranularity :week"),
         ~r/granularity is only supported with display :calendar/},
        {table("display :timeline\ndate_field :seen_at\nend_date_field :seen_on"),
         ~r/end_date_field is only supported with display :calendar/},
        {table("date_field :seen_at"),
         ~r/date_field is only supported with display :calendar or :timeline/},
        {table("""
         display :timeline
         date_field :seen_at

         sections do
           scope_by :summary
         end
         """), ~r/cannot declare a sections block/}
      ]

      for {body, pattern} <- cases do
        output = compile_ui(body)
        assert output =~ pattern, "expected #{inspect(pattern)} for:\n#{body}\ngot:\n#{output}"
      end
    end

    test "a valid timeline compiles, on a date attribute too" do
      assert compile_ui(table("display :timeline\ndate_field :seen_on\nquery :q")) == ""
      assert compile_ui(table("display :timeline\ndate_field :seen_at")) == ""
    end

    test "a declared timeline exports to a spec that resolves back" do
      {:ok, spec, _rejections} = Importer.import(TimelineUI)
      [table] = spec["components"]

      assert Map.take(table, ~w(display date_field)) ==
               %{"display" => "timeline", "date_field" => "seen_at"}

      assert {:ok, surface} = Dynamic.resolve(spec, allowlist: @allowlist)

      assert [%{timeline: %{date_field: :seen_at}}] =
               ResolvedView.resolve(surface.dsl_state).tables
    end

    test "a composed surface rejects what the DSL rejects" do
      assert {:ok, surface} = Dynamic.resolve(spec(%{}), allowlist: @allowlist)

      assert [%{timeline: %{date_field: :seen_at}}] =
               ResolvedView.resolve(surface.dsl_state).tables

      without_date =
        update_in(spec(%{}), ["components", Access.at(0)], &Map.delete(&1, "date_field"))

      for {input, pattern} <- [
            {without_date, ~r/display :timeline needs a date_field/},
            {spec(%{"date_field" => "note"}),
             ~r/date_field :note must be a public :date or datetime/},
            {spec(%{"granularity" => "week"}),
             ~r/granularity is only supported with display :calendar/},
            {spec(%{"display" => "list"}),
             ~r/date_field is only supported with display :calendar or :timeline/}
          ] do
        assert {:error, errors} = Dynamic.resolve(input, allowlist: @allowlist)
        assert errors |> Error.messages() |> Enum.join("\n") =~ pattern
      end
    end
  end
end
