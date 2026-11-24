/**
 * Document panes for the admin catalog (3.4): `documentPane` and
 * `documentViewer`.
 *
 * `documentViewer` draws the pages of a PDF with pdf.js, each as a canvas
 * with pdf.js's text layer over it (so assistive technology reads the page)
 * and the regions on top: boxes placed as fractions of their page. It has
 * zoom and page navigation, and activating a region (click, Enter, Space)
 * selects it and sends the `regionAction` event with `regionId`.
 *
 * pdf.js is several hundred kilobytes with its worker, so it is loaded the
 * first time a viewer has a document to open, through the `loadPdf`
 * dependency of `createAshAdminCatalog` (see priv/js/ash_a2ui_pdf.js, the
 * module that loader imports). A page that never opens a document never
 * fetches it.
 *
 * `documentPane` holds a surface's sections (`children`) and draws them
 * alone while hidden, beside its `viewer` while shown. Its switch shows and
 * hides it, and a link inside its children whose href starts with
 * `regionHref` opens it at that region (a review field's page tag).
 *
 * 3.8: while the pane is shown, a value and its region are linked both
 * ways. The element drawing a value that cites a region carries
 * REGION_ATTRIBUTE (`data-a2ui-region`), its value the region's address
 * (the review's `href`, several separated by spaces for a table row).
 * Pointing at it or focusing inside it links its regions in the viewer
 * (`link(ids)`: drawn in `linkedState(region)`, the pane's own scroll area
 * moved to the first one if it is out of view; nothing is written, sent or
 * focused). Activating a region scrolls the page to the value that cites
 * it and flashes it for 3 seconds; from the keyboard, focus moves to it.
 * Hover and focus link only while the document sits beside the sections.
 *
 * Both elements expose seams a host's catalog swap overrides to draw them
 * with its own design system, keeping the engine, the geometry and the
 * events:
 *
 *   documentPane    renderToggle({label, description, checked, onChange})
 *                   flashSource(element, on)  draws a value's flash (3.8)
 *                   sideBySide()  whether the document sits beside the
 *                     sections (3.8; hover and focus link only then)
 *   documentViewer  renderFrame({fileName, status, pageInfo, zoomLabel,
 *                     controls, pages, message})
 *                   renderControls({page, count, zoomLabel, canZoomIn,
 *                     canZoomOut, previous, next, zoomIn, zoomOut, strings})
 *                   renderRegion(region, {state, label, style, activate,
 *                     current})
 *                     (3.8: `current` is whether the region is the one a
 *                     person went to, for aria-current: a linked region
 *                     drawn selected is not; `activate(event)`: called with
 *                     no event, a key
 *                     event or a click with detail 0, it is a keyboard
 *                     activation)
 *                   linkedState(region)  the state a linked region is
 *                     drawn in (3.8; `linked` by default)
 *                   scrollArea()  the element that scrolls the pages
 *
 * The pure helpers (regions, states, hrefs, zoom) are exported for tests.
 */

/** The region states (catalog 3.4). */
export const REGION_STATES = Object.freeze([
  "pending",
  "reviewed",
  "selected",
  "reviewed-selected",
  "linked",
  "empty",
]);

/**
 * The attribute a drawn value carries when it cites regions (3.8): the
 * regions' addresses (a review's `href`, `#<pane>=<id>`), separated by
 * spaces. A host swap puts it on the element it draws for a value (a
 * field's row, a table's row) from the same `review.href`.
 */
export const REGION_ATTRIBUTE = "data-a2ui-region";

/**
 * The event a region's activation by a person raises on the viewer (3.8):
 * bubbling and composed, `detail` `{id, keyboard}`. The pane answers it by
 * going to the value that cites the region.
 */
export const REGION_ACTIVATE_EVENT = "ash-a2ui:document-region";

/** How long a value stays flashed after its region is activated (3.8). */
export const FLASH_MS = 3000;

/** The zoom steps, as factors of the width that fits the viewer. */
export const ZOOM_STEPS = Object.freeze([0.5, 0.75, 1, 1.25, 1.5, 2, 3]);

/**
 * The width the pages may take in their scroll area: its `clientWidth`
 * (inside its borders, without a scrollbar it shows) less its padding.
 */
export function usableWidth(area) {
  if (!area) return 0;
  const style = getComputedStyle(area);
  const padding = (parseFloat(style.paddingLeft) || 0) + (parseFloat(style.paddingRight) || 0);
  return area.clientWidth - padding;
}

/**
 * The width a fitted page is drawn at in a usable width: whole CSS pixels,
 * 1px short of it. `clientWidth` is rounded, and the area's real width (on
 * a 2x screen, half pixels) can be a fraction below it, so a page as wide
 * as the rounded width can still reach past the edge.
 */
export function fittedWidth(usable) {
  return Math.max(0, Math.floor(usable) - 1);
}

const fraction = (n) => typeof n === "number" && Number.isFinite(n) && n >= 0 && n <= 1;

/**
 * The server's regions, as drawn: anything that is not a box on a page is
 * dropped, and an unknown state is pending.
 */
export function parseRegions(value) {
  if (!Array.isArray(value)) return [];
  return value
    .filter(
      (r) =>
        r &&
        typeof r === "object" &&
        typeof r.id === "string" &&
        r.id !== "" &&
        Number.isInteger(r.page) &&
        r.page > 0 &&
        [r.x, r.y, r.width, r.height].every(fraction) &&
        r.width > 0 &&
        r.height > 0,
    )
    .map((r) => ({
      id: r.id,
      page: r.page,
      x: r.x,
      y: r.y,
      width: r.width,
      height: r.height,
      state: REGION_STATES.includes(r.state) ? r.state : "pending",
      label: typeof r.label === "string" ? r.label : "",
    }));
}

