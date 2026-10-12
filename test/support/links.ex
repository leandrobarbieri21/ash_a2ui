defmodule AshA2ui.Test.Links.Domain do
  @moduledoc """
  Domain for the reference-link fixtures (`link` / `links` field options,
  calculation-terminal `source` columns, deep-linked contexts). Kept apart
  from the frozen shared `AshA2ui.Test.Domain`.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.Links.Person
    resource AshA2ui.Test.Links.Note
    resource AshA2ui.Test.Links.Participant
  end
end

defmodule AshA2ui.Test.Links.Person do
  @moduledoc """
  A link target with a read policy: only `visible` people are readable, so
  links to hidden people must be pruned (the authorized relationship load
  never returns them). `display_name` is a calculation — the terminal of a
  `source` column. Shared (non-private) ETS so LiveView processes see it.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Links.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :visible, :boolean, public?: true, default: true
  end

  calculations do
    calculate :display_name, :string, expr("Dr. " <> name), public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:name, :visible]]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(visible == true)
    end

    policy action_type([:create, :destroy]) do
      authorize_if always()
    end
  end
end

defmodule AshA2ui.Test.Links.Participant do
  @moduledoc "Join resource: a person participating in a note."

  use Ash.Resource,
    domain: AshA2ui.Test.Links.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :note, AshA2ui.Test.Links.Note, public?: true, allow_nil?: false
    belongs_to :person, AshA2ui.Test.Links.Person, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: [:note_id, :person_id]]
  end
end

defmodule AshA2ui.Test.Links.Note do
  @moduledoc """
  The linking resource: a `belongs_to :person` (single link, labelled by
  the `display_name` calculation read through `source`), a bare
  `subject_id` uuid (an explicit `{surface, id_path}` link), and
  `many_to_many :participants` (a multi-valued `links` column).
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Links.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false
    attribute :subject_id, :uuid, public?: true
    attribute :body, :string, public?: true
    attribute :amount, :integer, public?: true

    attribute :status, :atom,
      public?: true,
      default: :open,
      constraints: [one_of: [:open, :closed]]
  end

  relationships do
    belongs_to :person, AshA2ui.Test.Links.Person, public?: true

    many_to_many :participants, AshA2ui.Test.Links.Person,
      public?: true,
      through: AshA2ui.Test.Links.Participant,
      source_attribute_on_join_resource: :note_id,
      destination_attribute_on_join_resource: :person_id
  end

  actions do
    defaults [:read, :destroy, create: [:title, :subject_id, :person_id, :body, :amount, :status]]

    update :update do
      primary? true
      accept [:title, :person_id]
    end
  end
end

defmodule AshA2ui.Test.Links.NotesUI do
  @moduledoc """
  Standalone surface over `Note` exercising every link form plus contexts
  for deep links: `:person` (a picker context scoping the table) and
  `:note` (pickerless, selected by the table's master/detail row select,
  rendered by a detail with link fields).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Links.Note
    surface_id "notes"

    context :person do
      resource AshA2ui.Test.Links.Person
      option_label :name
    end

    context :note do
      resource AshA2ui.Test.Links.Note
      option_label :title
      picker false
    end

    component :table do
      fields [:title, :status, :amount, :person_name, :subject_id, :participant_links]
      context_filter person_id: :person
      select_context :note

      row_layout do
        title :title
        badge :status
        badge_text open: "Open", closed: "Closed"
        badge_tones open: :success, closed: :neutral
        meta [:amount, :person_name, :subject_id, :participant_links]
      end
    end

    component :form do
      fields [:title, :person_id]
      update_action :update
    end

    component :detail, :note_detail do
      context :note
      fields [:title, :body, :person_name, :participant_links]
    end

    field :person_name do
      label "Person"
      source [:person, :display_name]
      link :person
    end

    field :person_id do
      link :person
    end

    field :subject_id do
      label "Subject"
      link {:person, :subject_id}
    end

    field :participant_links do
      label "Participants"
      links :participants
    end
  end
end

defmodule AshA2ui.Test.Links.PagedNotesUI do
  @moduledoc """
  A paginated link surface (page size 1) — the browser probe's windowed
  pagination + link-cell fixture (`priv/js/probe/links_probe.mjs`).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Links.Note
    surface_id "paged_notes"

    query :default do
      sortable [:title]
      default_sort title: :asc
      page_size 1
      max_page_size 5
    end

    component :table do
      fields [:title, :amount, :person_name]
      query :default
    end

    component :form do
      fields [:title]
      update_action :update
    end

    field :person_name do
      label "Person"
      source [:person, :display_name]
      link :person
    end
  end
end

defmodule AshA2ui.Test.Links.PeopleUI do
  @moduledoc """
  Related tables (`resource` on a `:table`): a surface over `Person` whose
  selected person's notes and participations are tables over `Note` and
  `Participant`, scoped by the `:person` context — each with its own
  fields, query, links and `source` columns resolved against its own
  resource.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Links.Person
    surface_id "people"

    context :person do
      resource AshA2ui.Test.Links.Person
      option_label :name
      picker false
    end

    query :notes do
      search_fields [:title]
      sortable [:title, :amount]
      default_sort title: :asc
      page_size 10
    end

    component :table do
      fields [:name]
      select_context :person
    end

    component :detail, :person_detail do
      context :person
      fields [:name]
    end

    component :table, :their_notes do
      resource AshA2ui.Test.Links.Note
      fields [:title, :status, :amount, :participant_links]
      query :notes
      context_filter person_id: :person
      require_context [:person]
    end

    component :table, :participations do
      resource AshA2ui.Test.Links.Participant
      fields [:note_title]
      context_filter person_id: :person
      require_context [:person]
    end

    field :participant_links do
      label "Participants"
      links :participants
    end

    field :note_title do
      label "Note"
      source [:note, :title]
      link :note
    end
  end
end
