defmodule AshA2ui.Label do
  @moduledoc """
  The one place a display label is derived from a name.

  Every heading, column, field, action, context, group, step and choice
  label that the DSL does not declare is the humanized name: underscores
  become spaces and the first letter is capitalized (`:due_date` →
  `"Due date"`). Declared labels are used as written.

  It is also the one place a label is translated: `resolve/4` and
  `translate/3` pass the chosen label through the surface's translator
  (`AshA2ui.L10n.metadata/3`), once, where the label is chosen, in the host's
  metadata domain. Without a translator the label is returned unchanged.
  `mix ash_a2ui.gettext.extract_metadata` collects the labels by resolving
  every surface through these functions, so its msgids are the labels shown.
  """

  alias AshA2ui.L10n

  @doc """
  The display label for `name`: the declared `label` when it is not `nil`,
  else the humanized name, translated with `l10n` under the msgctxt
  `context` (see `translate/3`).
  """
  @spec resolve(L10n.t(), String.t() | nil, atom | String.t(), String.t() | nil) :: String.t()
  def resolve(l10n, label, name, context \\ nil),
    do: translate(l10n, label || humanize(name), context)

  @doc """
  Translates an already chosen display label with `l10n`, in the metadata
  domain, under the msgctxt `context` when it is not `nil` (a value's label,
  so homographs translate separately). Labels carry no placeholders, so
  nothing is interpolated.
  """
  @spec translate(L10n.t(), String.t(), String.t() | nil) :: String.t()
  def translate(l10n, label, context \\ nil) when is_binary(label),
    do: L10n.metadata(l10n, label, context)

  @doc """
  The humanized form of an atom or string name: underscores to spaces, the
  first letter capitalized and the rest downcased (`String.capitalize/1`).

      iex> AshA2ui.Label.humanize(:due_date)
      "Due date"
  """
  @spec humanize(atom | String.t()) :: String.t()
  def humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  @doc """
  The humanized short name of a resource module (`MyApp.BulkTask` →
  `"Bulk task"`).

      iex> AshA2ui.Label.resource_name(MyApp.BulkTask)
      "Bulk task"
  """
  @spec resource_name(module) :: String.t()
  def resource_name(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> humanize()
  end

  @doc """
  A name with underscores as spaces and its case kept, for authoring tools
  that show a DSL key as words (`"option_label"` → `"option label"`).

      iex> AshA2ui.Label.words("option_label")
      "option label"
  """
  @spec words(String.t()) :: String.t()
  def words(name) when is_binary(name), do: String.replace(name, "_", " ")
end