/**
 * The state a region is drawn in: the selected region (the one a person
 * went to) is selected, or reviewed-selected once reviewed; linked and
 * empty keep their state. 3.8: a region in `linked` (the ids a value being
 * pointed at or focused cites), and not selected, is drawn in
 * `linkedState(region)`, `linked` by default.
 */
export function drawnState(region, selectedId, {linked = null, linkedState = () => "linked"} = {}) {
  if (selectedId != null && region.id === selectedId) return selectedState(region.state);
  if (Array.isArray(linked) && linked.includes(region.id)) return linkedState(region);
  return region.state;
}

/**
 * A state as its selected form: pending is selected, reviewed is
 * reviewed-selected; linked and empty keep their state. A host whose
 * linked regions read as selected returns it from `linkedState`.
 */
export function selectedState(state) {
  if (state === "reviewed" || state === "reviewed-selected") return "reviewed-selected";
  if (state === "pending" || state === "selected") return "selected";
  return state;
}

/** The region id a link's href names under the pane's `prefix`, or null. */
export function regionFromHref(href, prefix) {
  if (typeof href !== "string" || typeof prefix !== "string" || prefix === "") return null;
  if (!href.startsWith(prefix)) return null;
  const encoded = href.slice(prefix.length);
  if (encoded === "") return null;
  try {
    return decodeURIComponent(encoded.replace(/\+/g, " "));
  } catch {
    return null;
  }
}

/**
 * The region ids a REGION_ATTRIBUTE value names under the pane's `prefix`
 * (3.8): its addresses, separated by spaces, each decoded; anything else is
 * skipped, and an id named twice counts once.
 */
export function regionIdsOf(value, prefix) {
  if (typeof value !== "string") return [];
  const ids = [];
  for (const href of value.split(/\s+/)) {
    const id = regionFromHref(href, prefix);
    if (id && !ids.includes(id)) ids.push(id);
  }
  return ids;
}

/**
 * What a pointer or focus event's composed path links to (3.8): the
 * nearest element carrying REGION_ATTRIBUTE, or an element whose `href`
 * names a region under `prefix` (a review's page tag), whichever comes
 * first, as `{element, ids}`; null when there is none before `stop` (the
 * pane, or its viewer: pointing at the document links nothing).
 */
export function linkSourceOf(path, prefix, stop = []) {
  if (!Array.isArray(path)) return null;
  for (const node of path) {
    if (!node || stop.includes(node)) return null;
    if (typeof node.getAttribute !== "function") continue;
    const marked = node.getAttribute(REGION_ATTRIBUTE);
    if (marked) {
      const ids = regionIdsOf(marked, prefix);
      if (ids.length) return {element: node, ids};
    }
    const id = regionFromHref(node.getAttribute("href"), prefix);
    if (id) return {element: node, ids: [id]};
  }
  return null;
}

/**
 * Whether a region's activation came from the keyboard (3.8): no event (a
 * swap's key handler calls `activate()`), a key event, or a click with no
 * pointer behind it (detail 0: Enter or Space on a button).
 */
export function keyboardActivation(event) {
  if (!event) return true;
  if (typeof event.type === "string" && event.type.startsWith("key")) return true;
  return event.type === "click" && event.detail === 0;
}

/** The next zoom step in `direction` (1 in, -1 out), or the same at an end. */
export function nextZoom(zoom, direction) {
  const steps = ZOOM_STEPS;
  if (direction > 0) return steps.find((step) => step > zoom + 1e-9) ?? zoom;
  return [...steps].reverse().find((step) => step < zoom - 1e-9) ?? zoom;
}

/** A box's place on its page, as CSS percentages. */
export function boxStyle(region) {
  const percent = (n) => `${(n * 100).toFixed(3)}%`;
  return {
    left: percent(region.x),
    top: percent(region.y),
    width: percent(region.width),
    height: percent(region.height),
  };
}

/** Fills `%{name}` placeholders of a server-translated template. */
export function format(template, bindings) {
  if (typeof template !== "string") return "";
  return template.replace(/%\{(\w+)\}/g, (match, key) => (key in bindings ? String(bindings[key]) : match));
}

/** The engine a `loadPdf` loader resolved: ash_a2ui_pdf.js's, or a raw pdf.js module. */
export function toPdfEngine(loaded) {
  const candidate = loaded?.default ?? loaded;
  if (candidate && typeof candidate.open === "function" && candidate.TextLayer) return candidate;
  const pdfjs = candidate?.pdfjs ?? candidate;
  if (pdfjs && typeof pdfjs.getDocument === "function") {
    return {
      open: (src) => pdfjs.getDocument({url: src, isEvalSupported: false}),
      TextLayer: pdfjs.TextLayer,
      pdfjs,
    };
  }
  return null;
}

const DEFAULT_STRINGS = {
  loading: "Opening the document",
  failed: "This document can't be shown here.",
  pageOf: "%{page} of %{count}",
  pageLabel: "Page %{page} of %{count}",
  previousPage: "Previous page",
  nextPage: "Next page",
  zoomIn: "Zoom in",
  zoomOut: "Zoom out",
  pending: "Not reviewed",
  reviewed: "Reviewed",
  empty: "Not found in the document",
};

const sameIds = (a, b) => Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((id, i) => id === b[i]);

// The words a region's state reads as (selected states read as their base).
const STATE_WORD = {
  pending: "pending",
  selected: "pending",
  reviewed: "reviewed",
  "reviewed-selected": "reviewed",
  empty: "empty",
};

/**
 * Defines <ash-admin-document-pane> and <ash-admin-document-viewer> (once).
 * Called by createAshAdminCatalog with its element dependencies.
 */
