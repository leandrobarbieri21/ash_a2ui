# The composer's configured fixture LiveViews (the `live` router macro's
# __checks__ verifies the module at router compile time, so the fixtures must
# compile with test/support — before the router). Guarded like endpoint.ex for
# the NO_PHOENIX CI job.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Test.NoSurface do
    @moduledoc false
    # A plain module: hosts may list one; browse shows it honestly and import
    # reports that there is nothing to import.
    def present, do: true
  end

  defmodule AshA2ui.Test.ComposerLive do
    @moduledoc """
    The composer fixture: one standalone UI module (MinimalUI, the honest
    surface_id rejection), one on-resource surface (Ticket, nested forms
    importing into the spec), and one plain module (nothing to import), with
    the export module pinned for assertions.
    """

    use AshA2ui.Web.ComposerLive,
      surfaces: [AshA2ui.Test.MinimalUI, AshA2ui.Test.Ticket, AshA2ui.Test.NoSurface],
      export_module: "AshA2ui.Test.ComposedSurface"
  end

  defmodule AshA2ui.Test.ComposerRelatedLive do
    @moduledoc """
    The master/detail fixture: PeopleUI (a context, two related tables and
    link columns) with the related tables' resources passed as allowlist
    extras — the clinic-demo shape whose import used to drop both.
    """

    use AshA2ui.Web.ComposerLive,
      surfaces: [AshA2ui.Test.Links.PeopleUI],
      allowlist: [AshA2ui.Test.Links.Note, AshA2ui.Test.Links.Participant]
  end

  defmodule AshA2ui.Test.ComposerNamedAllowlistLive do
    @moduledoc """
    The map-allowlist fixture: the host names the one resource "renamed", so
    a short-name import does not resolve until the resource is renamed — the
    documented escape hatch for colliding short names.
    """

    use AshA2ui.Web.ComposerLive,
      surfaces: [AshA2ui.Test.MinimalUI],
      allowlist: %{"renamed" => AshA2ui.Test.Minimal}
  end
end
