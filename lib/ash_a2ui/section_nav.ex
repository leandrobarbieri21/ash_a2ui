defmodule AshA2ui.SectionNav do
  @moduledoc """
  Target struct for the `section_nav` DSL entity: a sticky list of the
  surface's sections beside them (admin catalog 3.5's entityPage `nav`).
  """

  defstruct [:id, label: "Sections", items: [], __spark_metadata__: nil]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          label: String.t(),
          items: [AshA2ui.SectionNav.Item.t()]
        }
end
