defmodule AshA2ui.Canvas.ProgressiveDisclosureTest do
  @moduledoc """
  A2UI-103/AC-4: the graph is the *declared* world, not the database. A
  table full of records contributes nothing to a graph build or a
  structural resolution — proven with a telemetry handler that counts every
  Ash read in the VM, not just by inspecting the output shape.
  """

  use ExUnit.Case, async: false

  # This file lives under `AshA2ui.Canvas.*`, so a bare `Canvas.*` would
  # expand into the wrong namespace — pin the fixture namespace explicitly.
  alias Ash.Domain.Info, as: DomainInfo
  alias AshA2ui.Canvas.ObjectRef
  alias Elixir.Canvas

  @registry Canvas.Test.Registry

  @tag ac: "A2UI-103/AC-4"
  test "does not materialize the database as a graph" do
    # records exist in the table before anything canvas-shaped runs
    for i <- 1..3 do
      Ash.create!(
        Canvas.Test.Post,
        %{name: "Disclosed #{System.unique_integer([:positive])}-#{i}"},
        authorize?: false
      )
    end

    # count every Ash read span in the VM — `[:ash, <domain>, :read, :start]`.
    # This catches reads through ANY path (queries, Ash.get, aggregations),
    # regardless of data layer.
    counters = :counters.new(2, [:atomics])

    # Handlers must never raise: telemetry DETACHES a handler that fails,
    # which would silently blind the proof. The read span is
    # [:ash, <domain_short>, :read] — one attach per fixture domain short
    # name (telemetry matches exact event names, not prefixes).
    read_events =
      Enum.flat_map(Canvas.Test.Registry.domains(), fn domain ->
        short = domain |> DomainInfo.short_name() |> Atom.to_string()
        [[:ash, String.to_existing_atom(short), :read, :start]]
      end)

    handler = fn _event, _measurements, _metadata, counters ->
      :counters.add(counters, 1, 1)
    end

    :ok = :telemetry.attach_many("canvas-zero-reads", read_events, handler, counters)

    try do
      graph = AshA2ui.Canvas.build_graph(@registry)

      {:ok, _application} =
        AshA2ui.Canvas.resolve("application:registry", registry: @registry, actor: %{admin: true})

      {:ok, _domain} =
        AshA2ui.Canvas.resolve("domain:blog", registry: @registry, actor: %{admin: true})

      {:ok, _resource} =
        AshA2ui.Canvas.resolve("resource:blog.post", registry: @registry, actor: %{admin: true})

      # zero reads: the graph and the structural objects are declared
      # metadata, not queries
      assert :counters.get(counters, 1) == 0

      # and structurally: no record is a node — the collection is declared
      # as lens data only
      refute Enum.any?(Map.keys(graph.nodes), &String.starts_with?(&1, "record:"))
      refute Enum.any?(graph.edges, &String.starts_with?(&1.from, "record:"))
      refute Enum.any?(graph.edges, &String.starts_with?(&1.to, "record:"))
    after
      :telemetry.detach("canvas-zero-reads")
    end

    # the instrument is not just broken at zero: the SAME counter lights up
    # the moment a record ref resolves through its authorized read
    post =
      Canvas.Test.Post
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.read!()
      |> List.last()

    ref = "record:blog.post:" <> ObjectRef.encode_pk(post.id)

    :ok = :telemetry.attach_many("canvas-zero-reads", read_events, handler, counters)

    try do
      {:ok, _record_object} =
        AshA2ui.Canvas.resolve(ref, registry: @registry, actor: %{admin: true})

      assert :counters.get(counters, 1) >= 1
    after
      :telemetry.detach("canvas-zero-reads")
    end
  end
end
