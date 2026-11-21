defmodule AshA2ui.Test.DossierHandedLinesUI do
  @moduledoc """
  Standalone UI fixture for `context_record` with a review summary over
  table rows: the lines table names the dossier in `context_record`, so
  both its own read and the summary's read of its rows are handed the
  dossier (each line's `:label_review` reports whether it was).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Dossier
    surface_id "dossier_handed_lines"
    component_order :declared

    context :dossier do
      resource AshA2ui.Test.Dossier
      option_label :name
      picker false
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
      end
    end

    component :table, :lines do
      section "Lines"
      resource AshA2ui.Test.DossierLine
      context_filter dossier_id: :dossier
      require_context [:dossier]
      context_record dossier: [:name]
      fields [:label, :amount]
    end

    field :label, do: review(:label_review)
  end
end
