defmodule AshA2ui.Test.Search.Outage.Down do
  @moduledoc "Fails every read it prepares."

  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context), do: Ash.Query.add_error(query, "the store is down")
end
