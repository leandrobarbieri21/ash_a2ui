defmodule AshA2ui.Experience.SurfaceNamingTest do
  @moduledoc """
  A surface's heading is what the page is a page *of*, and the derived name
  cannot always supply it.

  Before `title`, every heading was the humanized module short name. That is
  singular where the page is a list, and it is named after a module rather than
  after the thing: a strangler read model over another application's estate is
  `Legacy.User`, so its page was headed "User" — which reads as *this*
  application's users, and is the one reading that is definitely wrong.

  `title` and `record_label` are separate on purpose. They are different words
  in the same surface: the heading is a collection ("Legacy users"), and the
  task labels take a singular ("Create legacy user"). Collapsing them into one
  option would force one of the two to be ungrammatical.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Experience
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Experience.EstateUser
  alias AshA2ui.Test.Experience.Task

  setup do
    # The heading lives on the admin catalog's `entityPage` root, so the
    # catalog has to be on for the encoder assertions to have anything to read.
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
    end)

    :ok
  end

  defp view!(resource), do: ResolvedView.resolve(resource, [])

  defp root_title!(resource) do
    [_create, components, _data] = AshA2ui.Info.build_surface(resource, actor: nil)

    components["updateComponents"]["components"]
    |> Enum.find(&(&1["component"] == "entityPage"))
    |> Map.fetch!("title")
  end

  describe "a surface that declares neither" do
    test "still derives both from the resource, exactly as before" do
      view = view!(Task)

      assert Experience.surface_title(view) == "Task"
      assert Experience.resource_label(view) == "Task"
      assert Experience.create_label(view) == "Create Task"
    end

    test "the page heading is the derived label" do
      assert root_title!(Task) == "Task"
    end
  end

  describe "a surface that declares its own words" do
    test "the heading is the declared title, not the module's short name" do
      assert root_title!(EstateUser) == "Legacy users"
    end

    test "task labels take the singular record_label" do
      view = view!(EstateUser)

      assert Experience.create_label(view) == "Create legacy user"
      assert Experience.panel_title(:edit, view) == "Edit legacy user"
      assert Experience.panel_title(:view, view) == "View legacy user"
    end

    test "the empty state speaks the record_label too" do
      view = view!(EstateUser)
      [table] = view.tables

      assert Experience.empty_message(view, table) == "No legacy user records yet."
    end

    test "title and record_label are genuinely independent" do
      view = view!(EstateUser)

      # The whole reason for two options: the heading is plural and the task
      # label is singular, so one string could not have served both.
      refute Experience.surface_title(view) == Experience.resource_label(view)
    end
  end

  describe "degenerate declarations" do
    test "an empty string is treated as absent rather than as a blank heading" do
      # A heading is not something a surface can opt out of -- falling back is
      # the only behaviour that leaves the page readable.
      view = %{view!(Task) | title: "", record_label: ""}

      assert Experience.surface_title(view) == "Task"
      assert Experience.resource_label(view) == "Task"
    end
  end
end
