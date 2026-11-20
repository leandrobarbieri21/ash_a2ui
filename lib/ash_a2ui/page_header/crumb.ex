defmodule AshA2ui.PageHeader.Crumb do
  @moduledoc "Target struct for a `page_header`'s `crumb` entity: one breadcrumb step."

  defstruct [:label, :href, :page, :live, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          label: String.t(),
          href: String.t() | nil,
          page: atom | nil,
          live: :navigate | :patch | nil
        }
end
