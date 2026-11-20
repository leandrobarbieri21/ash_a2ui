# Document Panes

A record that was read from a document (a contract, a referral, a policy)
can show that document beside its details, with each value boxed where it
sits on its page. A person checks the values against the source without
leaving the page, and a field's page tag ("p. 3") opens the document at the
value. The same viewer serves signing (the boxes are signature fields) and
acknowledgement.

The admin catalog draws it (catalog 3.4). The basic catalog leaves it out.

## Declaring a pane

```elixir
defmodule MyApp.UI.ContractPageUI do
  use AshA2ui.Standalone

  a2ui do
    for_resource MyApp.Contract

    context :contract do
      resource MyApp.Contract
      picker false
    end

    component :detail, :details do
      section "Overview"
      context :contract
      fields [:name, :payment_term]
    end

    document_pane :document do
      context :contract
      source :page_document
      label "Show document"
      description "Read-only, for reviewing values"
    end

    field :payment_term do
      review :payment_term_review
    end
  end
end
```

- `context` names a context at least one `:detail` card renders: the pane is
  bound to those cards.
- `source` names a public attribute or calculation of the context's
  resource: `%{url: "/contracts/9/file", name: "contract.pdf"}`, or `nil`
  when the record has no document (the switch is not drawn). The browser
  fetches `url` as the reader, so serve it through a route that checks the
  reader may open the file.
- `regions` (optional) names one holding regions no field cites.
- `label` is the switch (default "Show document", a library string) and
  `description` the words beside it, both translated in the metadata domain.
- `url_param` is the address parameter that holds the pane open (default:
  the pane's name).

A surface has at most one pane, and the pane holds all its sections.

## Where the boxes come from

A field's `review` (see `AshA2ui.Review`) may carry `boxes`: where the value
sits on the document's pages, as fractions of the page from its top-left
corner.

```elixir
%{
  state: :pending,
  page: 2,
  boxes: [%{page: 2, x: 0.2941, y: 0.8485, width: 0.1088, height: 0.0152}]
}
```

Each field with boxes is a region of the pane, named by the field, drawn in
its review state (`pending`, `reviewed`; a `missing` value with a box draws
`empty`) and labelled by the field's label. Its review's `href` becomes
`#<url_param>=<field>`, so the page tag opens the pane at the box. Convert
your extraction's coordinates to fractions on the server, and never send the
words the box covers: the pane draws the page itself.

Regions from `regions` are maps with `id`, `page`, `x`, `y`, `width`,
`height`, `state` (`pending`, `reviewed`, `selected`, `reviewed_selected`,
`linked` or `empty`) and an optional `label`. Bad ones are dropped.

The document travels with the record, at `/detail/<context>/_document_<name>`,
so a context change or a field action re-sends the regions in their new
states.

## What a person sees

- The switch, off by default. On, the sections sit beside the document, one
  part to two, and the document follows the window; on a narrow page it
  stacks under them.
- Each page with its text layer, so a screen reader reads the document and
  a person can select its words; zoom (50% to 300% of the width that fits)
  and page navigation.
- Each region over its box: a button named by its label and state. Choosing
  it selects it and sends the `document_region` action with its id.
- A value and its region, linked both ways (admin catalog 3.8). While the
  document sits beside the sections, pointing at a value that cites a
  region, or focusing anything inside it (its page tag), shows the region
  linked and scrolls the document, never the page, if the region is out of
  view. Focus stays where it is and nothing is sent; leaving or blurring
  clears it. A table row links every region its cells cite. Choosing a
  region also scrolls the page to the value citing it and flashes it for
  three seconds; from the keyboard (Enter or Space), focus moves to the
  value. Stacked on a narrow page, or with the pane hidden, pointing and
  focusing link nothing.

## The address and the actions

`AshA2ui.LiveRenderer` keeps the pane open in the address:
`?document=shown` while open, nothing while closed. A reload or a shared
link reopens it, back and forward show and hide it, and a PubSub refresh
keeps it open. The switch sends `document_pane` (`%{"pane", "shown"}`) and a
region `document_region` (`%{"pane", "regionId"}`); both are quiet and read
nothing, and the server writes them to `/ui/documents/<name>`.

A LiveView without `deep_link: true` records the address by calling
`AshA2ui.LiveRenderer.handle_params/4` from its own `handle_params/3`. The
page around the surface can follow the pane with
`AshA2ui.DocumentPane.url_state/2` on its params.

## Wiring pdf.js

pdf.js loads the first time a document opens. The host owns `pdfjs-dist`,
pinned exactly (6.2.108 or later), and bundles ash_a2ui's two modules as
their own entries:

```sh
esbuild deps/ash_a2ui/priv/js/ash_a2ui_pdf.js \
        deps/ash_a2ui/priv/js/ash_a2ui_pdf_worker.js \
        --bundle --format=esm --outdir=priv/static/assets/js
```

then passes the loader to the admin catalog:

```js
const adminCatalog = createAshAdminCatalog({
  // ...
  loadPdf: () =>
    import("/assets/js/ash_a2ui_pdf.js").then((engine) => {
      engine.configure({wasmUrl: "/assets/pdfjs/wasm/"})
      return engine
    }),
})
```

Serve `node_modules/pdfjs-dist/wasm/` at the `wasmUrl`: pdf.js decodes
scanned (JBIG2) and JPEG 2000 images and applies ICC profiles with it, and
without it those images draw blank. Under a CSP without
`'wasm-unsafe-eval'` pdf.js uses the JavaScript fallbacks from the same
directory. ADR 0002 records the checks.

## Drawing it in your design system

Swap `documentPane` and `documentViewer` in the admin catalog (ADR 0001,
section 6) and override their seams: `renderToggle` on the pane;
`renderFrame`, `renderControls`, `renderRegion` and `scrollArea` on the
viewer. The engine, the geometry and the events stay the package's.
`--ash-admin-document-pane-top` sets where the shown document sticks under
a sticky header.

The links between values and regions (3.8) need three things from a swap:

- A swap that draws its own field or table row puts `data-a2ui-region`
  (`REGION_ATTRIBUTE`, exported by `ash_admin_catalog.js`) on the element
  it draws for the value, its value `regionAddresses(review)` for a field
  or `regionAddresses(rowReviews(row, columns))` for a row. The stock
  `fieldDisplay` and `dataGrid` do this; a swap that leaves it out keeps
  only the page tag's link.
- `renderRegion`'s `activate(event)` reads a call with no event, a key
  event, or a click with `detail` 0 as the keyboard (focus then moves to
  the value), so a key handler calls `activate()`. Its `current` says
  whether the region is the one a person went to: use it for
  `aria-current`, since a linked region may be drawn selected.
- The viewer's `linkedState(region)` is the state a linked region is drawn
  in, `linked` by default; return `selectedState(region.state)` to draw
  it selected. The pane's `flashSource(element, on)` draws the flash (the
  section nav's outline by default), and `sideBySide()` says whether the
  document is beside the sections.
