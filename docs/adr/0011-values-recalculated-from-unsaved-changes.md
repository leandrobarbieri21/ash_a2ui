# 0011. Values recalculated from unsaved changes: the save's own actions, rolled back

- Status: proposed
- Date: 2026-11-24
- Builds on: [0010](0010-editing-a-record-in-place.md) (drafts on the client, one save
  through declared actions), [0006](0006-the-js-elixir-boundary.md) (the server decides
  meaning, the browser draws), [0007](0007-authorization-has-no-side-channel.md) and
  [0009](0009-untrusted-input-names-things-and-the-server-resolves-them.md).

## Context

A record page shows values worked out from the values a person corrects in place: a
notice date from an end date and a notice period, a yearly amount from a monthly one. Under
0010 those values change only once the save lands, so while checking a correction the person
cannot see what it does. Hosts want the worked-out values to follow the unsaved changes, before
Save.

The rule that works a value out is the host's: a calculation, an expression the data layer
evaluates, a decision table, or an attribute an action's change stores (a deadline kept so
every reader uses the same one). A copy of that rule in the browser would drift from it. Even
on the server, loading the calculations on a record with the changes applied in memory falls
short: an expression the data layer evaluates reads the stored row, and a value an action's
change derives is never computed.

## Decision

### 1. A field declares that it follows the changes

A field's `recalculate true` marks it as worked out from the record's editable values. It must
be drawn on a `:detail` card whose context has an editable card, and must not be editable itself
(an edited value shows the person's change). The verifier holds both.

### 2. The server runs the save, reads, and rolls back

The save bar sends `preview_changes` with the same edits `save_changes` takes, whenever they
change. The server resolves them through the same allowlist, re-reads each card's record as the
actor, refuses it unless `visible` holds, and runs each card's `update_action` with the changes,
as the save would, inside one transaction. It reads the recalculated fields with each context's
record inside the transaction, then rolls it back. Whatever the host's rule is, the value is the
one the save would produce. The values leave the transaction through the process dictionary,
since each data layer reports a rollback's value in its own shape. The actions return their
notifications instead of sending them, and the notifications queued in the transaction are
dropped with it.

A context resource without transactions cannot be rolled back, so the verifier refuses
`recalculate` there (ETS), and the server checks again before running anything.

### 3. The result is a draft too

The result goes to `/ui/preview/<context>/<field>` as the field's display value (and a steps
field's steps), and the field binds it as `preview`. It sits beside `/ui/edits` and lives as
long as the changes do: Discard clears it, a save clears it, and a whole-model refresh keeps it
while it keeps the changes. Writing `/detail/<context>` instead would be undone by any other
action that re-sends the record (a field's review mark) while the changes still wait.

An update the action refuses previews nothing: the stored values show, and Save reports the
refusal at the inputs, as before. The action is quiet: it never touches the outcome line.

## Consequences

- Admin catalog 3.15.0, additive: `fieldDisplay` gains `preview`, `saveBar` gains `preview`
  (the envelope). A renderer that ignores them shows the stored values until Save.
- Each kept change costs a write and a rollback on the server: the actions run, with their
  locks, inside a transaction that never commits. Changes are kept on Enter or leaving an input,
  not per keystroke, so there is one preview per kept change.
- A host's side effect that escapes the transaction runs on every preview: an HTTP call in an
  `after_action`, a message sent to another process, and an `after_transaction` hook (the
  preview's transaction surrounds the action's, so the hook runs before the rollback). Effects
  that are notifications, or jobs enqueued in the same database, are rolled back with it. A host
  whose update actions have other effects should not mark fields `recalculate`.

## Not decided here

- Previewing values shown outside `:detail` cards (a page header's meta, a table's rows).
