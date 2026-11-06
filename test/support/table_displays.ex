defmodule AshA2ui.Test.TableDisplays.Domain do
  @moduledoc """
  Domain for the timeline and matrix fixtures (`display :timeline`,
  `display :matrix`). Kept apart from the frozen shared `AshA2ui.Test.Domain`.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.TableDisplays.Visit
    resource AshA2ui.Test.TableDisplays.Result
  end
end

defmodule AshA2ui.Test.TableDisplays.Visit do
  @moduledoc """
  Fixture resource for timelines: a clinic visit log entry, `seen_at` a UTC
  datetime, `seen_on` a date, `note` not a date at all.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.TableDisplays.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :summary, :string, public?: true, allow_nil?: false
    attribute :seen_at, :utc_datetime, public?: true
    attribute :seen_on, :date, public?: true
    attribute :note, :string, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end

defmodule AshA2ui.Test.TableDisplays.Result do
  @moduledoc """
  Fixture resource for matrices: one evaluated case (`case_name`) for one
  candidate (`candidate`, free text), with an `outcome` from a closed set and
  the `arm` it ran on (an enumerated column).
  """

  use Ash.Resource,
    domain: AshA2ui.Test.TableDisplays.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :case_name, :string, public?: true, allow_nil?: false
    attribute :candidate, :string, public?: true

    attribute :arm, :atom,
      public?: true,
      constraints: [one_of: [:baseline, :candidate, :shadow]]

    attribute :outcome, :atom,
      public?: true,
      constraints: [one_of: [:improved, :degraded, :failed, :skipped, :unmeasured]]

    attribute :rank, :integer, public?: true, default: 0
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end

defmodule AshA2ui.Test.TableDisplays.TimelineUI do
  @moduledoc "A timeline of visits over `seen_at`, queried, single table, v0.9.1."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.TableDisplays.Visit
    surface_id "visit_timeline"

    query :history do
      page_size 20
      sortable [:summary, :seen_at]
    end

    component :table, :history do
      fields [:summary, :seen_at]
      display :timeline
      date_field :seen_at
      query :history
    end
  end
end

defmodule AshA2ui.Test.TableDisplays.MatrixUI do
  @moduledoc """
  A matrix of results: a row per case, a column per candidate (free text, so
  columns come from the data), the outcome in each cell. Queried in `rank`
  order, single table, v0.9.1.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.TableDisplays.Result
    surface_id "result_matrix"

    query :results do
      page_size 50
      default_sort rank: :asc
      search_fields [:case_name]
      sortable [:rank]
    end

    component :table, :results do
      fields [:case_name, :candidate, :outcome]
      display :matrix
      row_field :case_name
      column_field :candidate
      cell_field :outcome
      query :results
    end
  end
end

defmodule AshA2ui.Test.TableDisplays.ArmMatrixUI do
  @moduledoc """
  A matrix whose columns are an enumerated attribute (`arm`), so every
  declared arm is a column even with no result, `spec_version "1.0"`.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.TableDisplays.Result
    surface_id "arm_matrix"
    spec_version "1.0"

    query :results do
      page_size 50
      default_sort rank: :asc
    end

    component :table, :results do
      fields [:case_name, :arm, :outcome]
      display :matrix
      row_field :case_name
      column_field :arm
      cell_field :outcome
      query :results
    end
  end
end
