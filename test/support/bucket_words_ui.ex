defmodule AshA2ui.Test.BucketWordsUI do
  @moduledoc """
  Fixture surface for dynamic table sets: a static `:new_words`
  table plus a sectioned `:per_bucket` template expanded at runtime into one
  table per `AshA2ui.Test.Bucket` — the misspellings-buckets proving case.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "bucket_words"

    query :word_q do
      search_fields [:word]
      sortable [:word]
      default_sort word: :asc
      page_size 5
    end

    component :table, :new_words do
      fields [:word, :replacement]
      read_action :new_words
      row_actions [:approve]
    end

    component :table, :per_bucket do
      fields [:word, :replacement]
      read_action :bucketed
      row_actions [:destroy]
      query :word_q

      sections do
        source AshA2ui.Test.Bucket
        scope_by :bucket_id
        label :name
        sort :name
      end

      editable do
        fields [:replacement]
        update_action :update_replacement
      end
    end

    action :approve do
      refreshes [:new_words, :per_bucket]
    end

    action :destroy do
      refreshes [:per_bucket]
    end

    action :update_replacement do
      refreshes [:per_bucket]
    end
  end
end

defmodule AshA2ui.Test.BucketWordsV1UI do
  @moduledoc """
  A second surface over the dynamic-table-set fixture of
  `AshA2ui.Test.BucketWordsUI`, under its own surface id.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "bucket_words_v1"

    query :word_q do
      search_fields [:word]
      sortable [:word]
      default_sort word: :asc
      page_size 5
    end

    component :table, :per_bucket do
      fields [:word, :replacement]
      read_action :bucketed
      row_actions [:destroy]
      query :word_q

      sections do
        source AshA2ui.Test.Bucket
        scope_by :bucket_id
        label :name
        sort :name
      end
    end
  end
end
