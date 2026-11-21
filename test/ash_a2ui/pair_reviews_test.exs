defmodule AshA2ui.PairReviewsTest do
  @moduledoc """
  Admin catalog 3.10: the items of a `pairs` field may carry their own
  review and key. Each row carries the normalized items at
  `_pairs_<field>` (the column's `items`); a field action on a pairs field
  is a button per item (the column's `pairAction`), run through the
  `field_action` ashAction with the item's key as the action's `:item`; a
  review summary counts each waiting item.
  """

  # Not async: the catalog is application config, and capture_io(:stderr)
  # captures a global device.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.{ActionHandler, Pairs}
  alias AshA2ui.Test.{Dossier, DossierNote, DossierNotesReviewUI, Messages, SchemaHelper}

  @pending %{state: :pending, page: 2, href: "#document=notes.0.notice"}
  @missing %{state: :missing}
  @reviewed %{state: :reviewed, page: 3}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      Ets.stop(Dossier)
      Ets.stop(DossierNote)
    end)

    dossier =
      Ash.create!(Dossier, %{name: "Harbour lease", name_review: @reviewed}, authorize?: false)

    other = Ash.create!(Dossier, %{name: "Elsewhere"}, authorize?: false)

    note = fn dossier, position, facts, attrs ->
      Ash.create!(
        DossierNote,
        Map.merge(
          %{dossier_id: dossier.id, title: "Note #{position}", position: position, facts: facts},
          attrs
        ),
        authorize?: false
      )
    end

    first =
      note.(
        dossier,
        1,
        [
          %{term: "Notice", value: "60 days", key: "0", review: @pending},
          %{term: "Cause", value: nil, key: "1", review: @missing},
          %{term: "Done", value: "Yes", key: "2", review: @reviewed}
        ],
        %{}
      )

    second =
      note.(
        dossier,
        2,
        [
          %{term: "Scope", value: "All", key: "a", review: @pending, action: false},
          %{term: "Unkeyed", value: "x", review: @pending},
          %{term: "Plain", value: 3}
        ],
        %{}
      )

    locked =
      note.(dossier, 3, [%{term: "Fee", value: "1", key: "0", review: @pending}], %{locked: true})

    foreign = note.(other, 1, [%{term: "Fee", value: "1", key: "0", review: @pending}], %{})

    %{dossier: dossier, first: first, second: second, locked: locked, foreign: foreign}
  end

  defp contexts(dossier), do: %{"dossier" => %{"value" => dossier.id, "label" => dossier.name}}

  defp surface(dossier) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(DossierNotesReviewUI,
        authorize?: false,
        context_state: %{"dossier" => %{"search" => "", "value" => dossier.id, "label" => "x"}}
      )

    SchemaHelper.assert_valid_agent_message(message, catalogs: SchemaHelper.admin_catalogs())

    grid = Enum.find(surface["components"], &(&1["component"] == "dataGrid"))
    "/" <> path = grid["rows"]["@path"]
    rows = get_in(surface["dataModel"], String.split(path, "/"))

    %{
      columns: Map.new(grid["columns"], &{&1["path"], &1}),
      rows: Map.new(rows, &{&1["id"], &1}),
      summary: surface["dataModel"]["detail"]["dossier"]["_review_summary_to_review"]
    }
  end

  defp check(dossier, record_id, item, opts \\ []) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    context =
      %{
        "component" => Keyword.get(opts, :component, "notes"),
        "field" => Keyword.get(opts, :field, "facts"),
        "recordId" => record_id,
        "contexts" => contexts(dossier)
      }
      |> then(&if(item, do: Map.put(&1, "item", item), else: &1))

    ActionHandler.handle(
      DossierNotesReviewUI,
      Messages.call("field_action", "dossier_notes_review", context),
      authorize?: false
    )
  end

  defp checked(note), do: Ash.get!(DossierNote, note.id, authorize?: false).checked

  describe "normalize/3" do
    test "keeps items with a term, writes values as text, and leaves bad parts out" do
      items =
        Pairs.normalize(
          [
            %{
              "term" => "A",
              "value" => Decimal.new("1.50"),
              "key" => 7,
              "review" => %{"state" => "pending"}
            },
            %{term: "B", value: nil, key: "", review: %{state: "nonsense"}},
            %{term: "", value: "dropped"},
            "not a map",
            %{term: "C", value: true, key: "c", action: false}
          ],
          nil,
          true
        )

      assert [
               %{
                 "term" => "A",
                 "value" => "1.50",
                 "key" => "7",
                 "action" => true,
                 "review" => review
               },
               %{"term" => "B", "value" => "", "action" => false} = b,
               %{"term" => "C", "value" => "", "key" => "c", "action" => false}
             ] = items

      assert review["state"] == "pending"
      refute Map.has_key?(b, "key")
      refute Map.has_key?(b, "review")
    end

    test "a field without an action carries no offers; a value that is not a list has no items" do
      assert [item] = Pairs.normalize([%{term: "A", value: "1", key: "k"}])
      refute Map.has_key?(item, "action")
      assert Pairs.normalize(nil) == []
      assert Pairs.normalize(%{term: "A"}) == []
    end
  end

  describe "the wire" do
    test "the column binds the items and carries the per-item button", %{dossier: dossier} do
      %{columns: columns} = surface(dossier)

      assert columns["facts"]["pairs"] == true
      assert columns["facts"]["items"] == %{"path" => "_pairs_facts"}

      assert columns["facts"]["pairAction"] == %{
               "label" => "Mark as reviewed",
               "icon" => "check",
               "action" => "field_action",
               "context" => %{
                 "component" => "notes",
                 "field" => "facts",
                 "recordId" => %{"@path" => "id"},
                 "query" => %{"@path" => "/query"},
                 "contexts" => %{"@path" => "/context"}
               }
             }

      # the per-row button and its gate are not drawn for a pairs field
      refute Map.has_key?(columns["facts"], "action")
      refute Map.has_key?(columns["facts"], "actionVisible")
      refute Map.has_key?(columns["title"], "items")
    end

    test "each row carries its items with their reviews and offers",
         %{dossier: dossier, first: first, second: second, locked: locked} do
      %{rows: rows} = surface(dossier)

      assert [notice, cause, done] = rows[first.id]["_pairs_facts"]

      assert notice == %{
               "term" => "Notice",
               "value" => "60 days",
               "key" => "0",
               "action" => true,
               "review" => %{
                 "state" => "pending",
                 "stateLabel" => "Not reviewed",
                 "page" => 2,
                 "pageLabel" => "p. 2",
                 "href" => "#document=notes.0.notice"
               }
             }

      assert cause["review"]["state"] == "missing"
      assert cause["action"] == true
      assert done["review"]["state"] == "reviewed"

      # an item saying no, an item with no key, and an unreviewed plain item
      assert [%{"action" => false}, %{"action" => false} = unkeyed, plain] =
               rows[second.id]["_pairs_facts"]

      refute Map.has_key?(unkeyed, "key")
      assert plain == %{"term" => "Plain", "value" => "3", "action" => false}

      # the record does not offer the action: no item does
      assert [%{"action" => false}] = rows[locked.id]["_pairs_facts"]
    end
  end

  describe "field_action on an item" do
    test "runs the action for the item, refreshes the table and the context's record",
         %{dossier: dossier, first: first} do
      assert {:ok, messages} = check(dossier, first.id, "0")
      assert checked(first) == ["0"]

      refreshed =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/records", "value" => rows}} -> rows
          _other -> nil
        end)

      row = Enum.find(refreshed, &(&1["id"] == first.id))
      assert [%{"review" => %{"state" => "reviewed"}} | _rest] = row["_pairs_facts"]

      detail =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/detail/dossier", "value" => value}} -> value
          _other -> nil
        end)

      # what still waits: the first note's cause, the second note's two and
      # the locked note's one
      assert detail["_review_summary_to_review"]["count"] == 4
      assert Messages.response(messages)["value"]["kind"] == "success"
    end

    test "a missing item may be checked too", %{dossier: dossier, first: first} do
      assert {:ok, _messages} = check(dossier, first.id, "1")
      assert checked(first) == ["1"]
    end

    test "is refused without an item, or for an item not there or not offered",
         %{dossier: dossier, first: first, second: second} do
      assert {:error, messages} = check(dossier, first.id, nil)
      assert Messages.response(messages)["error"]
      assert {:error, _messages} = check(dossier, first.id, "9")
      assert {:error, _messages} = check(dossier, second.id, "a")
      assert checked(first) == []
      assert checked(second) == []
    end

    test "is refused on a record that does not offer it, or outside the table's scope",
         %{dossier: dossier, locked: locked, foreign: foreign} do
      assert {:error, _messages} = check(dossier, locked.id, "0")
      assert {:error, _messages} = check(dossier, foreign.id, "0")
      assert checked(locked) == []
      assert checked(foreign) == []
    end
  end

  describe "review summaries over items" do
    test "count each waiting item, in row and item order, and link to the table's section",
         %{dossier: dossier} do
      # name reviewed; note 1 waits on two facts, note 2 on two (keyed or
      # not), note 3 on one (locked: it still waits, only not by this person)
      %{summary: summary} = surface(dossier)

      assert summary == %{
               "count" => 5,
               "field" => "facts",
               "href" => "#notes",
               "label" => "Go to the first field to check"
             }
    end

    test "with every item reviewed, the fallback", %{dossier: dossier} do
      for note <- Ash.read!(DossierNote, authorize?: false), note.dossier_id == dossier.id do
        facts = Enum.map(note.facts, &Map.put(&1, :review, @reviewed))
        Ash.update!(note, %{facts: facts}, authorize?: false)
      end

      %{summary: summary} = surface(dossier)
      assert summary["count"] == 0
      assert summary["href"] == "#history"
    end
  end

  describe "compile-time checks" do
    defp compile(name, action, components) do
      capture_io(:stderr, fn ->
        Code.eval_quoted(
          quote do
            defmodule unquote(Module.concat(__MODULE__, name)) do
              @moduledoc false
              use AshA2ui.Standalone

              a2ui do
                for_resource AshA2ui.Test.DossierNote

                context :note do
                  resource AshA2ui.Test.DossierNote
                  picker false
                end

                unquote(components)

                field :facts do
                  pairs true
                  field_action unquote(action)
                end
              end
            end
          end
        )
      end)
    end

    defp table do
      quote do
        component :table, :notes do
          resource AshA2ui.Test.DossierNote
          fields [:title, :facts]
        end
      end
    end

    test "a pairs field's action takes the item" do
      assert compile("NoItem", :update, table()) =~ ~r/declares no :item argument/
      refute compile("WithItem", :check_fact, table()) =~ ~r/field_action/
    end

    test "a pairs field's action is a table's" do
      card =
        quote do
          component :detail, :facts_card do
            context :note
            fields [:facts]
          end
        end

      assert compile("OnACard", :check_fact, card) =~ ~r/drawn in a table's rows/
    end
  end
end
