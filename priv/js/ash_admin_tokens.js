/**
 * Shared design tokens and helpers for the Ash admin catalog v1 renderer
 * (`ash_admin_catalog.js`). Internal module — the public surface of this
 * library's JS is `createAshAdminCatalog/1`; everything here exists so the
 * ten admin components share one deliberate design system.
 *
 * ## Token architecture
 *
 * Every admin component renders inside shadow DOM, so page CSS cannot reach
 * it — but CSS custom properties inherit through shadow boundaries. Each
 * component's stylesheet declares a private `--am-*` token layer on `:host`
 * that reads, in order:
 *
 *     var(--ash-admin-<token>, var(--a2ui-<a2ui-token>, <literal default>))
 *
 * so a host themes the admin catalog three ways:
 *
 *   1. override `--ash-admin-*` anywhere in the document tree (admin-only,
 *      highest fidelity — the full list is below);
 *   2. override the pre-existing `--a2ui-*` variables (e.g. by importing
 *      `ash_a2ui_theme.css`, which also carries `light-dark()` values) —
 *      shared with the basic catalog for a coherent surface;
 *   3. do nothing — the literal defaults are a restrained, light-mode-first
 *      admin palette (slate neutrals + one indigo accent + semantic
 *      success/warning/error/destructive).
 *
 * Because the derived tokens are declared as `var()` reads (not static
 * values), inherited host overrides always win — there is no `:host`
 * declaration shadowing document-level theming.
 *
 * ## Token list (public `--ash-admin-*` surface)
 *
 * Spacing      space-2xs .25rem · space-xs .375rem · space-s .5rem ·
 *              space-m .75rem · space-l 1rem · space-xl 1.5rem · space-2xl 2rem
 * Typography   font-size-xs .75 · -s .8125 · -m .875 · -l 1 · -xl 1.25 ·
 *              -2xl 1.5 (rem) · font-weight-regular 400 · -medium 500 ·
 *              -semibold 600 · -bold 700 · line-height-body 1.5 · -tight 1.25
 * Radii        radius-s .375rem · radius-m .5rem · radius-l .75rem · pill 999px
 * Surfaces     surface · surface-sunken · surface-raised
 * Text         text · text-muted · text-faint
 * Lines        border · border-strong
 * Accent       primary · on-primary · primary-hover · primary-subtle
 * Feedback     success · success-subtle · warning · warning-subtle ·
 *              error · error-subtle · error-strong
 * Destructive  destructive · on-destructive · destructive-hover ·
 *              destructive-subtle
 * Misc         hover-tint · focus (focus-ring color) ·
 *              shadow-1 · shadow-2 · shadow-3
 * Lines (1.1)  border-width (falls back to --a2ui-border-width, then 1px)
 * Type (1.1)   font-mono (identifier cells)
 * Links (1.1)  link · link-hover
 * Badges (1.1) badge-radius · badge-border · badge-<tone>-background ·
 *              badge-<tone>-text for tone in neutral/info/success/warning/
 *              danger/accent
 * Grid (1.1)   grid-max-height (scroll frame; sticky header) ·
 *              grid-radius · grid-shadow · grid-header-background ·
 *              grid-header-text · grid-header-font-size ·
 *              grid-header-font-weight · grid-header-transform ·
 *              grid-header-tracking · grid-row-active (press tint)
 *
 * ## Motion
 *
 * Micro-interactions are color/opacity/shadow transitions of 120–200ms and
 * one indeterminate spinner; a blanket `prefers-reduced-motion` rule in the
 * shared stylesheet collapses all of them (no animated travel anywhere).
 */

/**
 * Builds the shared stylesheet chunks from the host's `lit.css` tag.
 *
 * @param {Function} css the `css` template tag from the host's Lit instance
 * @returns {{shared: object, buttons: object}} two Lit CSSResult chunks —
 *   `shared` (tokens + utilities, included first by every component) and
 *   `buttons` (the button system, included by components that render
 *   buttons).
 */
