/**
 * The pdf.js engine for AshA2ui document viewers, as its own bundle.
 *
 * pdf.js and its worker are several hundred kilobytes. The admin catalog's
 * `documentViewer` loads them only when a viewer opens a document, through
 * the `loadPdf` dependency of `createAshAdminCatalog`. This file is the
 * module that loader imports: the one place `pdfjs-dist` is imported, so
 * the host bundles it apart from app.js.
 *
 * The host owns the `pdfjs-dist` npm dependency (like `lit`, `@a2ui/*` and
 * `mermaid`, nothing is bundled here). Pin it exactly, to a version not
 * affected by CVE-2026-16633 (6.2.108 or later; tested with 6.4.299). Wire
 * it as two ES module entry points served from one directory:
 *
 *     esbuild deps/ash_a2ui/priv/js/ash_a2ui_pdf.js \
 *             deps/ash_a2ui/priv/js/ash_a2ui_pdf_worker.js \
 *             --bundle --format=esm --outdir=priv/static/assets/js
 *
 * and pass
 *
 *     loadPdf: () => import("/assets/js/ash_a2ui_pdf.js")
 *
 * (a URL in a variable, or `--external:/assets/*`, so app.js does not
 * bundle it). The worker is found next to this module
 * (`ash_a2ui_pdf_worker.js`, a module worker on the page's own origin, so
 * a CSP with `default-src 'self'` covers it); `useWorker(url)` points it
 * elsewhere.
 *
 * Documents open with `isEvalSupported: false`, so a strict CSP (no
 * `unsafe-eval`, no `wasm-unsafe-eval`) draws them. `configure(options)`
 * adds pdf.js `getDocument` options for every document (`cMapUrl`,
 * `standardFontDataUrl`, `wasmUrl`, `iccUrl` for the host's copies of
 * pdfjs-dist's data directories).
 */

import * as pdfjs from "pdfjs-dist/build/pdf.mjs";

const defaults = {isEvalSupported: false};

pdfjs.GlobalWorkerOptions.workerSrc = new URL("./ash_a2ui_pdf_worker.js", import.meta.url).href;

/** Points pdf.js at its worker module (by default `ash_a2ui_pdf_worker.js` beside this one). */
export function useWorker(url) {
  pdfjs.GlobalWorkerOptions.workerSrc = String(url);
}

/** Adds pdf.js `getDocument` options for every document opened after it. */
export function configure(options = {}) {
  Object.assign(defaults, options, {isEvalSupported: false});
}

/** The engine `documentViewer` uses. `open(src)` returns pdf.js's loading task. */
const engine = {
  open: (src) => pdfjs.getDocument({...defaults, url: src}),
  TextLayer: pdfjs.TextLayer,
  version: pdfjs.version,
  pdfjs,
};

export default engine;
