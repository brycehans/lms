import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

// The route handlers import via the `@/…` path alias (see tsconfig.json), so we
// mirror that here. Tests are Node-environment: the route handlers are plain
// request→response functions with the Supabase client mocked out, no DOM needed.
export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
  },
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./", import.meta.url)),
    },
  },
});
