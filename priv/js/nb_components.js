/**
 * NB — the neobrutalist host-facing component layer ("Lane D").
 *
 * Where `ash_admin_catalog.js` supplies semantic components for surfaces on
 * the A2UI message wire, this file supplies the primitives a HOST renders
 * directly: the canvas/console overlays, the day view, operator chrome.
 * They are dependency-free custom elements (the `ash_a2ui_hook.js`
 * discipline: this file ships without imports; the host bundles nothing to
 * use it) styled entirely by CSS custom properties, so a host that themes
 * the `--a2ui-*` layer themes these too.
 *
 *     <script type="module">
 *       import {defineNbComponents} from "ash_a2ui/priv/js/nb_components.js";
 *       defineNbComponents();
 *     </script>
 *
 * `defineNbComponents()` is idempotent per tag (the admin-catalog rule), so
 * multiple bundles can call it. Every element dispatches `composed: true`
 * events (`nb-*`), which cross shadow boundaries and reach LiveView hooks
 * and `phx-window-keydown`-style listeners on the document.
 *
 * ## Components
 *
 *   nb-item        list-item card: sticker status dot, label, meta, hover lift
 *   nb-menu        trigger + popup menu (arrows/escape/home/end, outside
 *                  click, aria-expanded; instant open under reduced motion)
 *   nb-menu-item   a menu entry (label, value, disabled, selected)
 *   nb-sheet       side panel: role=dialog, focus trap, Escape/backdrop close
 *   nb-tabs        tab strip (roving tabindex, arrow keys) + nb-tab panels
 *   nb-tab         one tab panel (label, active); user DOM stays put
 *   nb-table       grid frame, sticky header, slot-driven columns
 *   nb-column      column header metadata (label, align, width)
 *   nb-row         one row (grid over the shared column template)
 *   nb-cell        one cell (alignment follows its column)
 *   nb-calendar    month (or week) grid: today ring, has-items dot,
 *                  selected lift, full date-grid keyboard pattern; emits
 *                  nb-select
 *   nb-scroller    stick-to-bottom message pane (MutationObserver), detaches
 *                  when scrolled up, "jump to latest" pill re-pins
 *   nb-pagination  windowed page chips, prev/next, aria-current="page"
 *
 * ## Design tokens
 *
 * Every component renders inside shadow DOM; only custom properties cross.
 * Each shadow stylesheet declares a private `--n-*` layer on `:host` that
 * reads, in order (the `ash_admin_tokens.js` three-layer architecture):
 *
 *     var(--nb-<token>, var(--a2ui-<a2ui-token>, <literal default>))
 *
 *   1. `--nb-*` — the public NB surface (hosts override these; the full
 *      list ships in `nb_motion.css`, which also exposes the motion half);
 *   2. `--a2ui-*` — the shared a2ui vocabulary, so importing
 *      `ash_a2ui_theme.css` (or bridging it to a house system, as
 *      clinic-demo bridges it to its Tailwind token sheet) themes the NB
 *      layer along with every surface;
 *   3. literal defaults — the neobrutalist "blue" scheme: pale-blue page,
 *      white surfaces, 2px black borders, hard offset shadows, black ink
 *      on every fill.
 *
 * The defaults mirror the framework chrome that landed in ash_bpmn's
 * `ash_bpmn.css` (2px border, 2px/4px/1px shadow rest/lift/press) so the
 * NB layer and the BPMN chrome read as one system.
 *
 * ## Motion
 *
 * Motion vocabulary is M3E translated into hard-shadow terms — travel and
 * shadow, never soft fades. Easing/duration tokens are read from
 * `nb_motion.css`'s public names with the same three-layer fallbacks, so
 * components work standalone (literals) or token-driven (host sheet).
 * Every animated piece is guarded by `prefers-reduced-motion: reduce`:
 * the state change lands instantly, only the travel is dropped.
 *
 * ## Zero jank
 *
 * These components never wait for a server: menus/sheets/tabs/calendars
 * change state synchronously and emit events for the host to sync back;
 * the scroller re-pins in a rAF; focus is managed client-side (sheet trap,
 * menu/trigger return, tab roving). See usage-rules/zero-jank.md — inside
 * shadow DOM the feedback has to be client-side by construction.
 */

/* ---------------------------------------------------------------------------
 * Shared stylesheets (plain strings — no framework, no imports).
 * ------------------------------------------------------------------------- */

/** The three-layer token sheet declared on every :host. */
const TOKENS_CSS = `
  :host {
    /* Ink + lines */
    --n-border: var(--nb-border, var(--a2ui-color-border, #141414));
    --n-border-width: var(--nb-border-width, var(--a2ui-border-width, 2px));
    /* Surfaces */
    --n-surface: var(--nb-surface, var(--a2ui-color-surface, #ffffff));
    --n-surface-sunken: var(--nb-surface-sunken, var(--a2ui-color-background, #d6ebfc));
    --n-text: var(--nb-text, var(--a2ui-color-on-surface, #141414));
    --n-text-muted: var(--nb-text-muted, #3a3a3a);
    /* Accent + the vivid secondaries (no --a2ui equivalents exist; the
     * literals are the clinic palette — every fill carries black ink). */
    --n-primary: var(--nb-primary, var(--a2ui-color-primary, #3b82f6));
    --n-on-primary: var(--nb-on-primary, var(--a2ui-color-on-primary, #141414));
    --n-yellow: var(--nb-yellow, #ffd83d);
    --n-pink: var(--nb-pink, #ff9ec9);
    --n-green: var(--nb-green, #4fd07a);
    --n-orange: var(--nb-orange, #ffa94d);
    --n-violet: var(--nb-violet, #b78aff);
    --n-cyan: var(--nb-cyan, #38c8e8);
    --n-red: var(--nb-red, #ff5c64);
    --n-neutral: var(--nb-neutral, #e2e6ec);
    /* Shape */
    --n-radius: var(--nb-radius, var(--a2ui-border-radius, 5px));
    /* The hard-shadow trio (rest / hover-lift / active-press). */
    --n-shadow: var(--nb-shadow, 2px 2px 0 0 var(--n-border));
    --n-shadow-lift: var(--nb-shadow-lift, 4px 4px 0 0 var(--n-border));
    --n-shadow-press: var(--nb-shadow-press, 1px 1px 0 0 var(--n-border));
    /* Dialog scrim */
    --n-overlay: var(--nb-overlay, var(--a2ui-modal-backdrop-bg, rgba(0, 0, 0, 0.8)));
    /* Type */
    --n-weight-medium: var(--nb-font-weight-medium, 500);
    --n-weight-bold: var(--nb-font-weight-bold, 700);
    --n-font-size-s: var(--nb-font-size-s, 0.8125rem);
    --n-font-size-m: var(--nb-font-size-m, 0.875rem);
    /* Motion (M3E translated; see nb_motion.css). */
    --n-ease-emphasized: var(--nb-ease-emphasized, cubic-bezier(0.2, 0, 0, 1));
    --n-ease-decel: var(--nb-ease-emphasized-decel, cubic-bezier(0.05, 0.7, 0.1, 1));
    --n-dur-short: var(--nb-dur-short, 120ms);
    --n-dur-medium: var(--nb-dur-medium, 250ms);

    box-sizing: border-box;
    font-family: inherit;
    font-size: var(--n-font-size-m);
    line-height: 1.5;
    color: var(--n-text);
  }
  *,
  *::before,
  *::after {
    box-sizing: border-box;
  }
`;

/**
 * The interaction vocabulary: every pressable thing lifts on hover (the
 * element rises one pixel, the shadow grows to 4px) and presses on
 * :active (sinks, shadow collapses to 1px) — the ripple substitute.
 * Focus is always a hard black ring with a white offset, never a soft
 * glow. Reduced motion drops the travel, never the state.
 */
