# AshA2ui document pane rules

Rules for `document_pane` entities: the document a record was read from,
drawn beside the surface's sections with each value boxed on its page
(admin catalog 3.4). See the Document Panes topic and ADR 0002.

## Declaring

- Bind the pane to a context a `:detail` card renders. Its regions are the
  `boxes` of those cards' fields' `review` citations:

  ```elixir
  document_pane :document do
    context :contract
    source :page_document          # %{url, name} | nil
    regions :page_document_regions # optional: regions no field cites
    label "Show document"
    description "Read-only, for reviewing values"
  end
  ```

- `source` names a public attribute or calculation of the context's
  resource returning `%{url: ..., name: ...}` or `nil`. `nil` means no
  document and no switch. Compute it as the reader: only return the address
  of a file the reader may open, and serve that address through a route that
  checks again.
- A review's boxes are fractions of the page from its top-left corner:
  `%{page: 2, x: 0.29, y: 0.85, width: 0.11, height: 0.015}`. Convert the
  extraction's page coordinates on the server; never send the cited words.
- Use `regions` for boxes no field cites (a table value, a signature
  field): `%{id, page, x, y, width, height, state, label}`, states
  `pending | reviewed | selected | reviewed_selected | linked | empty`.
- One pane per surface. The pane holds every section of the surface.

## The address and the actions

- `AshA2ui.LiveRenderer` keeps the pane open in the address
  (`?<url_param>=shown`, the name by default) and reads it on mount and on
  back/forward. Off is the default and leaves no parameter. A LiveView
  without `deep_link: true` calls `AshA2ui.LiveRenderer.handle_params/4`
  from its own `handle_params/3`, or the switch cannot patch the address.
- The page around the surface can follow the pane with
  `AshA2ui.DocumentPane.url_state/2` on its params (to hide a side nav, say),
  or the `:ash_a2ui_document_state` assign.
- `document_pane` (shown or hidden) and `document_region` (a region a person
  went to) are quiet actions that read nothing. Answer them in
  `handle_event("a2ui:message", ...)` if the host needs to.

## Loading pdf.js

- The host owns `pdfjs-dist`, pinned exactly, 6.2.108 or later
  (CVE-2026-16633). Bundle `priv/js/ash_a2ui_pdf.js` and
  `priv/js/ash_a2ui_pdf_worker.js` as their own ES module entries into one
  directory, never into app.js, and pass
  `loadPdf: () => import("/assets/js/ash_a2ui_pdf.js")` to
  `createAshAdminCatalog`. pdf.js loads the first time a document opens.
- Serve `pdfjs-dist/wasm/` and call `configure({wasmUrl})` on the loaded
  module, or scanned (JBIG2) and JPEG 2000 images draw blank. A strict CSP
  without `'wasm-unsafe-eval'` is fine: pdf.js falls back to its JavaScript
  decoders.

## Drawing it in a design system

- Swap `documentPane` and `documentViewer` (ADR 0001, section 6) and
  override the seams: `renderToggle` on the pane; `renderFrame`,
  `renderControls`, `renderRegion` and `scrollArea` on the viewer. Keep the
  engine, the geometry and the events.
- `--ash-admin-document-pane-top` sets where the shown document sticks
  under a sticky header; `--ash-admin-document-pane-height` and
  `--ash-admin-document-pane-stacked-height` its heights.

## Avoid

- ❌ Hand-writing a split view or a PDF viewer beside a surface.
- ❌ Sending a document's text, or a client-supplied file address.
- ❌ Importing `pdfjs-dist` into app.js or the catalog bundle.
- ❌ Stamping or editing a PDF in the browser.
