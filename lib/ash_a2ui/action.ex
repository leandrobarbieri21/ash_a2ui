defmodule AshA2ui.Action do
  @moduledoc """
  Target struct for the `action` DSL entity: per-action metadata.

  * `label` is the text of the action's buttons (row, bulk, prompt — both
    compositions); `nil` (the default) uses the humanized action name.
  * `refreshes` names the table components (by component key — the unnamed
    table is `:table`) whose records are refreshed after the named Ash action
    succeeds. `nil` (the default) refreshes every table; `[]` refreshes none.
  * `prompt_fields` declares action arguments/accepts collected from the user
    in a per-row prompt (Modal) before the action is invoked.
  * `visible_when` is a keyword list of per-record equality conditions
    (`nil` means `is_nil`, a list means membership) that gate whether the row
    action is offered — and, mandatorily, whether the handler accepts it.
  * `prompt_options` holds the per-row option scopes of relationship
    prompt fields (`AshA2ui.PromptOptions`): such a field offers only the
    options a destination read action returns for the row the prompt is
    opened on.
  * `via` delegates a row action to a host-provided function instead of
    running the mapped Ash action directly: the row button still emits the
    ordinary `invoke` event, but the handler calls
    `apply(module, function, [context | extra_args])` and renders whatever
    the function returns through the standard success/error channels (see
    the `via` option docs on `AshA2ui` for the exact contract). `nil` (the
    default) dispatches to the Ash action named by the row action, as before.
  """

  defstruct [
    :name,
    :label,
    :refreshes,
    :prompt_title,
    :via,
    prompt_fields: [],
    prompt_options: [],
    visible_when: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          refreshes: [atom] | nil,
          prompt_fields: [atom],
          prompt_options: [AshA2ui.PromptOptions.t()],
          prompt_title: String.t() | nil,
          visible_when: [{atom, term}],
          via: {module, atom, [term]} | nil
        }
end
