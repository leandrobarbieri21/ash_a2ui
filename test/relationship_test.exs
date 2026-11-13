defmodule AshA2ui.RelationshipTest do
  @moduledoc """
  Relationship rendering tests: `belongs_to` form selects (inference, the
  `/options/<field>` convention, option loading with actor/tenant opts,
  submit casting) and `source` table columns (relationship loading, nil-safe
  serialization). Every emitted message is validated against the vendored
  A2UI 1.0 schemas.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{Author, Messages, Post}
  alias AshA2ui.Test.Surface

  defp components_by_id(messages) do
    Surface.components_by_id(messages)
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"createSurface" => %{"dataModel" => value}} when path == "/" -> value
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _ -> nil
    end)
  end

  defp envelope(name, context) do
    Messages.call(name, "posts", context)
  end

  defp create_author!(attrs) do
    Ash.create!(Author, attrs, authorize?: false)
  end

  describe "ResolvedView select resolution" do
    test "a form field matching a belongs_to source_attribute is inferred as a select" do
      view = ResolvedView.resolve(Post)

      assert %{author_id: select} = view.selects
      assert select.relationship == :author
      assert select.destination == Author
      assert view.fields[:author_id].widget == :choice_picker
    end

    test "option defaults: label from the fallback chain, value from the primary key" do
      view = ResolvedView.resolve(Post)
      select = view.selects[:author_id]

      assert select.option_label == :name
      assert select.option_value == :id
      assert select.option_sort == :name
      assert select.option_limit == 100
    end

    test "source columns produce relationship load statements" do
      view = ResolvedView.resolve(Post)

      assert view.fields[:author_email].source == [:author, :email]
      assert view.loads == [:author]
    end

    test "fields without a matching relationship are not selects" do
      view = ResolvedView.resolve(AshA2ui.Test.KitchenSink)
      assert view.selects == %{}
      assert view.loads == []
    end
  end

  describe "form select encoding" do
    test "the belongs_to form input is a ChoicePicker bound to /form/<field>" do
      messages = AshA2ui.Info.build_surface(Post)
      Enum.each(messages, &assert_valid_agent_message/1)

      components = components_by_id(messages)

      assert %{
               "component" => "ChoicePicker",
               "variant" => "mutuallyExclusive",
               "value" => %{"@path" => "/form/author_id"},
               "options" => _options
             } = components["form_input_author_id"]
    end

    test "loaded options are emitted inline and mirrored at /options/<field>" do
      author_b = create_author!(%{name: "Bea", email: "bea@example.com"})
      author_a = create_author!(%{name: "Al", email: "al@example.com"})

      messages = AshA2ui.Info.build_surface(Post)
      Enum.each(messages, &assert_valid_agent_message/1)

      expected_options = [
        %{"label" => "Al", "value" => author_a.id},
        %{"label" => "Bea", "value" => author_b.id}
      ]

      components = components_by_id(messages)
      assert components["form_input_author_id"]["options"] == expected_options

      value = Surface.data_model(messages)

      assert value["options"] == %{"author_id" => expected_options}
    end

    test "build_data_model/2 carries /options so full refreshes keep selects usable" do
      author = create_author!(%{name: "Solo", email: nil})

      message = AshA2ui.Info.build_data_model(Post)
      assert_valid_agent_message(message)

      assert message["updateDataModel"]["value"]["options"] == %{
               "author_id" => [%{"label" => "Solo", "value" => author.id}]
             }
    end

    test "a nil option label falls back to the option value" do
      defmodule NoLabelUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Post
          surface_id "no_label_posts"

          component :form do
            fields [:title, :author_id]
            create_action :create
          end

          field :author_id do
            option_label(:email)
          end
        end
      end

      author = create_author!(%{name: "Label-less", email: nil})

      message = AshA2ui.Info.build_data_model(NoLabelUI)
      assert_valid_agent_message(message)

      assert [%{"label" => label, "value" => value}] =
               message["updateDataModel"]["value"]["options"]["author_id"]

      assert value == author.id
      assert label == author.id
    end

    test "option_limit truncates and option_sort orders the option list" do
      defmodule LimitedUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Post
          surface_id "limited_posts"

          component :form do
            fields [:title, :author_id]
            create_action :create
          end

          field :author_id do
            option_label(:name)
            option_sort(:email)
            option_limit(2)
          end
        end
      end

      create_author!(%{name: "C", email: "3@example.com"})
      create_author!(%{name: "A", email: "1@example.com"})
      create_author!(%{name: "B", email: "2@example.com"})

      message = AshA2ui.Info.build_data_model(LimitedUI)

      assert [%{"label" => "A"}, %{"label" => "B"}] =
               message["updateDataModel"]["value"]["options"]["author_id"]
    end

    test "option reads honor the actor and authorize? options" do
      defmodule ProtectedAuthor do
        @moduledoc false
        use Ash.Resource,
          domain: AshA2ui.ActionHandlerTest.TestDomain,
          data_layer: Ash.DataLayer.Ets,
          authorizers: [Ash.Policy.Authorizer]

        ets do
          private? true
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, create: :*]
        end

        policies do
          policy always() do
            authorize_if actor_present()
          end
        end
      end

      defmodule ProtectedPost do
        @moduledoc false
        use Ash.Resource,
          domain: AshA2ui.ActionHandlerTest.TestDomain,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshA2ui]

        ets do
          private? true
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        relationships do
          belongs_to :author, ProtectedAuthor, public?: true
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:title, :author_id]
          end
        end

        a2ui do
          surface_id "protected_posts"

          component :form do
            fields [:title, :author_id]
            create_action :create
          end
        end
      end

      Ash.create!(ProtectedAuthor, %{name: "Hidden"}, authorize?: false)

      # without an actor the policy forbids the option read
      assert_raise Ash.Error.Forbidden, fn ->
        AshA2ui.Info.build_data_model(ProtectedPost)
      end

      message = AshA2ui.Info.build_data_model(ProtectedPost, actor: %{id: "someone"})

      assert [%{"label" => "Hidden"}] =
               message["updateDataModel"]["value"]["options"]["author_id"]
    end
  end

  describe "submit_form with a select value" do
    test "casts a string uuid select value to the belongs_to attribute" do
      author = create_author!(%{name: "Writer", email: "w@example.com"})

      env =
        envelope("submit_form", %{
          "values" => %{"title" => "Hello", "author_id" => author.id}
        })

      assert_valid_renderer_message(env)
      assert {:ok, messages} = ActionHandler.handle(Post, env)
      Enum.each(messages, &assert_valid_agent_message/1)

      assert [post] = Ash.read!(Post, authorize?: false)
      assert post.author_id == author.id
    end

    test "unwraps a one-element list value (ChoicePicker string-list binding)" do
      author = create_author!(%{name: "Wrapped", email: nil})

      env =
        envelope("submit_form", %{
          "values" => %{"title" => "Hi", "author_id" => [author.id]}
        })

      assert {:ok, _messages} = ActionHandler.handle(Post, env)
      assert [%{author_id: author_id}] = Ash.read!(Post, authorize?: false)
      assert author_id == author.id
    end
  end

  describe "source table columns" do
    test "the column cell binds to the field name and rows carry the walked value" do
      author = create_author!(%{name: "Ada", email: "ada@example.com"})

      Ash.create!(Post, %{title: "Loaded", author_id: author.id}, authorize?: false)

      messages = AshA2ui.Info.build_surface(Post)
      Enum.each(messages, &assert_valid_agent_message/1)

      components = components_by_id(messages)

      assert %{"component" => "Text", "text" => %{"@path" => "author_email"}} =
               components["table_cell_author_email_value"]

      records = value_at(messages, "/")["records"]
      assert [%{"title" => "Loaded", "author_email" => "ada@example.com"}] = records
    end

    test "a nil relationship serializes to an empty string" do
      Ash.create!(Post, %{title: "Orphan"}, authorize?: false)

      message = AshA2ui.Info.build_data_model(Post)

      assert [%{"title" => "Orphan", "author_email" => ""}] =
               message["updateDataModel"]["value"]["records"]
    end

    test "action follow-up refreshes also walk source columns" do
      author = create_author!(%{name: "Eve", email: "eve@example.com"})

      env =
        envelope("submit_form", %{
          "values" => %{"title" => "Via action", "author_id" => author.id}
        })

      assert {:ok, messages} = ActionHandler.handle(Post, env)
      Enum.each(messages, &assert_valid_agent_message/1)

      assert [%{"title" => "Via action", "author_email" => "eve@example.com"}] =
               value_at(messages, "/records")
    end
  end
end
