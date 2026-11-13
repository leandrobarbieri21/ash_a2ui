// Module resolution for the catalog tests: priv/js imports `@a2ui/...` as a
// host bundle would, and priv/js has no node_modules. A bare specifier node
// cannot resolve from there resolves from test/js instead.

const TEST_JS = new URL("./package.json", import.meta.url).href;

export async function resolve(specifier, context, next) {
  try {
    return await next(specifier, context);
  } catch (error) {
    const bare = !/^(\.|\/|[a-z]+:)/.test(specifier);
    if (error?.code !== "ERR_MODULE_NOT_FOUND" || !bare) throw error;
    return next(specifier, {...context, parentURL: TEST_JS});
  }
}