const BASE_CSS = `
  .nb-btn {
    font: inherit;
    font-weight: var(--n-weight-medium);
    color: var(--n-text);
    background: var(--n-surface);
    border: var(--n-border-width) solid var(--n-border);
    border-radius: var(--n-radius);
    box-shadow: var(--n-shadow);
    cursor: pointer;
    transition:
      transform var(--n-dur-short) var(--n-ease-emphasized),
      box-shadow var(--n-dur-short) var(--n-ease-emphasized);
  }
  .nb-btn:hover:not(:disabled) {
    transform: translate(-1px, -1px);
    box-shadow: var(--n-shadow-lift);
  }
  .nb-btn:active:not(:disabled) {
    transform: translate(1px, 1px);
    box-shadow: var(--n-shadow-press);
  }
  .nb-btn:disabled {
    opacity: 0.5;
    cursor: default;
  }
  .nb-btn:focus-visible,
  :host(:focus-visible) {
    outline: var(--n-border-width) solid var(--n-border);
    outline-offset: 2px;
  }
  @media (prefers-reduced-motion: reduce) {
    .nb-btn,
    .nb-btn:hover:not(:disabled),
    .nb-btn:active:not(:disabled) {
      transition: none;
      transform: none;
    }
  }
`;

/** Status vocabulary → fills, shared by nb-item dots and menu checks. */
const STATUS_FILLS = {
  booked: "var(--n-primary)",
  low: "var(--n-green)",
  medium: "var(--n-yellow)",
  high: "var(--n-orange)",
  emergency: "var(--n-red)",
  visit: "var(--n-violet)",
  discharged: "var(--n-cyan)",
  closed: "var(--n-neutral)",
};

const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/* ---------------------------------------------------------------------------
 * Base element.
 * ------------------------------------------------------------------------- */

class NbElement extends HTMLElement {
  constructor() {
    super();
    // Plain open shadow. No delegatesFocus: when a component's shadow has
    // no focusable inside (nb-item), delegated focus silently lands on
    // <body>, which orphans every host-level key handler — observed in
    // Chrome while probing. Components move focus explicitly instead.
    const root = this.attachShadow({mode: "open"});
    this.root = root;
  }

  /** Sets the shadow DOM to `tokens + base + css + body`. */
  render(css, body) {
    this.root.innerHTML = `<style>${TOKENS_CSS}${BASE_CSS}${css}</style>${body}`;
  }

  /** A composed, bubbling event — crosses shadow boundaries by design. */
  emit(type, detail = {}) {
    this.dispatchEvent(new CustomEvent(type, {bubbles: true, composed: true, detail}));
  }

  bool(value) {
    return value !== null && value !== "false";
  }
}

/* ---------------------------------------------------------------------------
 * nb-item — the list-item card.
 * ------------------------------------------------------------------------- */

class NbItem extends NbElement {
  static get observedAttributes() {
    return ["status", "label", "meta", "selectable"];
  }

  attributeChangedCallback() {
    this.paint();
  }

  connectedCallback() {
    // The host is programmatically focusable (not a tab stop) so hosts and
    // probes can drive the menu from the element itself; the real tab stop
    // is the trigger button in the shadow.
    this.tabIndex = -1;
    this.paint();
    this.addEventListener("keydown", this);
  }

  disconnectedCallback() {
    this.removeEventListener("keydown", this);
    this.removeEventListener("click", this);
  }

  handleEvent(event) {
    if (!this.bool(this.getAttribute("selectable"))) return;
    if (event.type === "click" || (event.type === "keydown" && (event.key === "Enter" || event.key === " "))) {
      if (event.type === "keydown") event.preventDefault();
      this.emit("nb-select", {status: this.getAttribute("status") || "", label: this.getAttribute("label") || ""});
    }
  }

  paint() {
    const status = this.getAttribute("status") || "";
    const selectable = this.bool(this.getAttribute("selectable"));
    const fill = STATUS_FILLS[status] || "var(--n-neutral)";
    this.render(
      `
      :host {
        display: block;
      }
      .item {
        display: flex;
        align-items: flex-start;
        gap: 0.75rem;
        padding: 0.625rem 0.875rem;
        background: var(--n-surface);
        border: var(--n-border-width) solid var(--n-border);
        border-radius: var(--n-radius);
        box-shadow: var(--n-shadow);
        transition:
          transform var(--n-dur-short) var(--n-ease-emphasized),
          box-shadow var(--n-dur-short) var(--n-ease-emphasized);
      }
      :host([selectable]) .item {
        cursor: pointer;
      }
      .item:hover {
        transform: translate(-1px, -1px);
        box-shadow: var(--n-shadow-lift);
      }
      :host([selectable]) .item:active {
        transform: translate(1px, 1px);
        box-shadow: var(--n-shadow-press);
      }
      /* The sticker dot: a small tilted color chip — the status reads
       * before the label does, the tilt keeps it from reading as a bullet. */
      .dot {
        flex: none;
        width: 0.875rem;
        height: 0.875rem;
        margin-top: 0.1875rem;
        background: ${fill};
        border: var(--n-border-width) solid var(--n-border);
        border-radius: 3px;
        transform: rotate(-8deg);
      }
      .label {
        font-weight: var(--n-weight-bold);
      }
      .meta {
        color: var(--n-text-muted);
        font-size: var(--n-font-size-s);
      }
      .action {
        margin-left: auto;
      }
      @media (prefers-reduced-motion: reduce) {
        .item,
        .item:hover,
        :host([selectable]) .item:active {
          transition: none;
          transform: none;
        }
      }
      `,
      `
      <div class="item" part="item">
        <span class="dot" part="dot" aria-hidden="true"></span>
        <div class="body" part="body">
          <div class="label" part="label"><slot name="label">${escapeHtml(this.getAttribute("label") || "")}</slot></div>
          <div class="meta" part="meta"><slot name="meta">${escapeHtml(this.getAttribute("meta") || "")}</slot></div>
        </div>
        <div class="action"><slot name="action"></slot></div>
      </div>
      `,
    );
    if (selectable) {
      this.setAttribute("role", "button");
      this.setAttribute("tabindex", "0");
    } else {
      this.removeAttribute("role");
      this.removeAttribute("tabindex");
    }
  }
}

/* ---------------------------------------------------------------------------
 * nb-menu / nb-menu-item — trigger + popup menu.
 *
 * Menu items live in the light DOM as <nb-menu-item> children so hosts can
 * render them server-side (LiveView loops, streams); the popup re-derives
 * from them on every open. The open is instant (state flips in the same
 * tick); the slide-in is 120ms of travel only, dropped under reduced
 * motion. No overlay: the popup is absolutely positioned, outside
 * pointerdown closes it, and focus never leaves the component.
 * ------------------------------------------------------------------------- */

class NbMenuItem extends HTMLElement {
  static get observedAttributes() {
    return ["label", "value", "selected", "disabled"];
  }
  // Pure light-DOM metadata; nb-menu renders the real (shadow) buttons.
}

class NbMenu extends NbElement {
  static get observedAttributes() {
    return ["label", "align"];
  }

  constructor() {
    super();
    this.onDocPointerDown = (event) => {
      if (!this.contains(event.target) && !this.root.contains(event.composedPath()[0])) this.close();
    };
  }

  connectedCallback() {
    this.paint();
    this.addEventListener("keydown", this);
  }

  disconnectedCallback() {
    this.removeEventListener("keydown", this);
    this.close();
  }

  get popup() {
    return this.root.querySelector(".popup");
  }

  attributeChangedCallback() {
    if (this.root) this.paint();
  }

  /**
   * The trigger button is the menu's focus home. Chrome makes a shadow
   * host with a focusable inside un-focusable as itself (observed while
   * probing: host.focus() with tabIndex=-1 is a silent no-op), so route
   * programmatic focus inward — the standard composite-component pattern —
   * and keyboard events bubble from the trigger to the host handler.
   */
  focus(options) {
    this.trigger?.focus(options);
  }

  itemNodes() {
    return [...this.children].filter((child) => child.tagName === "NB-MENU-ITEM");
  }

