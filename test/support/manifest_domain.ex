defmodule AshA2ui.Test.ManifestDomain do
  @moduledoc false
  # The domain of the `AshA2ui.Manifest` fixtures, apart from the shared
  # test domain.

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.ManifestTask
  end
end
