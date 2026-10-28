defmodule AshA2ui.DynamicRelatedLinksTest do
  @moduledoc """
  The dynamic spec's vocabulary for related tables (`resource` on a table)
  and reference links (`link` / `links` / `link_label`), next to the
  contexts it already carried: declared master/detail surfaces import to a
  spec that resolves, serializes and promotes back to a surface rendering
  exactly like the declared one — every resource through the allowlist,
  surface keys kept as strings.
  """

  # Shared ETS link fixtures.
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Error
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.Links.{Note, NotesUI, Participant, PeopleTaskUI, PeopleUI, Person}

  @allowlist Dynamic.allowlist([Person, Note, Participant])

  setup do
    for resource <- [Participant, Note, Person] do
      resource |> Ash.read!(authorize?: false) |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    end

    ada = Ash.create!(Person, %{name: "Ada"}, authorize?: false)
    bob = Ash.create!(Person, %{name: "Bob"}, authorize?: false)

    kickoff =
      Ash.create!(Note, %{title: "Kickoff", person_id: ada.id, subject_id: bob.id, amount: 3},
        authorize?: false
      )

    Ash.create!(Note, %{title: "Review", person_id: ada.id, status: :closed}, authorize?: false)
    Ash.create!(Participant, %{note_id: kickoff.id, person_id: bob.id}, authorize?: false)
    Ash.create!(Participant, %{note_id: kickoff.id, person_id: ada.id}, authorize?: false)

    %{ada: ada, bob: bob, kickoff: kickoff}
  end

  defp import!(module) do
    {:ok, spec, rejections} = Importer.import(module)
    # surface_id is resolve/deploy metadata — the only honest rejection
    assert Enum.map(rejections, & &1.feature) == ["surface_id"]
    spec
  end

  defp resolve!(spec, surface_id) do
    case Dynamic.resolve(spec, allowlist: @allowlist, surface_id: surface_id) do
      {:ok, surface} -> surface
      {:error, errors} -> flunk(Enum.join(Error.messages(errors), "\n"))
    end
  end

  defp envelope(surface_id, name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => surface_id,
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  describe "import → resolve renders like the declared surface" do
    test "contexts + related tables + a link column (PeopleUI)", %{ada: ada} do
      spec = import!(PeopleUI)

      tables = Map.new(spec["components"], &{&1["name"], &1})
      refute Map.has_key?(tables["table"], "resource")
      assert tables["table"]["select_context"] == "person"
      assert tables["their_notes"]["resource"] == "Note"
      assert tables["their_notes"]["context_filter"] == %{"person_id" => "person"}
      assert tables["their_notes"]["require_context"] == ["person"]
      assert tables["participations"]["resource"] == "Participant"
      assert [%{"name" => "person", "resource" => "Person"}] = spec["contexts"]

      fields = Map.new(spec["fields"], &{&1["name"], &1})
      assert fields["participant_links"]["links"] == "participants"
      assert fields["note_title"]["link"] == "note"

      surface = resolve!(spec, "people")

      for state <- [%{}, AshA2ui.Info.context_state_for(PeopleUI, %{"person" => ada.id})] do
        dynamic = Dynamic.build_surface(surface, context_state: state)
        Enum.each(dynamic, &assert_valid_server_message/1)
        assert dynamic == AshA2ui.Info.build_surface(PeopleUI, context_state: state)
      end

      # and the actions behave the same: a row select refreshes the related
      # tables with identical rows
      select = envelope("people", "context_select", %{"context" => "person", "value" => ada.id})
      assert Dynamic.handle_action(surface, select) == ActionHandler.handle(PeopleUI, select)
    end

    test "a master/detail task surface (PeopleTaskUI)" do
      surface = PeopleTaskUI |> import!() |> resolve!("people_tasks")
      assert Dynamic.build_surface(surface) == AshA2ui.Info.build_surface(PeopleTaskUI)
    end

    test "every link form and badge tones (NotesUI)", %{ada: ada, kickoff: kickoff} do
      spec = import!(NotesUI)
      fields = Map.new(spec["fields"], &{&1["name"], &1})

      assert fields["person_name"]["link"] == "person"
      assert fields["person_id"]["link"] == "person"
      assert fields["subject_id"]["link"] == %{"surface" => "person", "path" => ["subject_id"]}
      assert fields["participant_links"]["links"] == "participants"

      [table | _rest] = spec["components"]
      assert table["row_layout"]["badge_tones"] == %{"closed" => "neutral", "open" => "success"}

      surface = resolve!(spec, "notes")

      state = AshA2ui.Info.context_state_for(NotesUI, %{"person" => ada.id, "note" => kickoff.id})

      for opts <- [[], [context_state: state], [spec_version: "1.0"]] do
        assert Dynamic.build_surface(surface, opts) == AshA2ui.Info.build_surface(NotesUI, opts)
      end

      # the imported link fields validate open_surface exactly as declared
      open = envelope("notes", "open_surface", %{"field" => "subject_id", "surface" => "person"})
      assert {:ok, []} = Dynamic.handle_action(surface, open)
    end
  end

  describe "the stored-spec lifecycle carries the new vocabulary" do
    test "serialize → deserialize resolves to the same surface", %{ada: ada} do
      spec = import!(PeopleUI)
      serialized = Dynamic.serialize(spec)

      assert {:ok, surface} =
               Dynamic.deserialize(serialized, allowlist: @allowlist, surface_id: "people")

      state = AshA2ui.Info.context_state_for(PeopleUI, %{"person" => ada.id})

      assert Dynamic.build_surface(surface, context_state: state) ==
               AshA2ui.Info.build_surface(PeopleUI, context_state: state)
    end

    test "promotion emits resource modules and link literals that compile back", %{ada: ada} do
      {:ok, source} =
        Dynamic.to_dsl_source(import!(PeopleUI),
          module: AshA2ui.Promoted.PeopleUI,
          allowlist: @allowlist,
          surface_id: "people"
        )

      assert source =~ "resource AshA2ui.Test.Links.Note"
      assert source =~ "resource AshA2ui.Test.Links.Participant"
      assert source =~ "link :note"
      assert source =~ "links :participants"

      [{people, _binary} | _rest] = Code.compile_string(source)
      state = AshA2ui.Info.context_state_for(PeopleUI, %{"person" => ada.id})

      assert AshA2ui.Info.build_surface(people, context_state: state) ==
               AshA2ui.Info.build_surface(PeopleUI, context_state: state)

      {:ok, source} =
        Dynamic.to_dsl_source(import!(NotesUI),
          module: AshA2ui.Promoted.NotesUI,
          allowlist: @allowlist,
          surface_id: "notes"
        )

      assert source =~ ~s(link {"person", [:subject_id]})
      assert source =~ "badge_tones closed: :neutral, open: :success"

      [{notes, _binary} | _rest] = Code.compile_string(source)
      assert AshA2ui.Info.build_surface(notes) == AshA2ui.Info.build_surface(NotesUI)
    end

    test "the diff names a related table's resource change" do
      old = import!(PeopleUI)

      new =
        update_in(old["components"], fn components ->
          Enum.map(components, fn
            %{"name" => "participations"} = table -> Map.put(table, "resource", "Note")
            other -> other
          end)
        end)

      assert Enum.any?(
               Dynamic.Diff.summary(Dynamic.diff(old, new)),
               &(&1 =~ "participations" and &1 =~ "resource")
             )
    end
  end

  describe "validation" do
    defp spec_with(table_overrides, fields \\ []) do
      %{
        "resource" => "Person",
        "contexts" => [%{"name" => "person", "resource" => "Person", "picker" => false}],
        "components" => [
          %{"kind" => "table", "fields" => ["name"], "select_context" => "person"},
          Map.merge(
            %{
              "kind" => "table",
              "name" => "their_notes",
              "resource" => "Note",
              "fields" => ["title"],
              "context_filter" => %{"person_id" => "person"},
              "require_context" => ["person"]
            },
            table_overrides
          )
        ],
        "fields" => fields
      }
    end

    defp errors(spec, allowlist \\ @allowlist) do
      {:error, errors} = Dynamic.resolve(spec, allowlist: allowlist)
      Enum.map(errors, &{&1.path, &1.message})
    end

    test "a hand-written related table resolves" do
      assert {:ok, _surface} = Dynamic.resolve(spec_with(%{}), allowlist: @allowlist)
    end

    test "the agent-composed-surfaces topic's master/detail spec resolves", %{ada: ada} do
      spec = %{
        "resource" => "Person",
        "contexts" => [%{"name" => "person", "resource" => "Person", "picker" => false}],
        "components" => [
          %{"kind" => "table", "fields" => ["name"], "select_context" => "person"},
          %{
            "kind" => "table",
            "name" => "their_notes",
            "resource" => "Note",
            "fields" => ["title", "status", "subject_id"],
            "context_filter" => %{"person_id" => "person"},
            "require_context" => ["person"]
          }
        ],
        "fields" => [
          %{
            "name" => "subject_id",
            "label" => "Subject",
            "link" => %{"surface" => "person", "path" => ["subject_id"]}
          }
        ]
      }

      assert {:ok, surface} = Dynamic.resolve(spec, allowlist: @allowlist)
      state = AshA2ui.Info.context_state_for(surface.dsl_state, %{"person" => ada.id})
      messages = Dynamic.build_surface(surface, context_state: state)
      Enum.each(messages, &assert_valid_server_message/1)

      %{"updateDataModel" => %{"value" => %{"records" => records}}} = List.last(messages)
      kickoff = Enum.find(records["their_notes"], &(&1["title"] == "Kickoff"))
      assert length(records["their_notes"]) == 2
      assert kickoff["_links"]["subject_id"]["surface"] == "person"
    end

    test "a related table's resource must be allowlisted" do
      allowlist = Dynamic.allowlist([Person])

      assert [{"components[1].resource", message}] = errors(spec_with(%{}), allowlist)
      assert message =~ ~s(resource "Note" is not available)
      assert message =~ "use one of: Person"

      assert [{"components[1].resource", message}] = errors(spec_with(%{"resource" => 7}))
      assert message =~ "allowlisted resource"
    end

    test "the related-table rules are the compile-time verifiers'" do
      # fields resolve against the related resource …
      assert [{_path, message}] = errors(spec_with(%{"fields" => ["name"]}))
      assert message =~ "unknown field :name"

      # … and related tables stay read-only
      assert Enum.any?(
               errors(spec_with(%{"row_actions" => ["destroy"]})),
               fn {_path, message} -> message =~ "row_actions" end
             )
    end

    test "malformed links are rejected with the accepted shapes" do
      for link <- [
            7,
            %{"surface" => "person"},
            %{"surface" => "person", "path" => []},
            %{"surface" => "", "path" => ["subject_id"]},
            %{"surface" => "person", "path" => ["subject_id"], "extra" => true},
            "not a name"
          ] do
        spec = spec_with(%{}, [%{"name" => "title", "link" => link}])
        assert [{"fields[0].link", message} | _] = errors(spec)
        assert is_binary(message)
      end
    end

    test "badge tones come from the fixed vocabulary" do
      layout = %{"title" => "title", "badge" => "status", "badge_tones" => %{"open" => "loud"}}
      spec = spec_with(%{"fields" => ["title", "status"], "row_layout" => layout})

      assert [{"components[1].row_layout.badge_tones", message}] = errors(spec)

      assert message =~
               "use one of: accent, danger, gray, info, neutral, pending, success, warning"
    end

    test "a link's surface key stays a string — no atom is created from it" do
      key = "never_an_atom_#{System.unique_integer([:positive])}"

      spec =
        spec_with(%{"fields" => ["title", "subject_id"]}, [
          %{"name" => "subject_id", "link" => %{"surface" => key, "path" => ["subject_id"]}}
        ])

      assert {:ok, surface} = Dynamic.resolve(spec, allowlist: @allowlist)
      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end

      field = AshA2ui.ResolvedView.resolve(surface.dsl_state).fields[:subject_id]
      assert field.link == {key, [:subject_id]}
    end

    test "the spec schema offers the vocabulary to an LLM" do
      schema = Dynamic.spec_schema(@allowlist)
      component = schema["properties"]["components"]["items"]["properties"]
      field = schema["properties"]["fields"]["items"]["properties"]

      assert component["resource"]["enum"] == ["Note", "Participant", "Person"]
      assert Map.has_key?(component["row_layout"]["properties"], "badge_tones")
      assert %{"anyOf" => [_name, %{"required" => ["surface", "path"]}]} = field["link"]
      assert Map.has_key?(field, "links")
      assert Map.has_key?(field, "link_label")
    end
  end
end
