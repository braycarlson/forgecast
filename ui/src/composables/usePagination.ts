import { ref, computed } from "vue"

export function usePagination(initialPage: number, initialPerPage: string) {
    const currentPage = ref(initialPage)
    const perPage = ref(initialPerPage)
    const totalPages = ref(1)
    const totalItems = ref(0)

    const parsedPerPage = computed(() => parseInt(perPage.value, 10))

    function resetPage() {
        currentPage.value = 1
    }

    return {
        currentPage,
        perPage,
        totalPages,
        totalItems,
        parsedPerPage,
        resetPage,
    }
}