  paint() {
    const align = this.getAttribute("align") === "end" ? "right" : "left";
    this.render(
      `
      :host {
        position: relative;
        display: inline-block;
      }
      .trigger-caret {
        margin-left: 0.375rem;
        font-size: 0.75em;
      }
      .popup {
        position: absolute;
        top: calc(100% + 0.375rem);
        ${align}: 0;
        z-index: 30;
        min-width: 12rem;
        padding: 0.25rem;
        background: var(--n-surface);
        border: var(--n-border-width) solid var(--n-border);
        border-radius: var(--n-radius);
        box-shadow: var(--n-shadow-lift);
      }
      .popup[data-open="false"] {
        display: none;
      }
      .popup[data-open="true"] {
        /* Container transform, M3E move #1: the panel arrives from its
         * trigger along one axis while the shadow grows into place. */
        animation: nb-menu-in var(--n-dur-short) var(--n-ease-decel);
      }
      @keyframes nb-menu-in {
        from {
          transform: translateY(-4px);
          box-shadow: var(--n-shadow);
        }
        to {
          transform: translateY(0);
          box-shadow: var(--n-shadow-lift);
        }
      }
      .mi {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        width: 100%;
        padding: 0.4375rem 0.625rem;
        font: inherit;
        font-weight: var(--n-weight-medium);
        text-align: left;
        color: var(--n-text);
        background: none;
        border: none;
        border-radius: calc(var(--n-radius) - 2px);
        cursor: pointer;
      }
      .mi:hover:not([disabled]),
      .mi:focus-visible {
        background: var(--n-surface-sunken);
        outline: none;
      }
      .mi[disabled] {
        opacity: 0.5;
        cursor: default;
      }
      .mi-check {
        width: 0.625rem;
        height: 0.625rem;
        flex: none;
        background: var(--n-primary);
        border: var(--n-border-width) solid var(--n-border);
        border-radius: 2px;
        transform: rotate(-8deg);
      }
      @media (prefers-reduced-motion: reduce) {
        .popup[data-open="true"] {
          animation: none;
        }
      }
      `,
      `
      <button type="button" class="nb-btn trigger" part="trigger" aria-haspopup="menu" aria-expanded="false">
        <slot name="trigger">${escapeHtml(this.getAttribute("label") || "Menu")}</slot
        ><span class="trigger-caret" aria-hidden="true">▾</span>
      </button>
      <div class="popup" role="menu" part="popup" data-open="false"></div>
      `,
    );
    this.trigger = this.root.querySelector(".trigger");
    this.trigger.addEventListener("click", () => (this.isOpen() ? this.close() : this.open()));
  }

  isOpen() {
    return this.popup?.dataset.open === "true";
  }

  open({focus = 0} = {}) {
    const popup = this.popup;
    if (!popup) return;
    // Rebuild from light DOM on every open — host-rendered items (a
    // LiveView loop) are picked up without any observer.
    const items = this.itemNodes();
    popup.innerHTML = items
      .map((item, index) => {
        const label = escapeHtml(item.getAttribute("label") || "");
        const value = escapeHtml(item.getAttribute("value") || label);
        const disabled = item.hasAttribute("disabled") ? " disabled" : "";
        const selected = item.hasAttribute("selected") ? ` aria-checked="true"` : "";
        const role = item.hasAttribute("selected") || item.hasAttribute("checkable") ? "menuitemcheckbox" : "menuitem";
        const check = item.hasAttribute("selected") ? `<span class="mi-check" aria-hidden="true"></span>` : "";
        return `<button type="button" role="${role}" class="mi" data-index="${index}" data-value="${value}"${disabled}${selected}>${check}<span>${label}</span></button>`;
      })
      .join("");
    popup.querySelectorAll(".mi").forEach((button) => {
      button.addEventListener("click", () => {
        if (button.disabled) return;
        this.emit("nb-select", {value: button.dataset.value || "", index: Number(button.dataset.index)});
        this.close();
      });
    });

    popup.dataset.open = "true";
    this.trigger.setAttribute("aria-expanded", "true");
    document.addEventListener("pointerdown", this.onDocPointerDown, true);

    const focusables = [...popup.querySelectorAll(".mi:not([disabled])")];
    const target = focusables[Math.min(Math.max(focus, 0), focusables.length - 1)];
    if (target) target.focus();
  }

  close({refocus = true} = {}) {
    const popup = this.popup;
    if (!popup || popup.dataset.open !== "true") return;
    popup.dataset.open = "false";
    popup.innerHTML = "";
    this.trigger.setAttribute("aria-expanded", "false");
    document.removeEventListener("pointerdown", this.onDocPointerDown, true);
    if (refocus) this.trigger.focus();
  }

  handleEvent(event) {
    if (event.key === "Escape" && this.isOpen()) {
      event.stopPropagation();
      this.close();
      return;
    }
    if (!this.isOpen()) {
      if (event.key === "ArrowDown" || event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        this.open({focus: event.key === "ArrowDown" ? 0 : -1});
      }
      return;
    }
    const items = [...this.popup.querySelectorAll(".mi:not([disabled])")];
    const current = items.indexOf(this.root.activeElement);
    const move = (index) => {
      event.preventDefault();
      items[(index + items.length) % items.length]?.focus();
    };
    switch (event.key) {
      case "ArrowDown":
        move(current + 1);
        break;
      case "ArrowUp":
        move(current - 1);
        break;
      case "Home":
        move(0);
        break;
      case "End":
        move(items.length - 1);
        break;
      case "Tab":
        this.close({refocus: false});
        break;
    }
  }
}

/* ---------------------------------------------------------------------------
 * nb-sheet — the canvas/console side panel.
 *
 * role=dialog + aria-modal, a true focus trap (Tab cycles inside shadow and
 * slotted content alike), Escape and backdrop press both request close.
 * The host can cancel by calling preventDefault() on nb-close — a sheet
 * with unsaved form state stays open. State flips client-side, instantly;
 * the slide is travel only, dropped under reduced motion.
 * ------------------------------------------------------------------------- */

class NbSheet extends NbElement {
  static get observedAttributes() {
    return ["open", "side", "label"];
  }

  constructor() {
    super();
    this.onKeydown = (event) => this.handleEvent(event);
  }

  connectedCallback() {
    this.paint();
  }

  attributeChangedCallback(name) {
    if (name === "open" && this.root) {
      const open = this.bool(this.getAttribute("open"));
      if (open) this.trapStart();
      else this.trapStop();
    }
    if (this.root) this.paint();
  }

  disconnectedCallback() {
    this.trapStop();
  }

  paint() {
    const side = this.getAttribute("side") || "right";
    const offscreen = side === "bottom" ? "translateY(16px)" : `translateX(${side === "left" ? "-16px" : "16px"})`;
    const geometry =
      side === "bottom"
        ? "left: 0; right: 0; bottom: 0; max-height: 70vh; border-radius: var(--n-radius) var(--n-radius) 0 0;"
        : side === "left"
          ? "top: 0; bottom: 0; left: 0; width: min(26rem, 92vw); border-radius: 0 var(--n-radius) var(--n-radius) 0;"
          : "top: 0; bottom: 0; right: 0; width: min(26rem, 92vw); border-radius: var(--n-radius) 0 0 var(--n-radius);";
    this.render(
      `
      :host {
        position: fixed;
        inset: 0;
        z-index: 40;
        display: none;
      }
      :host([open]) {
        display: block;
      }
      .backdrop {
        position: absolute;
        inset: 0;
        background: var(--n-overlay);
        animation: nb-backdrop-in var(--n-dur-short) ease-out;
      }
      @keyframes nb-backdrop-in {
        from { opacity: 0; }
        to { opacity: 1; }
      }
      .sheet {
        position: absolute;
        display: flex;
        flex-direction: column;
        background: var(--n-surface);
        color: var(--n-text);
        border: var(--n-border-width) solid var(--n-border);
        box-shadow: var(--n-shadow-lift);
        ${geometry}
        /* Container transform, M3E move #1: the sheet arrives from its edge
         * with its shadow already grown — the panel reads as slid INTO the
         * page, not faded onto it. */
        animation: nb-sheet-in var(--n-dur-medium) var(--n-ease-decel);
      }
      @keyframes nb-sheet-in {
        from { transform: ${offscreen}; box-shadow: var(--n-shadow); }
        to { transform: translate(0, 0); box-shadow: var(--n-shadow-lift); }
      }
      .bar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
        padding: 0.75rem 1rem;
        border-bottom: var(--n-border-width) solid var(--n-border);
        background: var(--n-surface-sunken);
      }
      .title {
        font-weight: var(--n-weight-bold);
        font-size: 1rem;
      }
      .content {
        flex: 1;
        overflow: auto;
        padding: 1rem;
      }
      @media (prefers-reduced-motion: reduce) {
        .sheet,
        .backdrop {
          animation: none;
        }
      }
      `,
      `
      <div class="backdrop" part="backdrop"></div>
      <div class="sheet" role="dialog" aria-modal="true" aria-label="${escapeHtml(this.getAttribute("label") || "Panel")}" part="sheet">
        <header class="bar">
          <span class="title" part="title"><slot name="header">${escapeHtml(this.getAttribute("label") || "")}</slot></span>
          <button type="button" class="nb-btn close" aria-label="Close panel">×</button>
        </header>
        <div class="content" part="content"><slot></slot></div>
      </div>
      `,
    );

    this.root.querySelector(".backdrop").addEventListener("pointerdown", () => this.requestClose());
    this.root.querySelector(".close").addEventListener("click", () => this.requestClose());
  }

