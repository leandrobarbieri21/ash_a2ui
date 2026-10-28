// `validate-color` (an @a2ui/web_core 0.12+ dependency) ships only CommonJS,
// which an import map cannot load. web_core calls it only where there is no
// `CSS.supports`, which a browser always has, so the probes map it here.
export default function validateColor() {
  return false;
}
