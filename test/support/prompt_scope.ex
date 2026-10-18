# Fixtures for per-row prompt option scopes (`prompt_options`): a task's
# delegate prompt offers only that task's candidates (clinic-demo's
# delegate principal picker listed every principal).

defmodule AshA2ui.Test.PromptScope.Domain do
  @moduledoc "Domain for the per-row prompt option scope fixtures."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.PromptScope.Principal
    resource AshA2ui.Test.PromptScope.Task
  end
end

defmodule AshA2ui.Test.PromptScope.CandidatesForTask do
  @moduledoc """
  The scope read's preparation: the principals listed as candidates on the
  task named by the `task_id` argument, the task read as the query's actor
  (a task the actor cannot read has no candidates).
  """

  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(query, _opts, context) do
    task_id = Ash.Query.get_argument(query, :task_id)

    case Ash.get(AshA2ui.Test.PromptScope.Task, task_id,
           actor: context.actor,
           tenant: context.tenant,
           error?: false
         ) do
      {:ok, %{candidate_ids: [_ | _] = ids}} -> Ash.Query.filter(query, id in ^ids)
      _no_task_or_no_candidates -> Ash.Query.filter(query, false)
    end
  end
end

defmodule AshA2ui.Test.PromptScope.Principal do
  @moduledoc """
  A relationship destination: actor-scoped reads, plus the per-task scope
  read `:candidates_for_task`.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.PromptScope.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :team, :string, public?: true, allow_nil?: false
    attribute :org, :string, public?: true, default: "acme"
  end

  preparations do
    prepare AshA2ui.Test.Adoption.ActorScope
  end

  actions do
    defaults [:read, :destroy, create: :*]

    read :candidates_for_task do
      argument :task_id, :uuid, allow_nil?: false
      prepare AshA2ui.Test.PromptScope.CandidatesForTask
    end

    # Verification fixtures: a second required argument the scope read
    # cannot fill, and one with a default it need not.
    read :candidates_in_org do
      argument :task_id, :uuid, allow_nil?: false
      argument :org, :string, allow_nil?: false
      prepare AshA2ui.Test.PromptScope.CandidatesForTask
    end

    read :candidates_paged do
      argument :task_id, :uuid, allow_nil?: false
      argument :page_size, :integer, allow_nil?: false, default: 25
      prepare AshA2ui.Test.PromptScope.CandidatesForTask
    end
  end
end

defmodule AshA2ui.Test.PromptScope.Task do
  @moduledoc "A task naming its delegation candidates (`candidate_ids`)."

  use Ash.Resource,
    domain: AshA2ui.Test.PromptScope.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :team, :string, public?: true, allow_nil?: false
    attribute :org, :string, public?: true, default: "acme"
    attribute :candidate_ids, {:array, :uuid}, public?: true, default: []
  end

  relationships do
    belongs_to :principal, AshA2ui.Test.PromptScope.Principal, public?: true
  end

  preparations do
    prepare AshA2ui.Test.Adoption.ActorScope
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :delegate do
      accept [:principal_id]
      validate present(:principal_id)
    end

    update :reassign do
      accept [:principal_id]
    end
  end
end

defmodule AshA2ui.Test.PromptScope.TasksUI do
  @moduledoc "`:delegate` prompts for a principal among the row's candidates."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.PromptScope.Task
    surface_id "scoped_tasks"

    component :table do
      fields [:title]
      row_actions [:delegate]
    end

    field :principal_id do
      label "Principal"
    end

    action :delegate do
      prompt_fields [:principal_id]

      prompt_options :principal_id do
        read_action :candidates_for_task
        record_argument :task_id
      end
    end
  end
end

defmodule AshA2ui.Test.PromptScope.MixedTasksUI do
  @moduledoc "A scoped and an unscoped prompt over the same field."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.PromptScope.Task
    surface_id "mixed_tasks"

    component :table do
      fields [:title]
      row_actions [:delegate, :reassign]
    end

    action :delegate do
      prompt_fields [:principal_id]

      prompt_options :principal_id do
        read_action :candidates_for_task
        record_argument :task_id
      end
    end

    action :reassign do
      prompt_fields [:principal_id]
    end
  end
end

defmodule AshA2ui.Test.PromptScope.SearchTasksUI do
  @moduledoc "A scoped prompt over a searchable select (`option_search`)."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.PromptScope.Task
    surface_id "scoped_search_tasks"

    component :table do
      fields [:title]
      row_actions [:delegate]
    end

    field :principal_id do
      label "Principal"
      option_search [:name]
    end

    action :delegate do
      prompt_fields [:principal_id]

      prompt_options :principal_id do
        read_action :candidates_for_task
        record_argument :task_id
      end
    end
  end
end

defmodule AshA2ui.Test.PromptScope.TasksV1UI do
  @moduledoc "The scoped prompt on the A2UI 1.0 wire."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.PromptScope.Task
    surface_id "scoped_tasks_v1"
    spec_version "1.0"

    component :table do
      fields [:title]
      row_actions [:delegate]
    end

    action :delegate do
      prompt_fields [:principal_id]

      prompt_options :principal_id do
        read_action :candidates_for_task
        record_argument :task_id
      end
    end
  end
end
