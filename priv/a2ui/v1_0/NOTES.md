# Vendored A2UI 1.0 specification files

These files are copied verbatim from the A2UI specification repository,
<https://github.com/a2ui-project/a2ui> (Apache License 2.0, copyright Google
LLC and the A2UI contributors). ash_a2ui speaks protocol 1.0 only.

- **Pin:** `8bf644a37d680a227296b8c0849a7f4b328b8b73` (`main`, 2026-11-12).
  The last commit touching any vendored file is `24d1bf9c8` (2026-11-10, the
  `@`-prefixed component envelope keys).
- **Status upstream:** `specification/v1_0/README.md` calls 1.0 the current
  stable version. There is no git tag for it.
- **Exception:** `catalogs/ash_a2ui/catalog.json` is ash_a2ui's own catalog,
  not an upstream file.

## File map

| Here | Upstream, at the pin |
|---|---|
| `json/agent_to_renderer.json` | `specification/v1_0/json/agent_to_renderer.json` |
| `json/agent_to_renderer_list.json` | `specification/v1_0/json/agent_to_renderer_list.json` |
| `json/agent_to_renderer_list_wrapper.json` | `specification/v1_0/json/agent_to_renderer_list_wrapper.json` |
| `json/renderer_to_agent.json` | `specification/v1_0/json/renderer_to_agent.json` |
| `json/renderer_to_agent_list.json` | `specification/v1_0/json/renderer_to_agent_list.json` |
| `json/renderer_to_agent_list_wrapper.json` | `specification/v1_0/json/renderer_to_agent_list_wrapper.json` |
| `json/common_types.json` | `specification/v1_0/json/common_types.json` |
| `json/catalog_definition.json` | `specification/v1_0/json/catalog_definition.json` |
| `json/agent_capabilities.json` | `specification/v1_0/json/agent_capabilities.json` |
| `json/renderer_capabilities.json` | `specification/v1_0/json/renderer_capabilities.json` |
| `json/renderer_data_model.json` | `specification/v1_0/json/renderer_data_model.json` |
| `json/sample.json` | `specification/v1_0/json/sample.json` |
| `catalogs/basic/v1/catalog.json` | `catalogs/basic/v1/catalog.json` |
| `test/testing_catalog.json` | `specification/v1_0/test/testing_catalog.json` |
| `test/cases/*.json`, `test/cases/contact_form_example.jsonl` | `specification/v1_0/test/cases/*` |

The normative prose these files go with is
`specification/v1_0/docs/a2ui_protocol.md`; the change list from 0.9 is
`specification/v1_0/docs/evolution_guide.md`.

## How the tests use them

`AshA2ui.Test.SchemaHelper` validates with JSV, a JSON Schema draft 2020-12
validator, the draft the files declare. `unevaluatedProperties` and string
formats are enforced, as in the upstream runner (ajv with
`--spec=draft2020` and `ajv-formats`). `AshA2ui.Test.SchemaHelper.Resolver`
serves every `https://a2ui.org/specification/v1_0/...` reference from this
directory, never the network:

- A URI resolves by its basename, because the files refer to each other both
  with and without a `json/` path segment.
- `catalog.json` is an alias for the catalog in use, as in the upstream
  runner. It is the basic catalog by default. A suite's `"catalog"` key, or
  the helper's `catalogs:` option, picks another. A list of catalogs is the
  mixed-catalog case: the alias becomes a `oneOf` over each catalog's
  `anyComponent` and `anyFunction`.
- `common_types.json` writes one key pattern with `\p{XID_Start}` and
  `\p{XID_Continue}`. The PCRE engine in OTP 27 does not support these
  ECMAScript binary properties, so the resolver rewrites them to their UAX #31
  general categories when it loads the file. The file on disk stays verbatim.

`test/v1_0_conformance_test.exs` runs the upstream corpus with no
exceptions. Every case in `test/cases` validates or fails exactly as
labelled, and every line of `contact_form_example.jsonl` validates. The basic
and testing catalogs pass the catalog checks, which are structure, UAX #31
names and restricted `$ref` targets. The runner's own `sample.json`,
capability, data-model and list-wrapper payloads validate.

## Rules the schemas cannot express

The library's own tests cover these.

- `updateDataModel.value` is required, and `null` deletes the key at `path`.
- `surfaceId` is unique for the renderer's lifetime. `functionCallId`
  correlates a function call with its response.
- Catalog entity and argument names follow UAX #31.
- `allowedCallers` (`rendererOnly`, the default, `agentOnly` or
  `rendererOrAgent`) and `requiresUserActivation` are enforced at run time
  from the catalog, not on the wire.
- `@index` is evaluable only inside list-template iteration.
- An unknown agent function gets an `agentFunctionResponse` error
  (`UNKNOWN_FUNCTION` or `INVALID_FUNCTION_CALL`).
- The MIME type is `application/a2ui+json`.

## Watch list

- **a2ui-project/a2ui#4171** (`feat!: emit @child, @action, and
  @functionCall across v1.0 spec and SDKs`) was still open at the pin. If it
  merges, `Child` references, `Action` and `FunctionCall` objects take `@`
  keys. This would be a breaking change to every surface the encoder emits.
  Re-vendor, run the conformance test, and update the encoder in the same
  change.
- The published `@a2ui/web_core` and `@a2ui/lit` (0.15.0 at the pin) are
  behind these schemas. The `@` envelope keys, the required `TextField.value`
  and agent-function fallback routing are listed as unreleased in
  `typescript/core/web_core/CHANGELOG.md`. Feeding the fixtures in
  `test/fixtures/v1_0_contract/` through a 0.15.0 `MessageProcessor` gives:
  - a component carrying `@checks`, `@accessibility` or `@catalogId` fails
    with `VALIDATION_FAILED` ("Unrecognized key(s)"), and the whole
    `createSurface` is dropped (no components reach the model). The bare
    `checks` and `accessibility` keys work;
  - a `TextField` without `value` is accepted;
  - an action whose `functionCall` names a function no catalog declares does
    nothing: no `callAgentFunction` goes out and no error is reported;
  - `MessageProcessor.callAgentFunction(surfaceId, call, {timeoutMs})` works.
    It sends `callAgentFunction` with a fresh `functionCallId`, and the
    matching `agentFunctionResponse` resolves the promise (`value`) or
    rejects it (`error`, or `TIMEOUT`).

  A build of upstream `main` at the pin accepts every fixture unchanged,
  reads the bare keys as their `@` forms, rejects a `TextField` without
  `value`, and routes the undeclared action function to the agent as
  `callAgentFunction`.

## Re-vendoring

Copy the files in the map from the new upstream commit. Update the pin above,
then run `mix test test/v1_0_conformance_test.exs test/schema_helper_test.exs`.
A failing upstream case is a bug to fix here, never an exception to list.
