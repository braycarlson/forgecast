import { ref, watch, readonly } from "vue"
import { useAuth } from "@/composables/useAuth"

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4000/api"

const favoriteLanguages = ref<Set<string>>(new Set())
const favoritePlatforms = ref<Set<string>>(new Set())
const loaded = ref(false)

function loadLocal(key: string): Set<string> {
    try {
        const raw = localStorage.getItem(`forgecast_fav_${key}`)
        if (raw) return new Set(JSON.parse(raw) as string[])
    } catch { /* ignored */ }
    return new Set()
}

function saveLocal(key: string, set: Set<string>) {
    localStorage.setItem(`forgecast_fav_${key}`, JSON.stringify([...set]))
}

async function fetchRemote(key: string): Promise<Set<string>> {
    try {
        const res = await fetch(`${API_URL}/preferences/favorite_${key}`, {
            credentials: "include",
        })

        if (!res.ok) return new Set()
        const data = await res.json()
        const items = data.value?.items
        if (Array.isArray(items)) return new Set(items as string[])
    } catch { /* ignored */ }
    return new Set()
}

async function saveRemote(key: string, set: Set<string>) {
    try {
        await fetch(`${API_URL}/preferences/favorite_${key}`, {
            method: "PUT",
            credentials: "include",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ value: { items: [...set] } }),
        })
    } catch { /* ignored */ }
}

async function load() {
    const { user } = useAuth()

    if (user.value) {
        const [langs, plats] = await Promise.all([
            fetchRemote("languages"),
            fetchRemote("platforms"),
        ])

        favoriteLanguages.value = langs.size > 0 ? langs : loadLocal("languages")
        favoritePlatforms.value = plats.size > 0 ? plats : loadLocal("platforms")

        // Migrate localStorage to remote if remote was empty
        if (langs.size === 0 && favoriteLanguages.value.size > 0) {
            saveRemote("languages", favoriteLanguages.value)
        }
        if (plats.size === 0 && favoritePlatforms.value.size > 0) {
            saveRemote("platforms", favoritePlatforms.value)
        }
    } else {
        favoriteLanguages.value = loadLocal("languages")
        favoritePlatforms.value = loadLocal("platforms")
    }

    loaded.value = true
}

function toggleFavoriteLanguage(language: string) {
    const next = new Set(favoriteLanguages.value)
    if (next.has(language)) next.delete(language)
    else next.add(language)
    favoriteLanguages.value = next
    persist("languages", next)
}

function toggleFavoritePlatform(platform: string) {
    const next = new Set(favoritePlatforms.value)
    if (next.has(platform)) next.delete(platform)
    else next.add(platform)
    favoritePlatforms.value = next
    persist("platforms", next)
}

function persist(key: string, set: Set<string>) {
    saveLocal(key, set)

    const { user } = useAuth()
    if (user.value) {
        saveRemote(key, set)
    }
}

export function usePreferences() {
    const { user, loading: authLoading, onLogout } = useAuth()

    if (!loaded.value) {
        // Load once auth resolves
        if (!authLoading.value) {
            load()
        } else {
            const stop = watch(authLoading, (isLoading) => {
                if (!isLoading) {
                    stop()
                    load()
                }
            })
        }
    }

    // Reload when user logs in
    watch(user, (newUser) => {
        if (newUser) {
            loaded.value = false
            load()
        }
    })

    // Clear favorites on logout
    onLogout(() => {
        favoriteLanguages.value = new Set()
        favoritePlatforms.value = new Set()
        localStorage.removeItem("forgecast_fav_languages")
        localStorage.removeItem("forgecast_fav_platforms")
        loaded.value = false
    })

    return {
        favoriteLanguages: readonly(favoriteLanguages),
        favoritePlatforms: readonly(favoritePlatforms),
        toggleFavoriteLanguage,
        toggleFavoritePlatform,
        loaded: readonly(loaded),
    }
}
