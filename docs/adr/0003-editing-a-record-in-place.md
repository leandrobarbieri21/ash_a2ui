# 0003. Editing a record in place: drafts on the client, one save through declared actions

- Status: proposed
- Date: 2026-11-20

## Context

A record page built from `:detail` cards was read-only. Hosts need a person to correct a value
where they read it: a value an extraction read wrongly from a document, say, while the record
keeps its other state (a review already recorded). The design they work from has the value open
as an input in place, Enter or leaving it keep the change, Escape drops it, and nothing is
stored until a bar at the bottom of the page saves every change at once. While values under
review still wait, the save asks first: save the progress, or save and finish the review.

Tables already had `editable`, but it commits each cell on its own Save, and it cannot be
combined with a `row_layout`. Neither fits a page whose changes wait for one save.

## Decision

### 1. `editable` on a `:detail`, the input from the edited attribute

The table's `editable` entity also goes on a `:detail` card, with `visible` (a boolean field of
the record) gating it per record. The fields are the card's; a field shown as a display
calculation names the attribute behind it with the field's `edit` option. The input kind comes
from that attribute's type (text, integer, number, date, or a choice of an enum's or `one_of`'s
values). One entity keeps one allowlist idea: the fields listed are the only ones a client may
change, and the verifier holds them to what the update action accepts.

### 2. Drafts live in the surface's data model, not in the elements

A change is written to `/ui/edits/<card>/values/<field>` (with the card's record id). Every
element that needs it binds it: the field shows its draft, the bar counts the changes. The hook
keeps `/ui/edits` across a write of the whole data model (as it keeps a prompt's edits), so a
refresh never drops a person's work. Only the server's own write of `/ui/edits` (after a save)
replaces it. Each map is written whole, never a path inside it, because a binding of the whole
map does not see writes below it.

### 3. One save, through the actions the surface declares, in one transaction

The `save_bar` sends `save_changes` with every card's changes. The client names cards and
fields, never actions: each card's `editable` is the allowlist, as a field action's declaration
is. The server re-reads each record as the actor through its context, refuses it unless
`visible` holds, and runs each card's update action with only the changed fields. All of it runs
in one transaction (on a data layer that has them), so a refused card saves nothing. Each card
declares its own action, so a page whose cards are different records (a contract and its renewal
term) saves both, all or nothing.

### 4. The dialog's second choice is a declared action on the bar's record

`confirm` asks while fields under review (the context's `review` fields) still wait. Its second
choice runs `then_action` after the saves, in the same transaction, offered only while
`then_visible` holds; the server checks it again. `edit_reviews` tells the bar that saving an
edited field reviews it (the host's update action records that), so the count leaves edited
fields out. The count is the client's, from the bound review states: it changes as the person
types, so the dialog's words carry `%{count}` with a form for one, and the client picks.

## Consequences

- Admin catalog 3.9.0: `fieldDisplay` gains `edit`, `editValue`, `editVisible`, `editDraft` and
  `editError`; a new `saveBar` component. Both are additive: a renderer or swap that ignores
  them draws the card read-only.
- A surface with an editable card must declare a `save_bar` (nothing else would save it).
- On a data layer without transactions (ETS), a refusal after an earlier card's write leaves that
  write. The package says so; hosts on Postgres get all or nothing.

## Not decided here

- Holding a field action's write (a review mark) until Save, as the change is. A host that wants
  it today records the mark at once.
- A "Leave without saving?" guard on navigation away from a page with changes.
