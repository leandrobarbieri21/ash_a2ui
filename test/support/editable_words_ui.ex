defmodule AshA2ui.Test.EditableWordsUI do
  @moduledoc """
  Fixture surface for inline cell editing: a single table over
  `AshA2ui.Test.BucketWord` whose `:replacement` column commits per cell
  through `update_replacement` (which validates lowercase — the error-mirror
  proving case).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "editable_words"

    component :table do
      fields [:word, :replacement]

      editable do
        fields [:replacement]
        update_action :update_replacement
      end
    end
  end
end

defmodule AshA2ui.Test.EditableWordsV1UI do
  @moduledoc """
  A second surface over the inline-cell-editing fixture of
  `AshA2ui.Test.EditableWordsUI`, under its own surface id.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "editable_words_v1"

    component :table do
      fields [:word, :replacement]

      editable do
        fields [:replacement]
        update_action :update_replacement
      end
    end
  end
end
