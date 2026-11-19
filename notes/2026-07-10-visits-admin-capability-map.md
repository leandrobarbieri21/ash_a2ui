# Visits admin stress test — capability map & design record (2026-07-10)

A host app's visits admin screen
(a ~1,300-line LiveView controller) was chosen as a stress test for AshA2ui. This note records the
behavior→capability map that drove the `visits-wave` branch, and what the
screen still needs beyond it.

## Behavior → capability map

Legend: (a) already expressible pre-wave, (b) expressible once Wave 6 layout
primitives (group / card row_layout) land, (c) was missing — shipped in this
wave, (d) still missing.

| visits_live behavior | Class | AshA2ui expression |
|---|---|---|
| Global search: user by email/name/id (entry point) | (c) | `context :user` with `option_search [:email, :name, ...]` — surface-level searchable picker, `"context_search"` action |
| Global search also jumps to a visit/patient id (polymorphic) | (d) | Not modeled; contexts search one resource. Workaround: additional pickerless contexts + separate search, or a future polymorphic-context feature |
| Selected User card (name/email/id/timestamp) | (c) | `component :detail do context :user end` → `/detail/user` |
| "User's Practices" select filtered by selected user | (c) | `context :practice` with `depends_on :user`, `depends_on_path [:memberships, :user_id]`; `auto_select_single` covers the one-practice fast path |
| Visits list scoped to user+practice; empty until a user is picked | (c) | table `context_filter user_id: :user, practice_id: :practice` + `require_context [:user]` |
| Start Date filter (visits since X) | (c) | `query ... range_filters [:inserted_at]` → `/query/ranges/<field>/from\|to`, inclusive bounds, date→day-edge expansion |
| Patient Name / ID / Visit ID filter over the list | (a) | `query` `search_fields` with relationship paths (`[:patient, :full_name]`, id casts pending string-typed columns) |
| Clear filters | (a) | query state reset via the emitted controls (client rewrites `/query`; Apply) + `context_clear` |
| Click visit row → visit detail panel | (c) | `select_context :visit` row button + `component :detail do context :visit end` (pickerless context) |
| Visit detail sub-entities: audio files list, play audio, view transcript | (d) | Needs nested detail collections / media components — not in the basic catalog; out of scope for a declarative table+detail surface |
| Queue transcribe/tags jobs on an audio file | (d) as-is; (a) reshaped | Generic Ash actions with `:record_id` are expressible today, but only as row actions of a *table over audio files* — no audio-file table exists on this surface yet |
| View traces link-out | (a) | Map-returning generic action or plain link in host page chrome |
| Role-gated visibility of admin actions | (a) | Ash policies + `visible_when`; authorization stays server-side |
| Card/grid layout polish | (b) | Wave 6 `group` / `row_layout` primitives |

## What shipped (this branch)

- `context` DSL entity + `AshA2ui.ContextRunner` + `VerifyContexts`:
  server-validated selections, dependent option sources with cascades and
  `auto_select_single`, `context_filter` / `require_context` /
  `select_context` on tables.
- `:detail` component type rendering a context's record at
  `/detail/<context>`.
- `range_filters` on the query entity (`/query/ranges` state, inclusive
  bounds, datetime day-expansion).
- LiveRenderer `:context_state` tracking for PubSub refreshes.
- Wire contracts frozen in
  `documentation/topics/contexts-and-details.md`,
  `queries-and-pagination.md`, `data-model-conventions.md`;
  `usage-rules/contexts.md`.

## Roadmap seeds this stress test surfaced

- **Polymorphic context search** — one search input resolving across
  multiple resources (user OR visit id OR patient id) with a typed result
  list; would subsume the screen's entry search completely.
- **Context-scoped sub-tables in details** — a table whose rows are a
  *collection* of the selected context's record (visit → audio files),
  giving row actions (queue jobs) a natural home.
- **Media/binary components** — audio playback and long-text (transcript)
  viewing exceed the v0.9.1 basic catalog.
