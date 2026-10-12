defmodule AshA2ui.RelatedTablesVerifierTest do
  @moduledoc """
  Compile-time checks for related tables (`resource` on a `:table`):
  read-only, `:table`-only, and fields/queries/context filters resolved
  against the table's own resource (capture_io(:stderr) + regex pattern).
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "a related table with row actions does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule RelatedRowActions do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Person

            component :table, :notes do
              resource AshA2ui.Test.Links.Note
              fields [:title]
              row_actions [:destroy]
            end
          end
        end
      end)

    assert result =~ ~r/related table :notes: a related table is read-only/
  end

  test "resource on a :detail component does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule DetailResource do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Person

            context :person do
              resource AshA2ui.Test.Links.Person
            end

            component :detail do
              context :person
              resource AshA2ui.Test.Links.Note
            end
          end
        end
      end)

    assert result =~ ~r/only :table components may read another resource/
  end

  test "a related table's fields are checked against its own resource" do
    result =
      capture_io(:stderr, fn ->
        defmodule RelatedUnknownField do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Person

            component :table, :notes do
              resource AshA2ui.Test.Links.Note
              # :name is Person's, not Note's
              fields [:title, :name]
            end
          end
        end
      end)

    assert result =~ ~r/references unknown field :name/
  end

  test "a related table's context_filter keys are attributes of its own resource" do
    result =
      capture_io(:stderr, fn ->
        defmodule RelatedContextFilter do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Person

            context :person do
              resource AshA2ui.Test.Links.Person
            end

            component :table, :notes do
              resource AshA2ui.Test.Links.Note
              fields [:title]
              context_filter visible: :person
            end
          end
        end
      end)

    assert result =~ ~r/:visible is not a public attribute of AshA2ui.Test.Links.Note/
  end

  test "a related table's links resolve against its own resource" do
    result =
      capture_io(:stderr, fn ->
        defmodule RelatedLinks do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Person

            component :table, :notes do
              resource AshA2ui.Test.Links.Note
              fields [:title, :who]
            end

            field :who do
              links :participants
            end
          end
        end
      end)

    assert result == ""
  end
end
