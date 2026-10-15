defmodule AshA2ui.TypeMapper do
  @moduledoc """
  Maps Ash types to default widget atoms: string -> `:text_field`, boolean ->
  `:check_box`, atom with `one_of` constraints and `Ash.Type.Enum`
  implementations -> `:choice_picker`, date/datetime -> `:date_time_input`.
  Numeric types map to `:text_field` (the numeric keyboard hint is applied by
  the encoder). Unknown types fall back to `:text_field`.

  The widget atom -> catalog component name mapping (`:text_field` ->
  `"TextField"`, ...) lives in the encoder (`AshA2ui.Encoder.V0_9_1`).
  """

  alias Ash.Resource.Info, as: ResourceInfo

  @text_field_types [Ash.Type.String, Ash.Type.CiString] ++
                      [Ash.Type.Integer, Ash.Type.Decimal, Ash.Type.Float]

  @date_time_types [
    Ash.Type.Date,
    Ash.Type.UtcDatetime,
    Ash.Type.UtcDatetimeUsec,
    Ash.Type.NaiveDatetime
  ]

  @doc """
  Returns the default widget atom for the given Ash type (a type module or a
  builtin alias like `:string`) and its constraints.
  """
  @spec widget_for(ash_type :: module | atom, constraints :: keyword) :: atom
  def widget_for(ash_type, constraints \\ []) do
    ash_type
    |> Ash.Type.get_type()
    |> do_widget_for(constraints)
  end

  defp do_widget_for(type, _constraints) when type in @text_field_types, do: :text_field
  defp do_widget_for(Ash.Type.Boolean, _constraints), do: :check_box
  defp do_widget_for(type, _constraints) when type in @date_time_types, do: :date_time_input

  defp do_widget_for(Ash.Type.Atom, constraints) do
    if Keyword.keyword?(constraints) && constraints[:one_of] do
      :choice_picker
    else
      :text_field
    end
  end

  defp do_widget_for(type, _constraints) do
    if enum_type?(type), do: :choice_picker, else: :text_field
  end

  @doc """
  Whether the given type module implements `Ash.Type.Enum` (its values come
  from the module's `values/0` rather than a `one_of` constraint).
  """
  @spec enum_type?(term) :: boolean
  def enum_type?(type) when is_atom(type) and not is_nil(type) do
    Code.ensure_loaded?(type) and function_exported?(type, :values, 0) and
      Spark.implements_behaviour?(type, Ash.Type.Enum)
  end

  def enum_type?(_type), do: false

  @doc """
  The enumerated choices of the attribute or calculation `name` on
  `resource` (a resource module or its DSL state), as `{value, label}`
  pairs in declaration order: an `Ash.Type.Enum`'s values labelled by its
  `label/1` (humanized when the enum declares no label), else the `one_of`
  constraint's values humanized. `[]` when `name` is neither, or has no
  enumerable values.

  This is the one labelling rule behind ChoicePicker options, choice text
  in rows and board lane headings, so all three agree for the same value.
  """
  @spec choices(module | map, atom) :: [{atom | String.t(), String.t()}]
  def choices(resource, name) do
    case ResourceInfo.attribute(resource, name) || ResourceInfo.calculation(resource, name) do
      %{type: type} = field ->
        type = Ash.Type.get_type(type)

        if enum_type?(type) do
          Enum.map(type.values(), &{&1, enum_label(type, &1)})
        else
          field.constraints
          |> one_of()
          |> Enum.map(&{&1, humanize(&1)})
        end

      nil ->
        []
    end
  end

  defp one_of(constraints), do: Keyword.get(constraints, :one_of) || []

  # `Ash.Type.Enum.label/1` is nil unless the enum declared explicit labels.
  defp enum_label(type, value) do
    case type.label(value) do
      nil -> humanize(value)
      label -> to_string(label)
    end
  end

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
