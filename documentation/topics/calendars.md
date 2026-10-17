# Calendars

A `:table` can render its records on a calendar: a month grid, one week or
one day. You declare it with `display :calendar` and name the date field
that places each record. The table's `query` then reads only the visible
window, so search, filters, presets, context scoping, the actor's
authorization and pagination all work as they do for a list.

Calendars add no component kind and no client-supplied range. The client
only names a date (the window to show, or the day it picked); the server
works out the range and reads it as the actor.

## Declaring a calendar

```elixir
query :schedule do
  filters [:status]
  page_size 50
end

component :table, :schedule do
  fields [:title, :status, :starts_on, :ends_on]
  display :calendar
  date_field :starts_on
  end_date_field :ends_on      # optional: multi-day records
  granularity :month           # :month (default), :week or :day
  query :schedule
  row_actions [:confirm]

  row_layout do
    title :title
    badge :status
    badge_tones booked: :info, confirmed: :success, cancelled: :danger
  end
end
```

The rules, checked at compile time:

- `display :calendar` is for `:table` components, and needs a `date_field`
  and a `query`.
- `date_field` and `end_date_field` are public attributes of the table's
  resource of type `:date`, `:utc_datetime`, `:utc_datetime_usec`,
  `:datetime` or `:naive_datetime`. They must differ.
- `granularity` is `:day`, `:week` or `:month`.
- A calendar declares no `sections` and no `bulk_actions`.
- `date_field`, `end_date_field` and `granularity` are only accepted with
  `display :calendar`.

## The window

The window is part of the table's query state, at
`/query/<table>/window` (`/query/window` on a single-table surface):

```json
{
  "granularity": "month",
  "anchor": "2026-10-01",
  "from": "2026-10-01",
  "to": "2026-10-31",
  "selected": "",
  "label": "2026-10",
  "scopeLabel": "2026-10",
  "marks": [{"date": "2026-10-16", "count": 2, "label": "2026-10-16 (2)"}]
}
```

- A month window runs from the first to the last day of the month, a week
  window from Monday to Sunday, and a day window is one day.
- The first render shows the window holding today (`Date.utc_today/0`). A
  host can pass a carried state through `AshA2ui.Info.build_surface/2`'s
  `:query_state` option, e.g. `%{"window" => %{"anchor" => "2026-10-01"}}`.
- `marks` lists the days of the window that hold at least one record, with
  the count. They cover the whole window even when a day is picked or the
  window holds more records than one page.
- When the client sends the state back, only `anchor` and `selected` are
  read, as ISO 8601 dates. `from`, `to`, the labels and the marks are
  ignored.

Records match the window like this:

- Without an `end_date_field`, a record matches when its `date_field` is in
  the window.
- With an `end_date_field`, a record matches when it overlaps the window:
  it starts on or before the last day and ends on or after the first day. A
  `nil` end counts as the start day.
- Datetimes are compared in UTC. A day runs from 00:00:00 to
  23:59:59.999999 UTC.

Without a `default_sort` (and with no sort requested), a calendar reads in
`date_field` order.

## Moving the window and picking a day

Both are the ordinary `"query"` action. Next to the usual
`"query": {"path": ...}` binding, the context may carry:

| Key | Meaning |
|---|---|
| `"anchor": "2026-11-01"` | Show the window holding this date. `"today"` is accepted. |
| `"windowDelta": 1` | Move the window by whole months, weeks or days from the carried anchor. |
| `"date": "2026-10-16"` | Pick a day. `""` clears the pick. |

- A picked day narrows the records read to that day. The marks still cover
  the whole window.
- On a `:day` calendar, picking a day moves the window to it.
- Moving the window keeps the picked day only when it is still inside the
  new window.
- Either change resets the page to 1.
- Anything that is not an ISO date (or an integer delta) is rejected with
  an error status, and no read runs.

A row action's refresh carries the query state like any other refresh, so
the window and the picked day survive it.

Each row of a calendar table carries three reserved keys:
`_calendar_start` and `_calendar_end` (ISO dates; the end is never before
the start) and `_calendar_when` (the record's date or time span as text, in
UTC, for example `2026-10-16 – 2026-10-18` or `2026-10-20 09:30 – 09:45`).

## Rendering

### Basic catalog

The basic composition is the table's usual list, with window controls above
it, built only from basic-catalog components:

- a navigation Row: Previous, the window label, Next and Today;
- on month and week calendars, one Button per marked day (a horizontal
  List over `marks`) that picks the day, and a Row with the picked day (or
  the window) and an "All days" Button;
- each row starts with its `_calendar_when` text.

The list is an agenda of the window's records, or of the picked day's. Any
basic-catalog renderer shows it. The AshA2ui merged catalog renders the
calendar Buttons in its quiet utility tier.

### Admin catalog

Under `config :ash_a2ui, :catalog, :admin_v1` (admin catalog 1.3), the
table is emitted as a `calendarView` wrapping the table's `dataGrid`:

```json
{
  "id": "calendar",
  "component": "calendarView",
  "label": "Event",
  "granularity": "month",
  "window": {"path": "/query/window"},
  "windowAction": {
    "name": "query",
    "context": {"query": {"path": "/query"}, "component": "schedule"}
  },
  "children": ["data_grid"]
}
```

The renderer draws an `nb-calendar` grid (a month, or one week for week and
day calendars) with the marked days, beside the `dataGrid`. The grid keeps
its row actions, prompts, badges, links, empty state and pagination.

The renderer follows zero-jank rules. When the user moves the window or
picks a day, the grid changes at once, and the envelope carries the date
the grid now shows (`anchor` or `date`), never a delta. While requests are
in flight, replies to earlier requests do not move the grid back. The reply
to the latest request matches what is on screen.

`calendarView` uses `nb-calendar` from `priv/js/nb_components.js`. The
admin catalog imports that file and defines its elements itself, so a host
needs nothing beyond its existing `createAshAdminCatalog` setup.

## Limits

- One page of records per window. Set the query's `page_size` to the
  number of records a window usually holds. Pagination appears when a
  window holds more.
- The marks read is capped at 1,000 records per window.
- Days are UTC days. There is no per-actor time zone yet.
- The dynamic surface spec has no calendar vocabulary. Importing a
  calendar into a spec keeps a plain table and reports a rejection.
