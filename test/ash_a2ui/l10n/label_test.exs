defmodule AshA2ui.LabelTest do
  use ExUnit.Case, async: true

  doctest AshA2ui.Label
  doctest AshA2ui.L10n

  alias AshA2ui.L10n
  alias AshA2ui.Label

  test "humanize matches every former private copy" do
    for {name, label} <- [
          {:due_date, "Due date"},
          {"HTTP_status", "Http status"},
          {:open, "Open"},
          {"already Spaced", "Already spaced"},
          {:"", ""}
        ] do
      assert Label.humanize(name) == label
    end
  end

  test "interpolate fills known placeholders once and leaves unknown ones" do
    assert L10n.interpolate("%{a}/%{missing}", a: 1) == "1/%{missing}"
    assert L10n.interpolate("no placeholders", []) == "no placeholders"
    assert L10n.interpolate("%{a}", %{"a" => "x"}) == "x"
  end
end