  requestClose() {
    // Cancelable: a host with unsaved form state calls preventDefault()
    // and the sheet stays open — the component never overrides the host.
    const event = new CustomEvent("nb-close", {
      bubbles: true,
      composed: true,
      cancelable: true,
      detail: {},
    });
    this.dispatchEvent(event);
    if (event.defaultPrevented) return;
    this.open = false;
  }

  trapStart() {
    if (this.__trapped) return;
    this.__trapped = true;
    this.__previouslyFocused = document.activeElement;
    document.addEventListener("keydown", this.onKeydown, true);
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    this.__restoreOverflow = () => {
      document.body.style.overflow = previousOverflow;
    };
    requestAnimationFrame(() => this.focusFirst());
  }

  trapStop() {
    if (!this.__trapped) return;
    this.__trapped = false;
    document.removeEventListener("keydown", this.onKeydown, true);
    if (this.__restoreOverflow) this.__restoreOverflow();
    const restore = this.__previouslyFocused;
    if (restore && typeof restore.focus === "function") restore.focus();
    this.__previouslyFocused = null;
  }

  focusFirst() {
    this.focusables()[0]?.focus();
  }

  focusables() {
    const sheet = this.root.querySelector(".sheet");
    if (!sheet) return [];
    const selector =
      "button:not([disabled]), [href], input:not([type=hidden]):not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])";
    const items = [...sheet.querySelectorAll(selector)];
    // Slotted content: focusables may be assigned elements themselves or
    // nested inside them (the common case — inputs inside layout markup).
    for (const slotted of this.root.querySelector(".content slot").assignedElements()) {
      if (slotted.matches?.(selector)) items.push(slotted);
      if (slotted.querySelectorAll) items.push(...slotted.querySelectorAll(selector));
    }
    return items.filter((element) => element.offsetParent !== null || element === document.activeElement);
  }

  handleEvent(event) {
    if (!this.bool(this.getAttribute("open"))) return;
    if (event.key === "Escape") {
      event.stopPropagation();
      this.requestClose();
      return;
    }
    if (event.key === "Tab") {
      const items = this.focusables();
      if (items.length === 0) return;
      const first = items[0];
      const last = items[items.length - 1];
      const index = items.indexOf(document.activeElement);
      if (event.shiftKey && index <= 0) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (index === -1 || index === items.length - 1)) {
        event.preventDefault();
        first.focus();
      }
    }
  }

  set open(value) {
    if (value) this.setAttribute("open", "");
    else this.removeAttribute("open");
  }
}

/* ---------------------------------------------------------------------------
 * nb-tabs / nb-tab — tab strip with panels.
 *
 * Panels live inside their <nb-tab> children (each renders its own shadow
 * slot), so host DOM — LiveView streams included — never moves. The strip
 * follows the WAI-ARIA tabs pattern: roving tabindex, arrow/Home/End
 * navigation, selection follows focus, aria-selected + aria-controls wired
 * both ways. Panel changes animate the shared-axis X move (M3E move #2):
 * content leaves toward one side, enters from the other — travel, not
 * fades.
 * ------------------------------------------------------------------------- */

class NbTab extends NbElement {
  static get observedAttributes() {
    return ["label", "active"];
  }

  attributeChangedCallback() {
    this.paint();
  }

  connectedCallback() {
    this.paint();
  }

  paint() {
    const active = this.bool(this.getAttribute("active"));
    this.render(
      `
      :host {
        display: ${active ? "block" : "none"};
      }
      .panel {
        /* Shared axis X: entering panels arrive from the direction of
         * travel. The direction class is applied by nb-tabs on switch. */
        animation: nb-panel-in var(--n-dur-short) var(--n-ease-decel);
      }
      .panel[data-dir="back"] {
        animation-name: nb-panel-in-back;
      }
      @keyframes nb-panel-in {
        from { transform: translateX(12px); }
        to { transform: translateX(0); }
      }
      @keyframes nb-panel-in-back {
        from { transform: translateX(-12px); }
        to { transform: translateX(0); }
      }
      @media (prefers-reduced-motion: reduce) {
        .panel {
          animation: none;
        }
      }
      `,
      // aria-label derives from this tab's own label attribute: a value,
      // not an id reference — and it survives every re-render (an id ref
      // into the parent's shadow tree would not resolve from light DOM,
      // and labeling from nb-tabs was wiped by the queued attribute
      // callbacks of this element's own upgrade).
      `<div class="panel" part="panel" role="tabpanel" aria-label="${escapeHtml(
        this.getAttribute("label") || "Tab",
      )}"><slot></slot></div>`,
    );
  }
}

class NbTabs extends NbElement {
  static get observedAttributes() {
    return ["label"];
  }

  connectedCallback() {
    this.paint();
    this.__observer = new MutationObserver(() => this.paint());
    this.__observer.observe(this, {childList: true, subtree: false, attributes: true, attributeFilter: ["label", "active"]});
  }

  disconnectedCallback() {
    this.__observer?.disconnect();
  }

  tabs() {
    const tabs = [...this.children].filter((child) => child.tagName === "NB-TAB");
    // Children can be queried before their own definition runs (parser
    // order): force synchronous upgrade so tab.root exists downstream.
    for (const tab of tabs) customElements.upgrade(tab);
    return tabs;
  }

  activeIndex() {
    const tabs = this.tabs();
    const index = tabs.findIndex((tab) => this.bool(tab.getAttribute("active")));
    return index === -1 ? 0 : index;
  }

  paint() {
    const tabs = this.tabs();
    const active = this.activeIndex();
    tabs.forEach((tab, index) => {
      if (index === active) tab.setAttribute("active", "");
      else tab.removeAttribute("active");
      if (!tab.id) tab.id = `nb-tab-panel-${uid(this, index)}`;
    });
    this.render(
      `
      :host {
        display: block;
      }
      .strip {
        display: flex;
        gap: 0.375rem;
        flex-wrap: wrap;
        padding: 0.25rem;
        background: var(--n-surface-sunken);
        border: var(--n-border-width) solid var(--n-border);
        border-radius: var(--n-radius);
        box-shadow: var(--n-shadow);
        width: fit-content;
        max-width: 100%;
      }
      .tab {
        font: inherit;
        font-weight: var(--n-weight-medium);
        padding: 0.3125rem 0.75rem;
        color: var(--n-text);
        background: none;
        border: none;
        border-radius: calc(var(--n-radius) - 2px);
        cursor: pointer;
      }
      .tab:hover {
        background: var(--n-surface);
      }
      .tab[aria-selected="true"] {
        background: var(--n-primary);
        color: var(--n-on-primary);
        font-weight: var(--n-weight-bold);
        box-shadow: var(--n-shadow);
      }
      .tab:focus-visible {
        outline: var(--n-border-width) solid var(--n-border);
        outline-offset: 2px;
      }
      .panels {
        margin-top: 0.75rem;
      }
      `,
      `
      <div class="strip" role="tablist" part="strip" aria-label="${escapeHtml(this.getAttribute("label") || "Tabs")}">
        ${tabs
          .map((tab, index) => {
            const selected = index === active;
            const id = `${tab.id}-tab`;
            return `<button type="button" role="tab" class="tab" id="${id}" data-index="${index}"
              aria-selected="${selected}" aria-controls="${tab.id}" tabindex="${selected ? "0" : "-1"}"
            >${escapeHtml(tab.getAttribute("label") || `Tab ${index + 1}`)}</button>`;
          })
          .join("")}
      </div>
      <div class="panels"><slot></slot></div>
      `,
    );
    this.root.querySelectorAll(".tab").forEach((button) => {
      button.addEventListener("click", () => this.activate(Number(button.dataset.index), {focus: true}));
      button.addEventListener("keydown", (event) => this.onStripKeydown(event, Number(button.dataset.index)));
    });
  }

