/**
 * The mermaid engine for AshA2ui live diagrams, as its own bundle.
 *
 * Mermaid is several megabytes of JavaScript. The admin catalog's
 * `liveDiagram` loads it only when a diagram appears on a surface, through
 * the `loadMermaid` dependency of `createAshAdminCatalog`. This file is the
 * module that loader imports: it is the one place `mermaid` is imported,
 * so the host bundles it separately from app.js.
 *
 * The host owns the `mermaid` npm dependency (like `lit` and `@a2ui/*`,
 * nothing is bundled here). Two ways to wire it:
 *
 *   1. An ESM bundle with code splitting (`esbuild --format=esm
 *      --splitting`): pass
 *        loadMermaid: () => import("../../deps/ash_a2ui/priv/js/ash_a2ui_mermaid.js")
 *      and the import becomes its own chunk.
 *
 *   2. A classic (IIFE) app.js: add this file as a second esbuild entry
 *      point, served next to app.js, keep its URL external
 *      (`--external:/assets/*`), and pass
 *        loadMermaid: () => import("/assets/js/ash_a2ui_mermaid.js")
 *          .then(() => window.AshA2uiMermaid)
 *      (an IIFE bundle has no exports, so the engine also publishes itself
 *      on `window.AshA2uiMermaid`).
 *
 * Diagrams render with `securityLevel: "strict"`: no HTML labels, no
 * click handlers or links from the diagram source.
 */

import mermaid from "mermaid";

mermaid.initialize({startOnLoad: false, securityLevel: "strict"});

/** The engine `liveDiagram` uses: renders mermaid source to an SVG string. */
const engine = {
  strict: true,
  render: (id, source) => mermaid.render(id, source),
  mermaid,
};

if (typeof window !== "undefined") window.AshA2uiMermaid = engine;

export default engine;