export function createAdminStyles(css) {
  const shared = css`
    :host {
      /* Spacing scale */
      --am-space-2xs: var(--ash-admin-space-2xs, 0.25rem);
      --am-space-xs: var(--ash-admin-space-xs, 0.375rem);
      --am-space-s: var(--ash-admin-space-s, 0.5rem);
      --am-space-m: var(--ash-admin-space-m, 0.75rem);
      --am-space-l: var(--ash-admin-space-l, 1rem);
      --am-space-xl: var(--ash-admin-space-xl, 1.5rem);
      --am-space-2xl: var(--ash-admin-space-2xl, 2rem);

      /* Typography */
      --am-font-size-xs: var(--ash-admin-font-size-xs, 0.75rem);
      --am-font-size-s: var(--ash-admin-font-size-s, 0.8125rem);
      --am-font-size-m: var(--ash-admin-font-size-m, 0.875rem);
      --am-font-size-l: var(--ash-admin-font-size-l, 1rem);
      --am-font-size-xl: var(--ash-admin-font-size-xl, 1.25rem);
      --am-font-size-2xl: var(--ash-admin-font-size-2xl, 1.5rem);
      --am-font-weight-regular: var(--ash-admin-font-weight-regular, 400);
      --am-font-weight-medium: var(--ash-admin-font-weight-medium, 500);
      --am-font-weight-semibold: var(--ash-admin-font-weight-semibold, 600);
      --am-font-weight-bold: var(--ash-admin-font-weight-bold, 700);
      --am-line-height-body: var(--ash-admin-line-height-body, 1.5);
      --am-line-height-tight: var(--ash-admin-line-height-tight, 1.25);
      --am-tracking-wide: var(--ash-admin-tracking-wide, 0.05em);

      /* Radii */
      --am-radius-s: var(--ash-admin-radius-s, 0.375rem);
      --am-radius-m: var(--ash-admin-radius-m, 0.5rem);
      --am-radius-l: var(--ash-admin-radius-l, 0.75rem);
      --am-radius-pill: var(--ash-admin-radius-pill, 999px);

      /* Surfaces & text */
      --am-surface: var(--ash-admin-surface, var(--a2ui-color-surface, #ffffff));
      --am-surface-sunken: var(--ash-admin-surface-sunken, var(--a2ui-color-background, #f8fafc));
      --am-surface-raised: var(--ash-admin-surface-raised, var(--am-surface));
      --am-text: var(--ash-admin-text, var(--a2ui-color-on-surface, #0f172a));
      --am-text-muted: var(--ash-admin-text-muted, #475569);
      /* #5d6d81 clears WCAG AA (5.29:1 on #ffffff, 5.06:1 on sunken,
         4.83:1 on hover tints); the old #94a3b8 default failed at ~2.5:1. */
      --am-text-faint: var(--ash-admin-text-faint, #5d6d81);
      --am-border: var(--ash-admin-border, var(--a2ui-color-border, #e2e8f0));
      --am-border-strong: var(--ash-admin-border-strong, #cbd5e1);

      /* Accent */
      --am-primary: var(--ash-admin-primary, var(--a2ui-color-primary, #4f46e5));
      --am-on-primary: var(
        --ash-admin-on-primary,
        var(--a2ui-color-on-primary, #ffffff)
      );
      --am-primary-hover: var(--ash-admin-primary-hover, #4338ca);
      --am-primary-subtle: var(--ash-admin-primary-subtle, #eef2ff);

      /* Feedback */
      --am-success: var(--ash-admin-success, #047857);
      --am-success-subtle: var(--ash-admin-success-subtle, #ecfdf5);
      --am-warning: var(--ash-admin-warning, #b45309);
      --am-warning-subtle: var(--ash-admin-warning-subtle, #fffbeb);
      --am-error: var(--ash-admin-error, #b91c1c);
      --am-error-subtle: var(--ash-admin-error-subtle, #fef2f2);
      --am-error-strong: var(--ash-admin-error-strong, #991b1b);

      /* Destructive (defaults to the error family; separable for hosts whose
       * design language distinguishes them) */
      --am-destructive: var(--ash-admin-destructive, var(--am-error));
      --am-on-destructive: var(--ash-admin-on-destructive, #ffffff);
      --am-destructive-hover: var(--ash-admin-destructive-hover, var(--am-error-strong));
      --am-destructive-subtle: var(--ash-admin-destructive-subtle, var(--am-error-subtle));

      /* Interaction chrome */
      --am-hover-tint: var(--ash-admin-hover-tint, var(--a2ui-color-secondary, #f1f5f9));
      --am-focus: var(
        --ash-admin-focus,
        var(--a2ui-color-primary, #4f46e5)
      );

      /* Elevation */
      --am-shadow-1: var(--ash-admin-shadow-1, 0 1px 2px rgb(15 23 42 / 0.06));
      --am-shadow-2: var(
        --ash-admin-shadow-2,
        0 4px 12px rgb(15 23 42 / 0.08),
        0 1px 3px rgb(15 23 42 / 0.06)
      );
      --am-shadow-3: var(
        --ash-admin-shadow-3,
        0 12px 32px rgb(15 23 42 / 0.16),
        0 4px 12px rgb(15 23 42 / 0.08)
      );

      /* 1.1: lines, identifiers, links, badges */
      --am-border-width: var(--ash-admin-border-width, var(--a2ui-border-width, 1px));
      --am-font-mono: var(
        --ash-admin-font-mono,
        ui-monospace,
        "SFMono-Regular",
        Menlo,
        Consolas,
        monospace
      );
      --am-link: var(--ash-admin-link, var(--am-primary));
      --am-link-hover: var(--ash-admin-link-hover, var(--am-primary-hover));
      --am-badge-radius: var(--ash-admin-badge-radius, var(--am-radius-pill));
      --am-badge-border: var(--ash-admin-badge-border, transparent);

      box-sizing: border-box;
      color: var(--am-text);
      font-family: inherit;
      font-size: var(--am-font-size-m);
      line-height: var(--am-line-height-body);
    }

    *,
    *::before,
    *::after {
      box-sizing: inherit;
    }

    /* Screen-reader-only utility (captions, table action headers). */
    .sr-only {
      position: absolute;
      width: 1px;
      height: 1px;
      padding: 0;
      margin: -1px;
      overflow: hidden;
      clip: rect(0, 0, 0, 0);
      white-space: nowrap;
      border-width: 0;
    }

    /* One focus system for every interactive element in the catalog. */
    :where(button, a, input, select, textarea, [tabindex]):focus-visible {
      outline: 2px solid var(--am-focus);
      outline-offset: 2px;
    }

    /* Motion is a garnish, never a journey: 120–200ms color/opacity/shadow
     * transitions, one spinner — and none of it under reduced motion. */
    *,
    *::before,
    *::after {
      transition-duration: var(--am-motion-duration, 160ms);
      transition-timing-function: ease-out;
      transition-property: background-color, border-color, color, opacity,
        box-shadow;
    }
    @media (prefers-reduced-motion: reduce) {
      *,
      *::before,
      *::after {
        transition-duration: 0.01ms !important;
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
      }
    }
  `;

  const buttons = css`
    .am-btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: var(--am-space-xs);
      font: inherit;
      font-size: var(--am-font-size-m);
      font-weight: var(--am-font-weight-medium);
      color: var(--am-text);
      background: var(--am-surface);
      border: 1px solid var(--am-border-strong);
      border-radius: var(--am-radius-m);
      padding: var(--am-space-xs) var(--am-space-l);
      min-height: 2.25rem;
      cursor: pointer;
      text-decoration: none;
      white-space: nowrap;
    }
    .am-btn:hover {
      background: var(--am-hover-tint);
    }
    .am-btn:active {
      border-color: var(--am-text-faint);
    }
    .am-btn[disabled] {
      opacity: 0.55;
      cursor: not-allowed;
    }
    .am-btn-primary {
      color: var(--am-on-primary);
      background: var(--am-primary);
      border-color: var(--am-primary);
    }
    .am-btn-primary:hover:not([disabled]) {
      background: var(--am-primary-hover);
      border-color: var(--am-primary-hover);
    }
    .am-btn-destructive {
      color: var(--am-on-destructive);
      background: var(--am-destructive);
      border-color: var(--am-destructive);
    }
    .am-btn-destructive:hover:not([disabled]) {
      background: var(--am-destructive-hover);
      border-color: var(--am-destructive-hover);
    }
    .am-btn-quiet {
      color: var(--am-primary);
      background: transparent;
      border-color: transparent;
    }
    .am-btn-quiet:hover:not([disabled]) {
      background: var(--am-primary-subtle);
    }
    .am-btn-quiet.am-btn-danger {
      color: var(--am-destructive);
    }
    .am-btn-quiet.am-btn-danger:hover:not([disabled]) {
      background: var(--am-destructive-subtle);
    }
    .am-btn-sm {
      font-size: var(--am-font-size-s);
      min-height: 1.75rem;
      padding: var(--am-space-2xs) var(--am-space-s);
      border-radius: var(--am-radius-s);
    }
    .am-spinner {
      width: 1em;
      height: 1em;
      border-radius: 50%;
      border: 2px solid currentColor;
      border-right-color: transparent;
      animation: am-spin 0.7s linear infinite;
      flex: none;
    }
    @keyframes am-spin {
      to {
        transform: rotate(360deg);
      }
    }
  `;

  // Read-only content vocabulary shared by the DataGrid cells and
  // FieldDisplay values: reference links, status pills, identifiers and
  // markdown-ish lists. Every color/line/radius is a token.
  const content = css`
    .am-link {
      font: inherit;
      font-weight: var(--am-font-weight-medium);
      color: var(--am-link);
      background: none;
      border: 0;
      padding: 0;
      margin: 0;
      cursor: pointer;
      text-align: inherit;
      text-decoration: underline;
      text-decoration-thickness: var(--am-border-width);
      text-underline-offset: 0.2em;
    }
    .am-link:hover {
      color: var(--am-link-hover);
    }
    .am-links {
      display: inline-flex;
      flex-wrap: wrap;
      gap: var(--am-space-2xs) var(--am-space-s);
    }
    .am-badge {
      display: inline-flex;
      align-items: center;
      width: fit-content;
      padding: 0.0625rem var(--am-space-s);
      border: var(--am-border-width) solid var(--am-badge-border);
      border-radius: var(--am-badge-radius);
      font-size: var(--am-font-size-xs);
      font-weight: var(--am-font-weight-semibold);
      line-height: var(--am-line-height-body);
      white-space: nowrap;
      background: var(--ash-admin-badge-neutral-background, var(--am-surface-sunken));
      color: var(--ash-admin-badge-neutral-text, var(--am-text));
    }
    .am-badge[data-tone="info"] {
      background: var(--ash-admin-badge-info-background, var(--am-primary-subtle));
      color: var(--ash-admin-badge-info-text, var(--am-primary));
    }
    .am-badge[data-tone="success"] {
      background: var(--ash-admin-badge-success-background, var(--am-success-subtle));
      color: var(--ash-admin-badge-success-text, var(--am-success));
    }
    .am-badge[data-tone="warning"] {
      background: var(--ash-admin-badge-warning-background, var(--am-warning-subtle));
      color: var(--ash-admin-badge-warning-text, var(--am-warning));
    }
    .am-badge[data-tone="danger"] {
      background: var(--ash-admin-badge-danger-background, var(--am-error-subtle));
      color: var(--ash-admin-badge-danger-text, var(--am-error));
    }
    .am-badge[data-tone="accent"] {
      background: var(--ash-admin-badge-accent-background, var(--am-primary));
      color: var(--ash-admin-badge-accent-text, var(--am-on-primary));
    }
    /* 1.8 column cells: a second line, a leading icon, a "+N more" tag
     * and a detail line, all tokens. */
    .am-cell {
      display: inline-flex;
      flex-direction: column;
      gap: var(--am-space-2xs);
      min-width: 0;
    }
    .am-cell-line {
      display: inline-flex;
      align-items: center;
      flex-wrap: wrap;
      gap: var(--am-space-xs);
    }
    .am-cell-icon {
      flex: none;
      color: var(--am-text-muted);
    }
    .am-cell-icon[data-tone="info"] {
      color: var(--am-primary);
    }
    .am-cell-icon[data-tone="success"] {
      color: var(--am-success);
    }
    .am-cell-icon[data-tone="warning"] {
      color: var(--am-warning);
    }
    .am-cell-icon[data-tone="danger"] {
      color: var(--am-error);
    }
    .am-cell-icon[data-tone="accent"] {
      color: var(--am-primary);
    }
    .am-cell-sub,
    .am-cell-detail {
      font-size: var(--am-font-size-xs);
      color: var(--am-text-muted);
    }
    .am-mono {
      font-family: var(--am-font-mono);
      font-size: 0.92em;
    }
    .am-list {
      margin: 0;
      padding-inline-start: 1.15em;
    }
    .am-list li + li {
      margin-top: var(--am-space-2xs);
    }
    .am-multiline {
      white-space: pre-line;
    }
  `;

  return {shared, buttons, content};
}

