defmodule AshA2ui.Test.Search.Domain do
  @moduledoc "Fixture domain for `AshA2ui.Shell.Search`: tenanted, policy-guarded resources."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.Search.Licence
    resource AshA2ui.Test.Search.Run
    resource AshA2ui.Test.Search.Outage
  end
end
