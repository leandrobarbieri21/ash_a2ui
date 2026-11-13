// A browser stand-in for the catalog tests: happy-dom's window installed on
// globalThis before lit or @a2ui/lit load. Import this module first.

import {GlobalRegistrator} from "@happy-dom/global-registrator";

if (!globalThis.window || !globalThis.customElements)
  GlobalRegistrator.register({url: "http://localhost/"});