  onStripKeydown(event, index) {
    const tabs = this.tabs();
    const last = tabs.length - 1;
    let target = null;
    if (event.key === "ArrowRight") target = (index + 1) % tabs.length;
    else if (event.key === "ArrowLeft") target = (index - 1 + tabs.length) % tabs.length;
    else if (event.key === "Home") target = 0;
    else if (event.key === "End") target = last;
    if (target === null) return;
    event.preventDefault();
    this.activate(target, {focus: true, direction: target > index ? "fwd" : "back"});
  }

  activate(index, {focus = false, direction = "fwd"} = {}) {
    const tabs = this.tabs();
    if (index < 0 || index >= tabs.length) return;
    const previous = this.activeIndex();
    tabs.forEach((tab, i) => {
      const panel = tab.root?.querySelector(".panel");
      if (i === index) {
        tab.setAttribute("active", "");
        if (panel) {
          panel.dataset.dir = index < previous || direction === "back" ? "back" : "fwd";
          // Restart the shared-axis animation on each activation.
          panel.style.animation = "none";
          void panel.offsetWidth;
          panel.style.animation = "";
        }
      } else {
        tab.removeAttribute("active");
      }
    });
    this.paint();
    const button = this.root.querySelector(`.tab[data-index="${index}"]`);
    if (button && focus) button.focus();
    this.emit("nb-change", {index, label: tabs[index].getAttribute("label") || ""});
  }
}

/* ---------------------------------------------------------------------------
 * nb-table / nb-column / nb-row / nb-cell — table frame with sticky header.
 *
 * Why custom row/cell elements instead of real <tr>/<td>: the HTML parser
 * DROPS table-section tags in a non-table context — `<nb-table><tr>` never
 * makes it into the DOM, server-rendered HEEx included (innerHTML parsing
 * applies the same rules). Custom elements are ordinary nodes to the
 * parser and to LiveView's patching alike, so `<nb-row><nb-cell>` is the
 * authoring and streaming surface. The frame is a role=grid (header cells
 * role=columnheader, rows role=row, cells role=gridcell — the table
 * semantics survive without table markup), laid out with a shared column
 * grid so header and rows cannot drift apart. The header rowgroup is
 * sticky (opaque fill — a sticky header that shows rows through it is a
 * classic tell); rows carry the hover tint and the press substitute.
 * ------------------------------------------------------------------------- */

class NbColumn extends HTMLElement {
  static get observedAttributes() {
    return ["label", "align", "width"];
  }
  // Light-DOM metadata consumed by nb-table.
}

/** A row: display grid over the table's shared column template. */
class NbRow extends HTMLElement {
  connectedCallback() {
    this.setAttribute("role", "row");
  }
}

/** A cell. Alignment follows its column (applied by nb-table on paint). */
class NbCell extends HTMLElement {
  connectedCallback() {
    this.setAttribute("role", "gridcell");
  }
}

class NbTable extends NbElement {
  connectedCallback() {
    this.paint();
    this.__observer = new MutationObserver(() => this.paint());
    this.__observer.observe(this, {childList: true, subtree: true});
  }

  disconnectedCallback() {
    this.__observer?.disconnect();
  }

  columns() {
    const columns = [...this.children].filter((child) => child.tagName === "NB-COLUMN");
    for (const column of columns) customElements.upgrade(column);
    return columns;
  }

  columnTemplate(columns) {
    if (columns.length === 0) return "repeat(auto-fit, minmax(6rem, 1fr))";
    return columns
      .map((column) => {
        const width = column.getAttribute("width");
        return width ? `minmax(0, ${width})` : "minmax(6rem, 1fr)";
      })
      .join(" ");
  }

  paint() {
    const columns = this.columns();
    const template = this.columnTemplate(columns);
    const alignments = columns.map((column) => column.getAttribute("align") || "start");

    // Keep light-DOM cells aligned with their column definition — the one
    // piece ::slotted selectors cannot express per-column.
    for (const row of this.querySelectorAll("nb-row")) {
      [...row.children].forEach((cell, index) => {
        if (cell.tagName === "NB-CELL") cell.style.textAlign = alignments[index] === "end" ? "right" : alignments[index] === "center" ? "center" : "left";
      });
    }

    this.render(
      `
      :host {
        display: block;
      }
      .wrap {
        max-height: var(--nb-table-max-height, 24rem);
        overflow: auto;
        border: var(--n-border-width) solid var(--n-border);
        border-radius: var(--n-radius);
        background: var(--n-surface);
        box-shadow: var(--n-shadow);
      }
      .grid {
        --nb-grid-cols: ${template};
        min-width: 100%;
        width: max-content;
      }
      .head,
      ::slotted(nb-row) {
        display: grid;
        grid-template-columns: var(--nb-grid-cols);
        align-items: center;
        gap: 0.5rem;
      }
      .head {
        position: sticky;
        top: 0;
        z-index: 1;
        padding: 0.5625rem 0.875rem;
        background: var(--n-surface-sunken);
        border-bottom: var(--n-border-width) solid var(--n-border);
        font-weight: var(--n-weight-bold);
        white-space: nowrap;
      }
      .head [data-align="end"] {
        text-align: right;
      }
      .head [data-align="center"] {
        text-align: center;
      }
      .body {
        display: flex;
        flex-direction: column;
        padding: 0.25rem;
      }
      ::slotted(nb-row) {
        padding: 0.5rem 0.625rem;
        border-radius: calc(var(--n-radius) - 2px);
        transition: background var(--n-dur-short) var(--n-ease-emphasized);
      }
      ::slotted(nb-row:hover) {
        background: var(--n-surface-sunken);
      }
      ::slotted(nb-row:active) {
        /* Press substitute on rows: deepen the tint — travel on rows is
         * not portable across engines, so the press reads through color. */
        background: color-mix(in srgb, var(--n-surface-sunken) 60%, var(--n-primary));
      }
      ::slotted(nb-cell) {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      @media (prefers-reduced-motion: reduce) {
        ::slotted(nb-row) {
          transition: none;
        }
      }
      `,
      `
      <div class="wrap" part="wrap">
        <div class="grid" role="grid" part="grid">
          <div class="head" role="row" part="head">
            ${columns
              .map((column) => {
                return `<div role="columnheader" data-align="${escapeHtml(column.getAttribute("align") || "start")}">${escapeHtml(column.getAttribute("label") || "")}</div>`;
              })
              .join("")}
          </div>
          <div class="body" role="rowgroup" part="body"><slot></slot></div>
        </div>
      </div>
      `,
    );
  }
}

/* ---------------------------------------------------------------------------
 * nb-calendar — the month grid for the day view.
 *
 * The WAI-ARIA date-grid pattern, complete: a 7-column grid, one tab stop
 * (the focused day), arrows move by day/week, Home/End bound the week,
 * PageUp/PageDown change months, Enter/Space select. States read at a
 * glance the way the clinic does: today wears a hard inset ring, days
 * with items carry the tilted sticker dot, the selected day lifts on a
 * primary-colored shadow. Emits nb-select {date} and, when the month is
 * navigated, nb-month-change {month} — both composed for LiveView hooks.
 *
 * `view="week"` shows one Monday-to-Sunday row instead: the week holding
 * the `month` attribute (read as a full YYYY-MM-DD date there), else the
 * selected day, else today. Previous/Next and PageUp/PageDown move a week,
 * arrows crossing the row move into the neighboring week, and every move
 * emits nb-week-change {week} (the Monday, YYYY-MM-DD).
 * ------------------------------------------------------------------------- */

class NbCalendar extends NbElement {
  static get observedAttributes() {
    return ["month", "selected", "today", "items", "view"];
  }

  constructor() {
    super();
    // Internal navigation state: the rendered month (or week) and the
    // focused day. They re-derive from attributes when the host writes
    // them, so the component is stateless from the host's point of view.
    this.__month = null;
    this.__week = null;
    this.__focusDate = null;
  }

