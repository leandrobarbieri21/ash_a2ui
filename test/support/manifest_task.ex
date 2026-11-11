defmodule AshA2ui.Test.ManifestTask do
  @moduledoc """
  Fixture for `AshA2ui.Manifest`: two named tables, presets of both kinds,
  and every row-action shape the manifest describes —

    * `:complete`: labelled, `visible_when` on one value;
    * `:reopen`: `visible_when` on a list of values;
    * `:annotate`: a prompt over a required accepted attribute, a required
      one-of argument and an optional boolean, with its own title;
    * `:discard`: a destroy (the admin catalog confirms it);
    * `:purge`: `visible_when` on `status: :done`, on a table whose default
      preset reads only open tasks: offered on no row it shows.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.ManifestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:open, :done]],
      default: :open

    attribute :note, :string, public?: true
    attribute :archived_at, :utc_datetime_usec, public?: true
  end

  actions do
    defaults [:read, create: :*]

    read :archived do
      filter expr(not is_nil(archived_at))
    end

    read :done do
      filter expr(status == :done)
    end

    update :complete do
      accept []
      change set_attribute(:status, :done)
    end

    update :reopen do
      accept []
      change set_attribute(:status, :open)
    end

    update :annotate do
      accept [:note]
      require_attributes [:note]
      argument :priority, :atom, allow_nil?: false, constraints: [one_of: [:low, :high]]
      argument :urgent, :boolean
    end

    update :purge do
      accept []
    end

    destroy :discard
  end

  a2ui do
    surface_id "manifest_tasks"

    query :open_query do
      search_fields [:title]
      default_preset :live

      preset :live do
        filter status: :open, archived_at: nil
      end

      preset :archived do
        read_action :archived
      end
    end

    component :table, :open_tasks do
      fields [:title, :status, :note]
      query :open_query
      row_actions [:complete, :annotate, :discard, :purge]
    end

    component :table, :done_tasks do
      fields [:title, :status]
      read_action :done
      row_actions [:reopen]
    end

    field :title do
      label "Task"
    end

    action :complete do
      label "Mark done"
      visible_when status: :open, archived_at: nil
    end

    action :reopen do
      visible_when status: [:done]
    end

    action :annotate do
      label "Add note"
      prompt_fields [:note, :priority, :urgent]
      prompt_title "Annotate task"
    end

    action :purge do
      visible_when status: :done
    end
  end
end
