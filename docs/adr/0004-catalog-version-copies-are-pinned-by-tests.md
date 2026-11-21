# 0004. The admin catalog's version lives in three copies pinned by tests; the renderer negotiates catalogs by id

- Status: proposed
- Date: 2026-11-14
- Plane: AST-187
- Builds on: [0001](0001-custom-component-catalogs.md) section 8, which sets the versioning
  rule. This record is about how the rule is enforced and how a renderer and server agree
  on a catalog.

## Context

A catalog's contract has to be known in three places that no compiler connects:

- the JSON definition, `priv/a2ui/admin_v1/catalog.json`, whose
  `metadata.extensions.ash_a2ui.version` is `"2.0.0"` and which carries a changelog entry
  for every release back to 1.1 (about eighteen minors of additive change);
- the browser module, `priv/js/ash_admin_catalog.js`, which exports
  `ADMIN_CATALOG_VERSION = "2.0.0"` (line 173) for a host to compare against;
- the server, `AshA2ui.Experience.admin_catalog_version/0` and `admin_catalog_id/0`
  (`lib/ash_a2ui/experience.ex`), which writes the id on `createSurface`.

Without a rule, the three drift: a component is added in JS and never described in the JSON,
or the id changes in one place. The failure shows only in a browser, as an unknown component
or a catalog the renderer does not match.

A server also cannot assume the renderer has the admin catalog. The catalog id in
`createSurface` must be one the renderer registered (ADR 0001 section 4).

## Decision

1. **The id names the major version, and the JSON `metadata.extensions.ash_a2ui.version`
   is the contract version.** `.../catalogs/admin/v2` is major 2; the file says 2.0.0.
   A change is a minor if it adds an optional component or prop whose absence loses no
   meaning (0001 section 8); anything else is a major and a new id.
2. **The Elixir function and the JS constant are copies, and tests pin them to the JSON.**
   `test/ash_a2ui/experience/admin_catalog_contract_test.exs` asserts
   `contract(catalog)["version"] == Experience.admin_catalog_version()` and that
   `ash_admin_catalog.js` contains the same `ADMIN_CATALOG_VERSION`;
   `test/js/ash_a2ui_catalogs.test.mjs` asserts the exported JS constant equals the JSON
   version; `test/catalog_definitions_test.exs` validates both shipped catalogs against the
   vendored `catalog_definition.json`. A version bump that touches one place fails CI.
3. **Every release adds a changelog entry to the JSON** next to the version, in the same
   commit as the change. The changelog is the release note for hosts that keep swaps (0001
   section 6).
4. **The server negotiates by id and never guesses.**
   `AshA2ui.Experience.catalog_for/1` takes the renderer's `supportedCatalogIds` and returns
   `{:ok, :admin_v1}` only when the basic, ash_a2ui and admin ids are all listed and the
   host configured the admin catalog; `{:ok, :basic}` when basic and ash_a2ui are listed;
   `{:error, :no_common_catalog}` otherwise. With no capabilities it uses the configured
   catalog. Inline catalogs are not accepted. There is no version range: a host that needs
   version-specific behaviour reads `ADMIN_CATALOG_VERSION` in the browser (0001 section 8).
5. **The `ash_a2ui` function catalog has no contract version.**
   `priv/a2ui/v1_0/catalogs/ash_a2ui/catalog.json` carries no `metadata`. It has two
   functions (`ashAction`, `downloadFile`) and its id ends `v1`. A change to either is a
   breaking change and a new id, not a minor. See the follow-up.

## Consequences

- A catalog change is one reviewable commit: JSON, JS and Elixir move together or CI
  fails. Drift between the three copies cannot reach a release.
- The cost is three edits per version bump, and a regex-based test in Elixir over a JS
  source string, which breaks if the constant is reformatted.
- A renderer without the admin catalog still gets a working basic surface through the
  `:basic` fallback; a renderer without the ash_a2ui catalog gets nothing
  (`:no_common_catalog`), because no surface the library builds works without `ashAction`.
- The `ash_a2ui` catalog cannot grow a minor without a metadata block. Adding an optional
  function argument today has no place to be recorded.

## Reversal

Replace the copies by generation: render `admin_catalog_version/0` and the JS constant from
the JSON at build time. Then the tests in point 2 delete. That is a build step and a
`mix` task, and it is the better design if the number of copies grows.

## Follow-ups

- Give `ash_a2ui/catalog.json` a `metadata.extensions.ash_a2ui.version` and a changelog, and
  pin it as point 2 does.
- Decide whether `catalog_for/1` should compare the renderer's catalog version when the
  renderer reports one.
