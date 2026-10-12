defmodule AshA2ui.LinksVerifierTest do
  @moduledoc """
  Compile-time failure tests for the reference-link field options and the
  `badge_tones` row-layout option (capture_io(:stderr) + regex pattern).
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "link on a to-many relationship does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule LinkToMany do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Note

            component :table do
              fields [:title, :people]
            end

            field :people do
              link :participants
            end
          end
        end
      end)

    assert result =~ ~r/link :participants must be a to-one/
  end

  test "links on a to-one relationship does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule LinksToOne do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Note

            component :table do
              fields [:title, :who]
            end

            field :who do
              links :person
            end
          end
        end
      end)

    assert result =~ ~r/links :person must be a to-many/
  end

  test "a link to a missing relationship does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule LinkMissing do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Note

            component :table do
              fields [:title]
            end

            field :title do
              link :nope
            end
          end
        end
      end)

    assert result =~ ~r/link :nope is not a public relationship/
  end

  test "link_label must be a public field of the destination" do
    result =
      capture_io(:stderr, fn ->
        defmodule LinkLabelMissing do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Note

            component :table do
              fields [:title, :who]
            end

            field :who do
              link :person
              link_label :nope
            end
          end
        end
      end)

    assert result =~ ~r/link_label :nope must be a public attribute/
  end

  test "link_label without a relationship link does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule LinkLabelOrphan do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Note

            component :table do
              fields [:title]
            end

            field :title do
              link_label :name
            end
          end
        end
      end)

    assert result =~ ~r/link_label is set but the field declares neither/
  end

  test "an id_path that is not an attribute path does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule LinkBadPath do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Note

            component :table do
              fields [:title, :subject]
            end

            field :subject do
              link {:person, [:missing_id]}
            end
          end
        end
      end)

    assert result =~ ~r/id_path terminal :missing_id is not a public attribute/
  end

  test "a links field in a form does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule LinksInForm do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Note

            component :form do
              fields [:title, :people]
              create_action :create
            end

            field :people do
              links :participants
            end
          end
        end
      end)

    assert result =~ ~r/link field :people cannot be rendered by a :form component/
  end

  test "a source path may end in a calculation of the destination" do
    result =
      capture_io(:stderr, fn ->
        defmodule SourceCalcTerminal do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Note

            component :table do
              fields [:title, :who]
            end

            field :who do
              source [:person, :display_name]
            end
          end
        end
      end)

    assert result == ""
  end

  test "badge_tones outside the tone vocabulary do not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule BadBadgeTone do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Links.Note

            component :table do
              fields [:title, :status]

              row_layout do
                title :title
                badge :status
                badge_tones open: :lime
              end
            end
          end
        end
      end)

    assert result =~ ~r/badge_tones for :open must be one of/
  end
end
