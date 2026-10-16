defmodule AshA2ui.Adoption.BoardSelectContextTest do
  @moduledoc """
  `select_context` on a `display :board` table: every card gets the same
  per-row "Select <context>" control a list table's rows get, dispatching
  `context_select` with the card's id, so a board can open a detail
  instead of deep-linking away (ash_enterprise's ImportBatch board). The
  sections verifier used to refuse `select_context` on every sectioned
  table; boards are now allowed, list-mode sections still are not.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper
  import ExUnit.CaptureIO

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Adoption.{Job, SelectBoardUI}

  @red %{id: "u-red", team: "red"}

  setup do
    Job |> Ash.read!(actor: @red) |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    %{job: Ash.create!(Job, %{title: "Open job", team: "red"}, authorize?: false)}
  end

  defp compile_ui(display) do
    name = "AshA2ui.Adoption.BoardSelectContextTest.Ui#{System.unique_integer([:positive])}"

    capture_io(:stderr, fn ->
      Code.compile_string("""
      defmodule #{name} do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Adoption.Job

          context :job do
            resource AshA2ui.Test.Adoption.Job
            option_label :title
            picker false
          end

          component :table, :board do
            fields [:title]
            display #{inspect(display)}
            select_context :job

            row_layout do
              title :title
            end

            sections do
              scope_by :status
            end
          end
        end
      end
      """)
    end)
  end

  test "the verifier accepts select_context on a board" do
    refute compile_ui(:board) =~ "select_context"
  end

  test "the verifier still refuses select_context on list-mode sections" do
    assert compile_ui(:list) =~ "cannot combine a sections block with select_context"
  end

  test "every card carries the select control", %{job: job} do
    messages = AshA2ui.Info.build_surface(SelectBoardUI, actor: @red)
    Enum.each(messages, &assert_valid_server_message/1)
    [_create, components, data] = messages
    by_id = Map.new(components["updateComponents"]["components"], &{&1["id"], &1})

    for lane <- ["board_open", "board_claimed"] do
      button = by_id["row_context_#{lane}_button"]
      assert button["component"] == "Button"
      assert by_id["row_context_#{lane}_text"]["text"] == "Select job"
      assert button["action"]["event"]["name"] == "context_select"
      assert button["action"]["event"]["context"]["context"] == "job"
      assert button["action"]["event"]["context"]["value"] == %{"path" => "id"}
    end

    assert [%{"id" => id}] = data["updateDataModel"]["value"]["records"]["board_open"]
    assert id == job.id
  end

  test "selecting a card fills the detail", %{job: job} do
    envelope = %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "context_select",
        "surfaceId" => "adoption_select_board",
        "sourceComponentId" => "row_context_board_open_button",
        "timestamp" => "2026-10-16T00:00:00Z",
        "context" => %{"context" => "job", "value" => job.id}
      }
    }

    assert {:ok, messages} = ActionHandler.handle(SelectBoardUI, envelope, actor: @red)

    detail =
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => "/detail/job", "value" => value}} -> value
        _other -> nil
      end)

    assert detail["title"] == "Open job"
    assert detail["status"] == "open"
  end
end
