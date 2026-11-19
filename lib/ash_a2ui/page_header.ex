defmodule AshA2ui.PageHeader do
  @moduledoc """
  Target struct for the `page_header` DSL entity: the page's header drawn by
  the surface (admin catalog 3.5) — a breadcrumb, the title, a line of tags
  and notes, and buttons — read from the record selected into `context`.

  The header's fields are read with that record into `/detail/<context>`,
  like a `:detail` card's, so every refresh of the record (a context
  change, a field action, a `page_action`) redraws the header too. Each
  `header_action` that runs an action carries whether it is offered at
  `/detail/<context>/_header_action_<name>`: its `visible` field holds and
  `Ash.can?/3` lets the person run it. See `data/3`.
  """

  alias AshA2ui.PageHeader.{Action, Item}

  defstruct [
    :context,
    :title,
    breadcrumb_label: "Breadcrumb",
    crumbs: [],
    tags: [],
    meta: [],
    actions: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          context: atom,
          title: atom,
          breadcrumb_label: String.t(),
          crumbs: [AshA2ui.PageHeader.Crumb.t()],
          tags: [Item.t()],
          meta: [Item.t()],
          actions: [Action.t()]
        }

  @doc "The record fields the header reads, in a stable order."
  @spec fields(t() | nil) :: [atom]
  def fields(nil), do: []

  def fields(%__MODULE__{} = header) do
    items =
      Enum.flat_map(header.tags ++ header.meta, fn item ->
        [item.field, item.tone, item.icon_field, item.help_field]
      end)

    actions = Enum.flat_map(header.actions, &[&1.href, &1.visible])

    Enum.uniq(Enum.reject([header.title | items ++ actions], &is_nil/1))
  end

  @doc """
  The header's computed data for `record`: `_header_action_<name>`, for
  each `header_action` that runs an action, whether it is offered to the
  person (`offered?/3`). Merged into `/detail/<context>`.
  """
  @spec data(t() | nil, struct(), keyword) :: %{String.t() => boolean}
  def data(nil, _record, _opts), do: %{}

  def data(%__MODULE__{actions: actions}, record, opts) do
    for %Action{run: run} = action <- actions, run, into: %{} do
      {"_header_action_#{action.name}", offered?(action, record, opts)}
    end
  end

  @doc """
  Whether a header action that runs an Ash action is offered on `record`:
  its `visible` field (when declared) is `true`, and `Ash.can?/3` says the
  actor may run it on that record (`maybe_is: false`: a check that cannot
  decide is a no).
  """
  @spec offered?(Action.t(), struct(), keyword) :: boolean
  def offered?(%Action{run: run} = action, record, opts) do
    visible?(action, record) and
      Ash.can?({record, run}, opts[:actor],
        tenant: opts[:tenant],
        maybe_is: false
      ) == true
  end

  defp visible?(%Action{visible: nil}, _record), do: true
  defp visible?(%Action{visible: field}, record), do: Map.get(record, field) == true

  @doc "The header action named `name` (a string from the client) that runs an action."
  @spec runnable(t() | nil, String.t()) :: Action.t() | nil
  def runnable(nil, _name), do: nil

  def runnable(%__MODULE__{actions: actions}, name) when is_binary(name) do
    Enum.find(actions, &(&1.run && Atom.to_string(&1.name) == name))
  end

  def runnable(_header, _name), do: nil
end
