defmodule AshA2ui.ColumnCaptionSortTest do
  @moduledoc """
  Catalog 1.11 on a `:table`: a badge's per-value tooltip (`badge_help`), a
  column's third line (`caption` + `caption_text`), a column's first sort
  direction (`sort_first`) and a query whose headers return to the default
  order on a third click (`sort_reset`).
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Test.CaptionedTask

  setup do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
    :ok
  end

  defp surface(resource) do
    [_create, components, data] = AshA2ui.Info.build_surface(resource, authorize?: false)
    by_id = Map.new(components["updateComponents"]["components"], &{&1["id"], &1})
    {by_id, data["updateDataModel"]["value"]}
  end

  defp columns(components),
    do: Map.new(components["data_grid"]["columns"], &{&1["path"], &1})

  test "the badge binds its help, the title its caption, the due date its first direction" do
    {components, _data} = surface(CaptionedTask)
    columns = columns(components)

    assert columns["status"]["badge"] == %{
             "path" => "_badge_status",
             "tonePath" => "_badge_tone_status",
             "helpPath" => "_badge_help_status"
           }

    assert columns["title"]["caption"] == %{"path" => "created_on", "text" => "Created {date}"}
    assert columns["title"]["subtitle"] == %{"path" => "assignee_name"}

    # The caption field rides in the row, not as a column of its own.
    refute Map.has_key?(columns, "created_on")
    refute Map.has_key?(columns, "assignee_name")

    assert %{"sortable" => true, "sortFirst" => "desc"} = columns["due_on"]
    assert %{"sortable" => true} = columns["title"]
    refute Map.has_key?(columns["title"], "sortFirst")
  end

  test "the grid's sort says it resets on a third click" do
    {components, _data} = surface(CaptionedTask)
    assert %{"reset" => true, "path" => "/query/sort"} = components["data_grid"]["sort"]
  end

  test "a query without sort_reset keeps toggling" do
    {components, _data} = surface(AshA2ui.Test.Paginated)
    refute Map.has_key?(components["data_grid"]["sort"] || %{}, "reset")
  end

  test "rows carry the badge's help per value, \"\" when it has none" do
    Ash.create!(
      CaptionedTask,
      %{title: "Fix the roof", status: :done, created_on: ~D[2026-10-13]},
      authorize?: false
    )

    {_components, data} = surface(CaptionedTask)
    [row] = data["records"]

    assert %{
             "_badge_status" => "Done",
             "_badge_tone_status" => "success",
             "_badge_help_status" => "Finished and checked",
             "created_on" => "2026-10-13"
           } = row

    layout = %AshA2ui.RowLayout{title: :title, badge: :status, badge_help: [open: "Still to do"]}
    assert AshA2ui.RowLayout.badge_data(layout, %{status: :done})["_badge_help_status"] == ""
    assert AshA2ui.RowLayout.badge_data(layout, %{status: nil})["_badge_help_status"] == ""
  end

  test "without badge_help a row carries no help key" do
    layout = %AshA2ui.RowLayout{title: :title, badge: :status}

    refute Map.has_key?(
             AshA2ui.RowLayout.badge_data(layout, %{status: :open}),
             "_badge_help_status"
           )
  end
end
