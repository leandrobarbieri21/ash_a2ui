defmodule AshA2ui.CatalogAssetImportsTest do
  @moduledoc """
  The merged catalog asset must bundle against whichever `@a2ui` release a
  host has installed. A static import of a name the installed package lacks
  fails the host's esbuild outright, so the host passes the catalog its
  `@a2ui` dependencies and the asset resolves element classes at runtime.
  This guards against a static import coming back.
  """

  use ExUnit.Case, async: true

  @asset "priv/js/ash_a2ui_catalog.js"

  test "the catalog asset has no static imports" do
    source = File.read!(@asset)

    refute Regex.match?(~r/^\s*import\s/m, source),
           "#{@asset} must not import at module scope; the host passes dependencies in, " <>
             "and the upstream element classes are resolved from customElements"
  end

  test "the upstream Text and Button classes are taken from the registry by the basic catalog's tag" do
    source = File.read!(@asset)

    assert source =~ ~s|upstreamElementClass(basicCatalog, "Text")|
    assert source =~ ~s|upstreamElementClass(basicCatalog, "Button")|
    assert source =~ "customElements.get(tagName)"
  end
end
