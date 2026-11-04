defmodule AshA2ui.L10n.GoldenTest do
  @moduledoc """
  Protocol goldens for localization (ADR 0060): the initial build, a
  refresh, option lists and action feedback, on v0.9.1 and v1.0, with the
  basic and the admin catalog. The payloads were captured on the base the
  localization work started from (e6af377), so without a translator the
  output stays byte-identical to it.

  Re-record (only on purpose) with
  `RECORD_L10N_GOLDEN=1 mix test test/ash_a2ui/l10n/golden_test.exs`.
  """

  # async: false — the admin-catalog cases flip the global :ash_a2ui
  # :catalog application env.
  use ExUnit.Case, async: false

  alias AshA2ui.Test.L10nScenarios

  @golden_dir Path.expand("golden", __DIR__)

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :catalog) end)
    :ok
  end

  for name <- L10nScenarios.scenario_names() do
    @scenario_name name
    test "golden #{name}" do
      assert_golden(
        @scenario_name,
        L10nScenarios.run(L10nScenarios.scenario(@scenario_name), [])
      )
    end
  end

  defp assert_golden(name, json) do
    path = Path.join(@golden_dir, "#{name}.json")

    if System.get_env("RECORD_L10N_GOLDEN") do
      File.mkdir_p!(@golden_dir)
      File.write!(path, json)
    end

    assert json == File.read!(path), "#{name} differs from its golden"
  end
end
