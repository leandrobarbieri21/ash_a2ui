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
- `granularities`, when given, is a non-empty list of those that includes
  `granularity` (which defaults to its first entry).
- A calendar declares no `sections` and no `bulk_actions`.
- `date_field`, `end_date_field`, `granularity` and `granularities` are
  only accepted with `display :calendar`.

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
  "preset": "",
  "label": "2026-10",
  "scopeLabel": "2026-10",
  "marks": [{"date": "2026-10-16", "count": 2, "label": "2026-10-16 (2)"}]
}
```

- A month window runs from the first to the last day of the month, a week
  window from Monday to Sunday, and a day window is one day.
- The first render shows the window holding today, in the calendar time
  zone (see below). A host can pass a carried state through `AshA2ui.Info.build_surface/2`'s
  `:query_state` option, e.g. `%{"window" => %{"anchor" => "2026-10-01"}}`.
- `marks` lists the days of the window that hold at least one record, with
  the count. They cover the whole window even when a day is picked or the
  window holds more records than one page.
- When the client sends the state back, only `anchor` and `selected` (as
  ISO 8601 dates) and `preset` (see "Quick ranges") are read. `from`, `to`,
  the labels and the marks are ignored.

Records match the window like this:

- Without an `end_date_field`, a record matches when its `date_field` is in
  the window.
- With an `end_date_field`, a record matches when it overlaps the window:
  it starts on or before the last day and ends on or after the first day. A
  `nil` end counts as the start day.
- For datetime fields, a day runs from local midnight to just before the
  next local midnight in the calendar time zone. A day that a
  daylight-saving change shortens or lengthens keeps its true length; when
  the change skips midnight, the day starts at the first instant after the
  gap.

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

## Switching between month, week and day

`granularities` lets the user change the window's size:

```elixir
component :table, :schedule do
  display :calendar
  date_field :starts_at
  granularities [:month, :week]   # opens on the month
  query :schedule
end
```

The client sends `"granularity": "week"` in a `"query"` action's context.
The server accepts only a size in `granularities`; anything else is
rejected before a read. The new window keeps the user's place: it holds the
picked day, else today when the old window held it, else the old window's
first day. The picked day survives when it is inside the new window (a day
window has none). The window state's `granularity` is the size shown, and
later requests keep it. The basic composition adds one Button per size to
the navigation Row; the admin `calendarView` carries `granularities` and
draws a switch (admin catalog 1.5).

Each row of a calendar table carries three reserved keys:
`_calendar_start` and `_calendar_end` (ISO dates; the end is never before
the start) and `_calendar_when` (the record's date or time span as text, in
the calendar time zone, for example `2026-10-16 – 2026-10-18` or
`2026-10-20 09:30 – 09:45`).

## The time zone

Days are cut in one time zone, set by the host:

```elixir
config :ash_a2ui, :calendar_time_zone, "America/Toronto"
# or, read on every request:
config :ash_a2ui, :calendar_time_zone, {MyApp.Clock, :zone, []}
```

The default is `"Etc/UTC"`. A zone other than UTC needs a time zone
database (`config :elixir, :time_zone_database, Tz.TimeZoneDatabase`, or
Tzdata's).

The zone decides which day "today" is (the first window, `"anchor":
"today"`, `calendar_anchor`), where a datetime field's day starts and ends,
which day a datetime record is marked on, and the times in
`_calendar_when`. `:date` and `:naive_datetime` fields have no zone and are
read as they are. The admin catalog's Today button uses the browser's date.

## Quick ranges

The query's presets apply to a calendar as to any list: the preset's read
or filter ANDs with the window. A preset can also move the window, so it
works as a quick range:

```elixir
query :agenda do
  preset :today do
    read_action :today
    calendar_anchor 0
  end

  preset :tomorrow do
    read_action :tomorrow
    calendar_anchor 1
  end
end
```

When the requested preset differs from the one the window last followed
(the window's `"preset"`, written by the server), the window moves to the
one holding today plus `calendar_anchor` days and the picked day is cleared.
An `anchor`, `windowDelta` or `date` in the same request applies on top.
While the preset stays selected the window does not move again, so the user
can still navigate. A `default_preset` with a `calendar_anchor` places the
first window the same way. `calendar_anchor` is ignored on tables that are
not calendars.

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
- One time zone per deployment (`:calendar_time_zone`). There is no
  per-actor time zone yet.
- Composed surfaces (`AshA2ui.Dynamic`) carry calendars as
  `"display": "calendar"` with `date_field`, `end_date_field` and
  `granularity`, and presets with `calendar_anchor`. The same rules apply (`AshA2ui.Calendar.validate/2`), and
  declared calendars import, promote and serialize losslessly. See the
  Agent-Composed Surfaces topic.
