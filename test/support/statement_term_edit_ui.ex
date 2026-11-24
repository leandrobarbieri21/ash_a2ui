defmodule AshA2ui.Test.StatementTermEditUI do
  @moduledoc """
  Standalone UI fixture for editing a related record's values in place: a
  statement's card shows its title and the term it states, kept on the
  statement's `:term` record. The term's values are edited through the
  relationship (`edit [:term, ...]`) and saved by the save bar through the
  statement's `:correct`, which corrects the term through the term's own
  `:correct`.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Statement
    surface_id "statement_term_edit"

    context :statement do
      resource AshA2ui.Test.Statement
      option_label :title
      picker false
    end

    component :detail, :term do
      context :statement
      fields [:title, :term_ends_text, :term_notice_text, :term_renewal_text]

      editable do
        fields [:title, :term_ends_text, :term_notice_text, :term_renewal_text]
        update_action :correct
        visible :correctable
      end
    end

    field :term_ends_text do
      label "Ends"
      edit [:term, :ends_on]
    end

    field :term_notice_text do
      label "Notice"
      edit [:term, :notice_days]
    end

    field :term_renewal_text do
      label "Renewal"
      edit [:term, :renewal]
    end

    save_bar do
      context :statement
    end
  end
end
