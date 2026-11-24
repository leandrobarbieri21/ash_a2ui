defmodule AshA2ui.Test.DossierLinesSaveBarUI do
  @moduledoc """
  Standalone UI fixture for a save bar over a record whose table rows are
  reviewed too (admin catalog 3.16): a dossier whose name was read from a
  document and is corrected in place, and its lines, each amount (and
  period) read too, checked line by line. The bar counts the name and each
  waiting line once, as the review summary does.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Dossier
    surface_id "dossier_lines_save_bar"
    component_order :declared

    context :dossier do
      resource AshA2ui.Test.Dossier
      option_label :name
      picker false
    end

    component :detail, :facts do
      section "Facts"
      context :dossier
      fields [:name]

      editable do
        fields [:name]
        update_action :update
      end
    end

    query :lines do
      default_sort position: :asc
    end

    component :table, :lines do
      section "Lines"
      resource AshA2ui.Test.DossierLine
      query :lines
      context_filter dossier_id: :dossier
      require_context [:dossier]
      fields [:label, :period, :amount]
    end

    field :name, do: review(:name_review)
    field :period, do: review(:period_review)

    field :amount do
      review :amount_review
      field_action :mark_reviewed
      field_action_visible :review_open
    end

    action :mark_reviewed do
      label "Mark as reviewed"
      icon "check"
      refreshes [:lines]
    end

    save_bar do
      context :dossier
      message "You have unsaved changes"
      status "%{count} to check"
      edit_reviews true
      show_while_waiting true
    end
  end
end
