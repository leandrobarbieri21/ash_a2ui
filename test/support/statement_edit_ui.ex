defmodule AshA2ui.Test.StatementEditUI do
  @moduledoc """
  Standalone UI fixture for editing a record in place (admin catalog 3.11): a
  statement's title, amount (shown as `amount_text`, edited as `:amount`)
  and kind, edited on its detail card while it is correctable, saved by the
  save bar through `:correct`; the bar counts the values still waiting and
  offers to save and mark the statement reviewed. It shows while values
  wait on a statement the person may correct (catalog 3.14).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Statement
    surface_id "statement_edit"

    context :statement do
      resource AshA2ui.Test.Statement
      option_label :title
      picker false
    end

    component :detail, :facts do
      context :statement
      fields [:title, :amount_text, :kind, :note]

      editable do
        fields [:title, :amount_text, :kind]
        update_action :correct
        visible :correctable
      end
    end

    field :title do
      review :title_review
    end

    field :amount_text do
      label "Amount"
      edit :amount
      review :amount_review
    end

    save_bar do
      context :statement
      message "You have unsaved changes"
      message_waiting "Reviewing the statement"
      status "%{count} to check"
      status_one "1 to check"
      status_reviewed "%{count} checked"
      status_reviewed_one "1 checked"
      edit_reviews true
      show_while_waiting :correctable

      confirm do
        title "Save with %{count} values unchecked?"
        title_one "Save with 1 value unchecked?"
        message "%{count} values still wait."
        save_label "Save progress"
        then_label "Save and finish"
        then_action :review
        then_visible :review_open
        then_saved_message "Saved and finished."
      end
    end
  end
end
