defmodule AshA2ui.Canvas.RegistryConsequenceTest do
  @moduledoc """
  A host can say what running an action does, within the vocabulary.

  A capability's consequence was derived from the action's type alone: a
  destroy is `:destructive`, a read is `:read`, and everything else, generic
  actions included, is a `:mutation`. A generic action that only reads is then
  shown as a change, and one that removes data or reaches outside is not
  confirmed. The optional `consequence/3` callback lets a host answer from its
  own declaration of what each action does.

  Without the callback, or with `nil`, nothing changes. An answer outside
  `:read`, `:mutation` and `:destructive` keeps the derived consequence, so an
  unrecognised answer never lightens a destroy into something unconfirmed.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Canvas.ObjectRef
  alias Elixir.Canvas

  @base Canvas.Test.Registry
  @resource_ref "resource:blog.post"

  defmodule Declares do
    @moduledoc false
    @behaviour AshA2ui.Canvas.Registry

    @impl true
    def domains, do: Canvas.Test.Registry.domains()

    @impl true
    def consequence(Canvas.Test.Post, :publish_summary, _derived), do: :destructive
    def consequence(_resource, _action, _derived), do: nil
  end

  defmodule ReadsOnly do
    @moduledoc false
    @behaviour AshA2ui.Canvas.Registry

    @impl true
    def domains, do: Canvas.Test.Registry.domains()

    @impl true
    def consequence(Canvas.Test.Post, :publish_summary, _derived), do: :read
    def consequence(_resource, _action, _derived), do: nil
  end

  defmodule SaysNothing do
    @moduledoc false
    @behaviour AshA2ui.Canvas.Registry

    @impl true
    def domains, do: Canvas.Test.Registry.domains()

    @impl true
    def consequence(_resource, _action, _derived), do: nil
  end

  defmodule UnknownAnswer do
    @moduledoc false
    @behaviour AshA2ui.Canvas.Registry

    @impl true
    def domains, do: Canvas.Test.Registry.domains()

    @impl true
    def consequence(_resource, _action, _derived), do: :harmless
  end

  defmodule StringAnswer do
    @moduledoc false
    @behaviour AshA2ui.Canvas.Registry

    @impl true
    def domains, do: Canvas.Test.Registry.domains()

    @impl true
    def consequence(_resource, _action, _derived), do: "read"
  end

  defmodule Raises do
    @moduledoc false
    @behaviour AshA2ui.Canvas.Registry

    @impl true
    def domains, do: Canvas.Test.Registry.domains()

    @impl true
    def consequence(_resource, _action, _derived), do: raise("declaration unavailable")
  end

  defp capability(object, verb, action) do
    Enum.find(object.capabilities, &(&1.verb == verb and &1.action_name == action))
  end

  defp summary(object),
    do: Enum.map(object.capabilities, &{&1.id, &1.consequence, &1.confirmation})

  defp record_ref do
    post =
      Canvas.Test.Post
      |> Ash.Changeset.for_create(:create, %{name: "Clinic hours"})
      |> Ash.create!()

    "record:blog.post:" <> ObjectRef.encode_pk(post.id)
  end

  test "without the callback the derived consequences stand" do
    {:ok, object} = AshA2ui.Canvas.resolve(@resource_ref, registry: @base)

    assert %{consequence: :destructive, confirmation: :required} =
             capability(object, :destroy, "destroy")

    assert %{consequence: :mutation, confirmation: :none} =
             capability(object, :act, "publish_summary")

    assert %{consequence: :read} = capability(object, :view, "read")
  end

  test "a declared consequence replaces the derived one, and drives confirmation" do
    {:ok, object} = AshA2ui.Canvas.resolve(@resource_ref, registry: Declares)

    assert %{consequence: :destructive, confirmation: :required} =
             capability(object, :act, "publish_summary")

    # nil for the others: the derived consequences are untouched
    assert %{consequence: :destructive, confirmation: :required} =
             capability(object, :destroy, "destroy")
  end

  test "a generic action declared read-only is shown as a read" do
    {:ok, object} = AshA2ui.Canvas.resolve(@resource_ref, registry: ReadsOnly)

    assert %{consequence: :read, confirmation: :none} =
             capability(object, :act, "publish_summary")
  end

  test "record capabilities take the declared consequence too" do
    ref = record_ref()
    {:ok, object} = AshA2ui.Canvas.resolve(ref, registry: Declares)

    assert %{consequence: :destructive, confirmation: :required} =
             capability(object, :act, "publish_summary")

    assert %{consequence: :mutation} = capability(object, :edit, "update")
  end

  test "returning nil means the same as not implementing it" do
    ref = record_ref()

    for target <- [@resource_ref, ref] do
      {:ok, base} = AshA2ui.Canvas.resolve(target, registry: @base)
      {:ok, object} = AshA2ui.Canvas.resolve(target, registry: SaysNothing)

      assert summary(object) == summary(base)
    end
  end

  test "an answer outside the vocabulary keeps the derived consequence" do
    ref = record_ref()

    for registry <- [UnknownAnswer, StringAnswer], target <- [@resource_ref, ref] do
      {:ok, base} = AshA2ui.Canvas.resolve(target, registry: @base)
      {:ok, object} = AshA2ui.Canvas.resolve(target, registry: registry)

      assert summary(object) == summary(base)
    end

    # the destroy is still confirmed: an unknown answer is never a lighter one
    {:ok, object} = AshA2ui.Canvas.resolve(@resource_ref, registry: UnknownAnswer)

    assert %{consequence: :destructive, confirmation: :required} =
             capability(object, :destroy, "destroy")
  end

  test "a callback that raises yields no capabilities at all" do
    assert_raise RuntimeError, "declaration unavailable", fn ->
      AshA2ui.Canvas.resolve(@resource_ref, registry: Raises)
    end
  end
end
