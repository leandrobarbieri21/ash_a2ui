defmodule AshA2ui.Adoption.PromptScopeTest do
  @moduledoc """
  Per-row prompt option scopes (`prompt_options`): a relationship prompt
  field can offer only the options that apply to the row it is opened on —
  clinic-demo's delegate prompt listed every principal instead of the
  task's candidates. The scope is server-authoritative: the options are
  read, as the actor, through a read action on the relationship's
  destination that receives the row's id; the client never sends a filter,
  and every picked value is re-read through the same scope before the
  write.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper
  import ExUnit.CaptureIO

  alias AshA2ui.ActionHandler

  alias AshA2ui.Test.PromptScope.{
    MixedTasksUI,
    Principal,
    SearchTasksUI,
    Task,
    TasksUI,
    TasksV1UI
  }

  @red %{id: "u-red", team: "red"}

  setup do
    # Private ETS tables: every test process starts with empty ones.
    rhea = Ash.create!(Principal, %{name: "Rhea", team: "red"}, authorize?: false)
    ravi = Ash.create!(Principal, %{name: "Ravi", team: "red"}, authorize?: false)
    rita = Ash.create!(Principal, %{name: "Rita", team: "red"}, authorize?: false)
    bea = Ash.create!(Principal, %{name: "Bea", team: "blue"}, authorize?: false)

    # Bea is a candidate the red actor cannot read: the scope read runs as
    # the actor, so she is never offered.
    intake =
      Ash.create!(
        Task,
        %{title: "Intake", team: "red", candidate_ids: [rhea.id, rita.id, bea.id]},
        authorize?: false
      )

    review =
      Ash.create!(Task, %{title: "Review", team: "red", candidate_ids: [ravi.id]},
        authorize?: false
      )

    hidden =
      Ash.create!(Task, %{title: "Blue task", team: "blue", candidate_ids: [bea.id]},
        authorize?: false
      )

    %{
      rhea: rhea,
      ravi: ravi,
      rita: rita,
      bea: bea,
      intake: intake,
      review: review,
      hidden: hidden
    }
  end

  defp surface(ui, opts \\ []) do
    version = Keyword.get(opts, :version, :v0_9_1)
    messages = AshA2ui.Info.build_surface(ui, actor: @red)

    # The admin catalog's semantic components are outside the basic schema.
    if Keyword.get(opts, :validate?, true),
      do: Enum.each(messages, &assert_valid_server_message(&1, version))

    {components, data} =
      case messages do
        [%{"createSurface" => %{"components" => components, "dataModel" => data}}] ->
          {components, data}

        _v0_9_1 ->
          {Enum.find_value(
             messages,
             &(&1["updateComponents"] && &1["updateComponents"]["components"])
           ),
           Enum.find_value(messages, &(&1["updateDataModel"] && &1["updateDataModel"]["value"]))}
      end

    {Map.new(components, &{&1["id"], &1}), data}
  end

  defp handle(ui, surface_id, name, context, version \\ "v0.9.1") do
    envelope = %{
      "version" => version,
      "action" => %{
        "name" => name,
        "surfaceId" => surface_id,
        "sourceComponentId" => "test",
        "timestamp" => "2026-10-17T00:00:00Z",
        "context" => context
      }
    }

    ActionHandler.handle(ui, envelope, actor: @red)
  end

  defp write_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp labels(options), do: options |> Enum.map(& &1["label"]) |> Enum.sort()

  describe "the emitted prompt" do
    test "a scoped field renders the option list over the prompt's own options, never every option" do
      {by_id, data} = surface(TasksUI)
      base = "row_action_delegate_prompt_select_principal_id"

      # Not a ChoicePicker with every option inlined.
      refute Map.has_key?(by_id, "row_action_delegate_prompt_input_principal_id")
      assert by_id["row_action_delegate_prompt"]["children"] |> Enum.member?(base)

      assert by_id[base]["component"] == "Column"
      assert by_id[base]["children"] == ["#{base}_label", "#{base}_selected", "#{base}_options"]
      assert by_id["#{base}_label"]["text"] == "Principal"

      assert by_id["#{base}_selected"]["text"] == %{
               "path" => "/prompt/select/delegate/principal_id/label"
             }

      assert by_id["#{base}_options"]["children"] == %{
               "componentId" => "#{base}_option_button",
               "path" => "/prompt/options/delegate/principal_id"
             }

      assert by_id["#{base}_option_button"]["action"] == %{
               "event" => %{
                 "name" => "option_select",
                 "context" => %{
                   "field" => "principal_id",
                   "value" => %{"path" => "value"},
                   "prompt" => "delegate",
                   "recordId" => %{"path" => "/prompt/record/delegate"}
                 }
               }
             }

      # No surface-wide option list: the principals reach the client only
      # through a row's prompt.
      refute Map.has_key?(data["options"] || %{}, "principal_id")

      assert data["prompt"] == %{
               "values" => %{"delegate" => %{"principal_id" => ""}},
               "select" => %{"delegate" => %{"principal_id" => %{"search" => "", "label" => ""}}},
               "options" => %{"delegate" => %{"principal_id" => []}},
               "record" => %{"delegate" => ""}
             }
    end

    test "a searchable scoped field's search carries the prompt and its row" do
      {by_id, _data} = surface(SearchTasksUI)
      base = "row_action_delegate_prompt_select_principal_id"

      assert by_id[base]["children"] == [
               "#{base}_label",
               "#{base}_selected",
               "#{base}_controls",
               "#{base}_options"
             ]

      assert by_id["#{base}_search_input"]["value"] == %{
               "path" => "/prompt/select/delegate/principal_id/search"
             }

      assert by_id["#{base}_search_button"]["action"]["event"] == %{
               "name" => "option_search",
               "context" => %{
                 "field" => "principal_id",
                 "search" => %{"path" => "/prompt/select/delegate/principal_id/search"},
                 "prompt" => "delegate",
                 "recordId" => %{"path" => "/prompt/record/delegate"}
               }
             }
    end

    test "an unscoped prompt over the same field keeps every option", %{rhea: rhea} do
      {by_id, data} = surface(MixedTasksUI)

      picker = by_id["row_action_reassign_prompt_input_principal_id"]
      assert picker["component"] == "ChoicePicker"
      assert labels(picker["options"]) == ["Ravi", "Rhea", "Rita"]
      assert Enum.any?(data["options"]["principal_id"], &(&1["value"] == rhea.id))

      assert by_id["row_action_delegate_prompt_select_principal_id_options"]["children"]["path"] ==
               "/prompt/options/delegate/principal_id"
    end

    test "the admin catalog's prompt dialog holds the same option list" do
      Application.put_env(:ash_a2ui, :catalog, :admin_v1)
      on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)

      {by_id, _data} = surface(TasksUI, validate?: false)
      prompt = by_id["row_action_delegate_prompt"]

      assert prompt["children"] |> Enum.member?("row_action_delegate_prompt_select_principal_id")

      assert by_id["row_action_delegate_prompt_select_principal_id_options"]["children"]["path"] ==
               "/prompt/options/delegate/principal_id"
    end

    test "the scoped prompt is valid on the A2UI 1.0 wire", %{intake: intake} do
      {by_id, _data} = surface(TasksV1UI, version: :v1_0)
      assert Map.has_key?(by_id, "row_action_delegate_prompt_select_principal_id_options")

      assert {:ok, messages} =
               handle(
                 TasksV1UI,
                 "scoped_tasks_v1",
                 "prompt",
                 %{"action" => "delegate", "recordId" => intake.id},
                 "v1.0"
               )

      Enum.each(messages, &assert_valid_server_message(&1, :v1_0))

      assert labels(write_at(messages, "/prompt/options/delegate")["principal_id"]) == [
               "Rhea",
               "Rita"
             ]
    end
  end

  describe "opening the prompt" do
    test "writes the row's options, read as the actor", %{intake: intake, review: review} do
      assert {:ok, messages} =
               handle(TasksUI, "scoped_tasks", "prompt", %{
                 "action" => "delegate",
                 "recordId" => intake.id
               })

      Enum.each(messages, &assert_valid_server_message/1)

      assert labels(write_at(messages, "/prompt/options/delegate")["principal_id"]) == [
               "Rhea",
               "Rita"
             ]

      assert write_at(messages, "/prompt/record/delegate") == intake.id

      assert {:ok, messages} =
               handle(TasksUI, "scoped_tasks", "prompt", %{
                 "action" => "delegate",
                 "recordId" => review.id
               })

      assert labels(write_at(messages, "/prompt/options/delegate")["principal_id"]) == ["Ravi"]
      assert write_at(messages, "/prompt/record/delegate") == review.id
    end

    test "the current value is pre-filled, with its label, only when it is in the row's scope",
         %{rhea: rhea, ravi: ravi} do
      for {principal, value, label} <- [{rhea, rhea.id, "Rhea"}, {ravi, "", ""}] do
        task =
          Ash.create!(
            Task,
            %{
              title: "Delegated",
              team: "red",
              candidate_ids: [rhea.id],
              principal_id: principal.id
            },
            authorize?: false
          )

        assert {:ok, messages} =
                 handle(TasksUI, "scoped_tasks", "prompt", %{
                   "action" => "delegate",
                   "recordId" => task.id
                 })

        assert write_at(messages, "/prompt/values/delegate") == %{"principal_id" => value}
        assert write_at(messages, "/prompt/select/delegate")["principal_id"]["label"] == label
      end
    end

    # The displayed selection and the submitted value agree: confirming the
    # pre-filled values as they are never fails as "not one of the
    # available options" on a field that showed no selection.
    test "confirming an out-of-scope current value unchanged is a required-field error",
         %{rhea: rhea, ravi: ravi} do
      task =
        Ash.create!(
          Task,
          %{title: "Delegated", team: "red", candidate_ids: [rhea.id], principal_id: ravi.id},
          authorize?: false
        )

      assert {:ok, messages} =
               handle(TasksUI, "scoped_tasks", "prompt", %{
                 "action" => "delegate",
                 "recordId" => task.id
               })

      values = write_at(messages, "/prompt/values/delegate")

      assert {:error, messages} =
               handle(TasksUI, "scoped_tasks", "invoke", %{
                 "action" => "delegate",
                 "recordId" => task.id,
                 "values" => values
               })

      error = write_at(messages, "/errors/principal_id")
      assert is_binary(error)
      refute error =~ "available options"
    end

    test "a row the actor cannot read has no prompt", %{hidden: hidden} do
      assert {:error, messages} =
               handle(TasksUI, "scoped_tasks", "prompt", %{
                 "action" => "delegate",
                 "recordId" => hidden.id
               })

      refute write_at(messages, "/prompt/options/delegate")
    end
  end

  describe "picking an option" do
    test "option_select takes a candidate of the row", %{intake: intake, rhea: rhea} do
      assert {:ok, messages} =
               handle(TasksUI, "scoped_tasks", "option_select", %{
                 "field" => "principal_id",
                 "value" => rhea.id,
                 "prompt" => "delegate",
                 "recordId" => intake.id
               })

      assert write_at(messages, "/prompt/values/delegate/principal_id") == rhea.id

      assert write_at(messages, "/prompt/select/delegate/principal_id") == %{
               "search" => "",
               "label" => "Rhea"
             }
    end

    test "option_select refuses a principal outside the row's scope",
         %{intake: intake, review: review, ravi: ravi, bea: bea, hidden: hidden} do
      # Readable by the actor, a candidate of another task.
      assert {:error, messages} =
               handle(TasksUI, "scoped_tasks", "option_select", %{
                 "field" => "principal_id",
                 "value" => ravi.id,
                 "prompt" => "delegate",
                 "recordId" => intake.id
               })

      refute write_at(messages, "/prompt/values/delegate/principal_id")

      # A candidate the actor cannot read.
      assert {:error, _messages} =
               handle(TasksUI, "scoped_tasks", "option_select", %{
                 "field" => "principal_id",
                 "value" => bea.id,
                 "prompt" => "delegate",
                 "recordId" => intake.id
               })

      # A row the actor cannot read, and no row at all.
      for record_id <- [hidden.id, nil] do
        assert {:error, _messages} =
                 handle(TasksUI, "scoped_tasks", "option_select", %{
                   "field" => "principal_id",
                   "value" => ravi.id,
                   "prompt" => "delegate",
                   "recordId" => record_id
                 })
      end

      # The scope follows the row it is given.
      assert {:ok, _messages} =
               handle(TasksUI, "scoped_tasks", "option_select", %{
                 "field" => "principal_id",
                 "value" => ravi.id,
                 "prompt" => "delegate",
                 "recordId" => review.id
               })
    end

    test "option_search searches within the row's scope", %{intake: intake} do
      assert {:ok, messages} =
               handle(SearchTasksUI, "scoped_search_tasks", "option_search", %{
                 "field" => "principal_id",
                 "search" => "rh",
                 "prompt" => "delegate",
                 "recordId" => intake.id
               })

      assert labels(write_at(messages, "/prompt/options/delegate/principal_id")) == ["Rhea"]
      refute write_at(messages, "/options/principal_id")

      assert {:ok, messages} =
               handle(SearchTasksUI, "scoped_search_tasks", "option_search", %{
                 "field" => "principal_id",
                 "search" => "r",
                 "prompt" => "delegate",
                 "recordId" => intake.id
               })

      assert labels(write_at(messages, "/prompt/options/delegate/principal_id")) == [
               "Rhea",
               "Rita"
             ]
    end

    test "option_search on a scoped field needs a readable row", %{hidden: hidden} do
      for record_id <- [nil, hidden.id] do
        assert {:error, messages} =
                 handle(SearchTasksUI, "scoped_search_tasks", "option_search", %{
                   "field" => "principal_id",
                   "search" => "",
                   "prompt" => "delegate",
                   "recordId" => record_id
                 })

        refute write_at(messages, "/prompt/options/delegate/principal_id")
      end
    end
  end

  describe "confirming" do
    test "invoke re-reads the picked value through the row's scope",
         %{intake: intake, rhea: rhea, ravi: ravi} do
      assert {:error, messages} =
               handle(TasksUI, "scoped_tasks", "invoke", %{
                 "action" => "delegate",
                 "recordId" => intake.id,
                 "values" => %{"principal_id" => ravi.id}
               })

      assert write_at(messages, "/errors/principal_id") == "is not one of the available options"
      assert Ash.get!(Task, intake.id, actor: @red).principal_id == nil

      assert {:ok, _messages} =
               handle(TasksUI, "scoped_tasks", "invoke", %{
                 "action" => "delegate",
                 "recordId" => intake.id,
                 "values" => %{"principal_id" => rhea.id}
               })

      assert Ash.get!(Task, intake.id, actor: @red).principal_id == rhea.id
    end

    test "a successful invoke resets the prompt's option scope", %{intake: intake, rhea: rhea} do
      assert {:ok, messages} =
               handle(TasksUI, "scoped_tasks", "invoke", %{
                 "action" => "delegate",
                 "recordId" => intake.id,
                 "values" => %{"principal_id" => rhea.id}
               })

      assert write_at(messages, "/prompt/options/delegate") == %{"principal_id" => []}
      assert write_at(messages, "/prompt/record/delegate") == ""
    end
  end

  describe "verification" do
    defp define(body) do
      capture_io(:stderr, fn ->
        Module.create(
          Module.concat(__MODULE__, :"Fixture#{System.unique_integer([:positive])}"),
          body,
          Macro.Env.location(__ENV__)
        )
      end)
    end

    defp scoped_ui(field, options) do
      quote do
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.PromptScope.Task

          component :table do
            fields [:title]
            row_actions [:delegate]
          end

          action :delegate do
            prompt_fields [:principal_id]

            prompt_options unquote(field) do
              read_action unquote(options[:read_action])
              record_argument(unquote(options[:record_argument]))
            end
          end
        end
      end
    end

    test "a valid scope compiles cleanly" do
      result =
        define(
          scoped_ui(:principal_id, read_action: :candidates_for_task, record_argument: :task_id)
        )

      refute result =~ "error"
    end

    test "the field must be one of the action's prompt_fields" do
      result =
        define(scoped_ui(:title, read_action: :candidates_for_task, record_argument: :task_id))

      assert result =~
               ~r/prompt_options :title is not one of the prompt_fields of action :delegate/
    end

    test "the read action must exist on the destination" do
      result = define(scoped_ui(:principal_id, read_action: :ghost, record_argument: :task_id))

      assert result =~
               ~r/read_action :ghost is not a read action of AshA2ui.Test.PromptScope.Principal/
    end

    test "the record argument must be an argument of the read action" do
      result =
        define(
          scoped_ui(:principal_id, read_action: :candidates_for_task, record_argument: :job_id)
        )

      assert result =~
               ~r/record_argument :job_id is not an argument of read action :candidates_for_task/
    end

    test "the read action's other arguments must not be required" do
      result =
        define(
          scoped_ui(:principal_id, read_action: :candidates_in_org, record_argument: :task_id)
        )

      assert result =~
               ~r/read action :candidates_in_org on AshA2ui.Test.PromptScope.Principal has other required arguments \[:org\]/
    end

    test "a required argument with a default is no obstacle" do
      result =
        define(
          scoped_ui(:principal_id, read_action: :candidates_paged, record_argument: :task_id)
        )

      refute result =~ "error"
    end

    test "the field must be a relationship select" do
      result =
        define(
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]

              update :rename do
                accept [:title]
              end
            end

            a2ui do
              component :table do
                fields [:title]
                row_actions [:rename]
              end

              action :rename do
                prompt_fields [:title]

                prompt_options :title do
                  read_action :read
                  record_argument(:id)
                end
              end
            end
          end
        )

      assert result =~ ~r/prompt_options :title is not a relationship prompt field/
    end
  end
end
