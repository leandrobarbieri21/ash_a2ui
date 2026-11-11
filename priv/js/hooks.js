// The package's LiveView hooks, for hosts to register (see README).
// `events`: every event name the hook passes to handleEvent; a host that
// loads the hook lazily subscribes to these before the code arrives.
// `load`: fetches the hook's code and resolves to the hook object.
//
// No top-level imports: hosts import this on every page, so it must not
// pull in a hook's dependencies. AshA2ui and AshA2uiShell are not in here —
// hosts import them directly (ash_a2ui_hook.js / ash_a2ui_shell_hook.js)
// because they need configureAshA2ui first; see
// documentation/topics/rendering-clients.md.
export const hooks = {
  AshCanvas: {
    events: ["canvas:graph"],
    load: () =>
      Promise.all([
        import("./ash_canvas_hook.js"),
        import("./ash_canvas_graph.js"), // registers <ash-canvas-graph> as a side effect
      ]).then(([hook]) => hook.AshCanvas),
  },
};
