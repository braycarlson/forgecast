import { ref, readonly } from "vue"

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4000/api"

export interface User {
    id: number
    username: string
    display_name: string | null
    avatar_url: string | null
}

const user = ref<User | null>(null)
const loading = ref(true)

let fetched = false

async function fetchUser() {
    if (fetched) return
    fetched = true
    loading.value = true

    try {
        const res = await fetch(`${API_URL}/auth/me`, { credentials: "include" })
        const data = await res.json()
        user.value = data.user ?? null
    } catch {
        user.value = null
    } finally {
        loading.value = false
    }
}

function login() {
    window.location.href = `${API_URL}/auth/github`
}

const logoutCallbacks: Array<() => void> = []

function onLogout(cb: () => void) {
    logoutCallbacks.push(cb)
}

async function logout() {
    try {
        await fetch(`${API_URL}/auth/logout`, {
            method: "POST",
            credentials: "include",
        })
    } catch { /* ignored */ }

    user.value = null
    fetched = false

    for (const cb of logoutCallbacks) {
        cb()
    }
}

export function useAuth() {
    fetchUser()

    return {
        user: readonly(user),
        loading: readonly(loading),
        login,
        logout,
        onLogout,
    }
}
