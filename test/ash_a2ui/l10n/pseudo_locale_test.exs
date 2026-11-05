defmodule AshA2ui.L10n.PseudoLocaleTest do
  @moduledoc """
  Re-runs every localization golden scenario with a pseudo-locale translator
  and compares the payload with the untranslated golden, leaf by leaf. Two
  translators run: `AshA2ui.Test.PseudoLocale` (the `gettext_fn` arity-3
  shape, which wraps every translation in ⟦…⟧) and
  `AshA2ui.Test.DomainPseudoLocale` (the domain-aware arity-4 shape, which
  wraps library strings in ⟦…⟧ and host display metadata in ⟪…⟫). For each:

    * the structure is identical: no key, list item or non-string value
      changes;
    * a string that changes equals the golden once its ⟦⟧ are removed, so
      only the wording changed;
    * it changes only under a key that carries display text
      (`@display_keys`), never in an id, a path, an action or field name, an
      enum or option value, or record data;
    * no string is translated twice: no group wraps exactly one other
      group. (A composite such as "⟦Create ⟦Task⟧⟧", a template with a
      translated label in it, is expected.)

  With the domain-aware translator, every ⟪…⟫ string is a msgid that
  `mix ash_a2ui.gettext.extract_metadata` collects for the surface, and an
  initial build shows exactly the collected set.
  """

  # async: false — the scenarios flip the global :ash_a2ui :catalog env.
  use ExUnit.Case, async: false

  alias AshA2ui.Gettext.Metadata
  alias AshA2ui.Info
  alias AshA2ui.Test.BulkTasksUI
  alias AshA2ui.Test.Experience.Task
  alias AshA2ui.Test.L10nScenarios

  @golden_dir Path.expand("golden", __DIR__)
  @translators [
    {"pseudo-locale", AshA2ui.Test.PseudoLocale},
    {"domain pseudo-locale", AshA2ui.Test.DomainPseudoLocale}
  ]
  @display_keys ~w(text label title message body placeholder description moreNoun confirmLabel
                   primary_label _range_text _empty_message _primary_label)
  # Row keys whose value is a label chosen by the record's value: an
  # enumerated value's label, a badge, an icon label, a detail line.
  @row_label_prefixes ~w(_badge_ _icon_label_ _detail_ _empty_message)
  @choice_cells ~w(status priority severity stage status_text)

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :catalog) end)
    :ok
  end

  for {label, translator} <- @translators, name <- L10nScenarios.scenario_names() do
    @scenario_name name
    @translator [gettext_fn: {translator, :translate}, locale: "pseudo"]
    test "#{label} #{name}" do
      golden = File.read!(Path.join(@golden_dir, "#{@scenario_name}.json"))
      pseudo = L10nScenarios.run(L10nScenarios.scenario(@scenario_name), @translator)

      changes = diff(Jason.decode!(golden), Jason.decode!(pseudo), [])

      # An option list carries record labels only; everything else has chrome.
      if not String.starts_with?(@scenario_name, "bulk_options") do
        assert changes != [], "nothing was translated"
      end

      for {path, plain, translated} <- changes do
        where = "#{@scenario_name} at #{inspect(path)}"
        key = path |> Enum.filter(&is_binary/1) |> List.last()

        assert display_key?(key), "#{where}: #{inspect(key)} is not display text"
        assert strip(translated) == plain, "#{where}: #{inspect(translated)} changed wording"
        refute double_wrapped?(translated), "#{where}: #{inspect(translated)} translated twice"
      end

      if @translator[:gettext_fn] == {AshA2ui.Test.DomainPseudoLocale, :translate} do
        assert_metadata_extracted(@scenario_name, pseudo)
      end
    end
  end

  defp display_key?(key),
    do:
      key in @display_keys or key in @choice_cells or
        String.starts_with?(key, @row_label_prefixes)

  # Every host label the runtime translated is in the extracted catalog for
  # the scenario's surface; an initial build shows the whole catalog.
  defp assert_metadata_extracted(name, pseudo) do
    shown =
      ~r/⟪([^⟦⟧⟪⟫]*)⟫/
      |> Regex.scan(pseudo, capture: :all_but_first)
      |> MapSet.new(fn [msgid] -> {nil, msgid} end)

    surface =
      cond do
        String.starts_with?(name, "bulk_") -> BulkTasksUI
        String.starts_with?(name, "hub_") -> AshA2ui.Test.HubUI
        String.starts_with?(name, "board_") -> AshA2ui.Test.BoardTaskUI
        String.starts_with?(name, "enum_") -> AshA2ui.Test.EnumRecord
        true -> Task
      end

    extracted = surface |> Metadata.surface_messages() |> MapSet.new()

    # A surface also collects the labels a record or a query state selects
    # (an enum's every label, empty states), so a build shows a subset.
    msgids = MapSet.new(extracted, fn {_context, msgid} -> msgid end)

    missing = Enum.reject(shown, fn {_context, msgid} -> msgid in msgids end)

    assert missing == [], "#{name}: not extracted: #{inspect(missing)}"
  end

  test "a gettext backend translates in the given locale, falling back per string" do
    Ash.create!(Task, %{name: "one"})
    l10n = [gettext_backend: {AshA2ui.Test.Gettext, "ash_a2ui"}, locale: "fr"]

    json = Task |> Info.build_surface(l10n) |> Jason.encode!()

    # Library strings, from the library domain (ash_a2ui.po).
    assert json =~ "Créer : Task"
    assert json =~ "1–1 sur 1"
    # Host labels, from the metadata domain (a2ui_metadata.po).
    assert json =~ ~s("Nom")
    # Absent from the catalogs: the msgid.
    assert json =~ ~s("Previous")
    # Record data and ids untouched.
    assert json =~ ~s("one")
    refute json =~ "Créer : Tâche"

    # Another metadata domain: labels are looked up there, library strings
    # are not.
    other = Task |> Info.build_surface([metadata_domain: "other"] ++ l10n) |> Jason.encode!()
    refute other =~ ~s("Nom")
    assert other =~ "Créer : Task"
  end

  defp diff(same, same, _path), do: []

  defp diff(%{} = plain, %{} = pseudo, path) do
    assert Map.keys(plain) == Map.keys(pseudo), "keys changed at #{inspect(Enum.reverse(path))}"
    Enum.flat_map(plain, fn {key, value} -> diff(value, pseudo[key], [key | path]) end)
  end

  defp diff(plain, pseudo, path) when is_list(plain) and is_list(pseudo) do
    assert length(plain) == length(pseudo),
           "list length changed at #{inspect(Enum.reverse(path))}"

    plain
    |> Enum.zip(pseudo)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{a, b}, index} -> diff(a, b, [index | path]) end)
  end

  defp diff(plain, pseudo, path) when is_binary(plain) and is_binary(pseudo),
    do: [{Enum.reverse(path), plain, pseudo}]

  defp diff(plain, pseudo, path) do
    flunk(
      "non-string value changed at #{inspect(Enum.reverse(path))}: " <>
        "#{inspect(plain)} -> #{inspect(pseudo)}"
    )
  end

  defp strip(string), do: String.replace(string, ["⟦", "⟧", "⟪", "⟫", "⟨", "⟩"], "")

  # Parses the ⟦⟧, ⟪⟫ and ⟨⟩ groups into a tree and looks for a group whose
  # whole content is one other group.
  defp double_wrapped?(string) do
    {nodes, ""} = parse(string, [])
    Enum.any?(nodes, &wraps_one?/1)
  end

  defp wraps_one?({:group, [{:group, _}]}), do: true
  defp wraps_one?({:group, children}), do: Enum.any?(children, &wraps_one?/1)
  defp wraps_one?(_text), do: false

  defp parse("", acc), do: {Enum.reverse(acc), ""}
  defp parse("⟧" <> rest, acc), do: {Enum.reverse(acc), "⟧" <> rest}
  defp parse("⟫" <> rest, acc), do: {Enum.reverse(acc), "⟫" <> rest}
  defp parse("⟩" <> rest, acc), do: {Enum.reverse(acc), "⟩" <> rest}

  defp parse("⟦" <> rest, acc) do
    {children, "⟧" <> rest} = parse(rest, [])
    parse(rest, [{:group, children} | acc])
  end

  defp parse("⟪" <> rest, acc) do
    {children, "⟫" <> rest} = parse(rest, [])
    parse(rest, [{:group, children} | acc])
  end

  defp parse("⟨" <> rest, acc) do
    {children, "⟩" <> rest} = parse(rest, [])
    parse(rest, [{:group, children} | acc])
  end

  defp parse(<<char::utf8, rest::binary>>, acc), do: parse(rest, [{:text, char} | acc])
end
