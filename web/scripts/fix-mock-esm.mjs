/**
 * tsc emits extensionless relative imports, which Node's ESM loader will not
 * resolve. Rewrites them in the throwaway .mocktest build so the mock router
 * can be exercised directly by node --test.
 */
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

function walk(dir) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full);
    else if (full.endsWith(".js")) {
      const src = readFileSync(full, "utf8");
      const out = src.replace(/from "(\.[^"]*?)"/g, (m, spec) =>
        spec.endsWith(".js") ? m : `from "${spec}.js"`);
      if (out !== src) writeFileSync(full, out);
    }
  }
}

walk(".mocktest");
