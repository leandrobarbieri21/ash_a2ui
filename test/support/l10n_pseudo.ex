defmodule AshA2ui.Test.PseudoLocale do
  @moduledoc false
  # A pseudo-locale translator for the localization goldens: wraps every
  # translated string in ⟦…⟧, so a test can see which strings were
  # translated, and that none was translated twice.

  alias AshA2ui.L10n

  def translate(msgid, bindings), do: "⟦" <> L10n.interpolate(msgid, bindings) <> "⟧"

  def translate(msgid, bindings, "pseudo"), do: translate(msgid, bindings)
  def translate(_msgid, _bindings, _other_locale), do: nil
end
