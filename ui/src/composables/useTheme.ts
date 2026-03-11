import { ref, watchEffect } from "vue"

type Theme = "light" | "dark"

const theme = ref<Theme>((localStorage.getItem("forgecast_theme") as Theme) ?? "dark")

watchEffect(() => {
    const root = document.documentElement
    root.classList.toggle("dark", theme.value === "dark")
    localStorage.setItem("forgecast_theme", theme.value)
})

export function useTheme() {
    function toggle() {
        theme.value = theme.value === "dark" ? "light" : "dark"
    }

    return { theme, toggle }
}
