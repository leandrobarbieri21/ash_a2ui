defmodule AshA2ui.V10ContractFixturesTest do
  @moduledoc """
  Hand-written spec-HEAD payloads for the four surface shapes the library
  emits most (a paginated table, a form with checks, a board of templated
  lanes and cards using `@index`, a multi-step wizard), in
  test/fixtures/v1_0_contract. They are the reference the 1.0 encoder is
  written against and the input of the renderer probe. Their Buttons call
  the ash_a2ui catalog's `ashAction`, as every control the encoder emits
  does. Each must stay a valid agent-to-renderer message list under the
  basic and ash_a2ui catalogs.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Test.Messages

  @dir Path.expand("fixtures/v1_0_contract", __DIR__)

  for name <- ~w(table form board wizard) do
    test "#{name}.json is a valid 1.0 message list" do
      messages = @dir |> Path.join(unquote(name) <> ".json") |> File.read!() |> Jason.decode!()

      assert [%{"createSurface" => _} | _] = messages
      assert_valid_agent_messages(messages, catalogs: Messages.catalogs())
      Enum.each(messages, &assert_valid_agent_message(&1, catalogs: Messages.catalogs()))
    end
  end
end
