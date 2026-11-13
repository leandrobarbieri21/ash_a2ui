defmodule AshA2ui.Wave6ActionHandlerTest do
  @moduledoc """
  Refresh-path tests for Wave 6: rows rewritten by `AshA2ui.ActionHandler`
  after an action succeeds carry the same `_badge_<field>` display text the
  encoder serializes on initial render.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Messages
  alias AshA2ui.Test.Promotion

  setup do
    on_exit(fn -> Ets.stop(Promotion) end)
    :ok
  end

  defp envelope(name, context) do
    Messages.call(name, "promotions", context)
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _ -> nil
    end)
  end

  test "success refreshes carry the badge display text" do
    Ash.create!(Promotion, %{name: "Dormant", is_active: false}, authorize?: false)

    env =
      envelope("submit_form", %{
        "values" => %{"name" => "Spring Sale", "is_active" => true}
      })

    assert {:ok, messages} = ActionHandler.handle(Promotion, env)
    Enum.each(messages, &assert_valid_agent_message/1)

    rows = value_at(messages, "/records")

    assert Enum.map(rows, &{&1["name"], &1["_badge_is_active"]}) |> Enum.sort() ==
             [{"Dormant", "Inactive"}, {"Spring Sale", "Active"}]
  end
end
