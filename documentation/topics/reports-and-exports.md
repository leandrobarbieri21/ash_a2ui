# Reports and File Export

Two features for surfaces that are *not* projections of resource rows:
`:report` components render the computed rows of a generic Ash action
(group-bys, aggregates, cross-resource stats), and `export` blocks deliver
server-generated CSV files through the v1.0 `callFunction` channel.

## `:report` components — aggregate/report queries

Tables render resource records; reports render **computed rows**. A
`:report` component declares a generic (`:action`-type) Ash action whose
return value is a list of row maps:

```elixir
# on the resource
action :usage_report, {:array, :map} do
  argument :from, :date
  argument :to, :date

  run fn input, context ->
    # any aggregation you like — actor available for scoping
    {:ok, [%{user: "ada", visits: 12, minutes: 340}, ...]}
  end
end

# on the surface
component :report, :usage do
  action :usage_report
  params [:from, :to]              # defaults to all of the action's arguments
  fields [:user, :visits, :minutes] # required: the column allowlist
end
```

### Rendering

A report section is a Card (`report_<name>`, a root child) containing:

- a heading (the humanized component name),
- one TextField per param, bound to the reserved
  `/report/<name>/params/<param>` path,
- a **Run** button dispatching the `"report"` client action (context:
  `"component"` and the current `"params"` bound from
  `/report/<name>/params`),
- a List templated over `/report/<name>/rows`, each row a Row of
  caption-labeled cells — one per declared field, bound template-relative
  to the row map's keys.

### The `"report"` action

The handler resolves the target report (the only one, or by the context's
`"component"`), filters the client params to the declared `params`
allowlist (blank inputs are unset), casts them against the action's
arguments, and runs the action **actor-scoped and authorized like any other
invocation**. Returned rows are serialized down to the declared `fields`
(atom or string keys accepted; values JSON-serialized like record fields)
and written wholesale to `/report/<name>/rows`. On v0.9.1 the outcome text
lands in the typed `/ui/feedback`; on v1.0 the structured `/ui/response` carries
`{"status": "ok", "result": {"count": n}}` and mirrors into the
`actionResponse`.

The trust model is unchanged: the client only ever references the declared
report by name — the action, the params it may set, and the columns it sees
are all DSL-declared. Compile-time checks
(`AshA2ui.Verifiers.VerifyReports`): the `action` must be a generic action
of the resource, `params` must name its arguments, `fields` is required
(report columns are row-map keys and cannot be inferred), and reports
cannot carry table/form options.

## `export` — CSV file export (v1.0-only)

An `export` block on a `:table` or `:report` component renders an **Export
CSV** button; the server generates the file and delivers it through a
`downloadFile` client-function call:

```elixir
component :report, :usage do
  action :usage_report
  fields [:user, :visits, :minutes]

  export do
    filename "usage.csv"   # default "<component name>.csv"
    column_select true     # per-column checkboxes (default false)
  end
end
```

### The frozen `downloadFile` wire contract

A successful `"export"` action emits one `callFunction` message:

```json
{
  "version": "v1.0",
  "functionCallId": "fc_…",
  "callFunction": {
    "call": "downloadFile",
    "args": {
      "filename": "usage.csv",
      "mimeType": "text/csv",
      "dataUrl": "data:text/csv;base64,…"
    }
  }
}
```

The shipped hook registers `downloadFile` as a built-in (a transient anchor
click on `dataUrl`, falling back to an `url` arg for hosts that upload the
file and pass a signed URL instead). The function is declared by the
shipped **AshA2ui extension catalog**
(`priv/a2ui/v1_0/catalogs/ash_a2ui/catalog.json`) — load it alongside the
basic catalog on renderers that validate function calls.

**Export is v1.0-only.** 0.9.1 has no server→client RPC channel to carry a
download, and encoding files into the data model would abuse the protocol —
so declaring `export` on a `spec_version "0.9.1"` surface is a compile-time
error (`AshA2ui.Verifiers.VerifyExport`). There is no 0.9.1 fallback.

### What gets exported

- **Tables**: the export re-reads the table under its context scope and —
  when a query is configured — the carried query state's
  search/filters/preset, but always page 1 at the export row cap (`limit`,
  default 10 000): an export is *the filtered set*, not the on-screen page.
  Cells go through the standard row serialization, so the CSV matches what
  the table renders. On dynamic table sets each expanded section exports
  its own rows, with the section label suffixed into the filename.
- **Reports**: the export re-runs the generic action with the carried
  params and exports the serialized rows.
- **Column selection**: with `column_select true`, one checkbox per
  exportable column binds to the reserved `/export/<name>/columns/<column>`
  booleans (all checked initially); the export includes only the checked
  columns, in declared order. Unchecking everything is rejected. Without
  `column_select`, all declared `columns` (default: the component's fields)
  are exported.

CSV encoding is RFC-4180 (CRLF rows, quote-doubling; see `AshA2ui.Csv`),
with humanized field labels (or declared `field ... label`s) as the header
row.
