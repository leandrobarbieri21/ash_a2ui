defmodule AshA2ui.Gettext do
  @moduledoc """
  The marker for every string ash_a2ui writes for a reader.

  `msg("Save changes")` returns its argument unchanged at runtime. It exists
  so `mix ash_a2ui.gettext.extract` can find each library-owned string and
  write it to `priv/gettext/ash_a2ui.pot`, the template shipped in the
  package (the same convention as `Ash.Gettext.error_message/1`). Hosts copy
  that template with `mix ash_a2ui.gen.gettext` and translate it with
  ordinary Gettext tooling; see the "Localizing ash_a2ui" section of the
  README.

  Only a string literal is extracted. Placeholders use Gettext's `%{key}`
  form, and the bindings are passed when the message is translated
  (`AshA2ui.L10n.t/3`).
  """

  @doc """
  Marks `msgid` as a library-owned, translatable string. Returns it as-is.
  """
  defmacro msg(msgid) do
    quote do: unquote(msgid)
  end

  @doc """
  Marks the plural library string `singular` / `plural` as translatable and
  returns the pair, for `AshA2ui.L10n.tn/4`. The extractor writes it as a
  `msgid` with a `msgid_plural`. Both must be string literals.
  """
  defmacro msg_plural(singular, plural) do
    quote do: {unquote(singular), unquote(plural)}
  end
end
