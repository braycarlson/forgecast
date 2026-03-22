import { ref, watch, onMounted, onUnmounted } from "vue"
import { watchDebounced } from "@vueuse/core"
import type { SortingState } from "@tanstack/vue-table"
import type { Repo } from "@/types/repo"
import { useFilter } from "@/composables/useFilter"
import { usePagination } from "@/composables/usePagination"
import { useUrlSync } from "@/composables/useUrlSync"
import { usePreferences } from "@/composables/usePreferences"
import { useAuth } from "@/composables/useAuth"

type Layout = "list" | "grid" | "table"

interface TrendingResponse {
    items: Repo[]
    total: number
    total_pages: number
    page: number
    per_page: number
}

interface FiltersResponse {
    platforms: string[]
    languages: string[]
}

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4000/api"

export function useTrending() {
    const url = useUrlSync()

    const filters = useFilter(
        url.querySet("platform"),
        url.querySet("language"),
    )

    const preferences = usePreferences()
    const { onLogout } = useAuth()

    onLogout(() => {
        filters.clearPlatforms()
        filters.clearLanguages()
        searchQuery.value = ""
        sorting.value = []
        pagination.perPage.value = "12"
        timeWindow.value = "24"
        hideEmpty.value = true
        pagination.resetPage()
        url.clear()
        fetchRepos()
    })

    const pagination = usePagination(
        parseInt(url.queryString("page", "1"), 10),
        url.queryString("per_page", "12"),
    )

    let controller: AbortController | null = null

    const repos = ref<Repo[]>([])
    const loading = ref(true)
    const refreshing = ref(false)
    const error = ref<string | null>(null)

    const searchQuery = ref(url.queryString("search", ""))
    const layout = ref<Layout>(url.queryString("layout", "grid") as Layout)
    const timeWindow = ref(url.queryString("window", "24"))
    const sorting = ref<SortingState>(url.initialSorting())
    const hideEmpty = ref(url.queryString("hide_empty", "true") !== "false")

    const imageErrors = ref(new Set<number>())

    function syncUrl() {
        url.sync({
            selectedPlatforms: filters.selectedPlatforms.value,
            selectedLanguages: filters.selectedLanguages.value,
            searchQuery: searchQuery.value,
            currentPage: pagination.currentPage.value,
            perPage: pagination.perPage.value,
            timeWindow: timeWindow.value,
            layout: layout.value,
            sorting: sorting.value,
            hideEmpty: hideEmpty.value,
        })
    }

    function onImageError(repoId: number) {
        const next = new Set(imageErrors.value)
        next.add(repoId)
        imageErrors.value = next
    }

    function showOgImage(repo: Repo): boolean {
        return !!repo.og_image_url && !imageErrors.value.has(repo.id)
    }

    function setLayout(value: string | undefined) {
        if (value === "list" || value === "grid" || value === "table") {
            layout.value = value
        }
    }

    async function fetchFilters() {
        try {
            const res = await fetch(`${API_URL}/filters`)
            const data: FiltersResponse = await res.json()
            filters.allPlatforms.value = data.platforms
            filters.allLanguages.value = data.languages
        } catch (err) {
            console.error("Failed to fetch filters:", err)
        }
    }

    async function fetchRepos() {
        controller?.abort()
        controller = new AbortController()

        const isInitialLoad = repos.value.length === 0
        if (isInitialLoad) {
            loading.value = true
        } else {
            refreshing.value = true
        }
        error.value = null

        try {
            const params = new URLSearchParams()
            params.set("page", pagination.currentPage.value.toString())
            params.set("per_page", pagination.perPage.value)
            params.set("window", timeWindow.value)

            if (filters.selectedPlatforms.value.size > 0) {
                params.set("platform", [...filters.selectedPlatforms.value].join(","))
            }
            if (filters.selectedLanguages.value.size > 0) {
                params.set("language", [...filters.selectedLanguages.value].join(","))
            }
            if (searchQuery.value) {
                params.set("search", searchQuery.value)
            }
            if (!hideEmpty.value) {
                params.set("hide_empty", "false")
            }

            const first = sorting.value[0]
            if (first) {
                params.set("sort", first.id)
                params.set("dir", first.desc ? "desc" : "asc")
            }

            const res = await fetch(`${API_URL}/trending?${params}`, {
                signal: controller.signal,
            })

            if (!res.ok) {
                throw new Error(`Request failed with status ${res.status}`)
            }

            const data: TrendingResponse = await res.json()

            repos.value = data.items ?? []
            pagination.totalPages.value = data.total_pages ?? 1
            pagination.totalItems.value = data.total ?? 0
        } catch (err) {
            if (err instanceof DOMException && err.name === "AbortError") return
            const message = err instanceof Error ? err.message : "An unexpected error occurred"
            error.value = message
            repos.value = []
        } finally {
            loading.value = false
            refreshing.value = false
        }
    }

    watchDebounced(
        [filters.selectedPlatforms, filters.selectedLanguages, pagination.perPage, timeWindow, hideEmpty],
        () => {
            pagination.resetPage()
            syncUrl()
            fetchRepos()
        },
        { debounce: 150, deep: true },
    )

    watch(pagination.currentPage, () => {
        window.scrollTo({ top: 0, behavior: "instant" })
        syncUrl()
        fetchRepos()
    })

    watch(sorting, () => {
        pagination.resetPage()
        syncUrl()
        fetchRepos()
    }, { deep: true })

    watch(layout, syncUrl)

    watchDebounced(searchQuery, () => {
        pagination.resetPage()
        syncUrl()
        fetchRepos()
    }, { debounce: 300 })

    onMounted(() => {
        fetchFilters()
        fetchRepos()
    })

    onUnmounted(() => {
        controller?.abort()
    })

    function reset() {
        filters.clearPlatforms()
        filters.clearLanguages()
        searchQuery.value = ""
        sorting.value = []
        pagination.perPage.value = "12"
        timeWindow.value = "24"
        hideEmpty.value = true
        layout.value = "grid"
        pagination.resetPage()
        url.clear()
        fetchRepos()
    }

    return {
        repos,
        reset,
        loading,
        refreshing,
        error,
        searchQuery,
        layout,
        perPage: pagination.perPage,
        parsedPerPage: pagination.parsedPerPage,
        currentPage: pagination.currentPage,
        totalPages: pagination.totalPages,
        totalItems: pagination.totalItems,
        timeWindow,
        sorting,
        hideEmpty,
        allPlatforms: filters.allPlatforms,
        allLanguages: filters.allLanguages,
        selectedPlatforms: filters.selectedPlatforms,
        selectedLanguages: filters.selectedLanguages,
        favoritePlatforms: preferences.favoritePlatforms,
        favoriteLanguages: preferences.favoriteLanguages,
        togglePlatform: filters.togglePlatform,
        toggleLanguage: filters.toggleLanguage,
        toggleFavoritePlatform: preferences.toggleFavoritePlatform,
        toggleFavoriteLanguage: preferences.toggleFavoriteLanguage,
        clearPlatforms: filters.clearPlatforms,
        clearLanguages: filters.clearLanguages,
        onImageError,
        showOgImage,
        setLayout,
    }
}
