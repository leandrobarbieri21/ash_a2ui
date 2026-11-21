defmodule AshA2ui.Test.DossierNotesReviewUI do
  @moduledoc """
  Standalone UI fixture for pair reviews (admin catalog 3.10): a dossier and
  its notes, drawn as cards, each note's facts a `pairs` field whose items
  carry their own review and key. Each fact has its own button checking it,
  offered while the note is open and the fact asks for it; the lead alert
  counts each waiting fact.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Dossier
    surface_id "dossier_notes_review"
    component_order :declared

    context :dossier do
      resource AshA2ui.Test.Dossier
      option_label :name
      picker false
    end

    section_nav do
      nav_item :facts_card, label: "Facts", anchor: "facts"
      nav_item :notes, label: "Notes", anchor: "notes"
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

    component :detail, :facts_card do
      section "Facts"
      context :dossier
      fields [:name]
    end

    query :notes do
      default_sort position: :asc
    end

    component :table, :notes do
      section "Notes"
      resource AshA2ui.Test.DossierNote
      query :notes
      display :cards
      context_filter dossier_id: :dossier
      require_context [:dossier]
      fields [:title, :facts]

      row_layout do
        title :title
        meta [:facts]
      end
    end

    field :name, do: review(:name_review)

    field :facts do
      label "Facts"
      pairs true
      field_action :check_fact
      field_action_visible :facts_open
    end

    action :check_fact do
      label "Mark as reviewed"
      icon "check"
      refreshes [:notes]
    end
  end
end
