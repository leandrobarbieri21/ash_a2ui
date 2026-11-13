defmodule AshA2ui.Wave4ReferralTest do
  @moduledoc """
  End-to-end tests for the Wave 4 feature set on the `AshA2ui.Test.Referral`
  fixture: relationship-path search, calculation filters, named filter
  presets (+ default preset and the read_action escape hatch), prompt-enabled
  row actions (Modal + `prompt`/`invoke "values"` wire contract), conditional
  row-action visibility (rendering + mandatory handler enforcement), and the
  multi-key calc sort. Every message is validated against the vendored
  A2UI 1.0 schemas.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{Author, Messages, Referral, Surface}

  setup do
    referrer = Ash.create!(Author, %{name: "Rita Referrer", email: "rita@referrals.test"})
    referred = Ash.create!(Author, %{name: "Ned Newcomer", email: "ned@referrals.test"})

    pending =
      Ash.create!(Referral, %{
        code: "PEND-1",
        referrer_id: referrer.id,
        referred_id: referred.id,
        contact_email: "Pending.User@Example.COM"
      })

    approved =
      Referral
      |> Ash.create!(%{code: "APPR-1"})
      |> Ash.update!(%{}, action: :approve)

    declined =
      Referral
      |> Ash.create!(%{code: "DECL-1"})
      |> Ash.update!(%{notes: "no thanks"}, action: :decline)

    deleted =
      Referral
      |> Ash.create!(%{code: "GONE-1"})
      |> Ash.update!(%{}, action: :soft_delete)

    %{
      referrer: referrer,
      referred: referred,
      pending: pending,
      approved: approved,
      declined: declined,
      deleted: deleted
    }
  end

  defp envelope(name, context) do
    Messages.call(name, "referrals", context)
  end

  defp by_path(messages) do
    for %{"updateDataModel" => %{"path" => path, "value" => value}} <- messages,
        into: %{},
        do: {path, value}
  end

  defp handle!(name, context) do
    envelope = envelope(name, context)
    assert_valid_renderer_message(envelope)
    result = ActionHandler.handle(Referral, envelope, actor: nil, authorize?: false)

    {_ok_or_error, messages} = result
    Enum.each(messages, &assert_valid_agent_message/1)
    result
  end

  defp query!(query_state) do
    assert {:ok, messages} = handle!("query", %{"query" => query_state})
    by_path(messages)
  end

  defp codes(rows), do: rows |> Enum.map(& &1["code"]) |> Enum.sort()

  defp components do
    Referral
    |> AshA2ui.Info.build_surface(authorize?: false)
    |> Surface.components_by_id()
  end

  defp initial_data_model do
    [message] = AshA2ui.Info.build_surface(Referral, authorize?: false)
    assert_valid_agent_message(message)
    Surface.data_model(message)
  end

  # --- relationship-path search ----------------------------------------------

  describe "relationship-path search" do
    test "matches through the referrer relationship" do
      values = query!(%{"search" => "rita@referrals"})
      assert codes(values["/records"]) == ["PEND-1"]
    end

    test "matches through the referred relationship" do
      values = query!(%{"search" => "ned newcomer"})
      assert codes(values["/records"]) == ["PEND-1"]
    end

    test "ORs plain attributes with path entries" do
      values = query!(%{"search" => "appr"})
      assert codes(values["/records"]) == ["APPR-1"]
    end
  end

  # --- calculation filters -----------------------------------------------------

  describe "calculation filters" do
    test "equality-filters on an expression calculation" do
      values = query!(%{"filters" => %{"status_label" => "pending!"}})
      assert codes(values["/records"]) == ["PEND-1"]
      assert values["/query"]["filters"]["status_label"] == "pending!"
    end

    test "still rejects non-allowlisted filters" do
      assert {:error, messages} =
               handle!("query", %{"query" => %{"filters" => %{"notes" => "x"}}})

      assert [
               %{
                 "updateDataModel" => %{
                   "path" => "/ui/feedback",
                   "value" => %{"message" => status}
                 }
               },
               _response
             ] = messages

      assert status =~ "not allowlisted"
    end
  end

  # --- named filter presets ----------------------------------------------------

  describe "named filter presets" do
    test "the default preset applies on the initial surface load" do
      value = initial_data_model()

      assert codes(value["records"]) == ["APPR-1", "DECL-1", "PEND-1"]
      assert value["query"]["preset"] == "active"
    end

    test "a keyword-filter preset composes is_nil, equality and membership" do
      assert codes(query!(%{"preset" => "pending"})["/records"]) == ["PEND-1"]
      assert codes(query!(%{"preset" => "closed"})["/records"]) == ["APPR-1", "DECL-1"]
    end

    test "a read_action preset switches the read" do
      values = query!(%{"preset" => "deleted"})
      assert codes(values["/records"]) == ["GONE-1"]
      assert values["/query"]["preset"] == "deleted"
    end

    test "search and filters compose on top of a preset" do
      values = query!(%{"preset" => "closed", "search" => "decl"})
      assert codes(values["/records"]) == ["DECL-1"]
    end

    test "missing and empty preset fall back to the default preset" do
      assert query!(%{})["/query"]["preset"] == "active"
      assert query!(%{"preset" => ""})["/query"]["preset"] == "active"
    end

    test "a one-element list preset is unwrapped (ChoicePickers bind string lists)" do
      # The @a2ui/lit ChoicePicker writes its selection to /query/preset as a
      # list — the browser sends ["pending"], not "pending".
      values = query!(%{"preset" => ["pending"]})
      assert codes(values["/records"]) == ["PEND-1"]
      assert values["/query"]["preset"] == "pending"

      # An empty list (nothing picked) falls back to the default preset.
      assert query!(%{"preset" => []})["/query"]["preset"] == "active"
      assert query!(%{"preset" => [""]})["/query"]["preset"] == "active"
    end

    test "unknown preset names are rejected before Ash is called" do
      assert {:error, messages} =
               handle!("query", %{"query" => %{"preset" => "everything"}})

      assert [
               %{
                 "updateDataModel" => %{
                   "path" => "/ui/feedback",
                   "value" => %{"message" => status}
                 }
               },
               _response
             ] = messages

      assert status =~ ~s(Preset "everything" is not allowlisted)
    end

    test "the preset picker is emitted without an All escape (default_preset set)" do
      picker = components()["query_preset_picker"]

      assert picker["component"] == "ChoicePicker"
      assert picker["value"] == %{"@path" => "/query/preset"}

      assert Enum.map(picker["options"], & &1["value"]) ==
               ["active", "pending", "closed", "deleted"]

      assert "query_preset_picker" in components()["query_controls_body"]["children"]
    end
  end

  # --- wire value encoding ---------------------------------------------------

  describe "CiString wire encoding" do
    # Regression: the query/records refresh path inspect()-ed CiString structs
    # onto the wire (`#Ash.CiString<"...">`), while the initial data model left
    # them raw. Both paths must serialize CiStrings as plain strings.
    test "the initial data model serializes ci_string fields as plain strings" do
      row = Enum.find(initial_data_model()["records"], &(&1["code"] == "PEND-1"))
      assert row["contact_email"] == "Pending.User@Example.COM"
    end

    test "the query records path serializes ci_string fields as plain strings" do
      row = query!(%{})["/records"] |> Enum.find(&(&1["code"] == "PEND-1"))
      assert row["contact_email"] == "Pending.User@Example.COM"
    end
  end

  # --- conditional row-action visibility ----------------------------------------

  describe "visible_when rendering" do
    test "rows carry _actions and per-action _visible slots" do
      rows = initial_data_model()["records"]
      row = Enum.find(rows, &(&1["code"] == "PEND-1"))

      assert row["_actions"] == ["approve", "decline", "soft_delete"]
      assert [%{"id" => id}] = row["_visible_approve"]
      assert id == row["id"]
      assert [%{"id" => _id}] = row["_visible_decline"]

      approved = Enum.find(rows, &(&1["code"] == "APPR-1"))
      assert approved["_actions"] == ["decline", "soft_delete"]
      assert approved["_visible_approve"] == []

      declined = Enum.find(rows, &(&1["code"] == "DECL-1"))
      assert declined["_actions"] == ["soft_delete"]
      assert declined["_visible_decline"] == []
    end

    test "conditional actions render as visibility slots in the row" do
      components = components()

      assert components["record_row"] == %{
               "id" => "record_row",
               "component" => "Card",
               "child" => "record_row_content"
             }

      # No View/Edit controls: the Referral surface declares no :form, so
      # there is no task panel to open.
      assert components["record_row_content"]["children"] == [
               "table_cell_code_row",
               "table_cell_status_row",
               "table_cell_status_label_row",
               "table_cell_contact_email_row",
               "row_action_approve_slot",
               "row_action_decline_slot",
               "row_action_soft_delete_button"
             ]

      assert components["row_action_approve_slot"] == %{
               "id" => "row_action_approve_slot",
               "component" => "List",
               "children" => %{
                 "componentId" => "row_action_approve_button",
                 "path" => "_visible_approve"
               }
             }

      # The decline slot wraps the Modal (prompt-enabled action).
      assert components["row_action_decline_slot"]["children"] == %{
               "componentId" => "row_action_decline_modal",
               "path" => "_visible_decline"
             }
    end
  end

  describe "visible_when enforcement" do
    test "invoking a non-visible action is rejected with an /ui/feedback error", %{
      approved: approved
    } do
      assert {:error, messages} =
               handle!("invoke", %{"action" => "approve", "recordId" => approved.id})

      assert [
               %{
                 "updateDataModel" => %{
                   "path" => "/ui/feedback",
                   "value" => %{"message" => status}
                 }
               },
               _response
             ] = messages

      assert status =~ "Approve is not available for this record"
    end

    test "invoking a visible action succeeds", %{pending: pending} do
      assert {:ok, messages} =
               handle!("invoke", %{"action" => "approve", "recordId" => pending.id})

      values = by_path(messages)
      assert values["/ui/feedback"]["message"] =~ "completed"

      row = Enum.find(values["/records"], &(&1["code"] == "PEND-1"))
      # the refreshed row reads like the initial render's: the enum label
      assert row["status"] == "Approved"
      assert row["_visible_approve"] == []
      assert "approve" not in row["_actions"]
    end

    test "an invoke without recordId on a conditional action is rejected" do
      assert {:error, messages} = handle!("invoke", %{"action" => "approve"})

      assert [
               %{
                 "updateDataModel" => %{
                   "path" => "/ui/feedback",
                   "value" => %{"message" => status}
                 }
               },
               _response
             ] = messages

      assert status =~ "requires a \"recordId\""
    end
  end

  # --- row-action prompts ---------------------------------------------------------

  describe "prompt rendering" do
    test "a prompt action renders a Modal with trigger, inputs and confirm" do
      components = components()

      assert components["row_action_decline_modal"] == %{
               "id" => "row_action_decline_modal",
               "component" => "Modal",
               "trigger" => "row_action_decline_button",
               "content" => "row_action_decline_prompt"
             }

      # The trigger dispatches "prompt" so the server can pre-fill.
      trigger = components["row_action_decline_button"]

      assert Surface.event(trigger) == %{
               "name" => "prompt",
               "sourceComponentId" => "row_action_decline_button",
               "context" => %{
                 "action" => "decline",
                 "recordId" => %{"@path" => "id"},
                 "component" => "table"
               }
             }

      assert components["row_action_decline_prompt"]["children"] == [
               "row_action_decline_prompt_title",
               "row_action_decline_prompt_input_notes",
               "row_action_decline_prompt_error_notes",
               "row_action_decline_confirm_button"
             ]

      assert components["row_action_decline_prompt_title"]["text"] == "### Decline referral"

      input = components["row_action_decline_prompt_input_notes"]
      assert input["component"] == "TextField"
      assert input["value"] == %{"@path" => "/prompt/values/decline/notes"}

      error = components["row_action_decline_prompt_error_notes"]
      assert error["text"] == %{"@path" => "/errors/notes"}

      confirm = components["row_action_decline_confirm_button"]

      assert Surface.event(confirm) == %{
               "name" => "invoke",
               "sourceComponentId" => "row_action_decline_confirm_button",
               "context" => %{
                 "action" => "decline",
                 "recordId" => %{"@path" => "id"},
                 "component" => "table",
                 "values" => %{"@path" => "/prompt/values/decline"},
                 "query" => %{"@path" => "/query"}
               }
             }
    end

    test "the initial data model carries the reserved /prompt state" do
      assert initial_data_model()["prompt"] == %{
               "values" => %{"decline" => %{"notes" => ""}}
             }
    end
  end

  describe "the prompt action" do
    test "pre-fills /prompt/values/<action> and clears /errors", %{declined: declined} do
      # :decline is visible on approved records too; use one with stored notes.
      record = Ash.update!(declined, %{}, action: :approve, authorize?: false)

      assert {:ok, messages} =
               handle!("prompt", %{"action" => "decline", "recordId" => record.id})

      assert by_path(messages) == %{
               "/prompt/values/decline" => %{"notes" => "no thanks"},
               "/errors" => %{}
             }
    end

    test "is rejected for actions without prompt_fields", %{pending: pending} do
      assert {:error, messages} =
               handle!("prompt", %{"action" => "approve", "recordId" => pending.id})

      assert [
               %{
                 "updateDataModel" => %{
                   "path" => "/ui/feedback",
                   "value" => %{"message" => status}
                 }
               },
               _response
             ] = messages

      assert status =~ "does not declare prompt_fields"
    end

    test "enforces visible_when", %{declined: declined} do
      assert {:error, messages} =
               handle!("prompt", %{"action" => "decline", "recordId" => declined.id})

      assert [
               %{
                 "updateDataModel" => %{
                   "path" => "/ui/feedback",
                   "value" => %{"message" => status}
                 }
               },
               _response
             ] = messages

      assert status =~ "Decline is not available for this record"
    end

    test "rejects non-allowlisted actions", %{pending: pending} do
      assert {:error, messages} =
               handle!("prompt", %{"action" => "update", "recordId" => pending.id})

      assert [
               %{
                 "updateDataModel" => %{
                   "path" => "/ui/feedback",
                   "value" => %{"message" => status}
                 }
               },
               _response
             ] = messages

      assert status =~ "not allowed"
    end
  end

  describe "invoke with values" do
    test "casts prompt values against the action's arguments", %{pending: pending} do
      assert {:ok, messages} =
               handle!("invoke", %{
                 "action" => "decline",
                 "recordId" => pending.id,
                 "values" => %{"notes" => "changed our minds"}
               })

      values = by_path(messages)

      record = Ash.get!(Referral, pending.id, authorize?: false)
      assert record.status == :declined
      assert record.notes == "changed our minds"

      # A successful prompt invoke resets the action's prompt state.
      assert values["/prompt/values/decline"] == %{}
    end

    test "maps validation errors to /errors/<field>", %{pending: pending} do
      assert {:error, messages} =
               handle!("invoke", %{
                 "action" => "decline",
                 "recordId" => pending.id,
                 "values" => %{"notes" => nil}
               })

      values = by_path(messages)
      assert values["/errors/notes"] =~ "is required"
      assert values["/ui/feedback"]["message"] =~ "Validation failed"
    end

    test "filters values outside the declared prompt_fields", %{pending: pending} do
      assert {:ok, _messages} =
               handle!("invoke", %{
                 "action" => "decline",
                 "recordId" => pending.id,
                 "values" => %{"notes" => "ok", "code" => "HACKED", "status" => "pending"}
               })

      record = Ash.get!(Referral, pending.id, authorize?: false)
      assert record.code == "PEND-1"
      assert record.status == :declined
    end

    test "ignores values on actions without prompt_fields", %{pending: pending} do
      assert {:ok, _messages} =
               handle!("invoke", %{
                 "action" => "approve",
                 "recordId" => pending.id,
                 "values" => %{"code" => "HACKED"}
               })

      record = Ash.get!(Referral, pending.id, authorize?: false)
      assert record.code == "PEND-1"
      assert record.status == :approved
    end
  end

  # --- multi-key calc sort ------------------------------------------------------

  describe "status-priority ordering" do
    test "the default sort orders by the calc, then the tiebreaker key" do
      Ash.create!(Referral, %{code: "PEND-0"})

      rows = query!(%{})["/records"]

      assert Enum.map(rows, & &1["code"]) == ["PEND-0", "PEND-1", "APPR-1", "DECL-1"]
    end

    test "clients may sort by the calc explicitly" do
      values = query!(%{"sort" => %{"field" => "status_priority", "dir" => "desc"}})

      assert Enum.map(values["/records"], & &1["code"]) == ["DECL-1", "APPR-1", "PEND-1"]
    end
  end
end
