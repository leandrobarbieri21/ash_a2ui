defmodule AshA2ui.Board.BoardDynamicTest do
  @moduledoc """
  Boards in composed surfaces (A2UI-110, Jira AST-176 board half): the
  dynamic spec carries `display: "board"` with source-less `sections`
  (`scope_by`, `values`, `labels`, `swimlanes_by`, `swimlane_values`,
  `swimlane_labels`, `swimlane_tones`). The shared verifiers
  (`VerifySections`, `VerifyLayouts`, `VerifyComponents`, `VerifyActions`)
  apply their DSL rules to it; composed specs additionally keep boards
  source-less and expand to at most 12 cells, counted by the same
  `AshA2ui.Board.cell_count/2` as the declared limit.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Error
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.BoardTask
  alias AshA2ui.Test.ComposedBoard.Job

  @allowlist Dynamic.allowlist([BoardTask, Job])

  defp board_spec(sections_overrides \\ %{}, table_overrides \\ %{}, extra \\ %{}) do
    Map.merge(
      %{
        "resource" => "BoardTask",
        "queries" => [%{"name" => "cell_q", "page_size" => 5}],
        "components" => [
          Map.merge(
            %{
              "kind" => "table",
              "name" => "board",
              "fields" => ["name", "priority", "status", "severity"],
              "display" => "board",
              "row_actions" => ["claim"],
              "query" => "cell_q",
              "row_layout" => %{"title" => "name", "badge" => "priority"},
              "sections" =>
                Map.merge(
                  %{
                    "scope_by" => "status",
                    "values" => ["open", "claimed"],
                    "labels" => %{"open" => "To do"},
                    "swimlanes_by" => "severity",
                    "swimlane_values" => ["very_high", "low"],
                    "swimlane_labels" => %{"very_high" => "Critical"},
                    "swimlane_tones" => %{"very_high" => "danger", "low" => "success"}
                  },
                  sections_overrides
                )
            },
            table_overrides
          )
        ],
        "actions" => [
          %{"name" => "claim", "visible_when" => %{"status" => "open"}, "refreshes" => ["board"]}
        ]
      },
      extra
    )
  end

  defp messages({:error, errors}), do: errors |> Error.messages() |> Enum.join("\n")

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  @tag ac: "A2UI-110/AC-1"
  test "a composed swimlaned board resolves, renders and moves cards" do
    card =
      Ash.create!(BoardTask, %{name: "card", status: :open, severity: :very_high},
        authorize?: false
      )

    Ash.create!(BoardTask, %{name: "calm", status: :claimed, severity: :low}, authorize?: false)

    assert {:ok, surface} = Dynamic.resolve(board_spec(), allowlist: @allowlist)

    messages = Dynamic.build_surface(surface, authorize?: false)
    Enum.each(messages, &assert_valid_server_message/1)
    data = Enum.find_value(messages, &get_in(&1, ["updateDataModel", "value"]))

    # Two lanes x two swimlanes: one cell table each, swimlane-major.
    assert data["records"] |> Map.keys() |> Enum.sort() ==
             Enum.sort([
               "board_open__very_high",
               "board_claimed__very_high",
               "board_open__low",
               "board_claimed__low"
             ])

    assert [%{"name" => "card"}] = data["records"]["board_open__very_high"]
    assert data["_swimlane_tone_board__very_high"] == "danger"

    components = Enum.find_value(messages, &get_in(&1, ["updateComponents", "components"]))
    assert Enum.any?(components, &(&1["id"] == "board_board_stages"))

    # The transition row action moves the card; the template-key refresh
    # re-reads every cell.
    envelope = %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "invoke",
        "surfaceId" => surface.surface_id,
        "sourceComponentId" => "row_action_claim",
        "timestamp" => "2026-10-17T00:00:00Z",
        "context" => %{
          "action" => "claim",
          "recordId" => card.id,
          "component" => "board_open__very_high"
        }
      }
    }

    assert {:ok, reply} = Dynamic.handle_action(surface, envelope, authorize?: false)
    assert value_at(reply, "/records/board_open__very_high") == []
    assert [%{"name" => "card"}] = value_at(reply, "/records/board_claimed__very_high")
  end

  @tag ac: "A2UI-110/AC-2"
  test "rejects what the DSL rejects, and more for composed boards" do
    job_board = fn sections ->
      board_spec(
        sections,
        %{
          "fields" => ["title", "stage", "region"],
          "row_actions" => [],
          "row_layout" => %{"title" => "title"}
        },
        %{
          "resource" => "Job",
          "actions" => []
        }
      )
    end

    cases = [
      # source-less only
      {board_spec(%{"source" => "BoardTask"}),
       ~r/a composed board's lanes are the values of scope_by — drop "source"/},
      # existing-atom lookup: an unknown attribute name is refused, not created
      {board_spec(%{"scope_by" => "zz_no_such_attribute_7c1"}),
       ~r/scope_by "zz_no_such_attribute_7c1" is not an attribute of the resource — name one of its enumerated attributes/},
      {board_spec(%{"swimlanes_by" => "zz_no_such_attribute_7c2"}),
       ~r/swimlanes_by "zz_no_such_attribute_7c2" is not an attribute/},
      # enumerable attributes only, values from the enumeration
      {board_spec(%{"scope_by" => "name", "values" => nil, "labels" => %{}}),
       ~r/scope_by :name of .* is neither an Ash.Type.Enum nor constrained by one_of|needs? enumerable values/},
      {board_spec(%{"values" => ["open", "nope"]}), ~r/values .*"nope"|:nope|nope/},
      {board_spec(%{"values" => []}), ~r/values \[\] leaves the board with nothing to show/},
      {board_spec(%{"swimlane_values" => []}), ~r/swimlane_values \[\]/},
      # labels are capped plain text, keyed by enumerated values
      {board_spec(%{"labels" => %{"open" => "<b>To do</b>"}}),
       ~r/labels values must be plain text/},
      {board_spec(%{"labels" => %{"open" => "[x](javascript:alert(1))"}}),
       ~r/labels values must be plain text/},
      {board_spec(%{"labels" => %{"open" => String.duplicate("a", 61)}}),
       ~r/plain text of 1 to 60 characters/},
      {board_spec(%{"swimlane_labels" => %{"zz_unknown_value_44" => "X"}}),
       ~r/swimlane_labels key "zz_unknown_value_44" is not one of the attribute's enumerated values/},
      # tones from the closed set
      {board_spec(%{"swimlane_tones" => %{"low" => "purple"}}),
       ~r/tone "purple" is not supported/},
      # the composed cell cap (5 stages x 3 regions)
      {job_board.(%{
         "scope_by" => "stage",
         "values" => nil,
         "labels" => %{},
         "swimlanes_by" => "region",
         "swimlane_values" => nil,
         "swimlane_labels" => %{},
         "swimlane_tones" => %{}
       }), ~r/expands to 15 cells .* at most 12/},
      # #25's runtime-name rule: names may not extend one another
      {board_spec(%{
         "swimlanes_by" => "tier",
         "swimlane_values" => ["high", "high_total"],
         "swimlane_labels" => %{},
         "swimlane_tones" => %{}
       }), ~r/high_total|extend/},
      # display :board needs a row_layout
      {board_spec(%{}, %{"row_layout" => nil}),
       ~r/a board needs a :table component with a sections block and a row_layout/},
      # bulk actions stay out of the spec
      {board_spec(%{}, %{"bulk_actions" => ["claim"]}), ~r/unknown key "bulk_actions"/},
      # row actions come from the resource; refreshes name spec components
      {board_spec(%{}, %{"row_actions" => ["zz_not_an_action"]}), ~r/zz_not_an_action/},
      {board_spec(%{}, %{}, %{"actions" => [%{"name" => "claim", "refreshes" => ["elsewhere"]}]}),
       ~r/refreshes unknown table component :elsewhere/}
    ]

    for {spec, pattern} <- cases do
      spec = drop_nils(spec)
      result = Dynamic.resolve(spec, allowlist: @allowlist)
      assert {:error, _errors} = result, "expected a rejection matching #{inspect(pattern)}"

      assert messages(result) =~ pattern,
             "expected #{inspect(pattern)}, got:\n#{messages(result)}"
    end
  end

  @tag ac: "A2UI-110/AC-2"
  test "the cap counts the chosen values; a nil-mapping calculation can swimlane" do
    spec = %{
      "resource" => "Job",
      "queries" => [%{"name" => "q", "page_size" => 5}],
      "components" => [
        %{
          "kind" => "table",
          "name" => "jobs",
          "fields" => ["title", "stage"],
          "display" => "board",
          "query" => "q",
          "row_layout" => %{"title" => "title"},
          "sections" => %{
            "scope_by" => "stage",
            "values" => ["new", "triage", "booked"],
            "swimlanes_by" => "region_or_none",
            "swimlane_tones" => %{"none" => "neutral"}
          }
        }
      ]
    }

    # 3 stages x 4 regions (with "none") = 12 cells: at the cap, accepted.
    assert {:ok, surface} = Dynamic.resolve(spec, allowlist: @allowlist)

    Ash.create!(Job, %{title: "No region yet"}, authorize?: false)

    data =
      surface
      |> Dynamic.build_surface(authorize?: false)
      |> Enum.find_value(&get_in(&1, ["updateDataModel", "value"]))

    assert [%{"title" => "No region yet"}] = data["records"]["jobs_new__none"]
  end

  @tag ac: "A2UI-110/AC-4"
  test "a composed limit below the board's lanes or cells is refused" do
    lanes = %{
      "values" => nil,
      "labels" => %{},
      "swimlanes_by" => nil,
      "swimlane_values" => nil,
      "swimlane_labels" => %{},
      "swimlane_tones" => %{}
    }

    cases = [
      # swimlaned: 2 lanes x 2 swimlanes = 4 cells
      {board_spec(%{"limit" => 3}), ~r/limit 3 is below the 4 cells \(2 lanes x 2 swimlanes\)/},
      # swimlaned with every value: 4 lanes x 3 swimlanes = 12 cells
      {board_spec(%{
         "values" => nil,
         "labels" => %{},
         "swimlane_values" => nil,
         "swimlane_labels" => %{},
         "swimlane_tones" => %{},
         "limit" => 5
       }), ~r/limit 5 is below the 12 cells \(4 lanes x 3 swimlanes\)/},
      # lanes only: every status value is a lane
      {board_spec(Map.put(lanes, "limit", 2)), ~r/limit 2 is below the 4 lanes/}
    ]

    for {spec, pattern} <- cases do
      result = Dynamic.resolve(drop_nils(spec), allowlist: @allowlist)
      assert {:error, _errors} = result, "expected a rejection matching #{inspect(pattern)}"

      assert messages(result) =~ pattern,
             "expected #{inspect(pattern)}, got:\n#{messages(result)}"
    end

    # A limit at the cell count is accepted.
    assert {:ok, _surface} = Dynamic.resolve(board_spec(%{"limit" => 4}), allowlist: @allowlist)
  end

  test "Board.cell_count/2 counts the chosen values, and errors without an enumeration" do
    sections = fn overrides ->
      Map.merge(
        %{scope_by: :status, values: nil, swimlanes_by: nil, swimlane_values: nil},
        overrides
      )
    end

    assert AshA2ui.Board.cell_count(BoardTask, sections.(%{})) == {:ok, 4}

    assert AshA2ui.Board.cell_count(BoardTask, sections.(%{values: [:open, "claimed"]})) ==
             {:ok, 2}

    assert AshA2ui.Board.cell_count(
             BoardTask,
             sections.(%{values: [:open, :claimed], swimlanes_by: :severity})
           ) == {:ok, 6}

    # Values outside the enumeration are not counted.
    assert AshA2ui.Board.cell_count(BoardTask, sections.(%{values: [:open, :nope]})) == {:ok, 1}

    # Without enumerable values there is nothing to count (the verifier's
    # :error branch reports this instead of crashing).
    assert AshA2ui.Board.cell_count(BoardTask, sections.(%{scope_by: :name})) == :error
    assert AshA2ui.Board.cell_count(BoardTask, sections.(%{swimlanes_by: :name})) == :error
  end

  @tag ac: "A2UI-110/AC-3"
  test "a declared swimlaned board exports, promotes and serializes back" do
    {:ok, spec, rejections} = Importer.import(AshA2ui.Test.SwimlaneBoardUI)

    assert Enum.map(rejections, & &1.feature) == ["surface_id"]

    [board] = spec["components"]
    assert board["display"] == "board"

    assert board["sections"] == %{
             "scope_by" => "status",
             "values" => ["open", "claimed", "completed"],
             "labels" => %{"open" => "To do"},
             "swimlanes_by" => "severity",
             "swimlane_values" => ["very_high", "low"],
             "swimlane_labels" => %{"very_high" => "Critical"},
             "swimlane_tones" => %{"very_high" => "danger", "low" => "success"}
           }

    assert {:ok, surface} = Dynamic.resolve(spec, allowlist: @allowlist)
    declared = sections(AshA2ui.Test.SwimlaneBoardUI)
    assert sections(surface.dsl_state) == declared

    assert {:ok, back} = spec |> Dynamic.serialize() |> Dynamic.deserialize(allowlist: @allowlist)
    assert sections(back.dsl_state) == declared

    assert {:ok, source} =
             Dynamic.to_dsl_source(spec,
               module: AshA2ui.Board.PromotedSwimlaneUI,
               allowlist: @allowlist
             )

    assert source =~ "display :board"
    assert source =~ "swimlanes_by :severity"
    assert source =~ "values [:open, :claimed, :completed]"
    refute source =~ ~r/^\s+source /m

    [{module, _binary}] = Code.compile_string(source)
    assert sections(module) == declared
  end

  # The resolved sections config of the view's one board template, with
  # keyword options sorted (a JSON object carries no key order).
  defp sections(ui) do
    [table] = AshA2ui.ResolvedView.resolve(ui).tables
    normalize(table.sections)
  end

  defp normalize(%{} = map) when not is_struct(map),
    do: Map.new(map, fn {k, v} -> {k, normalize(v)} end)

  defp normalize([{key, _value} | _rest] = keyword) when is_atom(key), do: Enum.sort(keyword)
  defp normalize(value), do: value

  defp drop_nils(%{} = map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {key, drop_nils(value)} end)
  end

  defp drop_nils(list) when is_list(list), do: Enum.map(list, &drop_nils/1)
  defp drop_nils(value), do: value
end