/** The badge tone vocabulary (row_layout `badge_tones`). */
export const BADGE_TONES = ["neutral", "info", "success", "warning", "danger", "accent"];

/**
 * The data grid's cell icons (catalog 1.8 column `icon`): each generic name
 * as stroke paths on a 20px grid. A renderer with its own icon set maps the
 * same names onto it.
 */
export const CELL_ICONS = {
  check: ["M4 10.5l4 4 8-9"],
  x: ["M5 5l10 10", "M15 5L5 15"],
  user_check: ["M8 3.5a3 3 0 1 0 0 6 3 3 0 0 0 0-6z", "M2.5 16.5a5.5 5.5 0 0 1 11 0", "M13.5 9.5l1.75 1.75L18.5 8"],
  user_x: ["M8 3.5a3 3 0 1 0 0 6 3 3 0 0 0 0-6z", "M2.5 16.5a5.5 5.5 0 0 1 11 0", "M14 8l4 4", "M18 8l-4 4"],
  alert: ["M10 3.5l7 12.5H3l7-12.5z", "M10 8.5v3", "M10 14v.01"],
  clock: ["M10 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14z", "M10 6.5V10l2.5 1.5"],
  info: ["M10 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14z", "M10 9v5", "M10 6.5v.01"],
};

/** The cell icon for a row's `_icon_<column>` value, or null for none. */
export function cellIcon(name) {
  return typeof name === "string" && Object.hasOwn(CELL_ICONS, name) ? CELL_ICONS[name] : null;
}

