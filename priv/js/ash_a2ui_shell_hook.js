// AshA2uiShell — the keyboard half of AshA2ui.Shell.Component.
//
// The server owns the shell: what is listed, what is highlighted, what a
// line runs. This hook only turns keys into the component's events:
//
//   * a key in the component's key table (data-keys, from
//     AshA2ui.Shell.keys/0) opens it in that mode, from anywhere on the page.
//     On a Mac, cmd stands in for ctrl;
//   * while it is open, the arrows move the highlight and escape closes it
//     (enter submits the form);
//   * a window "ash_a2ui:shell" event ({detail: {mode}}) opens it too, which
//     is what AshA2ui.Shell.Component.open/1 dispatches from a button.
//
// It focuses the input when the shell opens and gives focus back to where it
// was when the shell closes. No dependencies.

function keyLabel(event, ctrl) {
  const parts = []
  if (ctrl) parts.push("ctrl")
  if (event.altKey) parts.push("alt")
  if (event.shiftKey) parts.push("shift")
  parts.push((event.key || "").toLowerCase())
  return parts.join("+")
}

export const AshA2uiShell = {
  mounted() {
    this.onKey = (event) => this.handleKey(event)
    this.onOpen = (event) => {
      const mode = (event.detail && event.detail.mode) || "palette"
      this.openShell(mode)
    }
    // Capture, so a focused input's own handling (ctrl+k deletes to the end
    // of a line in some fields) never sees the key first.
    window.addEventListener("keydown", this.onKey, true)
    window.addEventListener("ash_a2ui:shell", this.onOpen)
    this.handleEvent("ash_a2ui:shell:input", ({value}) => {
      const input = this.input()
      if (input) {
        input.value = value
        input.focus()
        input.setSelectionRange(value.length, value.length)
      }
    })
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKey, true)
    window.removeEventListener("ash_a2ui:shell", this.onOpen)
  },

  updated() {
    if (this.isOpen()) {
      const input = this.input()
      if (input && document.activeElement !== input) input.focus()
      const active = this.el.querySelector('[data-shell-item][aria-selected="true"]')
      if (active && active.scrollIntoView) active.scrollIntoView({block: "nearest"})
    } else if (this.returnFocus) {
      const target = this.returnFocus
      this.returnFocus = null
      if (document.contains(target) && target.focus) target.focus()
    }
  },

  isOpen() {
    return this.el.dataset.open === "true"
  },

  input() {
    return this.el.querySelector("input[name=query]")
  },

  keys() {
    try {
      return JSON.parse(this.el.dataset.keys || "{}")
    } catch (_error) {
      return {}
    }
  },

  openShell(mode) {
    if (!this.isOpen()) this.returnFocus = document.activeElement
    this.pushEventTo(this.el, "shell:open", {mode})
  },

  handleKey(event) {
    const keys = this.keys()
    const mode =
      keys[keyLabel(event, event.ctrlKey)] ||
      (event.metaKey && !event.ctrlKey ? keys[keyLabel(event, true)] : undefined)

    if (mode && (event.ctrlKey || event.metaKey)) {
      event.preventDefault()
      event.stopPropagation()
      this.openShell(mode)
      return
    }

    if (!this.isOpen()) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.pushEventTo(this.el, "shell:close", {})
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      this.pushEventTo(this.el, "shell:move", {by: event.key === "ArrowDown" ? 1 : -1})
    }
  }
}

export default AshA2uiShell
