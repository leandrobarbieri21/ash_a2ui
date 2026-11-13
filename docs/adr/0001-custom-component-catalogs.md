# 0001. Custom component catalogs under A2UI 1.0

- Status: proposed
- Date: 2026-11-12
- Plane: PLS-21

## Context

The README listed "custom component catalogs beyond the basic catalog" as out of scope.
That is no longer true. The package ships the `ash_a2ui` catalog and the `admin` catalog
(`priv/a2ui/`, `priv/js/ash_admin_catalog.js`). A downstream host also has its own
catalog of Lit elements, kept in a private package. Some questions have no written answer:

1. How does a catalog plug in, on the server and in the browser?
2. Where does a new Lit component go: in ash_a2ui, or in a host's package?
3. What may a host rely on when it redraws a shipped catalog's components?

This ADR describes the catalog contract of A2UI 1.0, which ash_a2ui targets alone. That
contract ships with the "A2UI 1.0 only" release, being finished on branch `a2ui/1.0`.
`main` still carries the 0.9 code until then.

## Decision

### 1. A catalog is two things with one id

- A **definition**: a JSON file that names the components and functions, under a
  `catalogId` the owner controls.
- A **renderer module**: an ES module that exports `create<Name>Catalog(deps)`, built the
  way `createAshAdminCatalog` is. It does not import `@a2ui/*` or `lit` itself. The host
  passes them in, so one copy of each runs in the page.

### 2. The definition format

- `"protocolVersion": "1.0"` at the root. A catalog for 1.0 must declare it.
- `$ref`s to the shared types are relative: `common_types.json#/$defs/...`.
- A function's name sits under the `"@call"` key, as in the wire format.
- Functions declare who may call them:
  - `downloadFile` is `allowedCallers: "agentOnly"`. The agent sends it after an export.
  - `openSurface` and `ashAction` set `requiresUserActivation: true`, which makes them
    `rendererOnly`. A user gesture, such as a click, starts them.
- Components declare `allowedParents` and `allowedChildren` where the layout is fixed, such as
  the admin parts that belong inside an entity page. A renderer reports a violation. Leave
  the fields out where the tree is open.

### 3. Catalog ids

Ids are stable URIs. They need not resolve. They are not under a2ui.org, which is the
spec's namespace.

- `https://github.com/lukegalea/ash_a2ui/catalogs/ash_a2ui/v1`
- `https://github.com/lukegalea/ash_a2ui/catalogs/admin/v2`

A host names its catalog under its own domain or repository.

**These ids are new, and the change is breaking.** Before the 1.0 release the admin catalog
is `https://ash-a2ui.dev/catalogs/admin/v1` and the ash_a2ui catalog is
`https://a2ui.org/specification/v1_0/catalogs/ash_a2ui/catalog.json`. Every host that
registers, swaps or names these catalogs must move to the new ids.

Migration: a catalog built with `createAshAdminCatalog` or `createAshA2uiCatalog` carries the
new id by itself. Replace the old ids wherever the host writes them out: in
`supportedCatalogIds`, in a `createSurface.catalogId` or `@catalogId` it emits, in a wrapper
that matches catalogs by id, and in stored payloads and test fixtures. Read ids from the
code rather than writing them: `catalog.id` in the browser, `ASH_A2UI_CATALOG_ID` from
`ash_a2ui_protocol.js`, and `AshA2ui.Experience.admin_catalog_id/0` and
`AshA2ui.Encoder.ash_catalog_id/0` on the server.

### 4. Catalogs mix; they do not extend

A 1.0 surface can use several catalogs at once. Earlier drafts had the admin catalog
"extend basic" by repeating its components. That is replaced by mixing:

- A component from another catalog carries `@catalogId`.
- A function call into another catalog carries `catalogId`.
- `createSurface.catalogId` is the default for anything that names none.
- The renderer lists every catalog it can use in `supportedCatalogIds`. There is no
  fallback to a catalog that only appears in capabilities.
- All mixed catalogs must use the same spec version.

A private catalog therefore declares only its own components. Basic components in its
surfaces carry the basic catalog's `@catalogId`.

#### Where "admin draws basic X differently" goes

On an admin surface the encoder gives every basic component the basic catalog's
`@catalogId` (`AshA2ui.Encoder.with_catalog/2`). The renderer validates it against the basic
schema, which is strict, and draws it with the catalog registered under the basic id. So:

