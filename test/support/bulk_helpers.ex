defmodule AshA2ui.Test.BulkHelpers do
  @moduledoc """
  Shared setup and envelope helpers for the bulk-action tests (A2UI-104).
  """

  alias AshA2ui.Test.{BulkProject, BulkTask}

  @actor %{id: "bulk-tester"}

  @doc "The actor the bulk tests write as (the fixture's writes need one)."
  def actor, do: @actor

  @doc "Deletes every BulkTask and BulkProject."
  def reset! do
    for resource <- [BulkTask, BulkProject] do
      resource |> Ash.read!(authorize?: false) |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    end

    :ok
  end

  @doc "Creates a project."
  def project!(name), do: Ash.create!(BulkProject, %{name: name}, authorize?: false)

  @doc "Creates a task (attributes merged over an open, visible, score-0 task)."
  def task!(title, attrs \\ %{}) do
    Ash.create!(BulkTask, Map.merge(%{title: title}, attrs), authorize?: false)
  end

  @doc "Re-reads a task bypassing policies."
  def reload!(task), do: Ash.get!(BulkTask, task.id, authorize?: false)

  @doc "Carried row maps: `selected` tasks have `\"_selected\" => true`."
  def rows(tasks, selected) do
    selected_ids = MapSet.new(selected, & &1.id)

    Enum.map(tasks, fn task ->
      %{
        "id" => task.id,
        "title" => task.title,
        "_selected" => MapSet.member?(selected_ids, task.id)
      }
    end)
  end

  @doc "A carried `/context` map selecting `project`."
  def contexts(project) do
    %{"project" => %{"search" => "", "value" => project.id, "label" => project.name}}
  end

  @doc "A v0.9.1 client action envelope."
  def envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "bulk_tasks",
        "sourceComponentId" => "bulk_toolbar",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  @doc "The value of the first updateDataModel write at `path`."
  def value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  @doc "Every updateDataModel path in `messages`, in order."
  def paths(messages) do
    for %{"updateDataModel" => %{"path" => path}} <- messages, do: path
  end
end
