defmodule AshA2ui.Test.Adoption.Domain do
  @moduledoc """
  Domain for the adoption-findings fixtures: the library issues surfaced by
  adopting ash_a2ui in ash_enterprise and clinic-demo (actor-scoped reads,
  admin prompts and visibility, board lanes, prompt widgets, error feedback,
  action labels, select_context on boards). Kept apart from the frozen
  shared `AshA2ui.Test.Domain`.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.Adoption.Clerk
    resource AshA2ui.Test.Adoption.Queue
    resource AshA2ui.Test.Adoption.Job
  end
end

defmodule AshA2ui.Test.Adoption.ActorScope do
  @moduledoc """
  Read preparation scoping rows to the actor's `team` (and, when a tenant is
  given, to the tenant's `org`). Nobody acting reads nothing. A preparation,
  not a policy, so it only sees the actor and tenant the query was built
  with — the shape clinic-demo's worklist preparation has.
  """

  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(query, _opts, %{actor: %{team: team}, tenant: tenant}) do
    query = Ash.Query.filter(query, team == ^team)
    if is_nil(tenant), do: query, else: Ash.Query.filter(query, org == ^tenant)
  end

  def prepare(query, _opts, _context), do: Ash.Query.filter(query, false)
end

defmodule AshA2ui.Test.Adoption.Clerk do
  @moduledoc "A relationship destination whose reads are actor-scoped."

  use Ash.Resource,
    domain: AshA2ui.Test.Adoption.Domain,
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
  end
end

defmodule AshA2ui.Test.Adoption.Queue do
  @moduledoc "A sections source whose reads are actor-scoped."

  use Ash.Resource,
    domain: AshA2ui.Test.Adoption.Domain,
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
  end
end

defmodule AshA2ui.Test.Adoption.Job do
  @moduledoc """
  The surface resource. Reads are actor-scoped (`ActorScope`). Row actions:

    * `:claim` — a transition (`status` open → claimed), labelled in the UI;
    * `:assign` — a relationship prompt (`clerk_id`, a `belongs_to`);
    * `:reprioritize` — an enum prompt (the `priority` argument, `one_of`);
    * `:annotate` — a plain text prompt (the required `note` argument);
    * `:lock` — fails with a field-less error;
    * `:escalate` — forbidden unless the actor is an admin;
    * `:finish` — fails a validation on `status`, a field no prompt shows;
    * `:explode` — fails with a raw exception carrying row values.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Adoption.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :team, :string, public?: true, allow_nil?: false
    attribute :org, :string, public?: true, default: "acme"
    attribute :note, :string, public?: true

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:open, :claimed, :done]],
      default: :open

    attribute :priority, :atom,
      public?: true,
      constraints: [one_of: [:low, :normal, :high]],
      default: :normal
  end

  relationships do
    belongs_to :clerk, AshA2ui.Test.Adoption.Clerk, public?: true
    belongs_to :queue, AshA2ui.Test.Adoption.Queue, public?: true
  end

  preparations do
    prepare AshA2ui.Test.Adoption.ActorScope
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :update do
      primary? true
      accept [:title, :clerk_id]
    end

    update :claim do
      accept []
      change set_attribute(:status, :claimed)
    end

    update :assign do
      accept [:clerk_id]
      validate present(:clerk_id)
    end

    update :reprioritize do
      accept []

      argument :priority, :atom do
        allow_nil? false
        constraints one_of: [:low, :normal, :high]
      end

      change set_attribute(:priority, arg(:priority))
    end

    update :annotate do
      accept []
      argument :note, :string, allow_nil?: false
      change set_attribute(:note, arg(:note))
    end

    update :lock do
      accept []
      require_atomic? false
      change AshA2ui.Test.Adoption.Locked
    end

    update :escalate do
      accept []
      change set_attribute(:priority, :high)
    end

    update :finish do
      accept []
      validate attribute_equals(:status, :claimed)
      change set_attribute(:status, :done)
    end

    update :explode do
      accept []
      require_atomic? false
      change AshA2ui.Test.Adoption.Exploded
    end
  end

  policies do
    policy action(:escalate) do
      authorize_if actor_attribute_equals(:admin, true)
    end

    policy always() do
      authorize_if always()
    end
  end