/** How many values a "+N more" tag counts: the rest after the first, or 0
 * when the cell holds one value or none (`more` binds a count). */
export function moreCount(count) {
  const n = typeof count === "string" ? Number(count) : count;
  return Number.isInteger(n) && n >= 2 ? n - 1 : 0;
}

/** A row's detail line: the served text (`_detail_<column>`) with
 * `{date}` replaced by the date formatted for the reader, or "" when the
 * row has no detail. A missing date leaves no dangling placeholder. */
export function detailText(text, date) {
  if (typeof text !== "string" || text === "") return "";
  if (!text.includes("{date}")) return text;
  const formatted = date === null || date === undefined || date === "" ? "" : formatDisplayValue(date, "datetime");
  return text.replaceAll("{date}", formatted).replace(/[\s·:,-]+$/u, "").trim();
}

/** A badge tone value from the row (`_badge_tone_<field>`), constrained to
 * the vocabulary — anything else is "neutral". */
export function badgeTone(tone) {
  return BADGE_TONES.includes(tone) ? tone : "neutral";
}

/**
 * Normalizes a bound link value into a list of link objects
 * (`{surface, recordId, label, href?}`) — a single link, a list of links,
 * or nothing (absent → []). Entries without a surface are dropped.
 */
export function linkEntries(value) {
  const list = Array.isArray(value) ? value : value ? [value] : [];
  return list.filter(
    (entry) => entry && typeof entry === "object" && typeof entry.surface === "string" && entry.surface !== "",
  );
}

