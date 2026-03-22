<script setup lang="ts">
import { computed } from "vue"
import { RouterLink } from "vue-router"
import { useTheme } from "@/composables/useTheme"
import { Button } from "@/components/ui/button"
import {
    Pagination,
    PaginationContent,
    PaginationEllipsis,
    PaginationItem,
    PaginationNext,
    PaginationPrevious,
} from "@/components/ui/pagination"
import PageHeader from "@/components/PageHeader.vue"
import PageFooter from "@/components/PageFooter.vue"
import SearchToolbar from "@/components/SearchToolbar.vue"
import RepoCard from "@/components/RepoCard.vue"
import RepoTable from "@/components/RepoTable.vue"
import UserMenu from "@/components/UserMenu.vue"
import { Sun, Moon, ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight } from "lucide-vue-next"
import { useTrending } from "@/composables/useTrending"

const { theme, toggle: toggleTheme } = useTheme()

const {
    repos,
    reset,
    loading,
    refreshing,
    error,
    searchQuery,
    layout,
    perPage,
    parsedPerPage,
    currentPage,
    totalPages,
    totalItems,
    timeWindow,
    sorting,
    hideEmpty,
    allPlatforms,
    allLanguages,
    selectedPlatforms,
    selectedLanguages,
    favoritePlatforms,
    favoriteLanguages,
    togglePlatform,
    toggleLanguage,
    toggleFavoritePlatform,
    toggleFavoriteLanguage,
    onImageError,
    showOgImage,
    setLayout,
} = useTrending()

const visiblePages = computed(() => {
    const total = totalPages.value
    const current = currentPage.value
    const pages: (number | "ellipsis-start" | "ellipsis-end")[] = []

    if (total <= 7) {
        for (let i = 1; i <= total; i++) pages.push(i)
        return pages
    }

    pages.push(1)

    if (current > 3) {
        pages.push("ellipsis-start")
    }

    const start = Math.max(2, current - 1)
    const end = Math.min(total - 1, current + 1)

    for (let i = start; i <= end; i++) {
        pages.push(i)
    }

    if (current < total - 2) {
        pages.push("ellipsis-end")
    }

    pages.push(total)

    return pages
})
</script>

