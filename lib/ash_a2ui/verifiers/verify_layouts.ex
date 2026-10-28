defmodule AshA2ui.Verifiers.VerifyLayouts do
  @moduledoc """
  Verifies at compile time that layout declarations are sound:

    * `group` entities appear only on `:form` components, with unique names,
      at least one field each, fields that are members of the form's field
      list, and no field claimed by more than one group,
    * `row_layout` entities appear only on `:table` components, with
      `title`/`badge`/`meta` referencing the table's fields, no field
      referenced twice across `title`/`badge`/`meta`, `badge_text` values
      that are strings, `badge_text` only alongside a `badge`, and
      `badge_tones` values drawn from `AshA2ui.RowLayout.tones/0` (also only
      alongside a `badge`),
    * `column` entities appear only on `:table` components, with unique
      names that are table fields, `subtitle`/`icon`/`more`/`detail`/
      `detail_date` referencing table fields that are not columns of their
      own, the icon options only alongside an `icon` and the detail options
      only alongside a `detail`, `icon_names` drawn from
      `AshA2ui.Column.icons/0`, `icon_tones` from `AshA2ui.RowLayout.tones/0`,
      and `icon_labels`/`detail_text` values that are strings,
    * `display :board` appears only on `:table` components that declare a
      `sections` block and a `row_layout` (lanes render cards).

  Field-membership checks run against the component's field list as filled
  in by `AshA2ui.Transformers.InferFields`; components whose fields could
  not be resolved (standalone modules without a compilable `for_resource`)
  skip them.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    components = components(dsl_state)

    with :ok <- verify_placement(components, module) do
      Enum.reduce_while(components, :ok, fn component, :ok ->
        halt_on_error(verify_component(component, module))
      end)
    end
  end

  defp halt_on_error(:ok), do: {:cont, :ok}
  defp halt_on_error({:error, error}), do: {:halt, {:error, error}}

  defp verify_placement(components, module) do
    Enum.reduce_while(components, :ok, fn component, :ok ->
      cond do
        component.name != :form and component.groups != [] ->
          {:halt,
           {:error,
            error(module, [:a2ui, :component, component.name],
              message:
                "component #{inspect(component.name)} declares a group: " <>
                  "`group` entities are only supported on :form components"
            )}}

        component.name != :table and not is_nil(component.row_layout) ->
          {:halt,
           {:error,
            error(module, [:a2ui, :component, component.name],
              message:
                "component #{inspect(component.name)} declares a row_layout: " <>
                  "`row_layout` entities are only supported on :table components"
            )}}

        component.name != :table and component.columns != [] ->
          {:halt,
           {:error,
            error(module, [:a2ui, :component, component.name],
              message:
                "component #{inspect(component.name)} declares a column: " <>
                  "`column` entities are only supported on :table components"
            )}}

        invalid_board?(component) ->
          {:halt,
           {:error,
            error(module, [:a2ui, :component, AshA2ui.Component.key(component), :display],
              message:
                "component #{inspect(AshA2ui.Component.key(component))} declares display " <>
                  ":board: a board needs a :table component with a sections block and " <>
                  "a row_layout"
            )}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  # A board renders sections as lanes of cards: it needs a sectioned :table
  # with a row_layout.
  defp invalid_board?(%{display: :board} = component) do
    component.name != :table or is_nil(component.sections) or is_nil(component.row_layout)
  end

  defp invalid_board?(_component), do: false

  defp verify_component(%{name: :form} = component, module) do
    verify_groups(component, module)
  end

  defp verify_component(%{name: :table} = component, module) do
    with :ok <- verify_table_row_layout(component, module) do
      verify_columns(component, module)
    end
  end

  defp verify_component(_component, _module), do: :ok

  # --- groups ---------------------------------------------------------------

  defp verify_groups(component, module) do
    with :ok <- verify_unique_group_names(component, module),
         :ok <- verify_group_fields_present(component, module),
         :ok <- verify_group_fields_known(component, module) do
      verify_group_fields_disjoint(component, module)
    end
  end

  defp verify_unique_group_names(component, module) do
    component.groups
    |> Enum.frequencies_by(& &1.name)
    |> Enum.find(fn {_name, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {name, _count} ->
        {:error,
         error(module, [:a2ui, :component, :form, :group, name],
           message: "duplicate group #{inspect(name)}: group names must be unique within a form"
         )}
    end
  end

  defp verify_group_fields_present(component, module) do
    case Enum.find(component.groups, &(&1.fields == [])) do
      nil ->
        :ok

      group ->
        {:error,
         error(module, [:a2ui, :component, :form, :group, group.name],
           message: "group #{inspect(group.name)} declares no fields"
         )}
    end
  end

  defp verify_group_fields_known(%{fields: nil}, _module), do: :ok

  defp verify_group_fields_known(component, module) do
    known = MapSet.new(component.fields)

    Enum.reduce_while(component.groups, :ok, fn group, :ok ->
      case Enum.find(group.fields, &(not MapSet.member?(known, &1))) do
        nil ->
          {:cont, :ok}

        unknown ->
          {:halt,
           {:error,
            error(module, [:a2ui, :component, :form, :group, group.name],
              message: """
              group #{inspect(group.name)} references field #{inspect(unknown)}, which is not \
              one of the form's fields.

              Every grouped field must be in the form component's (declared or inferred) \
              fields list: #{inspect(component.fields)}
              """
            )}}
      end
    end)
  end

  defp verify_group_fields_disjoint(component, module) do
    component.groups
    |> Enum.flat_map(fn group -> Enum.map(group.fields, &{&1, group.name}) end)
    |> Enum.group_by(fn {field, _group} -> field end, fn {_field, group} -> group end)
    |> Enum.find(fn {_field, groups} -> length(groups) > 1 end)
    |> case do
      nil ->
        :ok

      {field, groups} ->
        {:error,
         error(module, [:a2ui, :component, :form, :group],
           message:
             "field #{inspect(field)} belongs to more than one group " <>
               "(#{inspect(groups)}): every field may be grouped at most once"
         )}
    end
  end

  defp verify_table_row_layout(%{row_layout: nil}, _module), do: :ok

  defp verify_table_row_layout(component, module),
    do: verify_row_layout(component, component.row_layout, module)

  # --- columns ----------------------------------------------------------------

  defp verify_columns(%{columns: []}, _module), do: :ok

  defp verify_columns(component, module) do
    with :ok <- verify_unique_column_names(component, module),
         :ok <- verify_column_fields_known(component, module),
         :ok <- verify_folded_fields(component, module) do
      Enum.reduce_while(component.columns, :ok, fn column, :ok ->
        halt_on_error(verify_column_options(component, column, module))
      end)
    end
  end

  defp verify_unique_column_names(component, module) do
    component.columns
    |> Enum.frequencies_by(& &1.name)
    |> Enum.find(fn {_name, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {name, _count} ->
        {:error,
         error(module, column_path(component, name),
           message: "duplicate column #{inspect(name)}: one column per table field"
         )}
    end
  end

  defp verify_column_fields_known(%{fields: nil}, _module), do: :ok

  defp verify_column_fields_known(component, module) do
    known = MapSet.new(component.fields)

    Enum.reduce_while(component.columns, :ok, fn column, :ok ->
      case Enum.find([column.name | AshA2ui.Column.source_fields(column)], &(&1 not in known)) do
        nil ->
          {:cont, :ok}

        unknown ->
          {:halt,
           {:error,
            error(module, column_path(component, column.name),
              message: """
              column #{inspect(column.name)} references field #{inspect(unknown)}, which is \
              not one of the table's fields.

              A column and the fields it reads from must all be in the table component's \
              (declared or inferred) fields list: #{inspect(component.fields)}
              """
            )}}
      end
    end)
  end

  # A field a column reads from is drawn inside that column, so it cannot
  # also be a column of its own.
  defp verify_folded_fields(component, module) do
    names = MapSet.new(component.columns, & &1.name)

    component.columns
    |> Enum.flat_map(fn column ->
      Enum.map(AshA2ui.Column.source_fields(column), &{column, &1})
    end)
    |> Enum.find(fn {_column, field} -> MapSet.member?(names, field) end)
    |> case do
      nil ->
        :ok

      {column, field} ->
        {:error,
         error(module, column_path(component, column.name),
           message:
             "column #{inspect(column.name)} reads from #{inspect(field)}, which is a column " <>
               "of its own: a field a column reads from is drawn inside it"
         )}
    end
  end

  defp verify_column_options(component, column, module) do
    path = column_path(component, column.name)

    cond do
      is_nil(column.icon) and
          [column.icon_names, column.icon_tones, column.icon_labels] != [[], [], []] ->
        {:error,
         error(module, path,
           message:
             "column #{inspect(column.name)} declares icon_names, icon_tones or icon_labels " <>
               "without an icon field"
         )}

      is_nil(column.detail) and
          (column.detail_text != [] or not is_nil(column.detail_date) or
             column.detail_icon_names != [] or column.detail_icon_tones != []) ->
        {:error,
         error(module, path,
           message:
             "column #{inspect(column.name)} declares detail_text, detail_date or detail icons " <>
               "without a detail field"
         )}

      is_nil(column.more) and not is_nil(Map.get(column, :more_values)) ->
        {:error,
         error(module, path,
           message: "column #{inspect(column.name)} declares more_values without a more field"
         )}

      is_nil(column.detail) and not is_nil(Map.get(column, :detail_help)) ->
        {:error,
         error(module, path,
           message: "column #{inspect(column.name)} declares detail_help without a detail field"
         )}

      is_nil(Map.get(column, :help)) and not is_nil(Map.get(column, :help_title)) ->
        {:error,
         error(module, path,
           message: "column #{inspect(column.name)} declares help_title without help"
         )}

      true ->
        verify_column_mappings(column, path, module)
    end
  end

  defp verify_column_mappings(column, path, module) do
    [
      {:icon_names, column.icon_names, &(&1 in AshA2ui.Column.icons()),
       "one of #{inspect(AshA2ui.Column.icons())}"},
      {:icon_tones, column.icon_tones, &(&1 in AshA2ui.RowLayout.tones()),
       "one of #{inspect(AshA2ui.RowLayout.tones())}"},
      {:icon_labels, column.icon_labels, &is_binary/1, "a string"},
      {:detail_text, column.detail_text, &is_binary/1, "a string"},
      {:detail_icon_names, column.detail_icon_names, &(&1 in AshA2ui.Column.icons()),
       "one of #{inspect(AshA2ui.Column.icons())}"},
      {:detail_icon_tones, column.detail_icon_tones, &(&1 in AshA2ui.RowLayout.tones()),
       "one of #{inspect(AshA2ui.RowLayout.tones())}"}
    ]
    |> Enum.find_value(:ok, &invalid_mapping(&1, path, module))
  end

  defp invalid_mapping({option, mapping, valid?, expected}, path, module) do
    case Enum.find(mapping, fn {_value, mapped} -> not valid?.(mapped) end) do
      nil ->
        nil

      {value, mapped} ->
        {:error,
         error(module, path ++ [option],
           message: "#{option} for #{inspect(value)} must be #{expected}, got: #{inspect(mapped)}"
         )}
    end
  end

  defp column_path(component, name),
    do: [:a2ui, :component, AshA2ui.Component.key(component), :column, name]

  # --- row_layout -------------------------------------------------------------

  defp verify_row_layout(component, layout, module) do
    with :ok <- verify_layout_fields_known(component, layout, module),
         :ok <- verify_layout_fields_distinct(layout, module),
         :ok <- verify_badge_text(layout, module) do
      verify_badge_tones(layout, module)
    end
  end

  defp verify_layout_fields_known(%{fields: nil}, _layout, _module), do: :ok

  defp verify_layout_fields_known(component, layout, module) do
    known = MapSet.new(component.fields)

    layout
    |> referenced_fields()
    |> Enum.find(&(not MapSet.member?(known, &1)))
    |> case do
      nil ->
        :ok

      unknown ->
        {:error,
         error(module, [:a2ui, :component, component.name, :row_layout],
           message: """
           row_layout references field #{inspect(unknown)}, which is not one of the table's \
           fields.

           title, badge, and meta must all reference the table component's (declared or \
           inferred) fields list: #{inspect(component.fields)}
           """
         )}
    end
  end

  defp verify_layout_fields_distinct(layout, module) do
    layout
    |> referenced_fields()
    |> Enum.frequencies()
    |> Enum.find(fn {_field, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {field, _count} ->
        {:error,
         error(module, [:a2ui, :component, :table, :row_layout],
           message:
             "row_layout references field #{inspect(field)} more than once across " <>
               "title, badge, and meta"
         )}
    end
  end

  defp verify_badge_text(%{badge: nil, badge_text: [_ | _]}, module) do
    {:error,
     error(module, [:a2ui, :component, :table, :row_layout, :badge_text],
       message: "row_layout declares badge_text without a badge field"
     )}
  end

  defp verify_badge_text(layout, module) do
    case Enum.find(layout.badge_text, fn {_value, text} -> not is_binary(text) end) do
      nil ->
        :ok

      {value, text} ->
        {:error,
         error(module, [:a2ui, :component, :table, :row_layout, :badge_text],
           message: "badge_text for #{inspect(value)} must be a string, got: #{inspect(text)}"
         )}
    end
  end

  defp verify_badge_tones(%{badge: nil, badge_tones: [_ | _]}, module) do
    {:error,
     error(module, [:a2ui, :component, :table, :row_layout, :badge_tones],
       message: "row_layout declares badge_tones without a badge field"
     )}
  end

  defp verify_badge_tones(layout, module) do
    case Enum.find(layout.badge_tones, fn {_value, tone} ->
           tone not in AshA2ui.RowLayout.tones()
         end) do
      nil ->
        :ok

      {value, tone} ->
        {:error,
         error(module, [:a2ui, :component, :table, :row_layout, :badge_tones],
           message:
             "badge_tones for #{inspect(value)} must be one of " <>
               "#{inspect(AshA2ui.RowLayout.tones())}, got: #{inspect(tone)}"
         )}
    end
  end

  defp referenced_fields(layout) do
    Enum.reject([layout.title, layout.badge], &is_nil/1) ++ (layout.meta || [])
  end

  defp error(module, path, opts) do
    DslError.exception([module: module, path: path] ++ opts)
  end

  defp components(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Component))
  end
end
