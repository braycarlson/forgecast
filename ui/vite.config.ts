import { fileURLToPath, URL } from "node:url"
import { defineConfig } from "vite"
import vue from "@vitejs/plugin-vue"
import tailwindcss from "@tailwindcss/vite"

export default defineConfig({
    plugins: [vue(), tailwindcss()],
    resolve: {
        alias: {
            "@": fileURLToPath(new URL("./src", import.meta.url)),
        },
    },
    server: {
        watch: {
            usePolling: true,
        },
        proxy: {
            "/api": {
                target: process.env.VITE_API_PROXY_TARGET || "http://localhost:4000",
                changeOrigin: true,
            },
        },
    },
})