  connectedCallback() {
    this.paint();
    this.addEventListener("keydown", this);
  }

  disconnectedCallback() {
    this.removeEventListener("keydown", this);
  }

  attributeChangedCallback() {
    this.__month = null;
    this.__week = null;
    this.__focusDate = null;
    if (this.root) this.paint();
  }

  get weekView() {
    return this.getAttribute("view") === "week";
  }

  monday(date) {
    const monday = new Date(date);
    monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
    monday.setHours(12, 0, 0, 0);
    return monday;
  }

  addDays(date, days) {
    const next = new Date(date);
    next.setDate(next.getDate() + days);
    next.setHours(12, 0, 0, 0);
    return next;
  }

  /** Whether `date` is a day the grid currently shows as in range. */
  inView(date, {month, week}) {
    if (this.weekView) {
      return date >= week && date < this.addDays(week, 7);
    }
    return date.getMonth() === month.getMonth() && date.getFullYear() === month.getFullYear();
  }

  parseISO(text) {
    const match = /^(\d{4})-(\d{2})(?:-(\d{2}))?$/.exec(text || "");
    if (!match) return null;
    const [, year, month, day] = match;
    const date = new Date(Number(year), Number(month) - 1, Number(day || 1));
    date.setHours(12, 0, 0, 0);
    return date;
  }

  monthISO(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
  }

  dayISO(date) {
    return `${this.monthISO(date)}-${String(date.getDate()).padStart(2, "0")}`;
  }

  state() {
    const today = this.getAttribute("today") ? this.parseISO(this.getAttribute("today")) : new Date();
    today.setHours(12, 0, 0, 0);
    const monthDate = this.__month
      ? this.__month
      : this.getAttribute("month")
        ? this.parseISO(this.getAttribute("month")) || today
        : today;
    const month = new Date(monthDate.getFullYear(), monthDate.getMonth(), 1);
    month.setHours(12, 0, 0, 0);
    const selected = this.getAttribute("selected") ? this.parseISO(this.getAttribute("selected")) : null;
    if (this.weekView) return this.weekState(today, selected);
    const items = this.itemSet();
    const focus =
      this.__focusDate && this.__focusDate.getMonth() === month.getMonth()
        ? this.__focusDate
        : selected && selected.getMonth() === month.getMonth() && selected.getFullYear() === month.getFullYear()
          ? selected
          : today.getMonth() === month.getMonth() && today.getFullYear() === month.getFullYear()
            ? today
            : month;
    return {today, month, selected, items, focus};
  }

  weekState(today, selected) {
    const anchor = this.getAttribute("month") ? this.parseISO(this.getAttribute("month")) : null;
    const week = this.__week || this.monday(anchor || selected || today);
    const items = this.itemSet();
    const within = (date) => date && date >= week && date < this.addDays(week, 7);
    const focus = within(this.__focusDate)
      ? this.__focusDate
      : within(selected)
        ? selected
        : within(today)
          ? today
          : week;
    const month = new Date(week.getFullYear(), week.getMonth(), 1);
    month.setHours(12, 0, 0, 0);
    return {today, month, week, selected, items, focus};
  }

  itemSet() {
    return new Set(
      (this.getAttribute("items") || "")
        .split(/[\s,]+/)
        .filter(Boolean)
        .map((token) => token.split("*")[0]),
    );
  }

  weeks(month, week) {
    if (this.weekView) return [Array.from({length: 7}, (_, index) => this.addDays(week, index))];
    // Monday-start grid; spillover days from neighbor months are rendered
    // muted and inert — navigation crosses months by recomputing instead.
    const start = new Date(month);
    const offset = (start.getDay() + 6) % 7;
    const cursor = new Date(month);
    cursor.setDate(cursor.getDate() - offset);
    const weeks = [];
    for (let week = 0; week < 6; week++) {
      const days = [];
      for (let day = 0; day < 7; day++) {
        days.push(new Date(cursor));
        cursor.setDate(cursor.getDate() + 1);
      }
      weeks.push(days);
      if (cursor.getMonth() !== month.getMonth() && cursor.getDay() === 1) break;
    }
    return weeks;
  }

