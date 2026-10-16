defmodule AshA2ui.Canvas.ObjectResolverTest do
  @moduledoc """
  A2UI-103/AC-1 + AC-5: structural objects resolve to labeled Objects with
  provenance, presence-derived capabilities, and derived projections; record
  refs resolve through an authorized read and carry the record's display
  identity with record-scoped capabilities.
  """

  use ExUnit.Case, async: true

  # This file lives under `AshA2ui.Canvas.*`, so a bare `Canvas.*` would
  # expand into the wrong namespace — pin the fixture namespace explicitly.
  alias Elixir.Canvas

  alias AshA2ui.Canvas.ObjectRef

  @registry Canvas.Test.Registry

  describe "structural objects" do
    @tag ac: "A2UI-103/AC-1"
    test "resolves structural objects with derived projections" do
      actor = %{admin: true}
      tenant = "tenant-#{System.unique_integer([:positive])}"
      opts = [registry: @registry, actor: actor, tenant: tenant]

      {:ok, app} = AshA2ui.Canvas.resolve("application:registry", opts)
      assert app.ref == %ObjectRef{id: "application:registry", kind: :application}
      assert app.label == "Canvas Test App"
      assert app.projections == [:browse]
      assert app.capabilities == []
      assert app.provenance == %{registry: @registry}

      {:ok, domain} = AshA2ui.Canvas.resolve("domain:blog", opts)
      assert domain.label == "Blog"
      assert domain.projections == [:browse]
      assert domain.provenance == %{domain: Canvas.Test.Blog}

      {:ok, resource} = AshA2ui.Canvas.resolve("resource:blog.post", opts)
      assert resource.ref == %ObjectRef{id: "resource:blog.post", kind: :resource}
      assert resource.label == "Posts"
      assert resource.provenance == %{domain: Canvas.Test.Blog, resource: Canvas.Test.Post}

      # presence-derived capabilities: every declared action, authorized? by
      # presence — execution still goes through the authorized action paths
      verbs = Enum.map(resource.capabilities, &{&1.verb, &1.action_name, &1.authorized?})
      assert {:create, "create", true} in verbs
      assert {:edit, "update", true} in verbs
      assert {:destroy, "destroy", true} in verbs
      assert {:view, "read", true} in verbs
      assert {:act, "publish_summary", true} in verbs

      # consequences and confirmations follow the contract
      destroy = Enum.find(resource.capabilities, &(&1.verb == :destroy))
      assert destroy.consequence == :destructive
      assert destroy.confirmation == :required

      create = Enum.find(resource.capabilities, &(&1.verb == :create))
      assert create.consequence == :mutation
      assert create.confirmation == :none

      # derived projections: inspect/browse always, create/edit by presence
      assert resource.projections == [:inspect, :browse, :create, :edit]
    end

    @tag ac: "A2UI-103/AC-1"
    test "a create-only resource projects no edit" do
      {:ok, product} =
        AshA2ui.Canvas.resolve("resource:catalog.product", registry: @registry, actor: nil)

      refute :edit in product.projections
      assert :create in product.projections
    end
  end

  describe "record objects" do
    @tag ac: "A2UI-103/AC-5"
    test "record refs resolve through authorized reads" do
      name = "Record #{System.unique_integer([:positive])}"
      post = Ash.create!(Canvas.Test.Post, %{name: name}, authorize?: false)

      ref = "record:blog.post:" <> ObjectRef.encode_pk(post.id)

      {:ok, object} =
        AshA2ui.Canvas.resolve(ref,
          registry: @registry,
          actor: %{admin: true},
          tenant: nil
        )

      # the record's display identity is the label
      assert object.label == name
      assert object.ref == %ObjectRef{id: ref, kind: :record}

      # record-scoped capabilities derived through Ash.can? for the actor
      assert Enum.all?(object.capabilities, & &1.authorized?)
      assert Enum.map(object.capabilities, & &1.verb) == [:view, :edit, :act]
      assert object.projections == [:view, :edit, :act]

      # provenance carries the record itself (server-side truth)
      assert object.provenance.record.id == post.id

      # an unreadable record (bad pk) does not exist for the actor
      assert AshA2ui.Canvas.resolve("record:blog.post:" <> ObjectRef.encode_pk("no-such-id"),
               registry: @registry,
               actor: %{admin: true}
             ) == {:error, :unknown_object}
    end
  end
end
