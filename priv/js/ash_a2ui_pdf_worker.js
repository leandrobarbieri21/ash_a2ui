/**
 * pdf.js's worker, as an ES module served beside ash_a2ui_pdf.js (bundle
 * both as entry points into one directory; see that file). pdf.js starts it
 * as a module worker and parses each document in it, off the main thread.
 */
import "pdfjs-dist/build/pdf.worker.mjs";
