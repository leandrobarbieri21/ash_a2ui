# Localization: translating the library's own strings

ash_a2ui writes some text itself: button labels ("Save", "Cancel", "Next"),
pagination ("1–20 of 143"), empty states ("No Ticket records yet."), panel
titles ("Create Ticket"), feedback ("Updated successfully.") and the
TimeScrubber's text. It also derives display labels from field and action
names (`:due_date` becomes "Due date"). These strings ship as a gettext
catalog, `priv/gettext/ash_a2ui.pot`, and are translated only when the host
passes a translator and a locale.

## Setting it up

- Copy the catalog into the app with `mix ash_a2ui.gen.gettext`, which
  writes `priv/gettext/ash_a2ui.pot`. With `--domain default` (or another
  domain) the entries are merged into that domain's `.pot` instead, between
  `## -- ash_a2ui-gettext:start --` markers, next to any section
  `mix ash.gen.gettext` wrote.
- Run `mix gettext.merge priv/gettext --locale fr` and fill in the
  `msgstr`s. Re-run both after upgrading ash_a2ui.
- Add the app's own declared labels (a field's `label "Due date"`, a
  surface `title`) to the same domain if they should be translated: every
  display label goes through the translator.

## Passing the translator

- Pass `gettext_backend: {MyAppWeb.Gettext, "ash_a2ui"}` and
  `locale: "fr"` to `AshA2ui.Info.build_surface/2`, `build_data_model/2`,
  `AshA2ui.ActionHandler.handle/3` and `AshA2ui.Diagram.refresh_messages/2`.
  Pass the same values to every call for one surface, or a refresh will
  switch language.
- `locale:` is always explicit. ash_a2ui never reads the process's
  Gettext locale (`Gettext.get_locale/1`), because builds run in async
  tasks and PubSub handlers where the ambient locale is not the reader's.
  `gettext_backend:` without `locale:` raises.
- For a translation layer that is not Gettext, pass
  `gettext_fn: {Module, :function}` instead. It is called as
  `Module.function(msgid, bindings)`, or with the locale as a third
  argument when `locale:` is given. `bindings` is a keyword list; return the
  translated, interpolated string. Return `nil` for "no translation".
- `AshA2ui.LiveRenderer`: pass `locale_fn: &(&1.assigns.locale)` and
  `gettext_backend:` (or `gettext_fn:`) to `use AshA2ui.LiveRenderer`. They
  reach the build, every refresh and every action.
- `AshA2ui.TimeScrubber`: pass the same `locale`, `gettext_backend` or
  `gettext_fn` attributes.
- ash_a2ui does not depend on `:gettext`. The host brings it.

## What is and is not translated

- Translated: declared and derived display labels (fields, columns,
  actions, contexts, groups, steps, prompt fields), surface and record
  titles, the library's chrome and feedback templates.
- Never translated: ids, data-model paths, enum and option values, action
  and field names, and record data. Labels derived from records (option
  labels, context labels) are the record's own text.
- Each string is translated once, where it is chosen. A template with a
  translated label inside ("Create %{resource}") gets the translated label
  as a binding.
- A missing translation falls back to the English msgid, string by string.
- Not yet translated: enum and choice labels, declared help text,
  descriptions, placeholders and empty-state text, the presence bar, and
  Ash's own error messages (translate those with `mix ash.gen.gettext`, as
  the Ash docs describe).

## Maintaining the catalog (library contributors)

- Wrap every new user-facing string in `AshA2ui.Gettext.msg/1` (a
  compile-time no-op the extractor looks for) and send it through
  `AshA2ui.L10n.t/3` or `AshA2ui.Label.resolve/3`. Use `%{name}`
  placeholders, never string interpolation, inside a msgid.
- Run `mix ash_a2ui.gettext.extract` and commit the `.pot`. A test fails
  when it is stale.
