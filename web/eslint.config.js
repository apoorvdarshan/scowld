import js from "@eslint/js";
import globals from "globals";

export default [
  js.configs.recommended,
  {
    files: ["src/**/*.js"],
    // Workers runtime globals that aren't part of the service worker set.
    languageOptions: { globals: { ...globals.serviceworker, WebSocketPair: "readonly" } },
  },
  {
    files: ["public/assets/**/*.js"],
    languageOptions: { globals: globals.browser, sourceType: "script" },
  },
  {
    files: ["scripts/**/*.js", "tests/**/*.js", "*.config.js"],
    languageOptions: { globals: globals.node },
  },
];
