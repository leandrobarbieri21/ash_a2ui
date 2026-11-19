defmodule AshA2ui.SectionNav.Item do
  @moduledoc "Target struct for a `section_nav`'s `nav_item` entity."

  defstruct [:component, :label, :anchor, :id, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          component: atom,
          label: String.t(),
          anchor: String.t(),
          id: String.t() | nil
        }
end
