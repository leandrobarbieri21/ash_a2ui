// Builds the two shipped catalogs against the pinned @a2ui runtime, in
// happy-dom: the merged basic catalog (createAshA2uiCatalog) and the admin
// catalog over it (createAshAdminCatalog), as a host bundle would.

import {register} from "node:module";
import "./dom.mjs";

register("./resolve_hooks.mjs", import.meta.url);

const lit = await import("lit");
const {A2uiLitElement, A2uiController} = await import("@a2ui/lit");
const basic = await import("@a2ui/web_core/catalogs/basic/v1");
export const webCore = await import("@a2ui/web_core");

export const ashCatalog = await import("../../priv/js/ash_a2ui_catalog.js");
export const adminCatalog = await import("../../priv/js/ash_admin_catalog.js");

const deps = {
  basicCatalog: basic.basicCatalog,
  ChoicePickerApi: basic.ChoicePickerApi,
  ColumnApi: basic.ColumnApi,
  A2uiLitElement,
  A2uiController,
  lit: {html: lit.html, css: lit.css, nothing: lit.nothing},
};

export const basicCatalog = basic.basicCatalog;
export const mergedCatalog = ashCatalog.createAshA2uiCatalog(deps);
export const admin = adminCatalog.createAshAdminCatalog({...deps, basicCatalog: mergedCatalog});
