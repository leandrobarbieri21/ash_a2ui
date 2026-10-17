defmodule AshA2ui.Adoption.ActorReadsTest do
  @moduledoc """
  Every read a surface makes carries the actor, tenant and `authorize?` it
  was built with — including the query builder's own preparations, which
  run when the query is built (`Ash.Query.for_read/4`), not when it is
  read. A read action whose preparation scopes rows to the actor (clinic's
  worklist) used to see nobody on the first read of a query-less table, on
  the option lists of relationship selects, and on a sections source read.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Adoption.{Clerk, Job, JobsUI, Queue, QueuedJobsUI}

  @red %{id: "u-red", team: "red"}

  setup do
    for resource <- [Job, Clerk, Queue] do
      resource
      |> Ash.read!(authorize?: false, actor: %{team: "red"})
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))

      resource
      |> Ash.read!(authorize?: false, actor: %{team: "blue"})
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    end

    Ash.create!(Clerk, %{name: "Rhea", team: "red"}, authorize?: false)
    Ash.create!(Clerk, %{name: "Rex", team: "red", org: "globex"}, authorize?: false)
    Ash.create!(Clerk, %{name: "Bea", team: "blue"}, authorize?: false)

    inbox = Ash.create!(Queue, %{name: "Inbox", team: "red"}, authorize?: false)
    Ash.create!(Queue, %{name: "Other team", team: "blue"}, authorize?: false)

    job =
      Ash.create!(Job, %{title: "Red job", team: "red", queue_id: inbox.id}, authorize?: false)

    Ash.create!(Job, %{title: "Globex job", team: "red", org: "globex"}, authorize?: false)
    Ash.create!(Job, %{title: "Blue job", team: "blue"}, authorize?: false)

    %{job: job, inbox: inbox}
  end

  defp root(messages) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
      _other -> nil
    end)
  end

  defp titles(rows), do: rows |> Enum.map(& &1["title"]) |> Enum.sort()

  test "a query-less table's first read carries the actor and tenant" do
    data = JobsUI |> AshA2ui.Info.build_surface(actor: @red, tenant: "acme") |> root()

    assert titles(data["records"]) == ["Red job"]
  end

  test "the actor alone scopes the first read (no tenant)" do
    data = JobsUI |> AshA2ui.Info.build_surface(actor: @red) |> root()

    assert titles(data["records"]) == ["Globex job", "Red job"]
  end

  test "nobody acting reads nothing" do
    data = JobsUI |> AshA2ui.Info.build_surface() |> root()

    assert data["records"] == []
  end

  test "build_data_model reads as the actor too" do
    %{"updateDataModel" => %{"value" => data}} =
      AshA2ui.Info.build_data_model(JobsUI, actor: @red, tenant: "acme")

    assert titles(data["records"]) == ["Red job"]
  end

  test "relationship select option lists read as the actor and tenant" do
    data = JobsUI |> AshA2ui.Info.build_surface(actor: @red, tenant: "acme") |> root()

    assert Enum.map(data["options"]["clerk_id"], & &1["label"]) == ["Rhea"]
  end

  test "a sections source read carries the actor and tenant", %{inbox: inbox} do
    messages = AshA2ui.Info.build_surface(QueuedJobsUI, actor: @red, tenant: "acme")
    data = root(messages)

    lane = AshA2ui.Sections.section_name(:per_queue, inbox.id)
    assert Map.keys(data["records"]) == [lane]
    assert titles(data["records"][lane]) == ["Red job"]
  end

  test "an action's refresh read carries the actor and tenant", %{job: job} do
    envelope = %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "invoke",
        "surfaceId" => "adoption_jobs",
        "sourceComponentId" => "test",
        "timestamp" => "2026-10-16T00:00:00Z",
        "context" => %{"action" => "claim", "recordId" => job.id}
      }
    }

    assert {:ok, messages} = ActionHandler.handle(JobsUI, envelope, actor: @red, tenant: "acme")

    records =
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => "/records", "value" => value}} -> value
        _other -> nil
      end)

    assert titles(records) == ["Red job"]
  end
end
