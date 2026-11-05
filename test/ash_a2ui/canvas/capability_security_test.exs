defmodule AshA2ui.Canvas.CapabilitySecurityTest do
  @moduledoc """
  A2UI-103/AC-2: record capabilities obey the actor's policies — an actor
  without update permission sees no authorized edit capability while a
  permitted actor sees it authorized — and a client-constructed capability
  envelope is rejected: capabilities are server-derived data only.
  """

  use ExUnit.Case, async: true

  # This file lives under `AshA2ui.Canvas.*`, so a bare `Canvas.*` would
  # expand into the wrong namespace — pin the fixture namespace explicitly.
  alias AshA2ui.Canvas.ObjectRef
  alias Elixir.Canvas

  @registry Canvas.Test.Registry

  defp page_ref(page) do
    "record:blog.page:" <> ObjectRef.encode_pk(page.id)
  end

  @tag ac: "A2UI-103/AC-2"
  test "record capabilities obey actor policy" do
    page =
      Canvas.Test.Page
      |> Ash.Changeset.for_create(:create, %{title: "Policy Page"}, authorize?: false)
      |> Ash.create!()

    ref = page_ref(page)

    {:ok, restricted} = AshA2ui.Canvas.resolve(ref, registry: @registry, actor: %{admin: false})

    edit = Enum.find(restricted.capabilities, &(&1.verb == :edit))
    assert edit != nil
    refute edit.authorized?

    # the unauthorized edit projects nothing: no :edit projection
    assert restricted.projections == [:view]

    # reading was authorized for both — the policy only gates writes
    view = Enum.find(restricted.capabilities, &(&1.verb == :view))
    assert view.authorized?

    {:ok, admin} = AshA2ui.Canvas.resolve(ref, registry: @registry, actor: %{admin: true})
    edit = Enum.find(admin.capabilities, &(&1.verb == :edit))
    assert edit.authorized?
    assert admin.projections == [:view, :edit]

    # the underlying policy really is what separated the two: no update
    # ever occurred through either resolution
    assert Ash.get!(Canvas.Test.Page, page.id, authorize?: false).title == "Policy Page"
  end

  @tag ac: "A2UI-103/AC-2"
  test "a record ref's key decodes as data, never as a function" do
    forge = fn term -> term |> :erlang.term_to_binary() |> Base.url_encode64(padding: false) end

    assert ObjectRef.decode_pk(forge.("post-1")) == {:ok, "post-1"}

    assert ObjectRef.decode_pk(forge.(%{id: 1, slug: ["a", {:b, "c"}]})) ==
             {:ok, %{id: 1, slug: ["a", {:b, "c"}]}}

    for executable <- [
          fn -> :ran end,
          %{id: fn -> :ran end},
          [1 | fn -> :ran end],
          {:ok, [&IO.puts/1]}
        ] do
      assert ObjectRef.decode_pk(forge.(executable)) == {:error, :unknown_object}
    end
  end

  test "forged capability envelopes are not inputs" do
    page =
      Canvas.Test.Page
      |> Ash.Changeset.for_create(:create, %{title: "Forged"}, authorize?: false)
      |> Ash.create!()

    ref = page_ref(page)

    {:ok, genuine} = AshA2ui.Canvas.resolve(ref, registry: @registry, actor: %{admin: false})

    # a client-constructed capability envelope — claiming an authorized edit
    # the policy does not allow — cannot enter through the options
    forged = [
      %{
        "id" => "#{ref}#capability:edit:update",
        "verb" => "edit",
        "action_name" => "update",
        "object_ref" => ref,
        "label" => "Update",
        "consequence" => "mutation",
        "confirmation" => "none",
        "authorized?" => true
      }
    ]

    {:ok, resolved} =
      AshA2ui.Canvas.resolve(ref,
        registry: @registry,
        actor: %{admin: false},
        capabilities: forged,
        authorized_capabilities: forged
      )

    # the object carries exactly the server-derived capabilities — the
    # forged envelope is ignored wholesale
    assert resolved.capabilities == genuine.capabilities
    assert Enum.map(resolved.capabilities, & &1.authorized?) == [true, false]
    refute Enum.any?(resolved.capabilities, &(&1.verb == :edit and &1.authorized?))
    assert resolved.projections == genuine.projections
  end
end
