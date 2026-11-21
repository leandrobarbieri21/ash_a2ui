defmodule AshA2ui.Test.MaskedDiagramSource do
  @moduledoc "Diagram fixture source: a marker with a forbidden label, one with a forbidden node label."

  def diagram(_context) do
    {:ok,
     %{
       source: "graph TD\n  a[Masked]\n  b[Second]",
       markers: [
         %{
           node_id: "a",
           label: %Ash.ForbiddenField{
             field: :name,
             type: :attribute,
             original_value: "SECRET-4711"
           },
           node_label: %Ash.ForbiddenField{
             field: :name,
             type: :attribute,
             original_value: "SECRET-4711"
           },
           status: :waiting,
           link: nil
         },
         %{node_id: "b", label: "Second", status: :active},
         %{
           node_id: "c",
           label: "Third",
           node_label: %Ash.ForbiddenField{
             field: :name,
             type: :attribute,
             original_value: "SECRET-4711"
           },
           status: :done
         }
       ]
     }}
  end
end

defmodule AshA2ui.Test.MaskedDiagramUI do
  @moduledoc "Diagram fixture surface: the masked marker's diagram."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.SecureLease
    surface_id "masked_diagram"

    diagram :flow do
      source AshA2ui.Test.MaskedDiagramSource
    end
  end
end
