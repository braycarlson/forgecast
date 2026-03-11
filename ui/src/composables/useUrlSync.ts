import { useRoute, useRouter } from "vue-router"
import type { SortingState } from "@tanstack/vue-table"

type Layout = "list" | "grid" | "table"

export function useUrlSync() {
    const route = useRoute()
    const router = useRouter()

    function queryString(key: string, fallback: string): string {
        const value = route.query[key]
        return typeof value === "string" ? value : fallback
    }

    function querySet(key: string): Set<string> {
        const value = route.query[key]
        if (typeof value !== "string" || !value) return new Set()
        return new Set(value.split(",").filter(Boolean))
    }

    function initialSorting(): SortingState {
        const field = queryString("sort", "")
        const dir = queryString("dir", "desc")
        if (!field) return []
        return [{ id: field, desc: dir === "desc" }]
    }

    interface SyncParams {
        selectedPlatforms: Set<string>
        selectedLanguages: Set<string>
        searchQuery: string
        currentPage: number
        perPage: string
        timeWindow: string
        layout: Layout
        sorting: SortingState
    }

    function sync(params: SyncParams) {
        const query: Record<string, string> = {}

        if (params.selectedPlatforms.size > 0) query.platform = [...params.selectedPlatforms].join(",")
        if (params.selectedLanguages.size > 0) query.language = [...params.selectedLanguages].join(",")
        if (params.searchQuery) query.search = params.searchQuery
        if (params.currentPage > 1) query.page = params.currentPage.toString()
        if (params.perPage !== "12") query.per_page = params.perPage
        if (params.timeWindow !== "24") query.window = params.timeWindow
        if (params.layout !== "grid") query.layout = params.layout

        const first = params.sorting[0]
        if (first) {
            query.sort = first.id
            query.dir = first.desc ? "desc" : "asc"
        }

        router.replace({ query })
    }

    function clear() {
        router.replace({ query: {} })
    }

    return {
        queryString,
        querySet,
        initialSorting,
        sync,
        clear,
    }
}