- **An extended variant**, a basic component with keys the basic schema lacks, becomes an
  admin component with its own name and schema. `filterPicker` is the precedent: a
  ChoicePicker with a hint, facet counts, dynamic options and grouped options. Extended keys
  never ride on a basic component, and two catalogs never declare one name, because that
  would make a mixed surface ambiguous.
- **A pure redraw** keeps the basic schema and is a swap of the basic catalog (section 6).
  `createAshA2uiCatalog` is one.

`createAshAdminCatalog` still carries every basic component, with its own TextField,
CheckBox, ChoicePicker, DateTimeInput and Modal elements. Its definition declares none of
them. On 1.0 they are bypassed: the encoder's basic components name the basic catalog, so
these elements draw only a basic component that names no catalog on an admin surface, which
the encoder does not emit. Each one becomes either a distinct admin component, if it extends
the basic schema, or an opt-in swap of the basic catalog, if it only redraws. In 1.0 the
basic TextField has `placeholder`, so TextField, CheckBox and DateTimeInput only redraw; the
prompt-closing Modal already ships in `createAshA2uiCatalog`.

### 5. Where a catalog lives, and how a host registers one

- A catalog that ash_a2ui's DSL can emit lives in ash_a2ui: the JSON under `priv/a2ui/`
  and the module under `priv/js/`. Today that is `ash_a2ui` and `admin`.
- Any other catalog lives in the host's own package, with its own id. A host's private
  catalog is not added to ash_a2ui.
- In the host bundle, build the catalog and add it to the list:
  `configureAshA2ui({MessageProcessor, Catalog, catalogs: [basic, admin, hostCatalog]})`.
  The renderer matches each id to a registered catalog exactly.
- A catalog is built with web_core's `Catalog` methods: `derive` for a catalog under a new
  id, `withEntries` for the same id with other entries. `retagged(api, tagName)` from
  `ash_a2ui_catalog.js` is the supported helper for an entry drawn by a host's element. Its
  signature follows the package's semver. (`catalogLike/5`, named in an earlier draft, is
  gone in 1.0.)

### 6. A host may redraw a shipped catalog under its id

A **swap** keeps a shipped catalog's id and draws one or more of its components with the
host's own elements. It declares no component and changes no schema. The host defines its
element under its own tag, then rebuilds the catalog with the entry swapped:

```js
// a wrapper: (catalog, deps) => catalog
export function withHostElements(catalog, deps) {
  defineHostFieldDisplay(deps); // customElements.define("host-field-display", ...)
  const components = [...catalog.components.values()].map((c) =>
    c.name === "fieldDisplay" ? retagged(c, "host-field-display") : c,
  );
  return catalog.withEntries(components, [...catalog.functions.values()]);
}
```

A wrapper of this form over a shipped catalog is a supported shape, the same as a
`create<Name>Catalog(deps)` factory.

Stable under the package's semver, for a swap:

- the catalog ids;
- the component names and their props: the JSON definition, and the schema each JS entry
  carries;
- the factories `createAshA2uiCatalog(deps)` and `createAshAdminCatalog(deps)` and their
  documented `deps`, including `renderActionButton`, `openSurface` and `loadMermaid`;
- `retagged(api, tagName)` and `ADMIN_CATALOG_VERSION`;
- the resolved props an element receives, read through the web_core 1.0 controller
  (`this.controller.props`) or node (`node.props`).

Not stable; any release may change them:

- the stock elements' tag names (`ash-admin-*`, `ash-a2ui-*`);
- the stock elements' internals: fields, methods, CSS classes, shadow DOM and `render()`;
- `element.context` and `this.context.componentModel`. web_core deprecates them, and the
  shipped elements will stop reading them. A swap reads props from the controller or node.

A swap that subclasses a stock element does so at its own risk. A host that only wants its
own buttons passes `renderActionButton` instead of swapping.

A swap draws; it never carries meaning. Everything the server means is in the props, and the
compatibility rule in section 8 keeps a prop a swap does not know safe to ignore.

### 7. Server emission stays a closed set

The encoder emits the `ash_a2ui` and `admin` catalogs. It has no behaviour, registry or DSL
option for a third. No second known user needs one.

Mixing changes what a host can do without one. A host that builds its own components writes
nodes with its own `@catalogId` and a surface whose default `catalogId` is its own or admin's.
It no longer has to copy basic components into its catalog, and the renderer accepts the
result as long as it lists all the ids.

