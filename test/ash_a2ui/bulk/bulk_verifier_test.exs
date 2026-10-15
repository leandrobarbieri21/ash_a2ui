defmodule AshA2ui.Bulk.BulkVerifierTest do
  @moduledoc """
  A2UI-104: compile-time checks of `bulk_actions` (capture_io(:stderr) +
  regex pattern, like the other verifier tests).
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  @tag ac: "A2UI-104/AC-8"
  test "rejects invalid bulk actions" do
    read_action =
      capture_io(:stderr, fn ->
        defmodule BulkReadAction do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BulkTask

            component :table do
              fields [:title]
              bulk_actions [:read]
            end
          end
        end
      end)

    assert read_action =~
             ~r/bulk action :read is a :read action: bulk_actions must name update, destroy or generic actions/

    prompted =
      capture_io(:stderr, fn ->
        defmodule BulkPromptedAction do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BulkTask

            component :table do
              fields [:title]
              row_actions [:update]
              bulk_actions [:update]
            end

            action :update do
              prompt_fields [:title]
            end
          end
        end
      end)

    assert prompted =~ ~r/bulk action :update declares prompt_fields: a bulk action cannot prompt/

    related =
      capture_io(:stderr, fn ->
        defmodule BulkRelatedTable do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BulkTask

            component :table do
              fields [:title]
            end

            component :table, :projects do
              resource AshA2ui.Test.BulkProject
              fields [:name]
              bulk_actions [:destroy]
            end
          end
        end
      end)

    assert related =~
             ~r/related table :projects: a related table is read-only, so it cannot declare bulk_actions/

    missing =
      capture_io(:stderr, fn ->
        defmodule BulkMissingAction do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BulkTask

            component :table do
              fields [:title]
              bulk_actions [:no_such_action]
            end
          end
        end
      end)

    assert missing =~ ~r/bulk action :no_such_action does not exist on the resource/

    generic_without_record_id =
      capture_io(:stderr, fn ->
        defmodule BulkGenericWithoutRecordId do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BulkTask

            component :table do
              fields [:title]
              bulk_actions [:ping]
            end
          end
        end
      end)

    assert generic_without_record_id =~
             ~r/bulk action :ping is a generic action without a :record_id argument: a generic bulk action runs once per selected record/
  end

  test "a valid bulk table with per-record visible_when compiles cleanly" do
    output =
      capture_io(:stderr, fn ->
        defmodule BulkValid do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BulkTask

            component :table do
              fields [:title, :status]
              bulk_actions [:approve, :destroy, :stamp]
            end

            action :approve do
              visible_when status: :open
            end
          end
        end
      end)

    assert output == ""
  end
end
