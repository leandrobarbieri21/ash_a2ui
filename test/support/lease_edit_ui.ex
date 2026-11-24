defmodule AshA2ui.Test.LeaseEditUI do
  @moduledoc """
  Standalone UI fixture for recalculating values from unsaved changes
  (admin catalog 3.15): a lease's terms card, whose rent and term a person
  corrects, the yearly rent and notice date worked out from them, and a
  timeline card of the term's dates. The worked-out values follow the
  unsaved changes (`recalculate`) before the save bar saves them.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Lease
    surface_id "lease_edit"

    context :lease do
      resource AshA2ui.Test.Lease
      option_label :title
      picker false
    end

    component :detail, :terms do
      context :lease
      fields [:title, :rent, :yearly_text, :ends_text, :notice_text, :notice_by_text]

      editable do
        fields [:title, :rent, :ends_text, :notice_text]
        update_action :correct
        visible :correctable
      end
    end

    component :detail, :timeline do
      context :lease
      fields [:timeline]
    end

    field :yearly_text do
      label "Yearly rent"
      recalculate true
    end

    field :ends_text do
      label "Ends"
      edit [:term, :ends_on]
    end

    field :notice_text do
      label "Notice"
      edit [:term, :notice_days]
    end

    field :notice_by_text do
      label "Notice by"
      note "Calculated"
      recalculate true
    end

    field :timeline do
      label "Timeline"
      steps true
      recalculate true
    end

    save_bar do
      context :lease
    end
  end
end
