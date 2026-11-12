# 0001. Custom component catalogs under A2UI 1.0

- Status: proposed
- Date: 2026-11-12
- Plane: PLS-21

## Context

The README listed "custom component catalogs beyond the basic catalog" as out of scope.
That is no longer true. The package ships the `ash_a2ui` catalog and the `admin` catalog
(`priv/a2ui/`, `priv/js/ash_admin_catalog.js`). A downstream host also has its own
catalog of Lit elements, kept in a private package. Two questions have no written answer:

1. How does a catalog plug in, on the server and in the browser?
2. Where does a new Lit component go: in ash_a2ui, or in a host's package?

This ADR describes the catalog contract of A2UI 1.0, which ash_a2ui targets alone.
It should merge after the "A2UI 1.0 only" change.

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
- `https://github.com/lukegalea/ash_a2ui/catalogs/admin/v1`

A host names its catalog under its own domain or repository.

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

### 5. Where a catalog lives, and how a host registers one

- A catalog that ash_a2ui's DSL can emit lives in ash_a2ui: the JSON under `priv/a2ui/`
  and the module under `priv/js/`. Today that is `ash_a2ui` and `admin`.
- Any other catalog lives in the host's own package, with its own id. A host's private
  catalog is not added to ash_a2ui.
- In the host bundle, build the catalog and add it to the list:
  `configureAshA2ui({MessageProcessor, catalogs: [basic, admin, hostCatalog]})`.
  The renderer matches each id to a registered catalog exactly.
- `retagged/2` and `catalogLike/5` from `ash_a2ui_catalog.js` are the supported helpers for
  building a catalog. Their signatures follow the package's semver.

### 6. Server emission stays a closed set

The encoder emits the `ash_a2ui` and `admin` catalogs. It has no behaviour, registry or DSL
option for a third. No second known user needs one.

Mixing changes what a host can do without one. A host that builds its own components writes
nodes with its own `@catalogId` and a surface whose default `catalogId` is its own or admin's.
It no longer has to copy basic components into its catalog, and the renderer accepts the
result as long as it lists all the ids. When a real need appears for ash_a2ui to emit a
host's components, a new ADR designs the extension point against that need.

### 7. Versioning

- The id names the major version (`.../v1`). The `version` field carries the contract
  version. The admin catalog moves from 1.11.0 to 2.0.0 for the A2UI 1.0 break; its id
  stays `.../admin/v1`.
- A minor change is additive: a new component or an optional prop. It bumps `version` and
  adds an `x-changelog` entry. The renderer module exports the same version constant.
- A private catalog follows the same rules. Its owner keeps the changelog.

### 8. Where "add a Lit component" goes

Ask in this order:

1. Is it an A2UI basic catalog component? We do not add to the basic catalog. It is the
   spec's. ash_a2ui only overrides how some basic components are drawn, to fix behaviour.
2. Does an ash_a2ui DSL feature need it, and does it have no domain noun in its name or
   props? Add it to the `admin` catalog as an additive minor version. Examples: `dataGrid`,
   `calendarView`, `liveDiagram`.
3. Is it domain-specific, or does only one host use it? Put it in that host's catalog package.

## Consequences

- Hosts can ship private catalogs with no change to ash_a2ui, and mix them with the
  shipped ones on one surface.
- Server-side emission of a custom catalog stays unsupported until a later ADR. This is the
  open edge of this decision.
- The README's out-of-scope line is narrowed to match.

## Not decided here

- Whether a host's catalog becomes a published package, and its name.
- A server-side extension point for third-party catalogs (see section 6).
