defmodule AshA2ui.Wave5ActionHandlerTest do
  @moduledoc """
  ActionHandler tests for Wave 5: the `option_search` / `option_select` /
  `nested_add` / `nested_remove` client actions, nested-value preparation on
  `submit_form`, nested validation-error paths + in-row mirrors, and the
  `start_edit` population of nested rows and select labels, and success
  resets. Every emitted message is validated
  against the vendored v0.9.1 JSON Schemas.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{Author, Tag, Ticket, TicketNote, TicketSearchUI}

  setup do
    on_exit(fn ->
      for resource <- [Ticket, TicketNote, Tag, Author] do
        Ets.stop(resource)
      end
    end)

    :ok
  end

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{"name" => name, "surfaceId" => "tickets", "context" => context}
    }
  end

  defp assert_all_valid(messages), do: Enum.each(messages, &assert_valid_server_message/1)

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> {:ok, value}
      _other -> nil
    end)
    |> case do
      {:ok, value} -> value
      nil -> flunk("no updateDataModel for #{path} in #{inspect(messages, pretty: true)}")
    end
  end

  defp create_tag(name), do: Ash.create!(Tag, %{name: name}, authorize?: false)

  defp create_author(name, email),
    do: Ash.create!(Author, %{name: name, email: email}, authorize?: false)

  describe "option_search" do
    test "returns the filtered option page at /options/<field>" do
      create_author("Ada Lovelace", "ada@example.com")
      create_author("Alan Turing", "alan@example.com")
      create_author("Grace Hopper", "grace@example.com")

      assert {:ok, messages} =
               ActionHandler.handle(
                 TicketSearchUI,
                 envelope("option_search", %{"field" => "author_id", "search" => "ada"})
               )

      assert_all_valid(messages)
      assert [%{"label" => "Ada Lovelace"}] = value_at(messages, "/options/author_id")
    end

    test "matches any declared option_search field" do
      create_author("Ada", "countess@analytical.engine")

      assert {:ok, messages} =
               ActionHandler.handle(
                 TicketSearchUI,
                 envelope("option_search", %{"field" => "author_id", "search" => "analytical"})
               )

      assert [%{"label" => "Ada"}] = value_at(messages, "/options/author_id")
    end

    test "an empty search returns the default first page" do
      create_author("Zoe", nil)
      create_author("Ada", nil)

      assert {:ok, messages} =
               ActionHandler.handle(
                 TicketSearchUI,
                 envelope("option_search", %{"field" => "author_id", "search" => ""})
               )

      assert [%{"label" => "Ada"}, %{"label" => "Zoe"}] =
               value_at(messages, "/options/author_id")
    end

    test "searches pick_existing nested-form options by argument name" do
      create_tag("urgent")
      create_tag("billing")

      assert {:ok, messages} =
               ActionHandler.handle(
                 TicketSearchUI,
                 envelope("option_search", %{"field" => "tags", "search" => "urg"})
               )

      assert [%{"label" => "urgent"}] = value_at(messages, "/options/tags")
    end

    test "rejects fields without option_search" do
      # The on-resource Ticket surface declares no option_search anywhere.
      assert {:error, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("option_search", %{"field" => "author_id", "search" => "x"})
               )

      assert_all_valid(messages)
      assert value_at(messages, "/ui/feedback")["message"] =~ "not a searchable select"
    end

    test "rejects unknown fields and malformed contexts" do
      assert {:error, messages} =
               ActionHandler.handle(
                 TicketSearchUI,
                 envelope("option_search", %{"field" => "nope", "search" => "x"})
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ "not a searchable select"

      assert {:error, messages} =
               ActionHandler.handle(TicketSearchUI, envelope("option_search", %{}))

      assert value_at(messages, "/ui/feedback")["message"] =~ ~s(missing "field")

      assert {:error, messages} =
               ActionHandler.handle(
                 TicketSearchUI,
                 envelope("option_search", %{"field" => "author_id", "search" => 5})
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ ~s("search" must be a string)
    end
  end

  describe "option_select" do
    test "writes the picked value to /form and the resolved label to /select" do
      author = create_author("Ada", "ada@example.com")

      assert {:ok, messages} =
               ActionHandler.handle(
                 TicketSearchUI,
                 envelope("option_select", %{"field" => "author_id", "value" => author.id})
               )

      assert_all_valid(messages)
      assert value_at(messages, "/form/author_id") == author.id

      assert value_at(messages, "/select/author_id") ==
               %{"search" => "", "label" => "Ada"}
    end

    test "unwraps one-element list values" do
      author = create_author("Ada", nil)

      assert {:ok, messages} =
               ActionHandler.handle(
                 TicketSearchUI,
                 envelope("option_select", %{"field" => "author_id", "value" => [author.id]})
               )

      assert value_at(messages, "/form/author_id") == author.id
    end

    test "rejects unknown option values" do
      assert {:error, messages} =
               ActionHandler.handle(
                 TicketSearchUI,
                 envelope("option_select", %{
                   "field" => "author_id",
                   "value" => Ash.UUID.generate()
                 })
               )

      assert_all_valid(messages)
      assert value_at(messages, "/ui/feedback")["message"] =~ "was not found"
    end

    test "rejects non-searchable selects" do
      author = create_author("Ada", nil)

      assert {:error, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("option_select", %{"field" => "author_id", "value" => author.id})
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ "not a searchable select"
    end
  end

  describe "nested_add / nested_remove" do
    test "create_inline appends a blank row with a server-generated _row" do
      existing = %{"_row" => "r1", "body" => "hello", "rating" => 3}

      assert {:ok, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("nested_add", %{"argument" => "notes", "rows" => [existing]})
               )

      assert_all_valid(messages)
      assert [^existing, blank] = value_at(messages, "/form/notes")
      assert %{"body" => "", "rating" => ""} = blank
      assert is_binary(blank["_row"]) and blank["_row"] != ""
    end

    test "pick_existing appends a validated %{_row, id, label} row and dedupes" do
      tag = create_tag("urgent")

      assert {:ok, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("nested_add", %{"argument" => "tags", "rows" => [], "value" => tag.id})
               )

      assert [row] = value_at(messages, "/form/tags")
      assert row == %{"_row" => tag.id, "id" => tag.id, "label" => "urgent"}

      # picked values may arrive as one-element lists (ChoicePicker binding);
      # an already-added id is a no-op.
      assert {:ok, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("nested_add", %{
                   "argument" => "tags",
                   "rows" => [row],
                   "value" => [tag.id]
                 })
               )

      assert [^row] = value_at(messages, "/form/tags")
    end

    test "pick_existing rejects unknown values" do
      assert {:error, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("nested_add", %{
                   "argument" => "tags",
                   "rows" => [],
                   "value" => Ash.UUID.generate()
                 })
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ "was not found"
    end

    test "nested_remove drops the identified row" do
      rows = [
        %{"_row" => "a", "body" => "one"},
        %{"_row" => "b", "body" => "two"}
      ]

      assert {:ok, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("nested_remove", %{"argument" => "notes", "rows" => rows, "row" => "a"})
               )

      assert_all_valid(messages)
      assert [%{"_row" => "b"}] = value_at(messages, "/form/notes")
    end

    test "rejects unknown arguments and malformed contexts" do
      assert {:error, messages} =
               ActionHandler.handle(Ticket, envelope("nested_add", %{"argument" => "nope"}))

      assert value_at(messages, "/ui/feedback")["message"] =~ "not a nested form"

      assert {:error, messages} = ActionHandler.handle(Ticket, envelope("nested_add", %{}))
      assert value_at(messages, "/ui/feedback")["message"] =~ ~s(missing "argument")

      assert {:error, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("nested_remove", %{"argument" => "notes", "rows" => []})
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ ~s(missing "row")

      assert {:error, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("nested_add", %{"argument" => "tags", "rows" => []})
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ ~s(missing "value")
    end
  end

  describe "submit_form with nested forms" do
    test "create casts create_inline rows (underscore keys stripped) and pick rows (ids)" do
      tag = create_tag("urgent")

      assert {:ok, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("submit_form", %{
                   "values" => %{
                     "subject" => "Printer on fire",
                     "notes" => [%{"_row" => "tmp", "body" => "extinguish", "rating" => 2}],
                     "tags" => [%{"_row" => tag.id, "id" => tag.id, "label" => "urgent"}]
                   }
                 })
               )

      assert_all_valid(messages)

      [ticket] =
        Ash.read!(Ticket, authorize?: false, load: [:notes, :tags])

      assert ticket.subject == "Printer on fire"
      assert [%{body: "extinguish", rating: 2}] = ticket.notes
      assert [%{name: "urgent"}] = ticket.tags

      # success resets /form to the stable nested shape and /select state
      assert value_at(messages, "/form") == %{"notes" => [], "tags" => []}
      assert value_at(messages, "/select") == %{"tags" => %{"search" => "", "picked" => []}}
    end

    test "update through direct_control updates kept rows and destroys omitted ones" do
      ticket =
        Ticket
        |> Ash.Changeset.for_create(
          :create,
          %{
            subject: "s",
            notes: [%{body: "keep", rating: 1}, %{body: "drop", rating: 2}]
          },
          authorize?: false
        )
        |> Ash.create!()

      [keep, drop] =
        TicketNote |> Ash.read!(authorize?: false) |> Enum.sort_by(& &1.body)

      assert {:ok, _messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("submit_form", %{
                   "recordId" => ticket.id,
                   "values" => %{
                     "subject" => "s2",
                     "notes" => [
                       %{"_row" => keep.id, "id" => keep.id, "body" => "kept!", "rating" => 5}
                     ]
                   }
                 })
               )

      notes = Ash.read!(TicketNote, authorize?: false)
      assert [%{body: "kept!", rating: 5}] = notes
      refute Enum.any?(notes, &(&1.id == drop.id))
    end

    test "unrelating a pick_existing row clears the tag's ticket_id" do
      tag = create_tag("urgent")

      ticket =
        Ticket
        |> Ash.Changeset.for_create(:create, %{subject: "s", tags: [tag.id]}, authorize?: false)
        |> Ash.create!()

      assert {:ok, _messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("submit_form", %{
                   "recordId" => ticket.id,
                   "values" => %{"subject" => "s", "tags" => []}
                 })
               )

      assert Ash.get!(Tag, tag.id, authorize?: false).ticket_id == nil
    end

    test "nested validation errors map to /errors/<argument>/<index>/<field> plus row mirrors" do
      rows = [
        %{"_row" => "a", "body" => "fine", "rating" => 1},
        %{"_row" => "b", "body" => "", "rating" => 2}
      ]

      assert {:error, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("submit_form", %{
                   "values" => %{"subject" => "s", "notes" => rows}
                 })
               )

      assert_all_valid(messages)
      assert value_at(messages, "/errors/notes/1/body") =~ "required"

      mirrored = value_at(messages, "/form/notes")
      assert [%{"_row" => "a"}, %{"_row" => "b", "_error_body" => error} | _] = mirrored
      assert error =~ "required"
      refute Map.has_key?(hd(mirrored), "_error_body")
    end

    test "top-level validation errors keep the frozen /errors/<field> shape" do
      assert {:error, messages} =
               ActionHandler.handle(
                 Ticket,
                 envelope("submit_form", %{"values" => %{"subject" => ""}})
               )

      assert value_at(messages, "/errors/subject") =~ "required"
    end
  end

  describe "start_edit with nested forms and searchable selects" do
    test "populates nested rows and searchable-select labels" do
      author = create_author("Ada", nil)
      tag = create_tag("urgent")

      ticket =
        Ticket
        |> Ash.Changeset.for_create(
          :create,
          %{
            subject: "s",
            author_id: author.id,
            notes: [%{body: "note", rating: 4}],
            tags: [tag.id]
          },
          authorize?: false
        )
        |> Ash.create!()

      note = TicketNote |> Ash.read!(authorize?: false) |> hd()

      assert {:ok, messages} =
               ActionHandler.handle(
                 TicketSearchUI,
                 envelope("start_edit", %{"recordId" => ticket.id})
               )

      assert_all_valid(messages)
      form = value_at(messages, "/form")
      assert form["subject"] == "s"
      assert form["author_id"] == author.id

      # TicketSearchUI declares only the :tags nested form
      assert form["tags"] == [%{"_row" => tag.id, "id" => tag.id, "label" => "urgent"}]

      assert value_at(messages, "/select") == %{
               "author_id" => %{"search" => "", "label" => "Ada"},
               "tags" => %{"search" => "", "picked" => []}
             }

      # the on-resource surface loads the create_inline rows
      assert {:ok, messages} =
               ActionHandler.handle(Ticket, envelope("start_edit", %{"recordId" => ticket.id}))

      form = value_at(messages, "/form")

      assert form["notes"] == [
               %{"_row" => note.id, "id" => note.id, "body" => "note", "rating" => 4}
             ]
    end
  end
end
