# Architecture decision records

Each file records one decision: the context, the decision, and what follows from it.
Number files in order. A status is `proposed`, `accepted`, or `superseded`.
Which extensions keep ADRs, and why ADRs rather than a `DESIGN.md`, is [0003](0003-adr-baseline-for-ash-extensions.md).
A record is `proposed` until a human merges the pull request that adds it.

| ADR | Title | Status |
|---|---|---|
| [0001](0001-custom-component-catalogs.md) | Custom component catalogs under A2UI 1.0 | proposed |
| [0002](0002-document-viewer-engine-and-contract.md) | The document viewer: pdf.js, and the pane's contract | proposed |
| [0003](0003-adr-baseline-for-ash-extensions.md) | The ADR baseline for Ash extensions: a threshold rule, and ADRs over DESIGN.md | proposed |
| [0004](0004-catalog-version-copies-are-pinned-by-tests.md) | The admin catalog's version lives in three copies pinned by tests; the renderer negotiates catalogs by id | proposed |
| [0005](0005-the-surface-protocol-is-a2ui-1-0-only-with-one-call-and-one-outcome-path.md) | The surface protocol: A2UI 1.0 only, one inline surface, one call path, one outcome map | proposed |
| [0006](0006-the-js-elixir-boundary.md) | The JS/Elixir boundary: the server decides meaning, the browser draws, shared constants are pinned by tests | proposed |
| [0007](0007-authorization-has-no-side-channel.md) | Authorization has no side channel: Ash policies decide, and the host supplies the actor through hooks | proposed |
| [0008](0008-the-dsl-compiles-to-one-resolved-view-and-the-verifiers-are-the-validator.md) | The DSL resolves to one plain struct, and the compile-time verifiers are the only validator | proposed |
| [0009](0009-untrusted-input-names-things-and-the-server-resolves-them.md) | Agent and client input only names things; the server resolves them through an allowlist it holds | proposed |
