defmodule AshA2ui.Adoption.AdminRowActionsTest do
  @moduledoc """
  The admin composition's row actions (catalog `:admin_v1`), as clinic-demo
  found them broken:

    * a prompt row action (`prompt_fields`) had nothing to collect its
      values — the grid dispatched `invoke` with the empty
      `/prompt/values/<action>` and failed validation;
    * every row action showed on every row, ignoring `visible_when` (the
      basic composition hides them per row through `_visible_<action>`).

  The renderer half (the prompt dialog, per-row hiding, the View panel's
  close control) is driven in a browser by
  `priv/js/probe/admin_rows_probe.mjs`.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Adoption.{Job, JobsUI}

  @red %{id: "u-red", team: "red"}

  setup do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)

    Job
    |> Ash.read!(actor: @red, authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false))

    open = Ash.create!(Job, %{title: "Open job", team: "red"}, authorize?: false)

    claimed =
      Ash.create!(Job, %{title: "Claimed job", team: "red", status: :claimed}, authorize?: false)

    %{open: open, claimed: claimed}
  end

  defp surface do
    [_create, components, data] = AshA2ui.Info.build_surface(JobsUI, actor: @red)
    by_id = Map.new(components["updateComponents"]["components"], &{&1["id"], &1})
    {by_id, data["updateDataModel"]["value"]}
  end

  defp entry(grid, action) do
    Enum.find(grid["rowActions"], &(&1["context"]["action"] == action))
  end

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "adoption_jobs",
        "sourceComponentId" => "data_grid",
        "timestamp" => "2026-10-16T00:00:00Z",
        "context" => context
      }
    }
  end

  # Resolves a rowActions context against one row and the data model, the
  # way the DataGrid does: row-relative refs against the row, absolute refs
  # against the data model.
  defp resolve(context, row, data) do
    Map.new(context, fn
      {key, %{"path" => "/" <> _ = path}} -> {key, get_in(data, path_keys(path))}
      {key, %{"path" => path}} -> {key, get_in(row, path_keys(path))}
      {key, value} -> {key, value}
    end)
  end

  defp path_keys(path), do: path |> String.trim_leading("/") |> String.split("/")

  test "a visible_when row action names the row-relative path that hides it" do
    {by_id, data} = surface()
    grid = by_id["data_grid"]

    assert entry(grid, "claim")["visiblePath"] == "_visible_claim"
    refute Map.has_key?(entry(grid, "lock"), "visiblePath")

    rows = Map.new(data["records"], &{&1["title"], &1})
    assert rows["Open job"]["_visible_claim"] != []
    assert rows["Claimed job"]["_visible_claim"] == []
  end

  test "a prompt row action carries a prompt whose inputs bind its values" do
    {by_id, _data} = surface()
    grid = by_id["data_grid"]
    annotate = entry(grid, "annotate")

    assert %{"content" => content, "title" => "Annotate", "open" => open} = annotate["prompt"]

    assert open == %{
             "action" => "prompt",
             "context" => %{
               "action" => "annotate",
               "recordId" => %{"path" => "id"},
               "component" => "table"
             }
           }

    assert content in grid["children"]
    assert by_id[content]["component"] == "Column"

    bound =
      for id <- by_id[content]["children"],
          %{"value" => %{"path" => path}} <- [by_id[id]],
          do: path

    assert "/prompt/values/annotate/note" in bound
  end

  test "values typed into the prompt reach the action", %{open: open} do
    {by_id, data} = surface()
    annotate = entry(by_id["data_grid"], "annotate")
    row = Enum.find(data["records"], &(&1["id"] == open.id))

    {:ok, _prefill} =
      ActionHandler.handle(
        JobsUI,
        envelope("prompt", resolve(annotate["prompt"]["open"]["context"], row, data)),
        actor: @red
      )

    data = put_in(data, ["prompt", "values", "annotate", "note"], "Called the owner")
    context = resolve(annotate["context"], row, data)

    assert {:ok, _messages} =
             ActionHandler.handle(JobsUI, envelope("invoke", context), actor: @red)

    assert Ash.get!(Job, open.id, actor: @red).note == "Called the owner"
  end

  test "the grid validates against the admin catalog definition" do
    {by_id, _data} = surface()
    catalog = "priv/a2ui/admin_v1/catalog.json" |> File.read!() |> Jason.decode!()

    schema =
      catalog["components"]["dataGrid"]
      |> Map.put("$defs", catalog["$defs"] || %{})
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.validate(schema, by_id["data_grid"]) == :ok
  end
end
