/**
 * Apply-on-change probe: the merged catalog Button's `apply_on_change`
 * watch, run against @a2ui/web_core's real DataModel (no browser).
 *
 *   node priv/js/probe/auto_apply_probe.mjs [--node-modules DIR]
 *
 * Asserts that an Apply button (the `query` event, `page: 1`) on a query
 * whose state carries `autoApply`:
 *   - is configured only when `autoApply` is present, and never for a pager
 *     button (`pageDelta`);
 *   - sends its envelope once, at once, when a filter or the preset changes;
 *   - sends it once, `debounceMs` after the last keystroke, for search;
 *   - does not send it again when the server writes the applied values
 *     back, nor on a write replacing the whole data model;
 *   - does nothing on a query without `autoApply`.
 */

import {dirname, join, resolve} from "node:path";
import {fileURLToPath, pathToFileURL} from "node:url";

const probeDir = dirname(fileURLToPath(import.meta.url));
const repoPrivJs = resolve(probeDir, "..");
const args = process.argv.slice(2);
const index = args.indexOf("--node-modules");
const nodeModules =
  index !== -1 ? args[index + 1] : join(repoPrivJs, "../../../clinic-demo/assets/node_modules");

const {DataModel} = await import(
  pathToFileURL(join(nodeModules, "@a2ui/web_core/src/v0_9/state/data-model.js")).href
);
const {autoApplyConfig, watchAutoApply, unwatchAutoApply} = await import(
  pathToFileURL(join(repoPrivJs, "ash_a2ui_catalog.js")).href
);

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const failures = [];
const results = [];

async function check(label, fn) {
  try {
    await fn();
    results.push(`ok    ${label}`);
  } catch (error) {
    failures.push(`FAIL  ${label}: ${error.message}`);
  }
}

function assertEqual(actual, expected, what) {
  if (actual !== expected) throw new Error(`${what}: expected ${expected}, got ${actual}`);
}

function queryState(extra = {}) {
  return {
    search: "",
    filters: {status: ""},
    preset: "",
    sort: null,
    page: 1,
    pageSize: 25,
    totalCount: 0,
    hasMore: false,
    ...extra,
  };
}

// A stand-in for the Button element: the seams the watch reads.
function button(dataModel, eventContext = {page: 1, query: {path: "/query"}}) {
  const element = {
    sent: 0,
    updates: 0,
    context: {
      componentModel: {properties: {action: {event: {name: "query", context: eventContext}}}},
      dataContext: {surface: {dataModel}},
    },
    controller: {props: {action: () => element.sent++}},
    requestUpdate: () => element.updates++,
  };
  return element;
}

const AUTO = {debounceMs: 40};

await check("configured only with autoApply, never for a pager button", async () => {
  const plain = new DataModel({query: queryState()});
  assertEqual(autoApplyConfig(button(plain)), null, "plain query");

  const auto = new DataModel({query: queryState({autoApply: AUTO})});
  assertEqual(autoApplyConfig(button(auto))?.debounceMs, 40, "autoApply query");

  const pager = button(auto, {pageDelta: 1, query: {path: "/query"}});
  assertEqual(autoApplyConfig(pager), null, "pager button");
});

await check("a filter change applies at once, the server's write-back does not", async () => {
  const dataModel = new DataModel({query: queryState({autoApply: AUTO})});
  const element = button(dataModel);
  watchAutoApply(element);

  dataModel.set("/query/filters/status", "open");
  await sleep(5);
  assertEqual(element.sent, 1, "sends after the pick");

  // The reply: the same values, a new page count.
  dataModel.set("/query", queryState({autoApply: AUTO, filters: {status: "open"}, totalCount: 3}));
  await sleep(5);
  assertEqual(element.sent, 1, "no send on the write-back");
  unwatchAutoApply(element);
});

await check("the preset applies at once", async () => {
  const dataModel = new DataModel({query: queryState({autoApply: AUTO})});
  const element = button(dataModel);
  watchAutoApply(element);

  dataModel.set("/query/preset", "archived");
  await sleep(5);
  assertEqual(element.sent, 1, "sends after the pick");
  unwatchAutoApply(element);
});

await check("search applies once, after a pause in typing", async () => {
  const dataModel = new DataModel({query: queryState({autoApply: AUTO})});
  const element = button(dataModel);
  watchAutoApply(element);

  for (const text of ["a", "ac", "acm", "acme"]) {
    dataModel.set("/query/search", text);
    await sleep(10);
  }
  assertEqual(element.sent, 0, "nothing while typing");
  await sleep(60);
  assertEqual(element.sent, 1, "one send after the pause");
  unwatchAutoApply(element);
});

await check("a write replacing the whole data model does not apply", async () => {
  const dataModel = new DataModel({query: queryState({autoApply: AUTO})});
  const element = button(dataModel);
  watchAutoApply(element);

  dataModel.set("/", {query: queryState({autoApply: AUTO, filters: {status: "closed"}})});
  await sleep(5);
  assertEqual(element.sent, 0, "no send on a root write");

  dataModel.set("/query/filters/status", "open");
  await sleep(5);
  assertEqual(element.sent, 1, "a later pick still applies");
  unwatchAutoApply(element);
});

await check("a query without autoApply never applies by itself", async () => {
  const dataModel = new DataModel({query: queryState()});
  const element = button(dataModel);
  watchAutoApply(element);

  dataModel.set("/query/filters/status", "open");
  dataModel.set("/query/search", "acme");
  await sleep(60);
  assertEqual(element.sent, 0, "no send");
  unwatchAutoApply(element);
});

await check("a multi-table query path is watched on its own", async () => {
  const dataModel = new DataModel({
    query: {table: queryState({autoApply: AUTO}), other: queryState()},
  });
  const element = button(dataModel, {page: 1, component: "table", query: {path: "/query/table"}});
  watchAutoApply(element);

  dataModel.set("/query/other/filters/status", "open");
  await sleep(5);
  assertEqual(element.sent, 0, "the other table's pick is not this one's");

  dataModel.set("/query/table/filters/status", "open");
  await sleep(5);
  assertEqual(element.sent, 1, "its own pick applies");
  unwatchAutoApply(element);
});

for (const line of [...results, ...failures]) console.log(line);
console.log(`${results.length} passed, ${failures.length} failed`);
process.exit(failures.length === 0 ? 0 : 1);
