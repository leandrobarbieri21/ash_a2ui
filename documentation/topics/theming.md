# Theming

AshA2ui emits A2UI **basic catalog** components; how they look is the
renderer's business. This guide covers making `@a2ui/lit`-rendered surfaces
match your app's design system — what the styling contract actually is,
what the extension ships to help, and where the protocol's limits are.

## The styling contract: CSS custom properties

`@a2ui/lit`'s basic catalog components render inside **shadow DOM**. Page
CSS — Tailwind utilities, element selectors, class selectors — cannot reach
their internals, and the components expose no `::part()`s. The one
supported seam (and the [official upstream theming
story](https://a2ui.org/guides/theming/)) is **CSS custom properties**:
every component reads `--a2ui-*` variables, which inherit through shadow
boundaries. The catalog injects its defaults at zero specificity
(`:where(:root)`), so any `:root { --a2ui-...: ...; }` in your stylesheet
wins.

Two tiers of variables:

- **Global tokens** — `--a2ui-color-background`, `--a2ui-color-surface`,
  `--a2ui-color-primary`, `--a2ui-color-secondary`, `--a2ui-color-input`,
  `--a2ui-color-border` (each with an `-on-` foreground pair), plus
  `--a2ui-border-radius`, the `--a2ui-spacing-*` scale (driven by
  `--a2ui-grid-base`) and the `--a2ui-font-size-*` scale.
- **Per-component overrides** — e.g. `--a2ui-card-background`,
  `--a2ui-card-box-shadow`, `--a2ui-button-padding`,
  `--a2ui-tabs-header-background-active`,
  `--a2ui-textfield-border-radius`. See the JSDoc on each component in
  `@a2ui/lit/src/v0_9/catalogs/basic/components/` for the full list.

Colors in the default theme use `light-dark()` and follow the user's
`prefers-color-scheme`; add the `a2ui-dark` or `a2ui-light` class to your
root element to force a scheme.

## What the extension ships

### `priv/js/ash_a2ui_theme.css` — a neutral starter theme

A dependency-free stylesheet that sets the `--a2ui-*` variables to neutral,
admin-friendly values (cards with subtle borders and shadows, tighter
button/card margins so `Row`/`List`/`Column` gaps own the layout rhythm,
0.5rem radii, indigo primary). Import it into your bundled CSS, then map
your own tokens after it — later declarations at the same `:root`
specificity win:

```css
/* assets/css/app.css */
@import "../../deps/ash_a2ui/priv/js/ash_a2ui_theme.css";

:root {
  /* Map your design system's tokens onto the surface. */
  --a2ui-color-surface: hsl(var(--card));
  --a2ui-color-on-surface: hsl(var(--card-foreground));
  --a2ui-color-primary: hsl(var(--primary));
  --a2ui-border-radius: var(--radius);
}
```

### `priv/js/ash_a2ui_catalog.js` — a merged catalog with structural fixes

Two basic-catalog structures are wrong for admin surfaces, and both are
structural (no CSS variable can fix them):

1. **ChoicePicker** renders single-choice pickers as **radio lists** (its
   only display styles are `checkbox` and `chips` — the spec has no
   dropdown, through v1.0).
2. **Search pickers** (surface-context pickers and searchable relationship
   selects) are emitted as a label + selected text + search field + Search
   button + flat option `List` composite — the basic catalog has no
   combobox, so a stock renderer shows every option before the user
   searches, with no overlay and no keyboard navigation.

`createAshA2uiCatalog(deps)` builds a catalog registered under the **same
catalog id the encoder emits**, reusing every basic-catalog component and
function except:

- **ChoicePicker** → a native, token-themed `<select>` for
  `mutuallyExclusive` pickers (checkbox list for `multipleSelection`).
- **Column** (only when `ColumnApi` is passed) → identical to the basic
  Column, except when the component is one of AshA2ui's picker composites,
  recognized through the extension's frozen id contract
  (`context_<name>_body`, `form_select_<field>`) plus structural checks
  against the live component tree. Searchable composites render as a
  **typeahead combobox**: debounced search-as-you-type driving the same
  `context_search`/`option_search` wire actions, results in an anchored
  overlay with arrow-key/Enter/Escape navigation, a "Type to search…"
  hint instead of a pre-search option dump, and the selection collapsed to
  a chip with Clear. Non-searchable context pickers render their options
  as a horizontal **chip group** with the selection highlighted.
  Composites the detector cannot fully verify — and every other Column —
  render exactly like the basic catalog, so the wire format stays plain
  basic catalog (progressive enhancement; stock renderers show the flat
  composite).

Like the hook, the file has no bundled dependencies — the host bundle
passes the renderer classes in:

```javascript
import {html, css, nothing} from "lit";
import {basicCatalog, A2uiLitElement, A2uiController} from "@a2ui/lit/v0_9";
import {Catalog} from "@a2ui/web_core/v0_9";
import {ChoicePickerApi, ColumnApi} from "@a2ui/web_core/v0_9/basic_catalog";
import {createAshA2uiCatalog} from "../../deps/ash_a2ui/priv/js/ash_a2ui_catalog.js";

const catalog = createAshA2uiCatalog({
  Catalog,
  basicCatalog,
  ChoicePickerApi,
  ColumnApi, // optional: omit to keep the stock Column (no combobox)
  A2uiLitElement,
  A2uiController,
  lit: {html, css, nothing},
});

configureAshA2ui({MessageProcessor, catalogs: [catalog]});
```

Pass **only** the merged catalog — it answers for the basic catalog id, so
also passing `basicCatalog` would shadow it (the processor takes the first
id match).

Combobox/chip styling rides the same token system, with a few extra knobs:
`--a2ui-combobox-max-height`, `--a2ui-combobox-z-index`,
`--a2ui-combobox-box-shadow`, `--a2ui-combobox-option-padding`,
`--a2ui-chip-background`/`--a2ui-chip-color`,
`--a2ui-chip-selected-background`/`--a2ui-chip-selected-color`, and
`--a2ui-chip-border-radius` (see the JSDoc in the file).

### Markdown rendering (fixes literal `##` headings)

The basic Text component turns `variant: "h2"` into the markdown string
`## Title` and needs a markdown renderer injected via Lit context — without
one it prints the raw string (upstream design decision,
[google/A2UI#1226](https://github.com/google/A2UI/issues/1226)). Install
the official renderer and hand it to the hook:

```bash
npm install @a2ui/markdown-it --prefix assets
```

```javascript
import {ContextProvider} from "@lit/context";
import {Context} from "@a2ui/lit/v0_9";
import {renderMarkdown} from "@a2ui/markdown-it";

configureAshA2ui({
  MessageProcessor,
  catalogs: [catalog],
  markdown: {ContextProvider, context: Context.markdown, render: renderMarkdown},
});
```

The hook attaches a `ContextProvider` to its container element, an ancestor
of every rendered component, so all Text components pick the renderer up.

### Admin catalog 1.1 tokens (grid, links, badges)

The admin catalog's DataGrid, Pagination and FieldDisplay read every line,
header and tone from tokens (each falls back to the existing
`--ash-admin-*`/`--a2ui-*` palette):

| Token | Default | Drives |
| --- | --- | --- |
| `--ash-admin-border-width` | `--a2ui-border-width`, else `1px` | grid frame/cell lines, badge and pager-chip borders |
| `--ash-admin-grid-max-height` | `none` | the grid's scroll frame (the header is sticky inside it) |
| `--ash-admin-grid-radius` / `-grid-shadow` | `radius-m` / `shadow-1` | the frame |
| `--ash-admin-grid-header-background` / `-text` | `surface-sunken` / `text` | header cells |
| `--ash-admin-grid-header-font-size` / `-font-weight` | `font-size-s` / bold | header type |
| `--ash-admin-grid-header-transform` / `-tracking` | `none` / `normal` | e.g. `uppercase` + `0.05em` |
| `--ash-admin-grid-row-active` | hover tint mixed with primary | row press feedback (clickable rows) |
| `--ash-admin-font-mono` | system mono stack | identifier cells (`mono`) |
| `--ash-admin-link` / `-link-hover` | `primary` / `primary-hover` | reference links |
| `--ash-admin-badge-radius` / `-badge-border` | pill / `transparent` | badge pills |
| `--ash-admin-badge-<tone>-background` / `-text` | subtle/strong feedback pairs | tones `neutral info success warning danger accent` |
| `--ash-admin-pager-chip-background` / `-border` / `-radius` / `-shadow` | surface / border / radius-s / none | windowed page chips |
| `--ash-admin-field-label-transform` / `-tracking` / `-text` | `uppercase` / wide / muted | FieldDisplay labels |

A neobrutalist host, for instance, sets `--ash-admin-border-width: 2px`,
`--ash-admin-badge-border: var(--border)` and
`--ash-admin-grid-shadow: var(--shadow)`.

## What the encoder does for you

Since v0.9.1 encoder updates, each record in a table renders as a `Card`
(`record_row`) wrapping a `Row` of labeled cells — every cell is a caption
`Text` with the humanized field name next to the bound value `Text` — so
themed surfaces get card chrome and readable "Label: value" rows without
any DSL changes.

Section chrome is Card-wrapped the same way: context picker sections
(`context_<name>` > `context_<name>_body`), detail panels (`detail_<name>`
> `detail_<name>_body`), query controls (`query<sfx>_controls` >
`query<sfx>_controls_body`), and form groups (`form_group_<name>`) all
emit as a basic-catalog `Card` over a body container, themed via the
`--a2ui-card-*` variables on every renderer.

## Protocol limits (what theming cannot do)

- The `createSurface.theme` block standardizes only
  `primaryColor`/`iconUrl`/`agentDisplayName`, and the Lit renderer applies
  only `primaryColor`. Page CSS variables are strictly more powerful — the
  encoder does not emit a theme block.
- No `::part()`s and no light-DOM classes: if a component's variables can't
  express what you need, the answer is a catalog override (like the
  shipped ChoicePicker), not CSS.
- Field-level iconography and status badges are not in the basic catalog;
  richer per-field decoration needs custom catalog components plus encoder
  support (roadmap).
