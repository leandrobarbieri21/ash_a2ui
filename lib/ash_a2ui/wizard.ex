defmodule AshA2ui.Wizard do
  @moduledoc """
  Wizard steps on `:form` components: the data model, the basic-catalog
  composition, and the pure helpers `AshA2ui.ActionHandler` uses for the
  `"wizard_next"` / `"wizard_back"` actions.

  The vocabulary (form steps, a review step) comes from PyroManiac
  (<https://github.com/frankdugan3/pyro_maniac>); the design record is
  `notes/2026-10-15-pyro-maniac-borrowings.md`, section 3.

  A stepped form is still **one** form over **one** Ash action: `/form` is
  carried across steps unchanged, and the last step's button is the usual
  `"submit_form"`.

  ## Data model

  Only surfaces whose form declares steps carry `/ui/wizard`:

      %{
        "index" => 0,
        "steps" => [%{"name" => "who", "label" => "Who", "state" => "current"}, ...],
        "who_visible" => [%{"id" => "on"}],
        "what_visible" => [],
        "nav" => %{
          "back_visible" => [],
          "next_visible" => [%{"id" => "on"}],
          "submit_visible" => []
        }
      }

  `"state"` is `"done"`, `"current"` or `"todo"`. The `*_visible` values
  are zero-or-one lists (`AshA2ui.Experience.sentinel/1`), the same
  technique as the `/ui/panel/*_visible` flags.

  ## Components

  The form's field children become a single `form_wizard` Column: a
  progress List (`form_wizard_progress`, templated over
  `/ui/wizard/steps`), one `form_step_<step>_slot` List per step templated
  over `/ui/wizard/<step>_visible`, and a `form_wizard_nav` Row holding the
  Back (`wizard_back`) and Next (`wizard_next`) buttons behind their nav
  sentinels. A review step renders `form_review_<field>` caption/value rows
  bound to `/form/<field>` (`/select/<field>/label` for a searchable
  select). Under experience v1 the submit button sits behind
  `/ui/wizard/nav/submit_visible`; under v2 the panel's
  `/ui/panel/submit_visible` gate already hides it before the last step, and
  the Next button's label binds `/ui/panel/primary_label` (which reads
  "Next" until the last step).
  """

  alias AshA2ui.Experience

  @next_label "Next"

  @doc "The form component's (normalized) steps, or `[]` without a stepped form."
  @spec steps(AshA2ui.ResolvedView.t() | map) :: [AshA2ui.Step.t()]
  def steps(%{components: components}) do
    case Enum.find(components, &(&1.name == :form)) do
      %{steps: steps} when is_list(steps) -> steps
      _no_form -> []
    end
  end

  def steps(_view), do: []

  @doc "Whether the surface's form declares steps."
  @spec stepped?(map) :: boolean
  def stepped?(view), do: steps(view) != []

  @doc "The index of the last step (`0` without steps)."
  @spec last_index(map) :: non_neg_integer
  def last_index(view), do: max(length(steps(view)) - 1, 0)

  @doc """
  Whether `index` is a step before the last one — the steps whose primary
  button is Next rather than the submit. Always `false` without steps.
  """
  @spec before_last_step?(map, integer) :: boolean
  def before_last_step?(view, index) do
    stepped?(view) and index < last_index(view)
  end

  @doc ~s(The primary label before the last step: "#{@next_label}".)
  @spec next_label() :: String.t()
  def next_label, do: @next_label

  @doc """
  Parses a client-carried step index: an integer (or an integer string) is
  clamped into the step range; anything else is refused with `:error`.
  Never creates atoms.
  """
  @spec parse_index(map, term) :: {:ok, non_neg_integer} | :error
  def parse_index(view, index) when is_integer(index), do: {:ok, clamp(view, index)}

  def parse_index(view, index) when is_binary(index) do
    case Integer.parse(index) do
      {integer, ""} -> {:ok, clamp(view, integer)}
      _not_an_integer -> :error
    end
  end

  def parse_index(_view, _index), do: :error

  defp clamp(view, index), do: index |> max(0) |> min(last_index(view))

  @doc """
  Filters a client-carried `/form` map down to the form's own fields
  (string keys compared against the compile-time field names). Unknown
  keys are dropped before anything is cast; a non-map yields `%{}`. The
  handler applies it on a stepped form's `wizard_next` and `submit_form`
  alike (one shared changeset path).
  """
  @spec form_values(map, term) :: map
  def form_values(view, values) when is_map(values) do
    allowed = view |> form_fields() |> MapSet.new(&Atom.to_string/1)
    Map.filter(values, fn {key, _value} -> is_binary(key) and MapSet.member?(allowed, key) end)
  end

  def form_values(_view, _values), do: %{}

  @doc "The fields of the steps up to and including `index`."
  @spec reached_fields(map, non_neg_integer) :: MapSet.t(atom)
  def reached_fields(view, index) do
    view
    |> steps()
    |> Enum.take(index + 1)
    |> Enum.flat_map(& &1.fields)
    |> MapSet.new()
  end

  @doc """
  The index of the earliest step owning any of `fields`, or `nil` when
  none of them belongs to a step.
  """
  @spec earliest_owning_index(map, [atom]) :: non_neg_integer | nil
  def earliest_owning_index(view, fields) do
    view
    |> steps()
    |> Enum.find_index(fn step -> Enum.any?(fields, &(&1 in step.fields)) end)
  end

  @doc "The `/ui/wizard` value for step `index` (see the moduledoc)."
  @spec state(map, non_neg_integer) :: map
  def state(view, index) do
    steps = steps(view)
    last = length(steps) - 1

    visibility =
      steps
      |> Enum.with_index()
      |> Map.new(fn {step, position} ->
        {"#{step.name}_visible", Experience.sentinel(position == index)}
      end)

    Map.merge(visibility, %{
      "index" => index,
      "steps" =>
        steps
        |> Enum.with_index()
        |> Enum.map(fn {step, position} ->
          %{
            "name" => to_string(step.name),
            "label" => step.label,
            "state" => step_state(position, index)
          }
        end),
      "nav" => %{
        "back_visible" => Experience.sentinel(index > 0),
        "next_visible" => Experience.sentinel(index < last),
        "submit_visible" => Experience.sentinel(index == last)
      }
    })
  end

  defp step_state(position, index) when position < index, do: "done"
  defp step_state(index, index), do: "current"
  defp step_state(_position, _index), do: "todo"

  # --- encoder hooks ---------------------------------------------------------

  @doc false
  # The form's field children on a stepped form: the single wizard Column.
  def field_children, do: ["form_wizard"]

  @doc false
  # The v1 form Column's submit child: gated on stepped forms.
  def submit_child(%{steps: [_ | _]}) do
    if Experience.v2?(), do: "form_submit_button", else: "form_wizard_submit_slot"
  end

  def submit_child(_form), do: "form_submit_button"

  @doc false
  # The wizard subtree. `anchor_ids` maps a field name to its input/error
  # component ids (the encoder's own field anchors, so inputs are emitted
  # exactly once, by the encoder's form descendants).
  def components(_view, %{steps: []}, _anchor_ids), do: []

  def components(view, form, anchor_ids) do
    step_slots = Enum.map(form.steps, &"form_step_#{&1.name}_slot")

    [
      %{
        "id" => "form_wizard",
        "component" => "Column",
        "children" => ["form_wizard_progress" | step_slots] ++ ["form_wizard_nav"]
      }
      | progress_components()
    ] ++
      Enum.flat_map(form.steps, &step_components(view, form, &1, anchor_ids)) ++
      nav_components(view)
  end

  defp progress_components do
    [
      %{
        "id" => "form_wizard_progress",
        "component" => "List",
        "direction" => "horizontal",
        "children" => %{
          "componentId" => "form_wizard_progress_item",
          "path" => "/ui/wizard/steps"
        }
      },
      %{
        "id" => "form_wizard_progress_item",
        "component" => "Row",
        "children" => ["form_wizard_progress_label", "form_wizard_progress_state"]
      },
      %{
        "id" => "form_wizard_progress_label",
        "component" => "Text",
        "text" => %{"path" => "label"}
      },
      %{
        "id" => "form_wizard_progress_state",
        "component" => "Text",
        "text" => %{"path" => "state"},
        "variant" => "caption"
      }
    ]
  end

  defp step_components(view, form, step, anchor_ids) do
    base = "form_step_#{step.name}"

    {description_ids, description} =
      case step.description do
        text when is_binary(text) and text != "" ->
          {["#{base}_description"],
           [%{"id" => "#{base}_description", "component" => "Text", "text" => text}]}

        _none ->
          {[], []}
      end

    {body_ids, body} =
      if step.review? do
        review_rows(view, form)
      else
        {Enum.flat_map(step.fields, anchor_ids), []}
      end

    [
      %{
        "id" => "#{base}_slot",
        "component" => "List",
        "children" => %{"componentId" => base, "path" => "/ui/wizard/#{step.name}_visible"}
      },
      %{
        "id" => base,
        "component" => "Column",
        "children" => ["#{base}_heading" | description_ids] ++ body_ids
      },
      %{
        "id" => "#{base}_heading",
        "component" => "Text",
        "text" => step.label,
        "variant" => "h3"
      }
    ] ++ description ++ body
  end

  # The review summary: one caption/value pair per form field (read-only
  # Texts). A searchable select shows the picked record's label from
  # /select/<field>/label, which option_select and the record population
  # already maintain; every other field binds its carried /form value.
  defp review_rows(view, form) do
    rows =
      Enum.flat_map(form.fields, fn field ->
        base = "form_review_#{field}"

        [
          %{
            "id" => base,
            "component" => "Row",
            "children" => ["#{base}_label", "#{base}_value"]
          },
          %{
            "id" => "#{base}_label",
            "component" => "Text",
            "text" => view.fields[field].label,
            "variant" => "caption"
          },
          %{
            "id" => "#{base}_value",
            "component" => "Text",
            "text" => %{"path" => review_path(view, field)}
          }
        ]
      end)

    {Enum.map(form.fields, &"form_review_#{&1}"), rows}
  end

  defp review_path(view, field) do
    case view.selects[field] do
      %{search_fields: [_ | _]} -> "/select/#{field}/label"
      _not_searchable -> "/form/#{field}"
    end
  end

  defp nav_components(_view) do
    next_text =
      if Experience.v2?(), do: %{"path" => "/ui/panel/primary_label"}, else: @next_label

    [
      %{
        "id" => "form_wizard_nav",
        "component" => "Row",
        "children" => ["form_wizard_back_slot", "form_wizard_next_slot"]
      },
      %{
        "id" => "form_wizard_back_slot",
        "component" => "List",
        "children" => %{
          "componentId" => "form_wizard_back_button",
          "path" => "/ui/wizard/nav/back_visible"
        }
      },
      %{
        "id" => "form_wizard_back_button",
        "component" => "Button",
        "child" => "form_wizard_back_text",
        "action" => %{
          "event" => %{
            "name" => "wizard_back",
            "context" => %{
              "index" => %{"path" => "/ui/wizard/index"},
              "recordId" => %{"path" => "/form/id"}
            }
          }
        }
      },
      %{"id" => "form_wizard_back_text", "component" => "Text", "text" => "Back"},
      %{
        "id" => "form_wizard_next_slot",
        "component" => "List",
        "children" => %{
          "componentId" => "form_wizard_next_button",
          "path" => "/ui/wizard/nav/next_visible"
        }
      },
      %{
        "id" => "form_wizard_next_button",
        "component" => "Button",
        "variant" => "primary",
        "child" => "form_wizard_next_text",
        "action" => %{
          "event" => %{
            "name" => "wizard_next",
            "context" => %{
              "values" => %{"path" => "/form"},
              "recordId" => %{"path" => "/form/id"},
              "index" => %{"path" => "/ui/wizard/index"}
            }
          }
        }
      },
      %{"id" => "form_wizard_next_text", "component" => "Text", "text" => next_text}
    ] ++ submit_slot()
  end

  defp submit_slot do
    if Experience.v2?() do
      []
    else
      [
        %{
          "id" => "form_wizard_submit_slot",
          "component" => "List",
          "children" => %{
            "componentId" => "form_submit_button",
            "path" => "/ui/wizard/nav/submit_visible"
          }
        }
      ]
    end
  end

  defp form_fields(%{components: components}) do
    case Enum.find(components, &(&1.name == :form)) do
      %{fields: fields} when is_list(fields) -> fields
      _no_form -> []
    end
  end
end
