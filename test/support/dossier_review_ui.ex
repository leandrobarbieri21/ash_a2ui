defmodule AshA2ui.Test.DossierReviewUI do
  @moduledoc """
  Standalone UI fixture for review summaries (admin catalog 3.6): a dossier
  whose name, owner and notes were read from a document, each with its
  review, and a lead alert summing up what still waits, linking to the
  first waiting field's section (the nav's anchor for Facts, the section's
  id for Notes, which the nav does not list).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Dossier
    surface_id "dossier_review"
    component_order :declared

    context :dossier do
      resource AshA2ui.Test.Dossier
      option_label :name
      picker false
    end

    section_nav do
      nav_item :facts, label: "Facts", anchor: "facts"
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
      fields [:name, :owner]
    end

    component :detail, :more_facts do
      section "Facts"
      context :dossier
      fields [:state]
    end

    component :detail, :notes_card do
      section "Notes"
      context :dossier
      fields [:notes]
    end

    field :name, do: review(:name_review)
    field :owner, do: review(:owner_review)
    field :notes, do: review(:notes_review)
  end
end
