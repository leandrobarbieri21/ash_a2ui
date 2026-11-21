defmodule AshA2ui.Test.DossierLinesReviewUI do
  @moduledoc """
  Standalone UI fixture for row field actions and review summaries over
  table rows (admin catalog 3.9): a dossier whose name was read from a
  document, and its lines, each amount (and period) read too. A line's
  amount carries a button checking the whole line, offered while the line
  waits; the lead alert counts the name and each waiting line once.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Dossier
    surface_id "dossier_lines_review"
    component_order :declared

    context :dossier do
      resource AshA2ui.Test.Dossier
      option_label :name
      picker false
    end

    section_nav do
      nav_item :facts, label: "Facts", anchor: "facts"
      nav_item :lines, label: "Lines", anchor: "lines"
    end

    component :detail, :to_review do
      context :dossier
      lead true

      alert do
        variant :warning
        title "Check what was read"
        message :notes
      end

      review_summary do
        link_label "Go to the first field to check"
        fallback_href "#history"
        fallback_label "Go to history"
      end
    end

    component :detail, :facts do
      section "Facts"
      context :dossier
      fields [:name]
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
  end
end
