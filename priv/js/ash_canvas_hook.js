/**
 * AshCanvas LiveView hook — the thin bridge between the `/canvas`
 * LiveView and the `<ash-canvas-graph>` element.
 *
 * Wiring (see docs/plans/2026-09-09-canvas-host-contract.md — names are
 * pinned; import ash_canvas_graph.js alongside so its side effect
 * registers the custom element):
 *
 *   - Server → client (once on mount): the LiveView pushes
 *     `canvas:graph` with `%{"revision" => ..., "nodes" => [...],
 *     "edges" => [...]}` (the JSON form of AshA2ui.Canvas.Graph). The
 *     hook hydrates the element via its `graph` property.
 *   - Client → server: the element dispatches a bubbling, composed
 *     `ash-canvas:select` CustomEvent (`detail.ref` = the node id); the
 *     hook forwards it as `pushEvent("canvas:select", {ref})`. Keeping
 *     the element's outbound contract a plain DOM event makes the element
 *     LiveView-agnostic (and testable outside a socket).
 *
 * The LiveView renders an empty container (`phx-update="ignore"` keeps
 * the created element across re-renders), so the hook creates the
 * element. It owns nothing else: selection semantics, keyboard model,
 * layout and styling all live in the element (ash_canvas_graph.js); the
 * element's teardown removes these listeners with the container.
 */

export const AshCanvas = {
  mounted() {
    const graphEl = document.createElement("ash-canvas-graph");
    this.el.appendChild(graphEl);

    this.handleEvent("canvas:graph", (graph) => {
      graphEl.graph = graph;
    });

    graphEl.addEventListener("ash-canvas:select", (event) => {
      const ref = event?.detail?.ref;
      if (typeof ref === "string" && ref !== "") this.pushEvent("canvas:select", {ref});
    });
  },
};

export default AshCanvas;
