defmodule AshA2ui.Test.HubContract.StatusText do
  @moduledoc "A module calculation (not sortable in the data layer): the status, computed in Elixir."
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:status]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, & &1.status)
  end
end
