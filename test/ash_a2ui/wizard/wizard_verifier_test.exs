defmodule AshA2ui.Wizard.WizardVerifierTest do
  @moduledoc """
  A2UI-106/AC-8: compile-time failures from `AshA2ui.Verifiers.VerifySteps`,
  using the `capture_io(:stderr)` + regex pattern of the existing verifier
  suites.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  @cases [
    {"a form field left out of every step", ~r/\[:team\] belong to no step/,
     quote do
       component :form do
         fields [:name, :email, :team]
         create_action :create
         step(:one, do: fields([:name]))
         step(:two, do: fields([:email]))
       end
     end},
    {"a field in two steps", ~r/field :email belongs to more than one step/,
     quote do
       component :form do
         fields [:name, :email]
         create_action :create
         step(:one, do: fields([:name, :email]))
         step(:two, do: fields([:email]))
       end
     end},
    {"duplicate step names", ~r/duplicate step :one/,
     quote do
       component :form do
         fields [:name, :email]
         create_action :create
         step(:one, do: fields([:name]))
         step(:one, do: fields([:email]))
       end
     end},
    {"a review step that is not last", ~r/review step :check is not the last step/,
     quote do
       component :form do
         fields [:name, :email]
         create_action :create
         step(:one, do: fields([:name]))
         step(:check, do: review?(true))
         step(:two, do: fields([:email]))
       end
     end},
    {"a review step with fields", ~r/review step :check declares fields/,
     quote do
       component :form do
         fields [:name, :email]
         create_action :create
         step(:one, do: fields([:name]))

         step :check do
           review?(true)
           fields [:email]
         end
       end
     end},
    {"steps mixed with groups", ~r/both `step` and `group` entities/,
     quote do
       component :form do
         fields [:name, :email]
         create_action :create
         group :basics, do: fields([:name])
         step(:one, do: fields([:name]))
         step(:two, do: fields([:email]))
       end
     end},
    {"a single step", ~r/a stepped form needs at least two steps/,
     quote do
       component :form do
         fields [:name]
         create_action :create
         step(:only, do: fields([:name]))
       end
     end},
    {"a step on a table", ~r/`step` entities are only supported on :form components/,
     quote do
       component :table do
         fields [:name, :email]
         step(:one, do: fields([:name]))
         step(:two, do: fields([:email]))
       end
     end},
    {"a step naming a non-form field", ~r/step :two references field :role/,
     quote do
       component :form do
         fields [:name, :email]
         create_action :create
         step(:one, do: fields([:name, :email]))
         step(:two, do: fields([:role]))
       end
     end},
    {"a non-review step without fields", ~r/step :empty declares no fields/,
     quote do
       component :form do
         fields [:name]
         create_action :create
         step(:one, do: fields([:name]))
         step(:empty, do: label("Nothing here"))
       end
     end}
  ]

  @tag ac: "A2UI-106/AC-8"
  test "rejects invalid steps" do
    for {{description, pattern, body}, index} <- Enum.with_index(@cases) do
      module = Module.concat(__MODULE__, "Case#{index}")

      ast =
        quote do
          defmodule unquote(module) do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Enrollment
              unquote(body)
            end
          end
        end

      result = capture_io(:stderr, fn -> Code.eval_quoted(ast) end)
      assert result =~ pattern, "#{description}: expected #{inspect(pattern)} in:\n#{result}"
    end
  end

  @tag ac: "A2UI-106/AC-8"
  test "a valid stepped form compiles cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule ValidSteps do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.Enrollment

            component :form do
              fields [:name, :email]
              create_action :create

              step :one do
                fields [:name]
              end

              step :two do
                fields [:email]
              end

              step :check do
                review?(true)
              end
            end
          end
        end
      end)

    refute result =~ "step"
  end
end
