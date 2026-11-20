# 0002. The document viewer: pdf.js, and the pane's contract

- Status: proposed
- Date: 2026-11-19
- Issue: lukegalea/ash_a2ui#120

## Context

Hosts need to show a person an exact document version: to check values an extraction run read
from it, to acknowledge it, and to sign it. Until now nothing in the package rendered a document;
a host could only offer a download.

A downstream host built it first as its own Lit element (a contract page's document pane: the PDF
drawn with pdf.js, each value the extraction read boxed on its page as fractions of the page,
tested in the browser to ±1.5px) and hand-wrote the split view beside its surface. Its placement
rule (upstream first) put the generic part here before that host merged it. Three later uses are
named: extraction review (the first), signing (`ash_signatures`, the regions are signature
fields) and policy acknowledgement (ash_enterprise ADR 0074).

## Decision

### 1. The engine is pdf.js, loaded only when a document opens

pdf.js (Apache-2.0, `pdfjs-dist`) draws the pages. The alternative was EmbedPDF (Apache-2.0,
PDFium compiled to WebAssembly), checked on 2026-11-19:

- pdf.js ships `TextLayer`, which puts each page's text in the DOM, where assistive technology
  reads it. EmbedPDF has no screen-reader layer (its issue #135 is open). A signer must be able to
  read what they sign, so this decides it.
- EmbedPDF needs `'wasm-unsafe-eval'` page-wide in `script-src`. pdf.js runs without it (below).
- Size, gzipped: pdf.js about 0.5 MB with its worker; EmbedPDF's wasm alone about 2.15 MB.
- EmbedPDF was mid-transition (v2 and v3 packages mixed, fast release churn).
- Extend's React components were not considered further: they bring React, Tailwind and shadcn
  into a Lit renderer, and their e-signature block stamps the PDF in the browser.

The host owns the `pdfjs-dist` dependency, as it owns `lit`, `@a2ui/*` and `mermaid`, and pins it
exactly, at 6.2.108 or later (CVE-2026-16633 affects 5.6.83 up to 6.2.108). The package ships the
loader module, `priv/js/ash_a2ui_pdf.js`, and the worker module, `priv/js/ash_a2ui_pdf_worker.js`;
the host bundles both as their own entries and passes `loadPdf` to `createAshAdminCatalog`. The
viewer calls it the first time it has a document to open, so a page that never shows a document
never fetches pdf.js. This is the pattern `liveDiagram` uses for mermaid.

Documents open with `isEvalSupported: false`. pdf.js 6 decodes JBIG2 and JPEG 2000 images, and
applies ICC profiles, with WebAssembly modules it fetches from `wasmUrl`; JBIG2 and JPEG 2000
have JavaScript fallbacks it imports from the same place. The pre-build checks (below) showed
what follows: **a host that wants scanned documents to draw serves `pdfjs-dist/wasm/` and passes
its address as `configure({wasmUrl})`**. Without it, JBIG2 and JPEG 2000 images draw blank (pdf.js
logs no error), though the rest of the page draws.

### 2. Two catalog components, one pane per surface (admin catalog 3.4)

- `documentViewer`: the pages of the PDF at `src`, each a canvas with pdf.js's text layer over
  it (`role="group"`, named "Page n of m"), zoom (steps of the width that fits: 50% to 300%) and
  page navigation, and **regions** on top. A region is `{id, page, x, y, width, height, state,
  label?}`: the box as fractions of its page from the top-left corner, so it needs no knowledge
  of the page's size or the zoom. `state` is one of `pending`, `reviewed`, `selected`,
  `reviewed-selected`, `linked` and `empty`. Regions sharing an id are one region drawn in
  several places. A region is a button named by its label and its state in words; activating it
  (click, Enter, Space) selects it and sends `regionAction`, the `document_region` event, with
  the region's id. Nothing is edited or signed in the browser: a host that stamps a signature
  does it on the server and sends the new version's address.
- `documentPane`: the surface's sections (`children`) and its viewer. Hidden (the default), the
  sections draw alone; shown, beside the document, one part to two, the document following the
  window; where there is no room for both (under 56rem of the pane's own width) the document
  stacks under the sections. The layout is the renderer's, not the host's. Its switch shows and
  hides it and sends `toggleAction`, the `document_pane` event, with `shown`. A link inside the
  sections whose href starts with `regionHref` (`#<url_param>=`) opens the pane at that region.

The renderer draws a change at once, writing the data model, and sends the action after; the
server writes the same values back (`/ui/documents/<name>/shown` and `/selected`). Both actions
are quiet and read nothing. A host answers them like any other action.

### 3. The DSL: a pane bound to a `:detail` context

```elixir
document_pane :document do
  context :contract              # at least one :detail card renders it
  source :page_document          # %{url, name} | nil, read as the reader
  regions :page_document_regions # optional: regions no field cites
  label "Show document"          # the switch; defaults to the library's "Show document"
  description "Read-only, for reviewing values"
  url_param "document"           # defaults to the pane's name
end
```

The regions come from the cards: each field of the context's `:detail` cards whose `review`
carries `boxes` is a region named by its field, in its review state (`missing` draws `empty`),
labelled by the field's label. Its review's `href` becomes the pane's, so the page tag opens the
pane at the value. `regions` adds the regions no field cites (a signature field, a table value).
The document travels with the record (`/detail/<context>/_document_<name>`), so every path that
re-sends the record (a context change, a field action) re-sends the regions with their new
states. `AshA2ui.LiveRenderer` keeps the pane open in the address, `?<url_param>=shown` only when
it is open (closed is the default and leaves nothing), reads it on mount and on back/forward, and
keeps it open across a full refresh. A surface has at most one pane. The basic catalog leaves the
pane out.

### 4. What stays the host's

Who may open which file (the `url` the source returns, read as the reader), where on the page a
value sits (the boxes), the review states, and the design system. A host redraws the two
components with a catalog swap (ADR 0001, section 6) through their seams: the pane's
`renderToggle`, the viewer's `renderFrame`, `renderControls`, `renderRegion` and `scrollArea`.
The engine, the geometry and the events stay the package's.

## The pre-build checks

Run by `priv/js/probe/document_probe.mjs --corpus DIR` on 2026-11-19, pdfjs-dist 6.4.299,
Chromium (Playwright), with pdf.js's own test files (mozilla/pdf.js `test/pdfs`, not committed):
`perf_codecs_jbig2.pdf` (a scanned JBIG2 page), `bug_jpx.pdf` and `perf_codecs_jpx.pdf` (JPEG
2000), `perf_structure_colorspace_fills.pdf` and `perf_structure_colorspace_images.pdf` (ICC
profiles), `structure_simple.pdf` (tagged), `perf_images_scan_bilevel.pdf` (a scan). Each was
opened under two CSPs set on every response, worker scripts included: strict
(`script-src 'self' 'unsafe-inline'`, no `'unsafe-eval'`, no `'wasm-unsafe-eval'`) and the first
host's (`'unsafe-eval'`, which also lets WebAssembly compile).

| | no `wasmUrl` | `wasmUrl`, strict CSP | `wasmUrl`, `'unsafe-eval'` |
|---|---|---|---|
| JBIG2 | opens, image blank | draws (JS fallback) | draws (wasm) |
| JPEG 2000 | opens, image blank | draws (JS fallback; the 0.5 MB file in about 5 s) | draws (wasm) |
| ICC profile | draws | draws | draws |
| Tagged | draws | draws | draws |
| Scan (no JBIG2/JPX) | draws | draws | draws |

No CSP violation was reported and nothing logged an error. Under the strict CSP pdf.js fetched
the wasm module, could not compile it and imported the JavaScript fallback from `wasmUrl`. The
ICC files never requested `qcms_bg.wasm`: pdf.js drew them in their alternate colour space.

## Consequences

- One viewer serves review, signing and acknowledgement; the host keeps its look and its rules.
- Untagged PDFs read poorly in any viewer: the text layer gives the words, not their structure.
  Signing and acknowledgement keep a text or HTML alternative.
- A host must pin `pdfjs-dist`, bundle the two modules, and serve `pdfjs-dist/wasm/` to draw
  scanned documents. Each upgrade of `pdfjs-dist` is the host's, checked against its CVE list.
- The admin catalog moves to 3.4.0 under the same id, after 3.3.0 (lukegalea/ash_a2ui#121, table review fields).
- Not done here: lazy page drawing for long documents (every page draws when the document opens),
  and printing or downloading from the viewer.
- Done later, in admin catalog 3.8.0: a value and its region linked both ways while the pane is
  shown. The renderer marks the element it draws for a value with `data-a2ui-region` (the review
  hrefs the server already sends), and the pane listens for pointer and focus through
  `composedPath()`, as the hook does for live links (3.7). Pointing at or focusing a value draws
  its regions in the viewer's `linkedState` (`linked` by default) and scrolls only the viewer's
  canvas; activating a region scrolls the page to the value and flashes it through the pane's
  `flashSource`, and from the keyboard moves focus to it. It is presentation state the browser
  keeps: nothing on the wire changes and no action is sent. Hover and focus link only while the
  document is beside the sections (`sideBySide()`).
