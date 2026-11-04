defmodule AshA2ui.Test.DomainPseudoLocale do
  @moduledoc false
  # A domain-aware pseudo-locale translator (the `gettext_fn` arity-4
  # shape): library strings are wrapped in ⟦…⟧ and host display metadata in
  # ⟪…⟫, so a test can see which owner each translated string came from.

  alias AshA2ui.L10n

  def translate(msgid, bindings, "pseudo", meta) do
    msgid = if meta[:plural] && meta[:count] != 1, do: meta[:plural], else: msgid
    text = L10n.interpolate(msgid, bindings)

    case meta[:domain] do
      "ash_a2ui" -> "⟦" <> text <> "⟧"
      "a2ui_metadata" -> "⟪" <> text <> "⟫"
    end
  end

  def translate(_msgid, _bindings, _other_locale, _meta), do: nil
end