  paint() {
    const view = this.state();
    const {today, month, week, selected, items, focus} = view;
    const locale = this.getAttribute("lang") || undefined;
    const title = this.weekView
      ? this.weekTitle(week, locale)
      : new Intl.DateTimeFormat(locale, {month: "long", year: "numeric"}).format(month);
    const weekdayFormatter = new Intl.DateTimeFormat(locale, {weekday: "short"});
    const weekdays = WEEKDAYS.map((_, index) => {
      const date = new Date(2024, 0, 1 + index); // 2024-01-01 was a Monday.
      return weekdayFormatter.format(date);
    });
    const weeks = this.weeks(month, week);
    const cells = weeks
      .map((week) => {
        const row = week
          .map((date) => {
            const iso = this.dayISO(date);
            const inMonth = this.inView(date, view);
            const isToday = this.dayISO(today) === iso;
            const isSelected = selected && this.dayISO(selected) === iso;
            const hasItems = items.has(iso);
            const isFocus = this.dayISO(focus) === iso && inMonth;
            const classes = ["day"];
            if (!inMonth) classes.push("day--out");
            if (isToday) classes.push("day--today");
            if (isSelected) classes.push("day--selected");
            if (hasItems) classes.push("day--items");
            return `<td role="gridcell" class="cell" data-date="${iso}"${
              isSelected ? ' aria-selected="true"' : ""
            }>${inMonth ? `<button type="button" class="${classes.join(" ")}" data-date="${iso}" tabindex="${isFocus ? "0" : "-1"}"${
              isToday ? ' aria-current="date"' : ""
            } aria-label="${new Intl.DateTimeFormat(locale, {
              dateStyle: "full",
            }).format(date)}">${String(date.getDate())}${
              hasItems ? '<span class="day-dot" aria-hidden="true"></span>' : ""
            }</button>` : `<span class="${classes.join(" ")}" aria-hidden="true">${date.getDate()}</span>`}</td>`;
          })
          .join("");
        return `<tr role="row">${row}</tr>`;
      })
      .join("");

    this.render(
      `
      :host {
        display: block;
        max-width: 22rem;
      }
      .cal {
        background: var(--n-surface);
        border: var(--n-border-width) solid var(--n-border);
        border-radius: var(--n-radius);
        box-shadow: var(--n-shadow);
        padding: 0.75rem;
      }
      .head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.5rem;
        margin-bottom: 0.5rem;
      }
      .title {
        font-size: 1rem;
        font-weight: var(--n-weight-bold);
      }
      .head .nb-btn {
        padding: 0.1875rem 0.5625rem;
        line-height: 1.2;
      }
      .grid {
        width: 100%;
        border-collapse: collapse;
        table-layout: fixed;
      }
      .weekday {
        padding: 0.25rem 0;
        font-size: var(--n-font-size-s);
        font-weight: var(--n-weight-bold);
        text-align: center;
      }
      .cell {
        text-align: center;
        padding: 1px;
      }
      .day {
        position: relative;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 2.25rem;
        height: 2.25rem;
        font: inherit;
        font-weight: var(--n-weight-medium);
        color: var(--n-text);
        background: none;
        border: none;
        border-radius: var(--n-radius);
        cursor: pointer;
        transition:
          transform var(--n-dur-short) var(--n-ease-emphasized),
          box-shadow var(--n-dur-short) var(--n-ease-emphasized),
          background var(--n-dur-short) var(--n-ease-emphasized);
      }
      .day:hover {
        background: var(--n-surface-sunken);
      }
      .day:focus-visible {
        outline: var(--n-border-width) solid var(--n-border);
        outline-offset: 1px;
      }
      /* Today: a hard inset ring — present, not shouting. */
      .day--today {
        box-shadow: inset 0 0 0 var(--n-border-width) var(--n-border);
      }
      /* Selected: filled, lifted onto a primary-colored hard shadow. */
      .day--selected {
        background: var(--n-primary);
        color: var(--n-on-primary);
        font-weight: var(--n-weight-bold);
        transform: translate(-1px, -1px);
        box-shadow: 3px 3px 0 0 var(--n-primary);
      }
      .day--selected:hover {
        transform: translate(-1px, -1px);
        background: var(--n-primary);
      }
      .day--out {
        color: var(--n-text-muted);
        opacity: 0.45;
      }
      span.day--out {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 2.25rem;
        height: 2.25rem;
      }
      /* Has-items: the tilted sticker dot, bottom-right of the day. */
      .day-dot {
        position: absolute;
        right: 3px;
        bottom: 3px;
        width: 0.4375rem;
        height: 0.4375rem;
        background: var(--nb-item-dot-color, var(--n-violet));
        border: 1.5px solid var(--n-border);
        border-radius: 2px;
        transform: rotate(-8deg);
      }
      @media (prefers-reduced-motion: reduce) {
        .day,
        .day--selected,
        .day--selected:hover {
          transition: none;
          transform: none;
        }
      }
      `,
      `
      <div class="cal" part="cal">
        <div class="head">
          <button type="button" class="nb-btn prev" aria-label="${this.weekView ? "Previous week" : "Previous month"}">‹</button>
          <h3 class="title" part="title" aria-live="polite">${escapeHtml(title)}</h3>
          <button type="button" class="nb-btn next" aria-label="${this.weekView ? "Next week" : "Next month"}">›</button>
        </div>
        <table class="grid" role="grid" aria-label="${escapeHtml(title)}">
          <thead aria-hidden="true">
            <tr>${weekdays.map((name) => `<th class="weekday">${escapeHtml(name)}</th>`).join("")}</tr>
          </thead>
          <tbody>${cells}</tbody>
        </table>
      </div>
      `,
    );

    this.root.querySelector(".prev").addEventListener("click", () => this.shift(-1));
    this.root.querySelector(".next").addEventListener("click", () => this.shift(1));
    this.root.querySelectorAll("button.day").forEach((button) => {
      button.addEventListener("click", () => this.selectDay(button.dataset.date));
    });
  }

  focusDateInMonth(date) {
    const target = this.root.querySelector(`button.day[data-date="${this.dayISO(date)}"]`);
    if (!target) return false;
    this.root.querySelectorAll("button.day").forEach((button) => button.setAttribute("tabindex", "-1"));
    target.setAttribute("tabindex", "0");
    target.focus();
    return true;
  }

  paintMonth(date) {
    if (this.weekView) {
      this.__week = this.monday(date);
    } else {
      this.__month = new Date(date.getFullYear(), date.getMonth(), 1);
      this.__month.setHours(12, 0, 0, 0);
    }
    this.__focusDate = date;
    this.paint();
    this.focusDateInMonth(date);
  }

  weekTitle(week, locale) {
    const sunday = this.addDays(week, 6);
    const format = new Intl.DateTimeFormat(locale, {month: "short", day: "numeric", year: "numeric"});
    return typeof format.formatRange === "function"
      ? format.formatRange(week, sunday)
      : `${format.format(week)} – ${format.format(sunday)}`;
  }

  /** Previous/Next: a month, or a week in the week view. */
  shift(delta) {
    if (this.weekView) this.shiftWeek(delta);
    else this.shiftMonth(delta);
  }

  shiftWeek(delta) {
    const {week, focus} = this.state();
    this.__week = this.addDays(week, 7 * delta);
    this.__focusDate = this.addDays(focus, 7 * delta);
    this.paint();
    this.focusDateInMonth(this.__focusDate);
    this.emit("nb-week-change", {week: this.dayISO(this.__week)});
  }

  /** The navigation event for a move that left the shown range. */
  emitRangeChange(date) {
    if (this.weekView) this.emit("nb-week-change", {week: this.dayISO(this.monday(date))});
    else this.emit("nb-month-change", {month: this.monthISO(date)});
  }

  shiftMonth(delta) {
    const {month, focus} = this.state();
    const next = new Date(month);
    next.setMonth(next.getMonth() + delta);
    const day = Math.min(focus.getDate(), 28);
    const target = new Date(next.getFullYear(), next.getMonth(), day);
    target.setHours(12, 0, 0, 0);
    this.__month = new Date(target.getFullYear(), target.getMonth(), 1);
    this.__focusDate = target;
    this.paint();
    this.focusDateInMonth(target);
    this.emit("nb-month-change", {month: this.monthISO(target)});
  }

  selectDay(iso) {
    this.emit("nb-select", {date: iso});
    const date = this.parseISO(iso);
    if (date) {
      if (this.weekView) this.__week = this.monday(date);
      else this.__month = new Date(date.getFullYear(), date.getMonth(), 1);
      this.__focusDate = date;
    }
    this.paint();
    this.focusDateInMonth(date);
  }

  handleEvent(event) {
    const key = event.key;
    if (!["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End", "PageUp", "PageDown", "Enter", " "].includes(key))
      return;
    const active = this.root.activeElement;
    const iso = active?.dataset?.date;
    if (!iso) return;
    event.preventDefault();
    const date = this.parseISO(iso);
    if (!date) return;
    const step = (field, amount) => {
      const next = new Date(date);
      if (field === "month") next.setMonth(next.getMonth() + amount);
      else next.setDate(next.getDate() + amount);
      next.setHours(12, 0, 0, 0);
      if (this.inView(next, this.state())) {
        this.__focusDate = next;
        this.paint();
        this.focusDateInMonth(next);
      } else {
        this.paintMonth(next);
        this.emitRangeChange(next);
      }
    };
    switch (key) {
      case "ArrowLeft":
        step("day", -1);
        break;
      case "ArrowRight":
        step("day", 1);
        break;
      case "ArrowUp":
        step("day", -7);
        break;
      case "ArrowDown":
        step("day", 7);
        break;
      case "Home": {
        const monday = new Date(date);
        monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
        this.__focusDate = monday;
        this.paint();
        this.focusDateInMonth(monday);
        break;
      }
      case "End": {
        const sunday = new Date(date);
        sunday.setDate(sunday.getDate() + (7 - sunday.getDay()) % 7);
        this.__focusDate = sunday;
        this.paint();
        this.focusDateInMonth(sunday);
        break;
      }
      case "PageUp":
        if (this.weekView) step("day", -7);
        else step("month", -1);
        break;
      case "PageDown":
        if (this.weekView) step("day", 7);
        else step("month", 1);
        break;
      case "Enter":
      case " ":
        this.selectDay(iso);
        break;
    }
  }
}

/* ---------------------------------------------------------------------------
 * nb-scroller — the stick-to-bottom message pane.
 *
 * Generalized from the clinic-demo NbScroller hook: while the pane is
 * pinned (within a threshold of the bottom) appended content keeps the
 * bottom pinned — in a rAF, so batches of appends land as one scroll. The
 * moment the reader scrolls up, the pane detaches: nothing yanks their
 * position, and a "jump to latest" pill offers the way back. A
 * MutationObserver watches light-DOM children, so LiveView streams and
 * plain appends behave identically. Emits nb-pinned-change {pinned}.
 * ------------------------------------------------------------------------- */

class NbScroller extends NbElement {
  static get observedAttributes() {
    return ["threshold"];
  }

  connectedCallback() {
    this.paint();
    this.view = this.root.querySelector(".view");
    this.__lastScrollTop = 0;

    // A scroll event fires when the POSITION moves — but also (per the
    // async dispatch order) after content growth below the viewport, with
    // the position unchanged. Recomputing pin state on that stale event
    // raced the append: the pane read as detached at the very moment it
    // should follow. So: recompute only on a real position change.
    this.onScroll = () => {
      if (this.view.scrollTop === this.__lastScrollTop) return;
      this.__lastScrollTop = this.view.scrollTop;
      this.updatePinned();
    };
    this.view.addEventListener("scroll", this.onScroll, {passive: true});

    this.observer = new MutationObserver(() => {
      if (this.pinned) {
        requestAnimationFrame(() => {
          if (this.pinned) this.view.scrollTop = this.view.scrollHeight;
        });
      }
    });
    this.observer.observe(this, {childList: true, subtree: true, characterData: true});
    this.updatePinned();
  }

  disconnectedCallback() {
    this.observer?.disconnect();
  }

  attributeChangedCallback() {
    this.threshold = Number(this.getAttribute("threshold") || 32);
  }

