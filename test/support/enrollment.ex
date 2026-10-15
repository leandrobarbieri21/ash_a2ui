defmodule AshA2ui.Test.Enrollment do
  @moduledoc """
  Fixture resource for wizard steps (A2UI-106): a stepped create/update
  form — `:who` (name, email), `:what` (role, team) and a `:confirm`
  review step. `name` and `team` are required so a blank later-step field
  fails the full changeset; `email` must contain an "@". `internal_note` is
  accepted by the actions but is not a form field, and
  `AshA2ui.Test.WizardProbe` reports every changeset the actions build to
  the calling process, so tests can prove what reached it.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false, constraints: [min_length: 1]
    attribute :email, :string, public?: true
    attribute :role, :string, public?: true
    attribute :team, :string, public?: true, allow_nil?: false
    attribute :internal_note, :string, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :email, :role, :team, :internal_note]
      validate match(:email, ~r/@/), message: "must be an email address"
      change AshA2ui.Test.WizardProbe
    end

    update :update do
      primary? true
      accept [:name, :email, :role, :team, :internal_note]
      validate match(:email, ~r/@/), message: "must be an email address"
      change AshA2ui.Test.WizardProbe
    end
  end

  a2ui do
    surface_id "enrollments"

    component :table do
      fields [:name, :email, :role, :team]
      read_action :read
    end

    component :form do
      fields [:name, :email, :role, :team]
      create_action :create
      update_action :update

      step :who do
        label "Who"
        description "Who is enrolling?"
        fields [:name, :email]
      end

      step :what do
        fields [:role, :team]
      end

      step :confirm do
        review? true
      end
    end
  end
end

defmodule AshA2ui.Test.EnrollmentV1UI do
  @moduledoc """
  The v1.0 twin of `AshA2ui.Test.Enrollment`'s stepped surface.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Enrollment
    surface_id "enrollments_v1"
    spec_version "1.0"

    component :form do
      fields [:name, :email, :role, :team]
      create_action :create
      update_action :update

      step :who do
        label "Who"
        fields [:name, :email]
      end

      step :what do
        fields [:role, :team]
      end

      step :confirm do
        review? true
      end
    end
  end
end

defmodule AshA2ui.Test.EnrollmentRowActionsUI do
  @moduledoc """
  `AshA2ui.Test.Enrollment`'s stepped form next to a table with a
  `:destroy` row action: a successful action that is not a form submit,
  for the wizard reset rules.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Enrollment
    surface_id "enrollments_row_actions"

    component :table do
      fields [:name, :team]
      read_action :read
      row_actions [:destroy]
    end

    component :form do
      fields [:name, :email, :role, :team]
      create_action :create
      update_action :update

      step :who do
        fields [:name, :email]
      end

      step :what do
        fields [:role, :team]
      end

      step :confirm do
        review? true
      end
    end
  end
end

defmodule AshA2ui.Test.TicketWizardUI do
  @moduledoc """
  A stepped form over `AshA2ui.Test.Ticket` with a searchable `belongs_to`
  select (`:author_id`), so the review step's value binding for a select
  can be checked.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Ticket
    surface_id "tickets_wizard"

    component :form do
      fields [:subject, :author_id]
      create_action :create
      update_action :update

      step :what do
        fields [:subject]
      end

      step :who do
        fields [:author_id]
      end

      step :confirm do
        review? true
      end
    end

    field :author_id do
      option_search [:name, :email]
    end
  end
end