<template>
    <div class="flex min-h-screen flex-col bg-background text-foreground">
        <header class="sticky top-0 z-40 border-b border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
            <div class="header-accent" />
            <div class="mx-auto flex h-16 max-w-5xl items-center justify-between px-4">
                <RouterLink
                    to="/"
                    class="flex items-center gap-2.5 hover:opacity-80 transition-opacity"
                    @click.prevent="reset"
                >
                    <img src="/forgecast.svg" alt="Forgecast" class="h-10 w-10" />
                </RouterLink>
                <div class="flex items-center gap-2">
                    <Button
                        variant="ghost"
                        size="icon"
                        aria-label="Toggle theme"
                        @click="toggleTheme"
                    >
                        <Sun v-if="theme === 'dark'" class="h-4 w-4" />
                        <Moon v-else class="h-4 w-4" />
                    </Button>
                    <UserMenu />
                </div>
            </div>
        </header>

        <main class="flex-1">
            <div class="mx-auto max-w-5xl px-4 py-8">
                <div class="mb-8">
                    <PageHeader
                        :total-items="totalItems"
                        :platforms="allPlatforms"
                        :languages="allLanguages"
                        :time-window="timeWindow"
                        :loading="loading"
                    />
                </div>

                <div class="mb-8">
                    <SearchToolbar
                        :search-query="searchQuery"
                        :layout="layout"
                        :per-page="perPage"
                        :time-window="timeWindow"
                        :sorting="sorting"
                        :hide-empty="hideEmpty"
                        :all-platforms="allPlatforms"
                        :all-languages="allLanguages"
                        :selected-platforms="selectedPlatforms"
                        :selected-languages="selectedLanguages"
                        :favorite-platforms="favoritePlatforms"
                        :favorite-languages="favoriteLanguages"
                        @update:search-query="searchQuery = $event"
                        @update:layout="setLayout($event)"
                        @update:per-page="perPage = $event"
                        @update:time-window="timeWindow = $event"
                        @update:sorting="sorting = $event"
                        @update:hide-empty="hideEmpty = $event"
                        @toggle-platform="togglePlatform"
                        @toggle-language="toggleLanguage"
                        @toggle-favorite-platform="toggleFavoritePlatform"
                        @toggle-favorite-language="toggleFavoriteLanguage"
                        @clear-platforms="selectedPlatforms = new Set()"
                        @clear-languages="selectedLanguages = new Set()"
                    />
                </div>

                <p v-if="loading" class="text-muted-foreground">Loading...</p>

                <div v-else-if="error" class="py-12 text-center">
                    <p class="text-destructive">{{ error }}</p>
                    <p class="mt-1 text-sm text-muted-foreground">Check that the API is running and try again.</p>
                </div>

                <div v-else>
                    <div :class="{ 'opacity-60 pointer-events-none transition-opacity duration-150': refreshing }">
                        <RepoTable
                            v-if="layout === 'table'"
                            :repos="repos"
                            :sorting="sorting"
                            @update:sorting="sorting = $event"
                        />

                        <div
                            v-else
                            :class="layout === 'grid'
                                ? 'grid grid-cols-1 gap-4 sm:grid-cols-2'
                                : 'flex flex-col gap-3'"
                        >
                            <RepoCard
                                v-for="repo in repos"
                                :key="repo.id"
                                :repo="repo"
                                :layout="layout"
                                :show-og-image="showOgImage(repo)"
                                @image-error="onImageError"
                            />
                        </div>

                        <div v-if="repos.length === 0 && layout !== 'table'" class="py-12 text-center text-muted-foreground">
                            No repositories match your filters.
                        </div>
                    </div>

                    <div v-if="totalPages > 1" class="mt-10 flex justify-center">
                        <Pagination
                            :total="totalItems"
                            :items-per-page="parsedPerPage"
                            :page="currentPage"
                            :sibling-count="1"
                            @update:page="currentPage = $event"
                        >
                            <PaginationContent class="flex items-center gap-1 [&_button]:cursor-pointer">
                                <li class="list-none">
                                    <Button
                                        variant="ghost"
                                        size="icon-sm"
                                        class="hidden sm:inline-flex cursor-pointer"
                                        :disabled="currentPage === 1"
                                        @click="currentPage = 1"
                                    >
                                        <ChevronsLeft class="h-4 w-4" />
                                    </Button>
                                </li>
                                <PaginationPrevious>
                                    <ChevronLeft class="h-4 w-4" />
                                </PaginationPrevious>

                                <template v-for="page in visiblePages" :key="page">
                                    <PaginationEllipsis
                                        v-if="typeof page === 'string'"
                                        :index="page === 'ellipsis-start' ? 2 : totalPages - 1"
                                    />
                                    <PaginationItem
                                        v-else
                                        :value="page"
                                        as-child
                                    >
                                        <Button
                                            :variant="page === currentPage ? 'default' : 'outline'"
                                            size="sm"
                                            class="h-9 !w-auto min-w-9 px-2.5 cursor-pointer"
                                            @click="currentPage = page"
                                        >
                                            {{ page }}
                                        </Button>
                                    </PaginationItem>
                                </template>

                                <PaginationNext>
                                    <ChevronRight class="h-4 w-4" />
                                </PaginationNext>
                                <li class="list-none">
                                    <Button
                                        variant="ghost"
                                        size="icon-sm"
                                        class="hidden sm:inline-flex cursor-pointer"
                                        :disabled="currentPage === totalPages"
                                        @click="currentPage = totalPages"
                                    >
                                        <ChevronsRight class="h-4 w-4" />
                                    </Button>
                                </li>
                            </PaginationContent>
                        </Pagination>
                    </div>
                </div>
            </div>
        </main>

        <PageFooter v-if="!loading" />
    </div>
</template>
