defmodule AshA2ui.L10n.PseudoLocaleTest do
  @moduledoc """
  Re-runs every localization golden scenario with a pseudo-locale translator
  (`AshA2ui.Test.PseudoLocale`, which wraps each translation in ⟦…⟧) and
  compares the payload with the untranslated golden, leaf by leaf:

    * the structure is identical: no key, list item or non-string value
      changes;
    * a string that changes equals the golden once its ⟦⟧ are removed, so
      only the wording changed;
    * it changes only under a key that carries display text
      (`@display_keys`), never in an id, a path, an action or field name, an
      enum or option value, or record data;
    * no string is translated twice: no ⟦…⟧ group wraps exactly one other
      group. (A composite such as "⟦Create ⟦Task⟧⟧", a template with a
      translated label in it, is expected.)
  """

  # async: false — the scenarios flip the global :ash_a2ui :catalog env.
  use ExUnit.Case, async: false

  alias AshA2ui.Info
  alias AshA2ui.Test.Experience.Task
  alias AshA2ui.Test.L10nScenarios

  @golden_dir Path.expand("golden", __DIR__)
  @translator [gettext_fn: {AshA2ui.Test.PseudoLocale, :translate}, locale: "pseudo"]
  @display_keys ~w(text label title message primary_label _range_text _empty_message)

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :catalog) end)
    :ok
  end

  for name <- L10nScenarios.scenario_names() do
    @scenario_name name
    test "pseudo-locale #{name}" do
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

        assert key in @display_keys, "#{where}: #{inspect(key)} is not display text"
        assert strip(translated) == plain, "#{where}: #{inspect(translated)} changed wording"
        refute double_wrapped?(translated), "#{where}: #{inspect(translated)} translated twice"
      end
    end
  end

  test "a gettext backend translates in the given locale, falling back per string" do
    Ash.create!(Task, %{name: "one"})

    json =
      Task
      |> Info.build_surface(gettext_backend: {AshA2ui.Test.Gettext, "ash_a2ui"}, locale: "fr")
      |> Jason.encode!()

    # Translated in the French catalog (create title, a declared label).
    assert json =~ "Créer : Task"
    assert json =~ "1–1 sur 1"
    # Absent from it: the msgid.
    assert json =~ ~s("Previous")
    # Record data and ids untouched.
    assert json =~ ~s("one")
    refute json =~ "Créer : Tâche"
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

  defp strip(string), do: String.replace(string, ["⟦", "⟧"], "")

  # Parses the ⟦⟧ groups into a tree and looks for a group whose whole
  # content is one other group.
  defp double_wrapped?(string) do
    {nodes, ""} = parse(string, [])
    Enum.any?(nodes, &wraps_one?/1)
  end

  defp wraps_one?({:group, [{:group, _}]}), do: true
  defp wraps_one?({:group, children}), do: Enum.any?(children, &wraps_one?/1)
  defp wraps_one?(_text), do: false

  defp parse("", acc), do: {Enum.reverse(acc), ""}
  defp parse("⟧" <> rest, acc), do: {Enum.reverse(acc), "⟧" <> rest}

  defp parse("⟦" <> rest, acc) do
    {children, "⟧" <> rest} = parse(rest, [])
    parse(rest, [{:group, children} | acc])
  end

  defp parse(<<char::utf8, rest::binary>>, acc), do: parse(rest, [{:text, char} | acc])
end
