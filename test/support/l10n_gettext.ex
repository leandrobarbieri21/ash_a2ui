defmodule AshA2ui.Test.Gettext do
  @moduledoc false
  # A real Gettext backend for the `gettext_backend:` translator tests, with a
  # partial French catalog (test/support/gettext/fr/LC_MESSAGES/ash_a2ui.po),
  # so untranslated msgids exercise the fallback.
  use Gettext.Backend, otp_app: :ash_a2ui, priv: "test/support/gettext"
end
