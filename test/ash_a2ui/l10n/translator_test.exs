defmodule AshA2ui.L10n.TranslatorTest do
  use ExUnit.Case, async: true

  alias AshA2ui.L10n
  alias AshA2ui.Label
  alias AshA2ui.Test.Gettext, as: Backend
  alias AshA2ui.Test.PseudoLocale

  defmodule Arity2Only do
    def translate(msgid, _bindings), do: "two:" <> msgid
  end

  defmodule Blank do
    def translate(_msgid, _bindings, _locale), do: ""
  end

  defmodule DomainAware do
    # Also exports the arity-2 and -3 shapes: arity 4 wins.
    def translate(msgid, _bindings), do: "two:" <> msgid
    def translate(msgid, _bindings, _locale), do: "three:" <> msgid
    def translate(msgid, bindings, locale, meta), do: inspect({msgid, bindings, locale, meta})
  end

  describe "new/1" do
    test "builds no translator without a gettext option" do
      assert L10n.new([]) == nil
      assert L10n.new(locale: "fr") == nil
    end

    test "rejects both translators at once" do
      assert_raise ArgumentError, ~r/either :gettext_fn or :gettext_backend/, fn ->
        L10n.new(
          gettext_fn: {PseudoLocale, :translate},
          gettext_backend: {Backend, "ash_a2ui"},
          locale: "fr"
        )
      end
    end

    test "requires an explicit locale with a backend" do
      assert_raise ArgumentError, ~r/explicit :locale/, fn ->
        L10n.new(gettext_backend: {Backend, "ash_a2ui"})
      end
    end

    test "checks the function's arity against whether a locale is given" do
      assert %L10n{} = L10n.new(gettext_fn: {Arity2Only, :translate})

      assert_raise ArgumentError, ~r{Arity2Only.translate/3 is not defined}, fn ->
        L10n.new(gettext_fn: {Arity2Only, :translate}, locale: "fr")
      end
    end

    test "rejects malformed options" do
      assert_raise ArgumentError, ~r/:metadata_domain must be/, fn ->
        L10n.new(gettext_fn: {PseudoLocale, :translate}, metadata_domain: :labels)
      end

      assert_raise ArgumentError, ~r/:locale must be/, fn -> L10n.new(locale: :fr) end
      assert_raise ArgumentError, ~r/:locale must be/, fn -> L10n.new(locale: "") end
      assert_raise ArgumentError, ~r/:gettext_fn must be/, fn -> L10n.new(gettext_fn: & &1) end

      assert_raise ArgumentError, ~r/:gettext_backend must be/, fn ->
        L10n.new(gettext_backend: Backend, locale: "fr")
      end
    end
  end

  describe "t/3 with :gettext_fn" do
    test "calls the function without a locale, with bindings" do
      l10n = L10n.new(gettext_fn: {PseudoLocale, :translate})
      assert L10n.t(l10n, "Updated %{field}.", field: "Name") == "⟦Updated Name.⟧"
    end

    test "passes the locale as a third argument" do
      assert L10n.t(L10n.new(gettext_fn: {PseudoLocale, :translate}, locale: "pseudo"), "Save") ==
               "⟦Save⟧"
    end

    test "falls back to the interpolated msgid on nil or an empty string" do
      missing = L10n.new(gettext_fn: {PseudoLocale, :translate}, locale: "de")
      blank = L10n.new(gettext_fn: {Blank, :translate}, locale: "fr")

      for l10n <- [missing, blank] do
        assert L10n.t(l10n, "Updated %{field}.", field: "Name") == "Updated Name."
      end
    end
  end

  describe "the domain-aware :gettext_fn (arity 4)" do
    test "tells library strings from host metadata by domain, with the context" do
      l10n = L10n.new(gettext_fn: {DomainAware, :translate}, locale: "fr")

      assert L10n.t(l10n, "Updated %{field}.", field: "Name") ==
               inspect({"Updated %{field}.", [field: "Name"], "fr", [domain: "ash_a2ui"]})

      assert L10n.metadata(l10n, "Due date") ==
               inspect({"Due date", [], "fr", [domain: "a2ui_metadata"]})

      assert L10n.metadata(l10n, "Open", "enum:Elixir.MyApp.Status") ==
               inspect(
                 {"Open", [], "fr",
                  [domain: "a2ui_metadata", context: "enum:Elixir.MyApp.Status"]}
               )
    end

    test "passes a nil locale and the configured metadata domain" do
      l10n = L10n.new(gettext_fn: {DomainAware, :translate}, metadata_domain: "labels")

      assert Label.translate(l10n, "Due date") ==
               inspect({"Due date", [], nil, [domain: "labels"]})
    end

    test "the arity-2 and -3 shapes get both owners' messages, without domain or context" do
      two = L10n.new(gettext_fn: {Arity2Only, :translate})
      assert L10n.t(two, "Save") == "two:Save"
      assert L10n.metadata(two, "Open", "enum:Elixir.MyApp.Status") == "two:Open"

      three = L10n.new(gettext_fn: {PseudoLocale, :translate}, locale: "pseudo")
      assert L10n.t(three, "Save") == "⟦Save⟧"
      assert Label.resolve(three, nil, :due_date) == "⟦Due date⟧"
      assert L10n.metadata(three, "Open", "enum:Elixir.MyApp.Status") == "⟦Open⟧"
    end
  end

  describe "t/3 with :gettext_backend" do
    test "translates in the given locale and interpolates" do
      l10n = L10n.new(gettext_backend: {Backend, "ash_a2ui"}, locale: "fr")

      assert L10n.t(l10n, "Save") == "Enregistrer"
      assert L10n.t(l10n, "Updated %{field}.", field: "Titre") == "Titre mis à jour."
    end

    test "falls back to the msgid when the catalog has no translation" do
      l10n = L10n.new(gettext_backend: {Backend, "ash_a2ui"}, locale: "fr")
      assert L10n.t(l10n, "Export CSV") == "Export CSV"
      assert L10n.t(l10n, "Select %{context}", context: "Clinic") == "Select Clinic"
    end

    test "looks labels up in the metadata domain, under their msgctxt" do
      l10n = L10n.new(gettext_backend: {Backend, "ash_a2ui"}, locale: "fr")

      # "Title" is host metadata: in a2ui_metadata.po, not in ash_a2ui.po.
      assert Label.translate(l10n, "Title") == "Titre"
      assert L10n.t(l10n, "Title") == "Title"
      # Library strings are not looked up in the metadata domain.
      assert Label.translate(l10n, "Save") == "Save"

      assert Label.translate(l10n, "Open") == "Ouvrir"
      assert Label.translate(l10n, "Open", "enum:Elixir.MyApp.Status") == "Ouvert"
      assert Label.translate(l10n, "Open", "enum:Elixir.MyApp.Other") == "Open"
    end

    test "never reads the ambient locale" do
      Gettext.put_locale(Backend, "fr")
      l10n = L10n.new(gettext_backend: {Backend, "ash_a2ui"}, locale: "en")

      assert L10n.t(l10n, "Save") == "Save"
      assert Gettext.get_locale(Backend) == "fr"
    end
  end
end