export function defineDocumentElements({
  A2uiLitElement,
  A2uiController,
  lit,
  apis,
  tags,
  styles,
  renderActionButton,
  dispatchActionSpec,
  bindingPath,
  applyWeight,
  childRefs,
  catalogId,
  loadPdf,
}) {
  const {html, css, nothing} = lit;

  let enginePromise = null;
  const loadEngine = () => {
    if (!enginePromise) {
      enginePromise =
        typeof loadPdf === "function"
          ? Promise.resolve()
              .then(() => loadPdf())
              .then((loaded) => {
                const engine = toPdfEngine(loaded);
                if (!engine) throw new Error("loadPdf resolved to no pdf.js engine");
                return engine;
              })
          : Promise.reject(new Error("no loadPdf dependency: pass one to createAshAdminCatalog"));
      // A failed load (offline, a deploy in between) is not kept: the next viewer tries again.
      enginePromise.catch(() => {
        enginePromise = null;
      });
    }
    return enginePromise;
  };

  // Sends a bare {name, context} event as the ash_a2ui catalog's ashAction.
  const send = (element, event, extra) => {
    if (!event || typeof event.name !== "string" || !element.context?.componentModel) return;
    dispatchActionSpec(element.context, {
      name: event.name,
      context: {...(event.context || {}), ...extra},
      catalogId,
    }).catch?.(() => {});
  };

  // Writes `value` at the path a prop binds, so the renderer shows it at once.
  const write = (element, prop, value) => {
    const path = bindingPath(element.context?.componentModel?.properties?.[prop]);
    const dataModel = element.context?.dataContext?.surface?.dataModel;
    if (typeof path === "string" && dataModel) dataModel.set(path, value);
  };

  defineViewer();
  definePane();

  // --- documentViewer ----------------------------------------------------------

  function defineViewer() {
    const tag = tags.documentViewer;
    if (customElements.get(tag)) return;

    class AshAdminDocumentViewer extends A2uiLitElement {
      static properties = {
        _status: {state: true},
        _pages: {state: true},
        _current: {state: true},
        _zoom: {state: true},
        _scale: {state: true},
        _selected: {state: true},
        _linked: {state: true},
      };

      static styles = [
        styles.shared,
        styles.buttons,
        css`
          :host {
            display: block;
            height: 100%;
            min-height: 0;
          }
          .viewer {
            display: flex;
            flex-direction: column;
            height: 100%;
            min-height: 0;
            overflow: hidden;
            border: var(--am-border-width) solid var(--am-border);
            border-radius: var(--am-radius-m);
            background: var(--am-surface-sunken);
          }
          .toolbar {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--am-space-xs);
            padding: var(--am-space-xs) var(--am-space-s);
            border-bottom: var(--am-border-width) solid var(--am-border);
            background: var(--am-surface);
            font-size: var(--am-font-size-s);
          }
          .file-name {
            flex: 1;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-weight: var(--am-font-weight-medium);
          }
          .controls {
            display: flex;
            align-items: center;
            gap: var(--am-space-2xs);
          }
          .page-info,
          .zoom {
            font-size: var(--am-font-size-xs);
            color: var(--am-text-muted);
            font-variant-numeric: tabular-nums;
          }
          .canvas {
            flex: 1;
            min-height: 0;
            overflow: auto;
            padding: var(--am-space-l) var(--am-space-m);
          }
          .pages {
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: var(--am-space-m);
            width: max-content;
            min-width: 100%;
          }
          .message {
            margin: var(--am-space-l) auto;
            text-align: center;
            color: var(--am-text-muted);
          }
          /* One page: its canvas, pdf.js's text layer over it, the regions on top. */
          .page {
            --user-unit: 1;
            --total-scale-factor: calc(var(--scale-factor) * var(--user-unit));
            --scale-round-x: 1px;
            --scale-round-y: 1px;
            position: relative;
            flex: none;
            background: #fff;
            box-shadow: 0 1px 3px rgb(0 0 0 / 0.18);
          }
          .page canvas {
            position: absolute;
            inset: 0;
            width: 100%;
            height: 100%;
          }
          .textLayer {
            position: absolute;
            inset: 0;
            overflow: clip;
            line-height: 1;
            text-align: initial;
            letter-spacing: normal;
            word-spacing: normal;
            text-size-adjust: none;
            forced-color-adjust: none;
            transform-origin: 0 0;
            caret-color: CanvasText;
            z-index: 0;
            --min-font-size: 1;
            --text-scale-factor: calc(var(--total-scale-factor) * var(--min-font-size));
            --min-font-size-inv: calc(1 / var(--min-font-size));
          }
          .textLayer :is(span, br) {
            color: transparent;
            position: absolute;
            white-space: pre;
            cursor: text;
            transform-origin: 0% 0%;
            user-select: text;
          }
          .textLayer > :not(.markedContent),
          .textLayer .markedContent span:not(.markedContent) {
            z-index: 1;
            --font-height: 0;
            font-size: calc(var(--text-scale-factor) * var(--font-height));
            --scale-x: 1;
            --rotate: 0deg;
            transform: rotate(var(--rotate)) scaleX(var(--scale-x)) scale(var(--min-font-size-inv));
          }
          .textLayer .markedContent {
            display: contents;
          }
          .textLayer ::selection {
            background: rgb(0 0 255 / 0.25);
          }
          /* No z-index: a stacking context here would keep the regions' multiply
             blend from reaching the page, and the words under a box would vanish.
             Painted after the text layer, the regions are on top of it. */
          .regions {
            position: absolute;
            inset: 0;
            pointer-events: none;
          }
          .region {
            position: absolute;
            box-sizing: content-box;
            margin: -2px 0 0 -2px;
            padding: 0;
            border: 2px solid transparent;
            border-radius: var(--am-radius-s);
            background: transparent;
            mix-blend-mode: multiply;
            pointer-events: auto;
            cursor: pointer;
          }
          .region[data-state="pending"] {
            background: var(--ash-admin-region-pending, var(--am-pending-subtle, var(--am-warning-subtle)));
          }
          .region[data-state="selected"] {
            background: var(--ash-admin-region-pending, var(--am-pending-subtle, var(--am-warning-subtle)));
            border-color: var(--am-focus);
          }
          .region[data-state="reviewed"] {
            background: var(--ash-admin-region-reviewed, var(--am-success-subtle));
          }
          .region[data-state="reviewed-selected"] {
            background: var(--ash-admin-region-reviewed, var(--am-success-subtle));
            border-color: var(--am-focus);
          }
          .region[data-state="linked"] {
            background: var(--ash-admin-region-linked, var(--am-primary-subtle));
            border-color: var(--am-focus);
          }
          .region[data-state="empty"] {
            background: var(--ash-admin-region-empty, var(--am-gray-subtle));
          }
          .region:focus-visible {
            outline: 2px solid var(--am-focus);
            outline-offset: 2px;
          }
          @media (prefers-reduced-motion: no-preference) {
            .region {
              transition: border-color 120ms ease;
            }
          }
        `,
      ];

      constructor() {
        super();
        this._pages = [];
        this._current = 1;
        this._zoom = 1;
        this._status = null;
        this._renders = [];
        this._textLayers = [];
        this._fit = 0;
      }

      createController() {
        return new A2uiController(this, apis.documentViewer);
      }

      get props() {
        return this.controller?.props;
      }

      strings() {
        return {...DEFAULT_STRINGS, ...(this.props?.strings || {})};
      }

      regions() {
        return parseRegions(this.props?.regions);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        this._resize?.disconnect();
        this._resize = null;
        this._sized = null;
        clearTimeout(this._refit);
        this._scroller?.removeEventListener("scroll", this._onScroll);
        this._scroller = null;
        this.close();
        this._src = undefined;
      }

      willUpdate(changed) {
        super.willUpdate(changed);
        const props = this.props;
        applyWeight(this, props);
        const src = typeof props?.src === "string" && props.src !== "" ? props.src : null;
        if (src !== this._src) {
          this._src = src;
          if (src) this.open(src);
          else {
            this.close();
            this._pages = [];
            this._status = null;
          }
        }
        const selected = typeof props?.selected === "string" && props.selected !== "" ? props.selected : null;
        if (selected !== this._boundSelected) {
          this._boundSelected = selected;
          if (selected) this.reveal(selected);
          else this._selected = null;
        }
      }

      updated(changed) {
        super.updated?.(changed);
        this.watchScroll();
        if (this._status === "ready") this.watchSize();
      }

      // ── the file ─────────────────────────────────────────────────────────

      async open(src) {
        this.close();
        this._status = "loading";
        // A new file is fitted afresh, at the zoom the person chose.
        this._scaled = false;
        this._pages = [];
        try {
          const engine = await loadEngine();
          if (src !== this._src) return;
          this._engine = engine;
          const task = engine.open(src);
          this._task = task;
          const doc = await task.promise;
          if (src !== this._src) return;
          const pages = [];
          for (let number = 1; number <= doc.numPages; number++) {
            const page = await doc.getPage(number);
            const {width, height} = page.getViewport({scale: 1});
            pages.push({number, width, height, page});
          }
          if (src !== this._src) return;
          this._pages = pages;
          this._status = "ready";
          await this.updateComplete;
          this.fit();
          this.watchSize();
          if (this._pending) this.reveal(this._pending);
        } catch (error) {
          if (src !== this._src) return;
          this._status = "failed";
          console.warn("documentViewer: the document could not be drawn", error);
        }
      }

      close() {
        this.cancelPaint();
        this._task?.destroy?.();
        this._task = null;
      }

      cancelPaint() {
        this._renders.forEach((render) => render.cancel?.());
        this._renders = [];
        this._textLayers.forEach((layer) => layer.cancel?.());
        this._textLayers = [];
      }

      /** The element that scrolls the pages (a swap that draws its own frame overrides it). */
      scrollArea() {
        return this.renderRoot.querySelector("[data-role='canvas']");
      }

      /** The page sheets, in order. */
      sheets() {
        return [...this.renderRoot.querySelectorAll("[data-page-sheet]")];
      }

      // The scale that fits the widest page in the canvas's usable width, then
      // the zoom on it. Only the fit zoom follows the width: a zoom the person
      // chose keeps its scale until they zoom again.
      fit() {
        const area = this.scrollArea();
        if (!area || this._pages.length === 0) return;
        const width = usableWidth(area);
        const fitted = fittedWidth(width);
        if (fitted <= 0) return;
        const widest = Math.max(...this._pages.map((page) => page.width));
        this._fitWidth = width;
        this._fitOuter = area.offsetWidth;
        this._fit = fitted / widest;
        if (this._zoom === 1 || !this._scaled) this.applyScale();
      }

      async applyScale() {
        const scale = this._fit * this._zoom;
        if (!scale) return;
        this._scale = scale;
        this._scaled = true;
        // At the fit zoom the pages fit by construction: no sideways
        // scrolling, so a rounding difference never draws a scrollbar. A zoom
        // the person chose scrolls both ways.
        const area = this.scrollArea();
        if (area) area.style.overflowX = this._zoom === 1 ? "hidden" : "";
        await this.updateComplete;
        this.paint();
      }

      // Each page at the scale, sharp on the screen's pixel ratio, its text layer over it.
      paint() {
        this.cancelPaint();
        const engine = this._engine;
        const ratio = window.devicePixelRatio || 1;
        for (const meta of this._pages) {
          const sheet = this.renderRoot.querySelector(`[data-page-sheet="${meta.number}"]`);
          const canvas = sheet?.querySelector("canvas");
          const text = sheet?.querySelector(".textLayer");
          if (!sheet || !canvas || !text) continue;
          const viewport = meta.page.getViewport({scale: this._scale * ratio});
          canvas.width = Math.floor(viewport.width);
          canvas.height = Math.floor(viewport.height);
          const render = meta.page.render({canvas, canvasContext: canvas.getContext("2d"), viewport});
          this._renders.push(render);
          render.promise.catch(() => {});

          text.replaceChildren();
          if (engine?.TextLayer) {
            const layer = new engine.TextLayer({
              textContentSource: meta.page.streamTextContent({includeMarkedContent: true, disableNormalization: true}),
              container: text,
              viewport: meta.page.getViewport({scale: this._scale}),
            });
            this._textLayers.push(layer);
            layer.render().then(
              () => this.dispatchEvent(new CustomEvent("document-page-text", {detail: {page: meta.number}})),
              () => {},
            );
          }
        }
      }

      // Re-fits when the scroll area's usable width changes: the window or the
      // pane resized, or a scrollbar appeared or went away. The viewer's own
      // box keeps its size when a scrollbar comes, so the scroll area is what
      // is watched.
      watchSize() {
        const area = this.scrollArea();
        if (!area || area === this._sized || typeof ResizeObserver === "undefined") return;
        this._resize ||= new ResizeObserver(() => this.onResize());
        if (this._sized) this._resize.unobserve(this._sized);
        this._sized = area;
        this._resize.observe(area);
      }

      onResize() {
        const area = this.scrollArea();
        const width = usableWidth(area);
        if (width <= 0 || width === this._fitWidth) return;
        // Wider in the same box because its scrollbar went away, but the pages
        // fitted to the wider width would bring it back: keep the narrower
        // fit, or the two would take turns.
        const scrollbarOnly = area.offsetWidth === this._fitOuter;
        if (this._zoom === 1 && scrollbarOnly && width > this._fitWidth && this.scrollsAt(width)) return;
        clearTimeout(this._refit);
        this._refit = setTimeout(() => this.fit(), 150);
      }

      // Whether the pages, fitted to `width`, would be taller than the scroll
      // area (so it would show its vertical scrollbar). Only an `auto` area
      // takes a scrollbar away when the pages get shorter.
      scrollsAt(width) {
        const area = this.scrollArea();
        const sheets = this.sheets();
        if (!area || sheets.length === 0 || !this._fitWidth) return false;
        const style = getComputedStyle(area);
        if (style.overflowY !== "auto") return false;
        const rects = sheets.map((sheet) => sheet.getBoundingClientRect());
        const pages = rects.reduce((sum, rect) => sum + rect.height, 0);
        const gaps = rects.at(-1).bottom - rects[0].top - pages;
        const padding = (parseFloat(style.paddingTop) || 0) + (parseFloat(style.paddingBottom) || 0);
        return pages * (width / this._fitWidth) + gaps + padding > area.clientHeight;
      }

      watchScroll() {
        const area = this.scrollArea();
        if (area === this._scroller) return;
        this._onScroll ||= () => this.onScroll();
        this._scroller?.removeEventListener("scroll", this._onScroll);
        this._scroller = area;
        area?.addEventListener("scroll", this._onScroll, {passive: true});
      }

      // The page a third of the way down the canvas: the one being read.
      onScroll() {
        const area = this.scrollArea();
        if (!area) return;
        const line = area.getBoundingClientRect().top + area.clientHeight / 3;
        let current = 1;
        for (const sheet of this.sheets()) {
          if (sheet.getBoundingClientRect().top <= line) current = Number(sheet.dataset.pageSheet);
        }
        this._current = current;
      }

      // ── navigation ───────────────────────────────────────────────────────

      goToPage(number) {
        const count = this._pages.length;
        const target = Math.min(Math.max(1, number), count);
        const sheet = this.renderRoot.querySelector(`[data-page-sheet="${target}"]`);
        const area = this.scrollArea();
        if (!sheet || !area) return;
        const offset = sheet.getBoundingClientRect().top - area.getBoundingClientRect().top;
        area.scrollTo({top: area.scrollTop + offset - 8, behavior: this.behavior()});
        this._current = target;
      }

      zoomBy(direction) {
        const zoom = nextZoom(this._zoom, direction);
        if (zoom === this._zoom) return;
        // Keep the page being read where it is.
        const area = this.scrollArea();
        const ratio = area && area.scrollHeight ? area.scrollTop / area.scrollHeight : 0;
        this._zoom = zoom;
        this.applyScale().then(() => {
          if (area) area.scrollTop = ratio * area.scrollHeight;
        });
      }

      behavior() {
        return window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth";
      }

      // ── regions ──────────────────────────────────────────────────────────

      /**
       * Shows the region `id` selected and scrolls the canvas so its first box
       * sits a third of the way down. Before the pages are drawn, it waits.
       */
      async reveal(id) {
        this._selected = id;
        if (this._status !== "ready") {
          this._pending = id;
          return;
        }
        this._pending = null;
        await this.updateComplete;
        if (!this.scrollToRegion(id)) return;
        // The viewer's top above the window: bring it into view.
        if (this.getBoundingClientRect().top < 0) this.scrollIntoView({block: "start", behavior: this.behavior()});
      }

      /**
       * Scrolls the canvas, and only the canvas, so region `id`'s first box
       * sits a third of the way down; with `ifHidden`, only when that box is
       * not already in view. Returns whether the box was found.
       */
      scrollToRegion(id, {ifHidden = false} = {}) {
        const box = this.renderRoot.querySelector(`[data-region="${CSS.escape(id)}"]`);
        const area = this.scrollArea();
        if (!box || !area) return false;
        const boxRect = box.getBoundingClientRect();
        const areaRect = area.getBoundingClientRect();
        const inView =
          boxRect.top >= areaRect.top &&
          boxRect.bottom <= areaRect.bottom &&
          boxRect.left >= areaRect.left &&
          boxRect.right <= areaRect.right;
        if (ifHidden && inView) return true;
        area.scrollTo({
          top: area.scrollTop + (boxRect.top - areaRect.top) - area.clientHeight / 3,
          left: area.scrollLeft + (boxRect.left - areaRect.left) - area.clientWidth / 3,
          behavior: this.behavior(),
        });
        return true;
      }

      /**
       * 3.8: shows regions `ids` linked (a value citing them is being
       * pointed at or focused) and, if the first one drawn is out of view,
       * scrolls the canvas to it. Presentation only: it never scrolls the
       * page, moves focus, writes the data model or sends anything.
       */
      async link(ids) {
        const list = (Array.isArray(ids) ? ids : [ids]).filter((id) => typeof id === "string" && id !== "");
        if (list.length === 0) return this.unlink();
        if (sameIds(list, this._linked)) return;
        this._linked = list;
        if (this._status !== "ready") return;
        await this.updateComplete;
        if (!sameIds(list, this._linked)) return;
        list.find((id) => this.scrollToRegion(id, {ifHidden: true}));
      }

      /** 3.8: no region linked. */
      unlink() {
        this._linked = null;
      }

      /**
       * 3.8: the state a linked region is drawn in. `linked` by default; a
       * host whose linked values read as selected overrides it (for one,
       * `selectedState(region.state)`).
       */
      linkedState(_region) {
        return "linked";
      }

      /**
       * A person activated region `id`: select it, keep it, and send the
       * action. 3.8: then raise REGION_ACTIVATE_EVENT, so the pane goes to
       * the value that cites it.
       */
      activate(id, event) {
        this._selected = id;
        this._boundSelected = id;
        write(this, "selected", id);
        send(this, this.props?.regionAction, {regionId: id});
        this.dispatchEvent(
          new CustomEvent(REGION_ACTIVATE_EVENT, {
            detail: {id, keyboard: keyboardActivation(event)},
            bubbles: true,
            composed: true,
          }),
        );
      }

      regionLabel(region, state, strings) {
        const word = strings[STATE_WORD[state]] || "";
        return [region.label, word].filter((part) => part).join(", ");
      }

      /** One region: a button over its box. */
      renderRegion(region, {state, label, style, activate, current}) {
        const css = Object.entries(style)
          .map(([key, value]) => `${key}:${value}`)
          .join(";");
        return html`<button
          type="button"
          class="region"
          data-region=${region.id}
          data-state=${state}
          aria-label=${label}
          aria-current=${current ? "true" : nothing}
          title=${label}
          style=${css}
          @click=${activate}
        ></button>`;
      }

      renderPage(meta, regions, strings) {
        const count = this._pages.length;
        const scale = this._scale || 0;
        // Whole CSS pixels, never wider than the scale gives (the epsilon keeps
        // 783.99999 from a fit of 784px at 784).
        const width = Math.floor(meta.width * scale + 1e-6);
        const height = Math.floor(meta.height * scale + 1e-6);
        const selected = this._selected;
        const linked = {linked: this._linked, linkedState: (region) => this.linkedState(region)};
        return html`<div
          class="page"
          data-page-sheet=${meta.number}
          role="group"
          aria-label=${format(strings.pageLabel, {page: meta.number, count})}
          style=${`--scale-factor:${scale};width:${width}px;height:${height}px`}
        >
          <canvas aria-hidden="true"></canvas>
          <div class="textLayer"></div>
          <div class="regions">
            ${regions
              .filter((region) => region.page === meta.number)
              .map((region) => {
                const state = drawnState(region, selected, linked);
                return this.renderRegion(region, {
                  state,
                  label: this.regionLabel(region, state, strings),
                  style: boxStyle(region),
                  activate: (event) => this.activate(region.id, event),
                  current: region.id === selected || region.state.endsWith("selected"),
                });
              })}
          </div>
        </div>`;
      }

      /** The page and zoom controls. */
      renderControls({page, count, zoomLabel, canZoomIn, canZoomOut, previous, next, zoomIn, zoomOut, strings}) {
        return html`<div class="controls">
          ${renderActionButton({label: strings.previousPage, icon: "chevron-left", size: "sm", tone: "quiet", disabled: page <= 1, onClick: previous})}
          <span class="page-info" data-role="page-info" aria-live="polite">${format(strings.pageOf, {page, count})}</span>
          ${renderActionButton({label: strings.nextPage, icon: "chevron-right", size: "sm", tone: "quiet", disabled: page >= count, onClick: next})}
          ${renderActionButton({label: strings.zoomOut, icon: "minus", size: "sm", tone: "quiet", disabled: !canZoomOut, onClick: zoomOut})}
          <span class="zoom" data-role="zoom">${zoomLabel}</span>
          ${renderActionButton({label: strings.zoomIn, icon: "plus", size: "sm", tone: "quiet", disabled: !canZoomIn, onClick: zoomIn})}
        </div>`;
      }

      /** The viewer's frame: the toolbar over the scrolling canvas. */
      renderFrame({fileName, status, controls, pages, message}) {
        return html`<section
          class="viewer"
          data-status=${status}
          aria-label=${fileName || nothing}
          aria-busy=${status === "ready" ? "false" : "true"}
        >
          <div class="toolbar">
            <span class="file-name">${fileName}</span>
            ${controls}
          </div>
          <div class="canvas" data-role="canvas">
            ${message ?? html`<div class="pages">${pages}</div>`}
          </div>
        </section>`;
      }

      render() {
        const props = this.props;
        if (!props) return nothing;
        const strings = this.strings();
        const status = this._status || "loading";
        const ready = status === "ready";
        const count = this._pages.length;
        const regions = ready ? this.regions() : [];
        const zoomLabel = ready && this._scale ? `${Math.round(this._scale * 100)}%` : "";

        const message =
          status === "failed"
            ? html`<p class="message" role="alert">${strings.failed}</p>`
            : ready
              ? null
              : html`<p class="message" role="status">${strings.loading}</p>`;

        return this.renderFrame({
          fileName: typeof props.fileName === "string" ? props.fileName : "",
          status,
          pageInfo: ready ? format(strings.pageOf, {page: this._current, count}) : "",
          zoomLabel,
          controls: ready
            ? this.renderControls({
                page: this._current,
                count,
                zoomLabel,
                canZoomIn: nextZoom(this._zoom, 1) !== this._zoom,
                canZoomOut: nextZoom(this._zoom, -1) !== this._zoom,
                previous: () => this.goToPage(this._current - 1),
                next: () => this.goToPage(this._current + 1),
                zoomIn: () => this.zoomBy(1),
                zoomOut: () => this.zoomBy(-1),
                strings,
              })
            : nothing,
          pages: ready ? this._pages.map((meta) => this.renderPage(meta, regions, strings)) : [],
          message,
        });
      }
    }

    customElements.define(tag, AshAdminDocumentViewer);
  }

  // --- documentPane ------------------------------------------------------------

  function definePane() {
    const tag = tags.documentPane;
    if (customElements.get(tag)) return;

    class AshAdminDocumentPane extends A2uiLitElement {
      static styles = [
        styles.shared,
        css`
          :host {
            display: block;
            container-type: inline-size;
          }
          .pane {
            display: flex;
            flex-direction: column;
            gap: var(--am-space-l);
          }
          .toggle {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--am-space-s);
          }
          .switch {
            display: inline-flex;
            align-items: center;
            gap: var(--am-space-xs);
            cursor: pointer;
            font-weight: var(--am-font-weight-medium);
          }
          .toggle-description {
            font-size: var(--am-font-size-xs);
            color: var(--am-text-muted);
          }
          .split {
            display: grid;
            grid-template-columns: minmax(0, 1fr);
            gap: var(--am-space-l);
            align-items: start;
          }
          .content {
            display: flex;
            flex-direction: column;
            gap: var(--am-space-xl);
            min-width: 0;
          }
          /* Shown and stacked (narrow): the document under the sections. */
          .document {
            min-width: 0;
            height: var(--ash-admin-document-pane-stacked-height, 80vh);
          }
          /* Shown with room for both: the sections beside the document, one part to
             two, the document following the window. */
          @container (min-width: 56rem) {
            .split[data-shown] {
              grid-template-columns: minmax(0, 1fr) minmax(0, 2fr);
            }
            .split[data-shown] .document {
              position: sticky;
              top: var(--ash-admin-document-pane-top, 0px);
              height: var(
                --ash-admin-document-pane-height,
                calc(100vh - var(--ash-admin-document-pane-top, 0px) - var(--am-space-l))
              );
            }
          }
        `,
      ];

      createController() {
        return new A2uiController(this, apis.documentPane);
      }

      get props() {
        return this.controller?.props;
      }

      connectedCallback() {
        super.connectedCallback();
        this._listeners ||= {
          click: (event) => this.onLinkClick(event),
          // 3.8: a value and its region, linked both ways.
          pointerover: (event) => this.onPointerOver(event),
          pointerout: (event) => this.onPointerOut(event),
          focusin: (event) => this.onFocusIn(event),
          focusout: () => this.endLink("focus"),
          [REGION_ACTIVATE_EVENT]: (event) => this.onRegionActivate(event),
        };
        for (const [type, listener] of Object.entries(this._listeners)) this.addEventListener(type, listener);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        for (const [type, listener] of Object.entries(this._listeners || {})) this.removeEventListener(type, listener);
        this.stopFlash();
      }

      willUpdate(changed) {
        super.willUpdate(changed);
        applyWeight(this, this.props);
      }

      hasDocument() {
        const document = this.props?.document;
        return Boolean(document && typeof document === "object" && typeof document.src === "string" && document.src);
      }

      shown() {
        return this.props?.shown === true && this.hasDocument();
      }

      /** Shows or hides the pane: at once here, then the action. */
      setShown(shown) {
        write(this, "shown", shown);
        send(this, this.props?.toggleAction, {shown});
      }

      // A review's page tag (or any link to a region): open the pane there.
      onLinkClick(event) {
        if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        const prefix = this.props?.regionHref;
        if (!prefix || !this.hasDocument()) return;
        const link = event.composedPath().find((node) => node instanceof HTMLAnchorElement || node?.localName === "a");
        const id = regionFromHref(link?.getAttribute?.("href"), prefix);
        if (!id) return;
        event.preventDefault();
        this.openAt(id);
      }

      /** Opens the pane (if hidden) at region `id`. */
      openAt(id) {
        if (!this.shown()) this.setShown(true);
        write(this, "selected", id);
        send(this, {name: "document_region", context: {pane: this.props?.pane}}, {regionId: id});
        this.updateComplete.then(() => this.viewer()?.reveal?.(id));
      }

      viewer() {
        return this.renderRoot.querySelector("[data-role='document']")?.firstElementChild ?? null;
      }

      // ── 3.8: a value and its region, linked both ways ────────────────────

      /**
       * Whether the document sits beside the sections (not stacked under
       * them in a narrow pane): hover and focus link a value to its region
       * only then. A swap that lays the pane out itself overrides it.
       */
      sideBySide() {
        const content = this.renderRoot.querySelector(".content");
        const document = this.renderRoot.querySelector("[data-role='document']");
        if (!content || !document) return false;
        const a = content.getBoundingClientRect();
        const b = document.getBoundingClientRect();
        return b.left >= a.right - 1 || b.right <= a.left + 1;
      }

      // What an event's path links to, while linking is on: {element, ids} or null.
      linkSource(event) {
        const prefix = this.props?.regionHref;
        if (!prefix || !this.shown() || !this.sideBySide()) return null;
        const viewer = this.viewer();
        if (!viewer) return null;
        return linkSourceOf(event.composedPath?.() || [], prefix, [viewer, this]);
      }

      onPointerOver(event) {
        if (event.pointerType === "touch") return;
        const source = this.linkSource(event);
        if (source) this.startLink(source, "pointer");
        else this.endLink("pointer");
      }

      onPointerOut(event) {
        // Moving to another element inside the pane: its pointerover decides.
        const to = event.relatedTarget;
        if (to && (to === this || this.contains(to))) return;
        this.endLink("pointer");
      }

      onFocusIn(event) {
        const source = this.linkSource(event);
        if (source) this.startLink(source, "focus");
      }

      startLink(source, by) {
        this._linkBy = by;
        this.viewer()?.link?.(source.ids);
      }

      // Ends a link made by `by` (pointer or focus); another one stays.
      endLink(by) {
        if (this._linkBy !== by) return;
        this._linkBy = null;
        this.viewer()?.unlink?.();
      }

      // A person activated a region: go to the value that cites it.
      onRegionActivate(event) {
        const {id, keyboard} = event.detail || {};
        if (typeof id !== "string" || !this.shown()) return;
        const source = this.findSource(id);
        if (source) this.goToSource(source, {focus: Boolean(keyboard)});
      }

      /**
       * The element drawing the value that cites region `id`: the first
       * found among the sections (through every shadow root) whose
       * REGION_ATTRIBUTE names it.
       */
      findSource(id) {
        const prefix = this.props?.regionHref;
        const content = this.renderRoot.querySelector(".content");
        if (!prefix || !content) return null;
        return findMarked(content, (element) => regionIdsOf(element.getAttribute(REGION_ATTRIBUTE), prefix).includes(id));
      }

      /**
       * Scrolls the page so `element` sits a third of the way down the
       * window (below the sticky line, `--ash-admin-nav-line`), flashes it
       * for FLASH_MS and, from the keyboard, moves focus to it.
       */
      goToSource(element, {focus = false} = {}) {
        const line = parseFloat(getComputedStyle(this).getPropertyValue("--ash-admin-nav-line")) || 0;
        element.style.scrollMarginTop = `${Math.round(Math.max(line, window.innerHeight / 3))}px`;
        const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
        element.scrollIntoView({block: "start", behavior: reduce ? "auto" : "smooth"});
        if (focus) {
          if (element.tabIndex < 0 && !element.hasAttribute("tabindex")) element.setAttribute("tabindex", "-1");
          element.focus({preventScroll: true});
        }
        this.flash(element);
      }

      flash(element) {
        this.stopFlash();
        this._flashed = element;
        element.setAttribute("data-a2ui-flashed", "");
        this.flashSource(element, true);
        this._unflash = setTimeout(() => this.stopFlash(), FLASH_MS);
      }

      stopFlash() {
        clearTimeout(this._unflash);
        const element = this._flashed;
        this._flashed = null;
        if (!element) return;
        element.removeAttribute("data-a2ui-flashed");
        this.flashSource(element, false);
      }

      /**
       * Draws (or clears) a value's flash. The stock one is the section
       * nav's outline (`--ash-admin-nav-outline`); a swap draws its own.
       */
      flashSource(element, on) {
        Object.assign(element.style, {
          outline: on ? "2px solid var(--ash-admin-nav-outline, var(--am-primary))" : "",
          outlineOffset: on ? "2px" : "",
          borderRadius: on ? "var(--am-radius-m)" : "",
        });
      }

      /** The switch. A swap draws its own; `onChange(checked)` shows or hides. */
      renderToggle({label, description, checked, onChange}) {
        return html`<div class="toggle" data-role="toggle">
          <label class="switch">
            <input type="checkbox" role="switch" .checked=${checked} @change=${(event) => onChange(event.target.checked)} />
            <span>${label}</span>
          </label>
          ${description ? html`<span class="toggle-description">${description}</span>` : nothing}
        </div>`;
      }

      render() {
        const props = this.props;
        if (!props) return nothing;
        const shown = this.shown();
        return html`<div class="pane" data-pane=${props.pane || nothing}>
          ${this.hasDocument()
            ? this.renderToggle({
                label: typeof props.label === "string" ? props.label : "",
                description: typeof props.description === "string" ? props.description : "",
                checked: shown,
                onChange: (checked) => this.setShown(Boolean(checked)),
              })
            : nothing}
          <div class="split" ?data-shown=${shown}>
            <div class="content">${childRefs(props.children).map((ref) => this.renderNode(ref))}</div>
            ${shown ? html`<div class="document" data-role="document">${this.renderNode(props.viewer)}</div>` : nothing}
          </div>
        </div>`;
      }
    }

    customElements.define(tag, AshAdminDocumentPane);
  }
}

// The first element under `root`, through every shadow root, that `test` accepts.
function findMarked(root, test) {
  for (const element of root.querySelectorAll?.(`[${REGION_ATTRIBUTE}]`) || []) {
    if (test(element)) return element;
  }
  for (const element of root.querySelectorAll?.("*") || []) {
    const found = element.shadowRoot && findMarked(element.shadowRoot, test);
    if (found) return found;
  }
  return null;
}
