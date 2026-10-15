import js from "@eslint/js";
import globals from "globals";

export default [
  js.configs.recommended,
  {
    files: ["src/**/*.js"],
    languageOptions: { globals: globals.serviceworker },
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
