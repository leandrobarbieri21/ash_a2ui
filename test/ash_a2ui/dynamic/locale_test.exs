defmodule AshA2ui.Dynamic.LocaleTest do
  @moduledoc """
  An agent-composed spec carries text no catalog holds: it is shown as
  written, while chrome and the labels the spec does not write are
  translated once.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Dynamic
  alias AshA2ui.Test.DomainPseudoLocale
  alias AshA2ui.Test.Minimal

  @allowlist Dynamic.allowlist([Minimal])
  @pseudo [gettext_fn: {DomainPseudoLocale, :translate}, locale: "pseudo"]

  defp spec do
    %{
      "resource" => "Minimal",
      "title" => "Mes choses",
      "fields" => [%{"name" => "name", "label" => "Nom"}],
      "components" => [
        %{"kind" => "table", "fields" => ["name", "id"], "read_action" => "read"},
        %{"kind" => "form", "fields" => ["name"], "create_action" => "create"}
      ]
    }
  end

  test "spec text is not translated, other labels are, once" do
    {:ok, surface} = Dynamic.resolve(spec(), allowlist: @allowlist)

    plain = surface |> Dynamic.build_surface(authorize?: false) |> Jason.encode!()
    pseudo = surface |> Dynamic.build_surface([authorize?: false] ++ @pseudo) |> Jason.encode!()

    assert plain =~ "Nom"
    assert pseudo =~ ~s("Nom")
    refute pseudo =~ "⟪Nom⟫"
    refute pseudo =~ "⟪⟪"
    assert pseudo =~ "⟪Id⟫"
    assert plain =~ ~s("Id")
  end

  test "spec_schema/2 tells the agent the locale; without it the schema is unchanged" do
    base = Dynamic.spec_schema(@allowlist)
    assert Dynamic.spec_schema(@allowlist, []) == base

    localized = Dynamic.spec_schema(@allowlist, locale: "fr_CA")
    assert localized["description"] =~ ~s(locale code "fr_CA")
    assert Map.delete(localized, "description") == Map.delete(base, "description")
  end

  test "validation errors stay English whatever the locale" do
    assert {:error, [error]} =
             Dynamic.resolve(Map.put(spec(), "resource", "Nope"), allowlist: @allowlist)

    assert error.message =~ "Nope"
  end
end
