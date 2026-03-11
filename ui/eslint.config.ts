import pluginVue from "eslint-plugin-vue"
import pluginTypeScript from "typescript-eslint"
import parserVue from "vue-eslint-parser"

export default [
    {
        ignores: [
            "dist/**",
            "node_modules/**",
            "*.d.ts",
            "src/components/ui/**",
        ],
    },

    ...pluginTypeScript.configs.recommended,

    ...pluginVue.configs["flat/recommended"],

    {
        files: ["src/**/*.vue"],
        languageOptions: {
            parser: parserVue,
            parserOptions: {
                parser: pluginTypeScript.parser,
                sourceType: "module",
            },
        },
    },

    {
        files: ["src/**/*.{ts,vue}"],
        rules: {
            // TypeScript
            "@typescript-eslint/no-explicit-any": "warn",
            "@typescript-eslint/no-unused-vars": ["warn", {
                argsIgnorePattern: "^_",
                varsIgnorePattern: "^_",
            }],

            // Vue: Composition API
            "vue/component-api-style": ["error", ["script-setup"]],
            "vue/define-macros-order": ["error", {
                order: ["defineProps", "defineEmits", "defineModel", "defineSlots"],
            }],
            "vue/block-order": ["error", {
                order: ["script", "template", "style"],
            }],

            // Vue: Template
            "vue/html-indent": ["error", 4],
            "vue/script-indent": ["error", 4, { baseIndent: 0 }],
            "vue/max-attributes-per-line": ["error", {
                singleline: { max: 3 },
                multiline: { max: 1 },
            }],
            "vue/first-attribute-linebreak": ["error", {
                singleline: "beside",
                multiline: "below",
            }],
            "vue/html-closing-bracket-newline": ["error", {
                singleline: "never",
                multiline: "always",
            }],
            "vue/html-self-closing": ["error", {
                html: { void: "always", normal: "always", component: "always" },
                svg: "always",
                math: "always",
            }],
            "vue/no-v-html": "warn",
            "vue/require-default-prop": "off",
            "vue/multi-word-component-names": "off",

            // Vue: Best practices
            "vue/no-unused-refs": "warn",
            "vue/no-useless-v-bind": "warn",
            "vue/prefer-true-attribute-shorthand": "warn",
            "vue/prefer-separate-static-class": "warn",
            "vue/no-static-inline-styles": "warn",
            "vue/eqeqeq": "error",
            "vue/no-constant-condition": "warn",
            "vue/require-typed-ref": "warn",
            "vue/singleline-html-element-content-newline": "off",
            "vue/attributes-order": "off",
        },
    },
]
