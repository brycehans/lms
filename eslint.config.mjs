// Flat config for ESLint 9. eslint-config-next 16 ships native flat-config
// arrays (its subpath exports default-export arrays), so we spread them directly
// — the old FlatCompat("next/core-web-vitals", "next/typescript") shim is what
// broke ESLint 9 (the legacy eslintrc loader can't validate the flat plugin
// objects). Keep eslint-config-next pinned in lockstep with `next`.
import nextCoreWebVitals from "eslint-config-next/core-web-vitals";
import nextTypescript from "eslint-config-next/typescript";

const eslintConfig = [
  { ignores: [".next/**", "node_modules/**", "out/**", "next-env.d.ts"] },
  ...nextCoreWebVitals,
  ...nextTypescript,
  {
    // Next 16's flat config newly enables React-Compiler lints as errors. They
    // fire on intentional, correct patterns here — the next-themes client-mount
    // gate (setState in an empty-dep effect), setting a "loading" status before
    // an async fetch, and reading `Date.now()` during a Server Component render
    // (which runs once server-side). Refactoring around opinionated stylistic
    // lints isn't worth the regression risk, so keep them as warnings (visible,
    // non-blocking) rather than build-breaking errors.
    rules: {
      "react-hooks/purity": "warn",
      "react-hooks/set-state-in-effect": "warn",
    },
  },
];

export default eslintConfig;