const BULLET = /^\s*(?:[-*\u2022]|\d+[.)])\s+/;

/**
 * Markdown-ish list detection for read-only text: an array renders as its
 * items; multi-line text whose non-empty lines are all bulleted (`-`, `*`,
 * `•`, `1.`) renders as those lines without their markers. Anything else is
 * not a list (`null`).
 */
export function listItems(value) {
  if (Array.isArray(value)) {
    const items = value
      .filter((item) => item !== null && item !== undefined && item !== "")
      .map((item) => (typeof item === "object" ? item.label ?? JSON.stringify(item) : String(item)));
    return items.length > 0 ? items : null;
  }
  if (typeof value !== "string" || !value.includes("\n")) return null;
  const lines = value.split(/\r?\n/).filter((line) => line.trim() !== "");
  if (lines.length < 2 || !lines.every((line) => BULLET.test(line))) return null;
  return lines.map((line) => line.replace(BULLET, "").trim());
}

/** Windowed page list: 1 … (p-s..p+s) … N, with "…" only where pages are skipped. */
export function pageWindow(page, totalPages, siblings = 1) {
  const total = Math.max(1, totalPages);
  const current = Math.min(Math.max(1, page), total);
  const pages = new Set([1, total, current]);
  for (let index = current - siblings; index <= current + siblings; index++) {
    if (index >= 1 && index <= total) pages.add(index);
  }
  const sorted = [...pages].sort((a, b) => a - b);
  const windowed = [];
  sorted.forEach((value, index) => {
    if (index > 0 && value - sorted[index - 1] > 1) windowed.push("…");
    windowed.push(value);
  });
  return windowed;
}

/**
 * Resolves an A2UI data binding leaf (`{"path": ...}`) against the surface
 * data model. Relative paths resolve under `basePath` (a row's template
 * scope); absolute paths resolve as-is; non-binding values pass through —
 * matching the GenericBinder's action-context resolution semantics, which is
 * exactly how the basic catalog's buttons resolve their envelopes.
 *
 * Used by the admin components that dispatch envelopes they received as raw
 * props (DataGrid row actions) or reconstructed (ActionBar submit, Pagination
 * page turns): `surface.dispatchAction` expects resolved context values.
 */