  paint() {
    this.render(
      `
      :host {
        position: relative;
        display: block;
      }
      .view {
        height: var(--nb-scroller-height, 16rem);
        overflow-y: auto;
        background: var(--n-surface);
        border: var(--n-border-width) solid var(--n-border);
        border-radius: var(--n-radius);
        box-shadow: var(--n-shadow);
      }
      .pad {
        padding: 0.75rem;
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .jump {
        position: absolute;
        right: 0.75rem;
        bottom: 0.75rem;
        display: none;
        padding: 0.3125rem 0.625rem;
        font: inherit;
        font-size: var(--n-font-size-s);
        font-weight: var(--n-weight-bold);
        color: var(--n-on-primary);
        background: var(--n-primary);
        border: var(--n-border-width) solid var(--n-border);
        border-radius: 999px;
        box-shadow: var(--n-shadow);
        cursor: pointer;
        /* Spring-in, M3E move #6 in hard-shadow terms: the pill lands
         * with a small overshoot rather than a fade. */
        animation: nb-jump-in var(--n-dur-short) var(--n-ease-decel);
      }
      :host([data-pinned="false"]) .jump {
        display: inline-flex;
        align-items: center;
        gap: 0.25rem;
      }
      @keyframes nb-jump-in {
        0% {
          transform: translateY(6px) scale(0.9);
          box-shadow: var(--n-shadow-press);
        }
        70% {
          transform: translateY(-1px) scale(1.02);
        }
        100% {
          transform: translateY(0) scale(1);
          box-shadow: var(--n-shadow);
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .jump {
          animation: none;
        }
      }
      `,
      `
      <div class="view" part="view">
        <div class="pad"><slot></slot></div>
      </div>
      <button type="button" class="jump" part="jump">Jump to latest ↓</button>
      `,
    );
    this.root.querySelector(".jump").addEventListener("click", () => this.scrollToLatest());
  }

  get pinned() {
    return this.dataset.pinned !== "false";
  }

  updatePinned() {
    const view = this.view;
    const pinned = view.scrollHeight - view.scrollTop - view.clientHeight <= (this.threshold || 32);
    if (pinned !== this.pinned) {
      this.dataset.pinned = String(pinned);
      this.setAttribute("aria-live", pinned ? "off" : "polite");
      this.emit("nb-pinned-change", {pinned});
    }
  }

  /** Pins and scrolls to the latest content. Instant by default — smooth
   * travel only when the user asked for it via the argument. */
  scrollToLatest({behavior = "instant"} = {}) {
    try {
      this.view.scrollTo({top: this.view.scrollHeight, behavior});
    } catch {
      this.view.scrollTop = this.view.scrollHeight;
    }
    this.__lastScrollTop = this.view.scrollTop;
    this.updatePinned();
  }
}

/* ---------------------------------------------------------------------------
 * nb-pagination — windowed page chips.
 * ------------------------------------------------------------------------- */

class NbPagination extends NbElement {
  static get observedAttributes() {
    return ["page", "total-pages", "sibling-count", "label"];
  }

  attributeChangedCallback() {
    if (this.root) this.paint();
  }

  connectedCallback() {
    this.paint();
  }

  pages() {
    const page = Math.max(1, Number(this.getAttribute("page") || 1));
    const total = Math.max(1, Number(this.getAttribute("total-pages") || 1));
    const siblings = Math.max(0, Number(this.getAttribute("sibling-count") ?? 1));
    // 1 … (p-s .. p+s) … N with ellipses only where a gap actually exists.
    const pages = new Set([1, total, page]);
    for (let index = page - siblings; index <= page + siblings; index++) {
      if (index >= 1 && index <= total) pages.add(index);
    }
    const sorted = [...pages].sort((a, b) => a - b);
    const windowed = [];
    sorted.forEach((value, index) => {
      if (index > 0 && value - sorted[index - 1] > 1) windowed.push("…");
      windowed.push(value);
    });
    return {page, total, windowed};
  }

  paint() {
    const {page, total, windowed} = this.pages();
    this.render(
      `
      :host {
        display: block;
      }
      .pager {
        display: flex;
        align-items: center;
        gap: 0.375rem;
        flex-wrap: wrap;
      }
      .chip {
        min-width: 2rem;
        height: 2rem;
        padding: 0 0.5rem;
        font: inherit;
        font-weight: var(--n-weight-medium);
        color: var(--n-text);
        background: var(--n-surface);
        border: var(--n-border-width) solid var(--n-border);
        border-radius: var(--n-radius);
        box-shadow: var(--n-shadow);
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        transition:
          transform var(--n-dur-short) var(--n-ease-emphasized),
          box-shadow var(--n-dur-short) var(--n-ease-emphasized);
      }
      .chip:hover:not(:disabled) {
        transform: translate(-1px, -1px);
        box-shadow: var(--n-shadow-lift);
      }
      .chip:active:not(:disabled) {
        transform: translate(1px, 1px);
        box-shadow: var(--n-shadow-press);
      }
      .chip:disabled {
        opacity: 0.45;
        cursor: default;
      }
      .chip:focus-visible {
        outline: var(--n-border-width) solid var(--n-border);
        outline-offset: 2px;
      }
      .chip--current {
        background: var(--n-primary);
        color: var(--n-on-primary);
        font-weight: var(--n-weight-bold);
      }
      .gap {
        padding: 0 0.125rem;
        color: var(--n-text-muted);
      }
      @media (prefers-reduced-motion: reduce) {
        .chip,
        .chip:hover:not(:disabled),
        .chip:active:not(:disabled) {
          transition: none;
          transform: none;
        }
      }
      `,
      `
      <nav class="pager" part="pager" aria-label="${escapeHtml(this.getAttribute("label") || "Pagination")}">
        <button type="button" class="chip" data-go="${page - 1}" ${page <= 1 ? "disabled" : ""} aria-label="Previous page">‹</button>
        ${windowed
          .map((value) =>
            value === "…"
              ? `<span class="gap" aria-hidden="true">…</span>`
              : value === page
                ? `<span class="chip chip--current" aria-current="page">${value}</span>`
                : `<button type="button" class="chip" data-go="${value}" aria-label="Page ${value}">${value}</button>`,
          )
          .join("")}
        <button type="button" class="chip" data-go="${page + 1}" ${page >= total ? "disabled" : ""} aria-label="Next page">›</button>
      </nav>
      `,
    );
    this.root.querySelectorAll("[data-go]").forEach((button) => {
      button.addEventListener("click", () => {
        const next = Number(button.dataset.go);
        if (next >= 1 && next <= total) this.emit("nb-change", {page: next});
      });
    });
  }
}

/* ---------------------------------------------------------------------------
 * Registration + helpers.
 * ------------------------------------------------------------------------- */

let uidCounter = 0;
function uid(element, index) {
  if (!element.__nbUid) element.__nbUid = `n${++uidCounter}`;
  return `${element.__nbUid}-${index}`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => {
    return {"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}[character];
  });
}

const NB_ELEMENTS = [
  ["nb-item", NbItem],
  ["nb-menu", NbMenu],
  ["nb-menu-item", NbMenuItem],
  ["nb-sheet", NbSheet],
  ["nb-tabs", NbTabs],
  ["nb-tab", NbTab],
  ["nb-table", NbTable],
  ["nb-column", NbColumn],
  ["nb-row", NbRow],
  ["nb-cell", NbCell],
  ["nb-calendar", NbCalendar],
  ["nb-scroller", NbScroller],
  ["nb-pagination", NbPagination],
];

/**
 * Defines every NB element. Idempotent per tag (an element already defined
 * is skipped), so hosts and storybook-style demo bundles can each call it.
 *
 * @param {CustomElementRegistry} [registry=customElements] pass a
 *   alternate registry only for exotic embedding setups.
 */
export function defineNbComponents({registry = customElements} = {}) {
  for (const [tag, element] of NB_ELEMENTS) {
    if (!registry.get(tag)) registry.define(tag, element);
  }
}

export {
  NbItem,
  NbMenu,
  NbMenuItem,
  NbSheet,
  NbTabs,
  NbTab,
  NbTable,
  NbColumn,
  NbRow,
  NbCell,
  NbCalendar,
  NbScroller,
  NbPagination,
  STATUS_FILLS,
};
