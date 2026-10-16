defmodule AshA2ui.Adoption.PromptWidgetsTest do
  @moduledoc """
  Prompt fields get the widgets form fields get, instead of always a plain
  TextField: a ChoicePicker over a relationship (`belongs_to`) field's
  options, loaded as the actor like a form select's; a ChoicePicker over an
  enumerated argument; the searchable-select composite when the field
  declares `option_search`. Values are still cast and validated
  server-side against the action.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Adoption.{Clerk, Job, JobsUI, SearchJobsUI}

  @red %{id: "u-red", team: "red"}

  setup do
    for resource <- [Job, Clerk] do
      resource |> Ash.read!(actor: @red) |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    end

    rhea = Ash.create!(Clerk, %{name: "Rhea", team: "red"}, authorize?: false)
    ravi = Ash.create!(Clerk, %{name: "Ravi", team: "red"}, authorize?: false)
    bea = Ash.create!(Clerk, %{name: "Bea", team: "blue"}, authorize?: false)

    job =
      Ash.create!(Job, %{title: "Open job", team: "red", clerk_id: rhea.id}, authorize?: false)

    %{rhea: rhea, ravi: ravi, bea: bea, job: job}
  end

  defp surface(ui) do
    messages = AshA2ui.Info.build_surface(ui, actor: @red)
    Enum.each(messages, &assert_valid_server_message/1)
    [_create, components, data] = messages

    {Map.new(components["updateComponents"]["components"], &{&1["id"], &1}),
     data["updateDataModel"]["value"]}
  end

  defp envelope(surface_id, name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => surface_id,
        "sourceComponentId" => "test",
        "timestamp" => "2026-10-16T00:00:00Z",
        "context" => context
      }
    }
  end

  defp write_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  test "a relationship prompt field is a ChoicePicker over the actor's options" do
    {by_id, data} = surface(JobsUI)
    input = by_id["row_action_assign_prompt_input_clerk_id"]

    assert input["component"] == "ChoicePicker"
    assert input["variant"] == "mutuallyExclusive"
    assert input["value"] == %{"path" => "/prompt/values/assign/clerk_id"}
    assert input["label"] == "Clerk id"
    assert input["options"] |> Enum.map(& &1["label"]) |> Enum.sort() == ["Ravi", "Rhea"]
    assert data["options"]["clerk_id"] == input["options"]
  end

  test "an enumerated argument prompt field is a ChoicePicker over its values" do
    {by_id, _data} = surface(JobsUI)
    input = by_id["row_action_reprioritize_prompt_input_priority"]

    assert input["component"] == "ChoicePicker"
    assert input["value"] == %{"path" => "/prompt/values/reprioritize/priority"}

    assert input["options"] == [
             %{"label" => "Low", "value" => "low"},
             %{"label" => "Normal", "value" => "normal"},
             %{"label" => "High", "value" => "high"}
           ]
  end

  test "a string argument stays a TextField" do
    {by_id, _data} = surface(JobsUI)
    assert by_id["row_action_annotate_prompt_input_note"]["component"] == "TextField"
  end

  test "picked values are cast and validated server-side", %{job: job, ravi: ravi} do
    # A single-select ChoicePicker binds a list.
    assert {:ok, _messages} =
             ActionHandler.handle(
               JobsUI,
               envelope("adoption_jobs", "invoke", %{
                 "action" => "reprioritize",
                 "recordId" => job.id,
                 "values" => %{"priority" => ["high"]}
               }),
               actor: @red
             )

    assert Ash.get!(Job, job.id, actor: @red).priority == :high

    assert {:error, messages} =
             ActionHandler.handle(
               JobsUI,
               envelope("adoption_jobs", "invoke", %{
                 "action" => "reprioritize",
                 "recordId" => job.id,
                 "values" => %{"priority" => ["urgent"]}
               }),
               actor: @red
             )

    assert is_binary(write_at(messages, "/errors/priority"))

    assert {:ok, _messages} =
             ActionHandler.handle(
               JobsUI,
               envelope("adoption_jobs", "invoke", %{
                 "action" => "assign",
                 "recordId" => job.id,
                 "values" => %{"clerk_id" => [ravi.id]}
               }),
               actor: @red
             )

    assert Ash.get!(Job, job.id, actor: @red).clerk_id == ravi.id
  end

  describe "a searchable relationship prompt field" do
    test "renders the searchable-select composite over prompt state" do
      {by_id, data} = surface(SearchJobsUI)
      base = "row_action_assign_prompt_select_clerk_id"

      assert by_id["row_action_assign_prompt"]["children"] == [
               "row_action_assign_prompt_title",
               base,
               "row_action_assign_prompt_error_clerk_id",
               "row_action_assign_confirm_button"
             ]

      assert by_id[base]["component"] == "Column"

      assert by_id["#{base}_selected"]["text"] == %{
               "path" => "/prompt/select/assign/clerk_id/label"
             }

      assert by_id["#{base}_search_button"]["action"]["event"] == %{
               "name" => "option_search",
               "context" => %{
                 "field" => "clerk_id",
                 "search" => %{"path" => "/prompt/select/assign/clerk_id/search"}
               }
             }

      assert by_id["#{base}_option_button"]["action"]["event"]["context"] == %{
               "field" => "clerk_id",
               "value" => %{"path" => "value"},
               "prompt" => "assign"
             }

      assert data["prompt"] == %{
               "values" => %{"assign" => %{"clerk_id" => ""}},
               "select" => %{"assign" => %{"clerk_id" => %{"search" => "", "label" => ""}}}
             }
    end

    test "search and select write the prompt's value, as the actor", %{
      job: job,
      ravi: ravi,
      bea: bea
    } do
      assert {:ok, messages} =
               ActionHandler.handle(
                 SearchJobsUI,
                 envelope("adoption_search_jobs", "option_search", %{
                   "field" => "clerk_id",
                   "search" => "ra"
                 }),
                 actor: @red
               )

      assert Enum.map(write_at(messages, "/options/clerk_id"), & &1["label"]) == ["Ravi"]

      assert {:ok, messages} =
               ActionHandler.handle(
                 SearchJobsUI,
                 envelope("adoption_search_jobs", "option_select", %{
                   "field" => "clerk_id",
                   "value" => ravi.id,
                   "prompt" => "assign"
                 }),
                 actor: @red
               )

      assert write_at(messages, "/prompt/values/assign/clerk_id") == ravi.id

      assert write_at(messages, "/prompt/select/assign/clerk_id") == %{
               "search" => "",
               "label" => "Ravi"
             }

      refute write_at(messages, "/form/clerk_id")

      # Another team's clerk is not the actor's to pick.
      assert {:error, _messages} =
               ActionHandler.handle(
                 SearchJobsUI,
                 envelope("adoption_search_jobs", "option_select", %{
                   "field" => "clerk_id",
                   "value" => bea.id,
                   "prompt" => "assign"
                 }),
                 actor: @red
               )

      # The prompt pre-fill shows the current value's label.
      assert {:ok, messages} =
               ActionHandler.handle(
                 SearchJobsUI,
                 envelope("adoption_search_jobs", "prompt", %{
                   "action" => "assign",
                   "recordId" => job.id
                 }),
                 actor: @red
               )

      assert write_at(messages, "/prompt/select/assign") == %{
               "clerk_id" => %{"search" => "", "label" => "Rhea"}
             }
    end
  end
end
