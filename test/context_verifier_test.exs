defmodule AshA2ui.ContextVerifierTest do
  @moduledoc """
  Compile-time verification of `context` entities and everything referencing
  them (`AshA2ui.Verifiers.VerifyContexts`): option keys, searchability,
  dependency declarations and paths, table `context_filter` /
  `require_context` / `select_context`, and `:detail` components.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  describe "context entities" do
    test "duplicate context names do not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule DuplicateContexts do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
              end

              context :owner do
                resource AshA2ui.Test.Owner
              end
            end
          end
        end)

      assert result =~ ~r/duplicate context :owner/
    end

    test "a non-resource context resource does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule NotAResource do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource Enum
              end
            end
          end
        end)

      assert result =~ ~r/is not an Ash resource/
    end

    test "private or missing option attributes do not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadOptionLabel do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
                option_label :nonexistent
              end
            end
          end
        end)

      assert result =~ ~r/option_label :nonexistent.*must be a public attribute/
    end

    test "non-string option_search entries do not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadOptionSearch do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :appointment do
                resource AshA2ui.Test.Appointment
                option_label :title
                option_search [:scheduled_for]
              end
            end
          end
        end)

      assert result =~ ~r/option_search entry :scheduled_for.*must be a string-typed/
    end

    test "depends_on without depends_on_path does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule MissingPath do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
              end

              context :clinic do
                resource AshA2ui.Test.Clinic
                depends_on(:owner)
              end
            end
          end
        end)

      assert result =~ ~r/sets depends_on without depends_on_path/
    end

    test "depending on a later-declared context does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule ForwardDependency do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :clinic do
                resource AshA2ui.Test.Clinic
                depends_on(:owner)
                depends_on_path([:memberships, :owner_id])
              end

              context :owner do
                resource AshA2ui.Test.Owner
              end
            end
          end
        end)

      assert result =~ ~r/not a previously declared context/
    end

    test "an invalid depends_on_path step does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadPathStep do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
              end

              context :clinic do
                resource AshA2ui.Test.Clinic
                depends_on(:owner)
                depends_on_path([:nonexistent, :owner_id])
              end
            end
          end
        end)

      assert result =~ ~r/step :nonexistent is not a public relationship/
    end
  end

  describe "table context options" do
    test "a context_filter naming an undeclared context does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule UndeclaredFilterContext do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              component :table do
                fields [:title]
                context_filter(owner_id: :owner)
              end
            end
          end
        end)

      assert result =~ ~r/:owner is not a declared context/
    end

    test "a context_filter over a non-attribute does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadFilterAttribute do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
              end

              component :table do
                fields [:title]
                context_filter(nonexistent: :owner)
              end
            end
          end
        end)

      assert result =~ ~r/:nonexistent is not a public attribute/
    end

    test "require_context outside the context_filter does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule RequireOutsideFilter do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
              end

              component :table do
                fields [:title]
                require_context([:owner])
              end
            end
          end
        end)

      assert result =~ ~r/does not appear in the table's context_filter/
    end

    test "context_record outside the context_filter does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule RecordOutsideFilter do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
              end

              component :table do
                fields [:title]
                context_record(owner: [:name])
              end
            end
          end
        end)

      assert result =~
               ~r/context_record entry :owner on table .* does not appear in the table's context_filter/
    end

    test "context_record on a non-table component does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule RecordOnForm do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
              end

              component :form do
                fields [:title]
                context_record(owner: [:name])
              end
            end
          end
        end)

      assert result =~ ~r/context_record is not supported on :form components/
    end

    test "select_context over a foreign resource does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule ForeignSelectContext do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
              end

              component :table do
                fields [:title]
                select_context(:owner)
              end
            end
          end
        end)

      assert result =~ ~r/must name a context over the table's own resource/
    end

    test "context options on a form component do not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule ContextOnForm do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
              end

              component :form do
                fields [:title]
                create_action :create
                require_context([:owner])
              end
            end
          end
        end)

      assert result =~ ~r/require_context is not supported on :form components/
    end
  end

  describe "detail components" do
    test "a detail without a context does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule DetailWithoutContext do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              component :detail do
                fields [:title]
              end
            end
          end
        end)

      assert result =~ ~r/:detail components must set context/
    end

    test "a detail referencing an undeclared context does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule DetailUndeclaredContext do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              component :detail do
                context :owner
                fields [:title]
              end
            end
          end
        end)

      assert result =~ ~r/references undeclared context :owner/
    end

    test "detail fields are validated against the context's resource" do
      result =
        capture_io(:stderr, fn ->
          defmodule DetailForeignField do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              context :owner do
                resource AshA2ui.Test.Owner
              end

              # :title is an Appointment field, not an Owner field.
              component :detail do
                context :owner
                fields [:title]
              end
            end
          end
        end)

      assert result =~ ~r/renders :title, which is not a public attribute/
    end
  end
end
