# Wizard Steps

A long create or edit form can be split into **steps**: pages the user
moves through with Back and Next, ending in an optional read-only review
before the usual submit. A stepped form is still one form over one Ash
action. Steps change what is shown and when the server checks it; they do
not change what is written.

The vocabulary (form steps, a closing review step) is borrowed from
[PyroManiac](https://github.com/frankdugan3/pyro_maniac), an Ash UI DSL that
declares form steps for its own renderer. We took the idea, not the code;
the design record is `notes/2026-10-15-pyro-maniac-borrowings.md`.

## Declaring steps

`step` entities go inside `component :form`, in order:

```elixir
component :form do
  fields [:name, :email, :role, :team]
  create_action :create
  update_action :update

  step :who do
    label "Who"                       # defaults to the humanized name
    description "Who is enrolling?"   # optional help text
    fields [:name, :email]
  end

  step :what do
    fields [:role, :team]
  end

  step :confirm do
    review? true                      # read-only summary of /form
  end
end
```

The compiler checks the declaration (`AshA2ui.Verifiers.VerifySteps`):

- every form field is in exactly one step, and every step field is a form
  field;
- step names are unique, and a stepped form has at least two steps;
- `review?` is allowed only on the last step and only without `fields`;
  every other step declares at least one field;
- `step` is not mixed with `group` or `nested_form` on the same form
  (groups and nested rows inside steps are a later item).

## What the server does

| Action | Context | What happens |
|---|---|---|
| `"wizard_next"` | `{"values": /form, "recordId": /form/id, "index": /ui/wizard/index}` | Builds the **full** changeset over the carried values, through the same code path `submit_form` writes with (`Ash.Changeset.for_create`, or `for_update` on the record read through the surface's read action), without submitting it. Errors on fields of the current or an earlier step go to `/errors/<field>` and the index stays; otherwise `/errors` clears and the index advances. Nothing is written to the data layer. |
| `"wizard_back"` | `{"index": /ui/wizard/index, "recordId": /form/id}` | Moves back one step. No validation; `/form` is not touched. |
| `"submit_form"` | unchanged | The usual create/update, over the same filtered values Next validated. On failure the index jumps to the earliest step owning an erroring field; an error on no step's field stays on the last step with the status line. |

`start_create`, `view_record`, `start_edit`, `cancel_record_task` and a
successful `submit_form` reset the index to step 0. Under experience v1,
`select_row` (which loads a record into the form) and every other
successful action (which clears `/form`) reset it as well. Under v2 a
successful row action leaves an open task's step alone, so the step and
the panel's primary label stay in agreement.

Everything the client carries is re-checked:

- `/form` keys outside the form's own fields are dropped before the cast,
  on `wizard_next` and on the final `submit_form` alike (both build the
  changeset through one shared path). A key the Ash action accepts but the
  form does not render never reaches the changeset. Keys are compared as
  strings; no atom is created. Forms without steps are unchanged:
  `submit_form` still casts every key the action accepts.
- The carried index is clamped into the step range. A value that is not an
  integer (or an integer string) is refused with a status message.
- Next validates every step up to the (clamped) index, so a client cannot
  skip a step's checks by sending a later index. The final `submit_form`
  validates everything regardless.

Validation runs the action's validations and changes at changeset-build
time, as `Ash.Changeset.for_create/4` always does. Before-action hooks,
authorization of the write and the data layer only run on the final
submit.

## Data model

Only surfaces whose form has steps carry `/ui/wizard`:

```json
{
  "index": 0,
  "steps": [
    {"name": "who", "label": "Who", "state": "current"},
    {"name": "what", "label": "What", "state": "todo"},
    {"name": "confirm", "label": "Confirm", "state": "todo"}
  ],
  "who_visible": [{"id": "on"}],
  "what_visible": [],
  "confirm_visible": [],
  "nav": {
    "back_visible": [],
    "next_visible": [{"id": "on"}],
    "submit_visible": []
  }
}
```

`state` is `"done"`, `"current"` or `"todo"`. The `*_visible` values are
zero-or-one lists, the same technique as the `/ui/panel/*_visible` flags
(see [Data Model Conventions](data-model-conventions.md)).

## What the encoder emits

The basic catalog has no stepper (the upstream request was closed in favor
of custom catalogs), so the wizard is composed from basic components and
works on v0.9.1 and v1.0 alike:

- `form_wizard` — a `Column` that replaces the form's field children:
  - `form_wizard_progress` — a horizontal `List` templated over
    `/ui/wizard/steps` (label + state per step);
  - `form_step_<step>_slot` — a `List` templated over
    `/ui/wizard/<step>_visible`, rendering `form_step_<step>`: a heading,
    the optional description, and the step's usual `form_input_<field>` /
    `form_error_<field>` pairs. A review step renders `form_review_<field>`
    rows instead: a caption and a `Text` bound to `/form/<field>`, or to
    `/select/<field>/label` for a searchable select (so the picked
    record's label shows, not its id);
  - `form_wizard_nav` — a `Row` with the Back and Next buttons, each behind
    its `/ui/wizard/nav/*_visible` sentinel.
- Experience v1: the form `Column`'s submit is wrapped in
  `form_wizard_submit_slot` (behind `/ui/wizard/nav/submit_visible`), so it
  appears on the last step only.
- Experience v2: the wizard is the task panel's form content. The Next
  button's label binds `/ui/panel/primary_label`, which reads "Next" before
  the last step and the usual "Create X" / "Save changes" on it; the
  panel's `submit_visible` hides the submit until the last step.
- The admin catalog (`catalog: :admin_v1`) keeps a stepped form on the
  basic composition, as it does for nested forms.

Forms without steps emit exactly what they did before; a test compares
their full surfaces against snapshots taken before steps existed.

The review step shows choice fields (enums, `one_of` constraints and
non-searchable relationship selects) by their stored value, not their
option label: the review `Text` binds the raw `/form` value, and a
single-select choice is carried as a one-element list. If that matters for
a form, put such fields on an earlier step and leave them out of the
review, or render your own summary.

## When to use something else

Steps cover linear flows over one Ash action, validated by the server at
each step. Branching flows (the next step depends on an answer), steps that
upload files, and steps that wait on background work (polling a job) still
belong in a LiveView. Agent-composed surfaces (`AshA2ui.Dynamic`) do not
accept steps yet.