export function resolveEventContext(value, dataModel, basePath) {
  if (value === null || typeof value !== "object") return value;
  if (typeof value.path === "string" && Object.keys(value).length === 1) {
    const abs = value.path.startsWith("/")
      ? value.path
      : `${basePath.replace(/\/$/, "")}/${value.path}`;
    return dataModel.get(abs);
  }
  if (Array.isArray(value)) return value.map((v) => resolveEventContext(v, dataModel, basePath));
  const out = {};
  for (const [k, v] of Object.entries(value)) out[k] = resolveEventContext(v, dataModel, basePath);
  return out;
}

/**
 * Reads a possibly-nested property out of a row object using a "/"-separated
 * relative path ("id", "patient/name", …). Missing keys resolve to undefined.
 */
export function getByPath(obj, path) {
  if (obj === null || obj === undefined) return undefined;
  let current = obj;
  for (const segment of String(path).split("/")) {
    if (current === null || typeof current !== "object") return undefined;
    current = current[segment];
  }
  return current;
}

const numberFormatter = new Intl.NumberFormat(undefined, {maximumFractionDigits: 4});
let dateFormatter = null;
let dateTimeFormatter = null;

function dateFormatters() {
  if (!dateFormatter) {
    dateFormatter = new Intl.DateTimeFormat(undefined, {dateStyle: "medium"});
    dateTimeFormatter = new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short",
    });
  }
  return {dateFormatter, dateTimeFormatter};
}

/**
 * Formats a FieldDisplay (or DataGrid cell) value for read-only typography.
 *
 * @param {*} value the raw bound value
 * @param {string} [format] "text" | "datetime" | "boolean" | "number"
 * @returns {string} the display string ("—" for empty values)
 */
export function formatDisplayValue(value, format) {
  if (value === null || value === undefined || value === "") return "—";

  switch (format) {
    case "boolean":
      if (typeof value === "boolean") return value ? "Yes" : "No";
      if (value === "true") return "Yes";
      if (value === "false") return "No";
      return String(value);
    case "number":
      if (typeof value === "number" && Number.isFinite(value)) {
        return numberFormatter.format(value);
      }
      if (typeof value === "string" && value.trim() !== "" && Number.isFinite(Number(value))) {
        return numberFormatter.format(Number(value));
      }
      return String(value);
    case "datetime": {
      const text = String(value);
      const hasTime = text.includes("T") && /[:0-9]/.test(text.split("T")[1] || "");
      // Date-only strings must not travel through the UTC-to-local
      // conversion (a plain Date would shift the calendar day in negative
      // offsets); datetime strings keep normal parsing.
      if (!hasTime) {
        const dateOnly = /^(?:\d{4}-\d{2}-\d{2})$/.exec(text.trim());
        if (dateOnly) {
          const [year, month, day] = text.split("-").map(Number);
          const {dateFormatter: d} = dateFormatters();
          return d.format(new Date(Date.UTC(year, month - 1, day)));
        }
      }
      const parsed = new Date(text);
      if (Number.isNaN(parsed.getTime())) return text;
      const {dateFormatter: d, dateTimeFormatter: dt} = dateFormatters();
      return hasTime ? dt.format(parsed) : d.format(parsed);
    }
    case "text":
    default: {
      if (typeof value === "boolean") return value ? "Yes" : "No";
      if (typeof value === "number") return numberFormatter.format(value);
      if (typeof value === "object") {
        try {
          return JSON.stringify(value);
        } catch {
          return String(value);
        }
      }
      return String(value);
    }
  }
}

/**
 * Applies the A2UI layout `weight` prop as flex-grow, mirroring the basic
 * catalog's shared base class (which is not part of @a2ui/lit's public
 * exports).
 */
export function applyWeight(el, props) {
  if (props && props.weight !== undefined) {
    el.style.flex = String(props.weight);
  } else {
    el.style.removeProperty("flex");
  }
}

/**
 * Normalizes a resolved `children` prop (ChildList binding) into an array of
 * `{id, basePath}` refs. Accepts the binder's array-of-string form too.
 */
export function childRefs(children) {
  if (!Array.isArray(children)) return [];
  return children
    .map((child) => {
      if (typeof child === "string") return {id: child, basePath: null};
      if (child && typeof child === "object" && typeof child.id === "string") {
        return {id: child.id, basePath: child.basePath || null};
      }
      return null;
    })
    .filter(Boolean);
}
