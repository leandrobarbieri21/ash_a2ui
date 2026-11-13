// The @a2ui/web_core runtime the node tests drive the hook with: the package
// pinned in test/js/package.json (`npm ci --prefix test/js`), or the package
// directory A2UI_WEB_CORE_DIR names (an upstream build, say).

import {existsSync, readFileSync} from "node:fs";
import {dirname, join, resolve} from "node:path";
import {fileURLToPath, pathToFileURL} from "node:url";

const here = dirname(fileURLToPath(import.meta.url));

export const repoRoot = resolve(here, "../..");

export const webCoreDir = process.env.A2UI_WEB_CORE_DIR
  ? resolve(process.env.A2UI_WEB_CORE_DIR)
  : join(here, "node_modules/@a2ui/web_core");

if (!existsSync(join(webCoreDir, "src/index.js"))) {
  throw new Error(
    `No @a2ui/web_core at ${webCoreDir}. Run \`npm ci --prefix test/js\` ` +
      "(or set A2UI_WEB_CORE_DIR to a web_core package directory).",
  );
}

const load = (sub) => import(pathToFileURL(join(webCoreDir, sub)).href);

export const webCore = await load("src/index.js");
export const {basicCatalog} = await load("src/catalogs/basic/v1/index.js");
export const webCoreVersion = JSON.parse(
  readFileSync(join(webCoreDir, "package.json"), "utf8"),
).version;

export const BASIC_CATALOG_ID = basicCatalog.id;

export function readJson(path) {
  return JSON.parse(readFileSync(join(repoRoot, path), "utf8"));
}

// Whether this web_core accepts the `@`-prefixed component envelope keys of
// spec HEAD (`@checks`, `@accessibility`, ...). 0.15.0 rejects them and drops
// the whole surface; the contract fixtures need them.
export function acceptsEnvelopeKeys() {
  const processor = new webCore.MessageProcessor([basicCatalog]);
  const errors = processor.processMessagesWithErrors([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "probe",
        catalogId: BASIC_CATALOG_ID,
        components: [{id: "root", component: "Text", text: "x", "@accessibility": {label: "x"}}],
      },
    },
  ]);
  processor.dispose();
  return errors.length === 0;
}
