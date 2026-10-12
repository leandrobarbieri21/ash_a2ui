defmodule AshA2ui.RelatedTablesTest do
  @moduledoc """
  Related tables: a `:table` component naming its own `resource` reads that
  resource (scoped by a context), with fields, queries, `source` columns and
  links resolved against it — read-only, as the surface's actor.
  """

  # Shared ETS fixtures.
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Links.{Note, Participant, PeopleUI, Person}

  setup do
    for resource <- [Participant, Note, Person] do
      resource |> Ash.read!(authorize?: false) |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    end

    ada = Ash.create!(Person, %{name: "Ada"}, authorize?: false)
    bob = Ash.create!(Person, %{name: "Bob"}, authorize?: false)

    kickoff =
      Ash.create!(Note, %{title: "Kickoff", person_id: ada.id, amount: 3}, authorize?: false)

    review =
      Ash.create!(Note, %{title: "Review", person_id: ada.id, amount: 1}, authorize?: false)

    _bobs = Ash.create!(Note, %{title: "Bob's", person_id: bob.id}, authorize?: false)

    Ash.create!(Participant, %{note_id: kickoff.id, person_id: bob.id}, authorize?: false)
    Ash.create!(Participant, %{note_id: review.id, person_id: ada.id}, authorize?: false)

    %{ada: ada, bob: bob, kickoff: kickoff, review: review}
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp root(messages), do: value_at(messages, "/")

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "people",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  test "related tables resolve against their own resource" do
    view = ResolvedView.resolve(PeopleUI)
    tables = Map.new(view.tables, &{&1.name, &1})

    assert tables[:table].resource == Person
    assert tables[:their_notes].resource == Note
    assert tables[:their_notes].read_action == :read
    assert tables[:participations].resource == Participant

    assert {:note, [:title]} in tables[:participations].loads or
             :note in tables[:participations].loads
  end

  test "unselected, related tables read nothing; selected, they read the person's rows", %{
    ada: ada,
    bob: bob
  } do
    messages = AshA2ui.Info.build_surface(PeopleUI)
    Enum.each(messages, &assert_valid_server_message/1)
    assert root(messages)["records"]["their_notes"] == []

    state = AshA2ui.Info.context_state_for(PeopleUI, %{"person" => ada.id})
    messages = AshA2ui.Info.build_surface(PeopleUI, context_state: state)
    records = root(messages)["records"]

    # query default sort applies, against Note's attributes
    assert Enum.map(records["their_notes"], & &1["title"]) == ["Kickoff", "Review"]
    kickoff = hd(records["their_notes"])
    assert kickoff["status"] == "Open"

    # links on the related table's own relationships
    assert [%{"surface" => "person", "recordId" => bob_id, "label" => "Bob"}] =
             kickoff["_links"]["participant_links"]

    assert bob_id == bob.id

    # a source column + link through the related resource
    assert [participation] = records["participations"]
    assert participation["note_title"] == "Review"
    assert participation["_links"]["note_title"]["surface"] == "note"
  end

  test "context_select refreshes the related tables", %{bob: bob} do
    {:ok, messages} =
      ActionHandler.handle(
        PeopleUI,
        envelope("context_select", %{"context" => "person", "value" => bob.id})
      )

    records = value_at(messages, "/records/their_notes")
    assert Enum.map(records, & &1["title"]) == ["Bob's"]
  end

  test "a related table's query runs against its resource", %{ada: ada} do
    state = AshA2ui.Info.context_state_for(PeopleUI, %{"person" => ada.id})

    {:ok, messages} =
      ActionHandler.handle(
        PeopleUI,
        envelope("query", %{
          "component" => "their_notes",
          "query" => %{"search" => "rev"},
          "contexts" => state
        }),
        []
      )

    records = value_at(messages, "/records/their_notes")
    assert Enum.map(records, & &1["title"]) == ["Review"]
  end
end
