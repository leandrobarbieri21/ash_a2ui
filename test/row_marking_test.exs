defmodule AshA2ui.RowMarkingTest do
  @moduledoc """
  The basic catalog marks each record's card with `data-a2ui-row-id` and each
  row action control with `data-a2ui-action` (see `AshA2ui.Manifest`). The
  client decides which element is the card from the component id alone, so
  every layout the encoder composes must name its card body the way the
  client's pattern expects: flat rows (`record_row<sfx>_content`), card rows
  and board cards (`record_row<sfx>_body`).
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Test.{BoardTask, BoardTaskUI, BulkCardsUI, BulkTask, Promotion}

  @catalog_js Path.expand("../priv/js/ash_a2ui_catalog.js", __DIR__)
  @external_resource @catalog_js

  # The client's pattern, read from the catalog source so the two cannot drift.
  @row_pattern (fn ->
                  [_, source] =
                    Regex.run(~r|const RECORD_ROW_CONTENT = /(.+)/;|, File.read!(@catalog_js))

                  Regex.compile!(source)
                end).()

  @action_pattern ~r/(^|_)row_action_.*_button$/

  defp components(messages) do
    messages
    |> Enum.flat_map(&(get_in(&1, ["updateComponents", "components"]) || []))
    |> Map.new(&{&1["id"], &1})
  end

  defp marked(components), do: Enum.filter(Map.keys(components), &Regex.match?(@row_pattern, &1))

  defp action_names(components) do
    for {id, %{"component" => "Button"} = button} <- components,
        Regex.match?(@action_pattern, id),
        not String.ends_with?(id, "_confirm_button"),
        do: get_in(button, ["action", "event", "context", "action"])
  end

  describe "card rows with bulk actions" do
    setup do
      for title <- ["a", "b"], do: Ash.create!(BulkTask, %{title: title}, authorize?: false)
      :ok
    end

    test "each table's card body is the element the client marks" do
      components = components(AshA2ui.Info.build_surface(BulkCardsUI, authorize?: false))

      assert Enum.sort(marked(components)) == [
               "record_row_everything_content",
               "record_row_inbox_body"
             ]

      assert components["record_row_inbox_body"]["component"] == "Column"
      assert components["record_row_inbox"]["child"] == "record_row_inbox_body"
      assert components["record_row_everything_content"]["component"] == "Row"
    end

    test "the bulk checkbox rides inside the marked card" do
      components = components(AshA2ui.Info.build_surface(BulkCardsUI, authorize?: false))

      assert "record_row_inbox_selected" in components["record_row_inbox_header"]["children"]
      assert components["record_row_inbox_body"]["children"] |> hd() == "record_row_inbox_header"
    end
  end

  describe "board cards" do
    setup do
      for {name, status} <- [{"one", :open}, {"two", :claimed}] do
        Ash.create!(BoardTask, %{name: name, status: status}, authorize?: false)
      end

      :ok
    end

    test "every lane's card body is marked, and row actions name their action" do
      components = components(AshA2ui.Info.build_surface(BoardTaskUI, authorize?: false))

      assert [_ | _] = bodies = marked(components)
      assert Enum.all?(bodies, &(components[&1]["component"] == "Column"))
      assert Enum.all?(bodies, &String.ends_with?(&1, "_body"))

      assert Enum.sort(Enum.uniq(action_names(components))) == ["claim", "complete"]
    end
  end

  test "plain card rows keep the marked body and name their row actions" do
    components = components(AshA2ui.Info.build_surface(Promotion, authorize?: false))

    assert marked(components) == ["record_row_body"]
    assert Enum.all?(action_names(components), &is_binary/1)
  end
end