A host's private components are not reachable from a declared (DSL) surface. Until a
server-side extension point exists, host catalog work on DSL surfaces is the shipped
catalogs plus swaps. When a real need appears for ash_a2ui to emit a host's components, a
new ADR designs the extension point against that need.

#### Component ids

The ids the encoder writes are best effort and may change in any release, except this set,
which a host may target. `<key>` is a component's `as` name, else its kind.

- `detail_<key>`: a `:detail` component's root.
- `detail_<key>_heading`: its heading, absent when the detail sits in a section and has no
  label.
- `detail_<key>_field_<field>`: an admin detail's `fieldDisplay` for one field.
- `section_<key>` and `section_<key>_heading`: a section's wrapper and heading, keyed by the
  first component in the section.
- `action_result_panel`: the panel showing a generic action's result.
- `context_<name>_body`: the body of a context picker, `<name>` being the context's name.
- `form_select_<field>`: a form's relationship or option picker for one field.

The last two are the ids the shipped Column already reads to recognise a picker composite,
so they were a contract in practice before this list named them.

The set is collision-free within a surface, and a test pins it. Both are follow-ups: today
two component keys can still make two of these ids equal.

### 8. Versioning

- The id names the major version: the ash_a2ui catalog is `.../ash_a2ui/v1` and the admin
  catalog, at 2.0.0, is `.../admin/v2`. The catalog's contract version sits in
  `metadata.extensions.ash_a2ui`, with its changelog. The renderer module exports the same
  version (`ADMIN_CATALOG_VERSION`). The admin catalog moves from 1.18.0 to 2.0.0 for the
  A2UI 1.0 break, and its id moves as section 3 says.
- A minor change is additive: a new component or an optional prop. It bumps the version and
  adds a changelog entry.
- **New wire keys are optional, ignorable, and lose no meaning when ignored.** A renderer or
  swap that does not know a key still draws the value, only less richly. The admin catalog
  grew this way from 1.8 to 1.18.
- A major change is one that removes or renames a component or prop, changes a prop's type
  or meaning, or adds a prop a swap must draw to keep the meaning. The rule above means the
  last should not happen.
- A host records the catalog version its swaps were drawn against, next to the swaps. When
  the loaded catalog is newer, the swaps may be missing new optional props.
- A private catalog follows the same rules. Its owner keeps the changelog.

### 9. Where "add a Lit component" goes

Ask in this order:

1. Is it an A2UI basic catalog component? We do not add to the basic catalog. It is the
   spec's. ash_a2ui only redraws some basic components, as a swap, to fix behaviour.
2. Does an ash_a2ui DSL feature need it, and does it have no domain noun in its name or
   props? Add it to the `admin` catalog as an additive minor version. Examples: `dataGrid`,
   `calendarView`, `liveDiagram`.
3. Is it domain-specific, or does only one host use it? Put it in that host's catalog package.

## Consequences

- Hosts can ship private catalogs with no change to ash_a2ui, and mix them with the
  shipped ones on one surface.
- Hosts can redraw the shipped catalogs under their ids, against a stated contract.
- The catalog id change breaks every host that names the old ids.
- Server-side emission of a custom catalog stays unsupported until a later ADR. This is the
  open edge of this decision.
- The README's out-of-scope line is narrowed to match.

## Follow-ups

- Make `createAshAdminCatalog` match its definition: drop the basic components it carries,
  and turn each of its TextField, CheckBox, ChoicePicker, DateTimeInput and Modal elements
  into an admin component or an opt-in basic swap (section 4).
- Move the shipped elements off `this.context` to the controller's props (section 6).
- A test that pins the stable component ids and checks they do not collide, and a
  compile-time check that rejects a component key that would make two of them equal, such as
  a detail named `x_heading` beside one named `x` (section 7).
- A dev-time warning when the loaded catalog is newer than the version a host's swaps were
  drawn against. Intended shape: `ash_a2ui_catalog.js` exports
  `warnIfNewer(loadedVersion, drawnAgainst, label)`, which a wrapper calls once with
  `ADMIN_CATALOG_VERSION`; it logs a console warning outside production and does nothing
  otherwise.

## Not decided here

- Whether a host's catalog becomes a published package, and its name.
- A server-side extension point for third-party catalogs (see section 7).