end

defmodule AshA2ui.Test.Adoption.Locked do
  @moduledoc "A change that fails the action with a field-less error."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.add_error(changeset, "This job is locked by another team.")
  end
end

defmodule AshA2ui.Test.Adoption.Exploded do
  @moduledoc """
  A change that fails the action with a raw (non-Ash) exception whose text
  carries row values, as a data-layer error would.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.add_error(changeset, %RuntimeError{
      message:
        "ERROR 23505 (unique_violation)\n\n    table: users\n" <>
          "    detail: Key (email)=(alice@example.com) already exists."
    })
  end
end

defmodule AshA2ui.Test.Adoption.JobsUI do
  @moduledoc """
  A query-less table (its first read must still carry the actor and
  tenant), a form with a relationship select, and every prompt kind.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Adoption.Job
    surface_id "adoption_jobs"

    component :table do
      fields [:title, :status, :priority]
      row_actions [:claim, :assign, :reprioritize, :annotate, :lock, :escalate, :finish]
    end

    component :form do
      fields [:title, :clerk_id]
    end

    action :claim do
      visible_when status: :open
    end

    action :assign do
      prompt_fields [:clerk_id]
      prompt_title "Assign a clerk"
    end

    action :reprioritize do
      prompt_fields [:priority]
    end

    action :annotate do
      prompt_fields [:note]
    end
  end
end

defmodule AshA2ui.Test.Adoption.Desk do
  @moduledoc """
  A host facade refusing a `via` row action: with a plain string (`refuse`)
  or with a raw exception carrying row values (`crash`).
  """

  def refuse(_context), do: {:error, "Only the holder can complete this task."}

  def crash(_context),
    do: {:error, %RuntimeError{message: "internal: Key (email)=(bob@example.com)"}}
end

defmodule AshA2ui.Test.Adoption.LeakyJobsUI do
  @moduledoc "Row actions failing with raw exceptions: a change's and a `via` function's."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Adoption.Job
    surface_id "adoption_leaky_jobs"

    component :table do
      fields [:title]
      row_actions [:explode, :claim]
    end

    action :claim do
      via {AshA2ui.Test.Adoption.Desk, :crash, []}
    end
  end
end

defmodule AshA2ui.Test.Adoption.ViaJobsUI do
  @moduledoc "A row action delegated (`via`) to a host function that refuses it."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Adoption.Job
    surface_id "adoption_via_jobs"

    component :table do
      fields [:title]
      row_actions [:claim]
    end

    action :claim do
      via {AshA2ui.Test.Adoption.Desk, :refuse, []}
    end
  end
end

defmodule AshA2ui.Test.Adoption.QueuedJobsUI do
  @moduledoc "A sectioned table whose section source reads are actor-scoped."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Adoption.Job
    surface_id "adoption_queued_jobs"

    component :table, :per_queue do
      fields [:title]

      sections do
        source AshA2ui.Test.Adoption.Queue
        scope_by :queue_id
        label :name
      end
    end
  end
end

defmodule AshA2ui.Test.Adoption.JobBoardUI do
  @moduledoc "A board: lanes over `status`, cards moved by `:claim`."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Adoption.Job
    surface_id "adoption_job_board"

    component :table, :board do
      fields [:title, :priority]
      display :board
      row_actions [:claim]

      row_layout do
        title :title
        badge :priority
      end

      sections do
        scope_by :status
        values [:open, :claimed, :done]
      end
    end

    action :claim do
      visible_when status: :open
      refreshes [:board]
    end
  end
end
