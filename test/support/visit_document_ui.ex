defmodule AshA2ui.Test.VisitDocumentUI do
  @moduledoc """
  Standalone UI fixture for document panes (admin catalog 3.4): a visit's
  detail card, its title and status cited on the referral it was read from,
  and the referral drawn beside it.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Appointment
    surface_id "visit_document"

    context :appointment do
      resource AshA2ui.Test.Appointment
      option_label :title
      picker false
    end

    component :detail, :review do
      section "Visit"
      context :appointment
      fields [:title, :status, :scheduled_for]
    end

    document_pane :referral do
      context :appointment
      source :referral_document
      regions :referral_regions
      label "Show referral"
      description "Read-only"
      url_param "document"
    end

    field :title do
      review :title_cited_review
    end

    field :status do
      review :status_cited_review
    end
  end
end
