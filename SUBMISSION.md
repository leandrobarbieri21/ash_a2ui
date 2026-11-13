# Submission checklist

Everything needed to publish `ash_a2ui` and get it in front of the Ash and
A2UI communities. Publishing requires the maintainer's hex.pm account;
everything below is staged so it's one command away.

## 0. Hold: publish only after the renderer release

ash_a2ui emits A2UI 1.0 as specified at the pinned upstream commit
(`priv/a2ui/v1_0/NOTES.md`). The published `@a2ui/lit` and `@a2ui/web_core`
0.15.0 predate three behaviours it relies on (the `@`-prefixed component
envelope keys, a required `TextField.value`, and routing a `functionCall`
action for a function no catalog declares to the agent), and 0.15.0 drops a
whole `createSurface` that carries an `@`-prefixed key. Do not publish to Hex
or post any of the drafts below until:

- [ ] an `@a2ui/lit` / `@a2ui/web_core` release implements those behaviours
      (compare the unreleased entries in
      `typescript/core/web_core/CHANGELOG.md` upstream), and
- [ ] the browser probes in `priv/js/probe/` pass against that release
      (`mix js.test` for the node tests), and
- [ ] the pin in `priv/a2ui/v1_0/NOTES.md` is checked against upstream `main`
      once more (re-vendor and run the conformance test if it moved, and look
      at the state of a2ui-project/a2ui#4171).

## 1. Publish to hex.pm

- [ ] Confirm the package name is still free: `mix hex.info ash_a2ui`
      (returned 404 as of 2026-07-10).
- [ ] Final local gate: `mix format --check-formatted && mix credo --strict
      && mix test && mix docs` all clean.
- [ ] `mix hex.build` and read the file list: the tarball excludes
      `priv/js/probe/`, `priv/a2ui/v1_0/test/` and `priv/js/nb_demo.html`.
- [ ] Verify package metadata in `mix.exs` (`:package` — maintainer,
      license, `files` list includes `priv`, `documentation`,
      `usage-rules.md`; links point at `lukegalea/ash_a2ui`).
- [ ] `mix hex.user auth` (once, on the publishing machine).
- [ ] `mix hex.publish` — review the file list and docs preview it prints
      **before** confirming.
- [ ] Tag the release: `git tag v0.1.0 && git push --tags` (or use
      `mix git_ops.release`, which manages CHANGELOG + version + tag).

### CI-driven publishing (optional, recommended after first manual publish)

- [ ] Create a hex.pm API key: `mix hex.user key generate --key-name ci
      --permission api:write`.
- [ ] Add it as the `HEX_API_KEY` repository secret on GitHub
      (`lukegalea/ash_a2ui` → Settings → Secrets → Actions). The shared
      `ash-project` CI workflow already wires it; the publish step is inert
      until the secret exists and a `v*` tag is pushed.

## 2. Verify hexdocs

- [ ] After publish, check <https://hexdocs.pm/ash_a2ui>:
  - [ ] README renders as the landing page ("Home").
  - [ ] Sidebar groups present: Tutorials / Topics / DSLs / About AshA2ui.
  - [ ] DSL cheat sheet (`DSL: AshA2ui`) renders with searchable entries
        (search for `row_actions` in the docs search box).
  - [ ] The topic pages and the tutorial render; spot-check relative
        links between them (they should have been rewritten by ExDoc, not
        point at `documentation/...` paths).
  - [ ] The hex/hexdocs badges in the README resolve (they 404 pre-publish).
- [ ] If anything is broken, fix and `mix hex.publish docs` to republish
      docs without a new release.

## 3. Elixir Forum post (Ash section)

Post to <https://elixirforum.com/c/elixir-framework-forums/ash-framework-forum>.
Draft:

> **Title:** AshA2ui — generate A2UI (Agent to UI) 1.0 surfaces from Ash resources
>
> Hi all. `ash_a2ui` is an Ash extension that generates
> [A2UI](https://github.com/a2ui-project/a2ui) 1.0 protocol messages from
> your resources.
>
> You declare a small `a2ui` block (table + form + row actions, or the same
> block in a standalone module via `use AshA2ui.Standalone`) and
> `AshA2ui.Info.build_surface/2` returns one `createSurface` message for any
> A2UI renderer (`@a2ui/lit`, `@a2ui/react`, an agent canvas). Controls
> send an `ashAction` function call back; the handler runs your Ash action
> with the actor and `authorize?: true`, writes the outcome to one
> `/ui/feedback` data-model map and answers with an `agentFunctionResponse`.
> The declared `row_actions` are the allowlist, and referencing a field or
> action that doesn't exist is a compile error.
>
> The protocol core depends only on `ash`. There is an optional LiveView
> transport (`AshA2ui.LiveRenderer`) with PubSub live refresh, and plain
> JSON endpoints work too.
>
> How it is checked: the A2UI 1.0 JSON Schemas, basic catalog and the
> upstream test cases are vendored at a pinned commit; the test suite
> validates every message the encoder and handler emit against them, and
> the upstream cases pass. It does not test a browser against a published
> renderer release, and it targets the 1.0 specification text, so it needs
> an `@a2ui/lit` release that implements it (see "What the renderer must
> support" in the docs).
>
> To try it: add `{:ash_a2ui, "~> 0.1"}`, follow the Getting Started
> tutorial at <https://hexdocs.pm/ash_a2ui>, and open the surface in a
> LiveView. If you only need an internal admin, AshAdmin is less work; the
> docs say where each fits.
>
> Feedback is welcome, especially from anyone rendering A2UI surfaces in
> agent canvases.

- [ ] Post it, and update the link here: ________

## 4. Ash Discord `#showcase` blurb

> **ash_a2ui** — declare an `a2ui do ... end` block on an Ash resource (or a
> standalone UI module) and get an A2UI 1.0 surface as one `createSurface`
> message: tables, forms, row actions, compile-time verifiers, actor-aware
> authorization. Core depends only on `ash`; optional LiveView transport with
> PubSub refresh. Messages are validated against the vendored A2UI 1.0
> schemas in the test suite.
> 📦 <https://hex.pm/packages/ash_a2ui> · 📚 <https://hexdocs.pm/ash_a2ui>

- [ ] Post in `#showcase` on the Ash Discord (invite: discord.gg/HTHRaaVPUc).

## 5. PR to ash-project/ash README ("Packages" section)

- [ ] Wait until the hex package + hexdocs are live (listing PRs for
      unpublished packages get bounced).
- [ ] Fork `ash-project/ash`, edit the README's community packages table,
      and add a one-liner in alphabetical position, matching the existing
      row format:

      | [AshA2ui](https://hexdocs.pm/ash_a2ui) | Generate A2UI (Agent to UI) 1.0 surfaces from Ash resources. |

- [ ] Open the PR referencing the hex package and the forum post; note that
      CI uses the shared `ash-project` reusable workflow and the test suite
      validates payloads against the vendored A2UI 1.0 schemas.

## 6. PR to a2ui-project/a2ui (ecosystem list)

- [ ] Same precondition as section 5: the Hex package and hexdocs are live.
- [ ] Read `CONTRIBUTING.md` upstream (a Google CLA is required) and open an
      issue or discussion first if the maintainers prefer one.
- [ ] Where the entry goes. The task brief named
      `docs/public/reference/renderers.md`, but that file's "Ecosystem
      Renderers" section is a bullet list of *renderers* and defers to
      `docs/public/ecosystem/renderers.md`. ash_a2ui produces A2UI, and that
      page already has an **Agent-Side Libraries** table ("These projects
      produce A2UI rather than rendering it") with columns Project, Language,
      Description and Links. The row below belongs there. Check the page's
      current layout at the time of the PR; if the maintainers would rather
      list it elsewhere, move the row.
- [ ] Title: `docs: add ash_a2ui to the ecosystem agent-side libraries`
- [ ] Add after the existing row:

      | **lukegalea/ash_a2ui** (`ash_a2ui`) | Elixir | Ash extension that generates A2UI 1.0 messages from Ash resources: one inline `createSurface` per surface, with an `ashAction` function call and `agentFunctionResponse` for server-handled actions. Messages are validated against the 1.0 schemas and upstream test cases in its test suite. Includes a Phoenix LiveView transport and a Lit hook. | [GitHub](https://github.com/lukegalea/ash_a2ui) · [Hex](https://hex.pm/packages/ash_a2ui) · [Docs](https://hexdocs.pm/ash_a2ui) |

- [ ] PR description:

> Adds `ash_a2ui` to the agent-side libraries table.
>
> What it does: generates A2UI 1.0 messages from Ash (Elixir) resources. A
> surface is one inline `createSurface`; user actions come back as a
> `callAgentFunction` and are answered with an `agentFunctionResponse`; a
> CSV export is a `callRendererFunction`.
>
> How it is verified: its test suite validates every message it emits against
> `specification/v1_0/json/*` and the basic catalog at `8bf644a` (draft 2020-12,
> JSV), and runs the cases in `specification/v1_0/test/cases`.
>
> How to try it: `{:ash_a2ui, "~> 0.1"}`, then the Getting Started tutorial at
> <https://hexdocs.pm/ash_a2ui>. It works with `@a2ui/lit`; it needs a
> release that implements the `@`-prefixed component keys and the
> agent-function fallback routing.
>
> Docs only; no code changes.

## 7. Post-publish housekeeping

- [ ] Flip the README "Status: not yet published" note to a normal install
      section.
- [ ] Replace the "pending POC" cells in the README coverage matrix and the
      LOC data point in `documentation/topics/what-is-ash-a2ui.md` once the
      reference POC lands.
- [ ] Watch the GitHub Actions run on the release tag — the hexdocs publish
      job needs `HEX_API_KEY` (step 1).
