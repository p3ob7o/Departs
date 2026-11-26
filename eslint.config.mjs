import js from "@eslint/js";
import ts from "typescript-eslint";
import { defineConfig } from "eslint/config";

export default defineConfig([
  js.configs.recommended,
  {
    files: ["**/*.ts"],
    extends: [ts.configs.recommended],
    languageOptions: { parserOptions: { projectService: true } },
    rules: { "@typescript-eslint/await-thenable": "error" },
  },
]);
