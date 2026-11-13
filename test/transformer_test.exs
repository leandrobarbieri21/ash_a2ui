defmodule AshA2ui.TransformerTest do
  @moduledoc """
  Tests for `AshA2ui.Transformers.InferFields` (table fields from public
  attributes, form fields from action accepts) and
  `AshA2ui.Transformers.AddRenderAction` (auto-added `render_a2ui` generic
  action, its opt-out, and standalone skip).
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Test.SchemaHelper
  alias Spark.Dsl.Extension

  defmodule InferredTable do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    attributes do
      uuid_primary_key :id

      attribute :name, :string, public?: true
      attribute :active, :boolean, public?: true
      attribute :secret, :string
      attribute :count, :integer, public?: true
    end

    actions do
      defaults [:read, create: :*]
    end

    a2ui do
      component :table do
        read_action :read
      end
    end
  end

  defmodule InferredFormPrimaryCreate do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    attributes do
      uuid_primary_key :id

      attribute :name, :string, public?: true
      attribute :email, :string, public?: true
      attribute :ignored, :string, public?: true
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:name, :email]
      end
    end

    a2ui do
      component :form do
        create_action :create
      end
    end
  end

  defmodule InferredFormNamedCreate do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    attributes do
      uuid_primary_key :id

      attribute :name, :string, public?: true
      attribute :email, :string, public?: true
    end

    actions do
      defaults [:read, create: :*]

      create :register do
        accept [:email]
      end
    end

    a2ui do
      component :form do
        create_action :register
      end
    end
  end

  defmodule InferredFormUpdateFallback do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    attributes do
      uuid_primary_key :id

      attribute :name, :string, public?: true
      attribute :note, :string, public?: true
    end

    actions do
      defaults [:read]

      update :update do
        primary? true
        accept [:note]
      end
    end

    a2ui do
      component :form do
        update_action :update
      end
    end
  end

  defmodule NoInferrableAction do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read]
    end

    a2ui do
      add_render_action?(false)

      component :form do
      end
    end
  end

  defmodule ExplicitFields do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    attributes do
      uuid_primary_key :id

      attribute :name, :string, public?: true
      attribute :active, :boolean, public?: true
    end

    actions do
      defaults [:read, create: :*]
    end

    a2ui do
      component :table do
        fields [:name]
      end

      component :form do
        fields [:name]
        create_action :create
      end
    end
  end

  defmodule StandaloneInferred do
    @moduledoc false
    use AshA2ui.Standalone

    a2ui do
      for_resource AshA2ui.Test.Minimal

      component :table do
        read_action :read
      end
    end
  end

  defmodule OptedOut do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read, create: :*]
    end

    a2ui do
      add_render_action?(false)

      component :table do
        fields [:name]
      end
    end
  end

  defmodule ExistingRenderAction do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshA2ui]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read, create: :*]

      action :render_a2ui, :string do
        run fn _input, _context -> {:ok, "custom"} end
      end
    end

    a2ui do
      component :table do
        fields [:name]
      end
    end
  end

  defp component(module, name) do
    module |> AshA2ui.Info.components() |> Enum.find(&(&1.name == name))
  end

  describe "InferFields — :table" do
    test "fills omitted fields from public attributes, in declared order, excluding the primary key" do
      assert component(InferredTable, :table).fields == [:name, :active, :count]
    end

    test "standalone modules infer from for_resource" do
      assert component(StandaloneInferred, :table).fields == [:name]
    end
  end

  describe "InferFields — :form" do
    test "fills omitted fields from the create action's accepts" do
      assert component(InferredFormPrimaryCreate, :form).fields == [:name, :email]
    end

    test "uses the component's create_action when it names a non-primary action" do
      assert component(InferredFormNamedCreate, :form).fields == [:email]
    end

    test "falls back to the update action's accepts when there is no create action" do
      assert component(InferredFormUpdateFallback, :form).fields == [:note]
    end

    test "leaves fields nil when no matching action exists" do
      assert component(NoInferrableAction, :form).fields == nil
    end
  end

  describe "InferFields — explicit fields" do
    test "explicitly declared fields are untouched" do
      assert component(ExplicitFields, :table).fields == [:name]
      assert component(ExplicitFields, :form).fields == [:name]
    end

    test "frozen fixtures keep their declared fields" do
      assert component(AshA2ui.Test.Minimal, :table).fields == [:name]
    end
  end

  describe "AddRenderAction" do
    test "adds a generic render_a2ui action returning {:array, :map}" do
      action = Ash.Resource.Info.action(InferredTable, :render_a2ui)

      assert %Ash.Resource.Actions.Action{type: :action} = action
      assert action.returns == {:array, Ash.Type.Map}
      assert action.run == {AshA2ui.RenderA2uiAction, []}
    end

    test "render_a2ui is invocable and returns the surface as one createSurface" do
      messages =
        AshA2ui.Test.KitchenSink
        |> Ash.ActionInput.for_action(:render_a2ui, %{})
        |> Ash.run_action!()

      assert [%{"createSurface" => _create}] = messages

      for message <- messages do
        SchemaHelper.assert_valid_agent_message(message)
      end
    end

    test "is added to the frozen fixtures (no opt-out declared)" do
      assert %Ash.Resource.Actions.Action{} =
               Ash.Resource.Info.action(AshA2ui.Test.KitchenSink, :render_a2ui)

      assert %Ash.Resource.Actions.Action{} =
               Ash.Resource.Info.action(AshA2ui.Test.Minimal, :render_a2ui)
    end

    test "is skipped when add_render_action? is false" do
      assert Ash.Resource.Info.action(OptedOut, :render_a2ui) == nil
    end

    test "does not replace an existing action of the same name" do
      action = Ash.Resource.Info.action(ExistingRenderAction, :render_a2ui)

      assert action.returns == Ash.Type.String
      refute action.run == {AshA2ui.RenderA2uiAction, []}
    end

    test "is skipped in standalone mode (UI modules are not resources)" do
      refute Ash.Resource.Info.resource?(StandaloneInferred)
      assert Extension.get_entities(StandaloneInferred, [:actions]) == []
    end

    test "the run module implements Ash.Resource.Actions.Implementation" do
      assert Code.ensure_loaded?(AshA2ui.RenderA2uiAction)
      assert function_exported?(AshA2ui.RenderA2uiAction, :run, 3)

      behaviours =
        AshA2ui.RenderA2uiAction.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Ash.Resource.Actions.Implementation in behaviours
    end
  end
end
