<script setup lang="ts">
import { ref, computed } from "vue"
import type { SortingState } from "@tanstack/vue-table"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import FilterControl from "@/components/toolbar/FilterControl.vue"
import DisplayControl from "@/components/toolbar/DisplayControl.vue"
import { X, SlidersHorizontal, ChevronUp } from "lucide-vue-next"

type Layout = "list" | "grid" | "table"

const props = defineProps<{
    searchQuery: string
    layout: Layout
    perPage: string
    timeWindow: string
    sorting: SortingState
    allPlatforms: string[]
    allLanguages: string[]
    selectedPlatforms: ReadonlySet<string>
    selectedLanguages: ReadonlySet<string>
    favoritePlatforms: ReadonlySet<string>
    favoriteLanguages: ReadonlySet<string>
}>()

const emit = defineEmits<{
    "update:searchQuery": [value: string]
    "update:layout": [value: string | undefined]
    "update:perPage": [value: string]
    "update:timeWindow": [value: string]
    "update:sorting": [value: SortingState]
    "update:selectedPlatforms": [value: Set<string>]
    "update:selectedLanguages": [value: Set<string>]
    togglePlatform: [value: string]
    toggleLanguage: [value: string]
    toggleFavoritePlatform: [value: string]
    toggleFavoriteLanguage: [value: string]
    clearPlatforms: []
    clearLanguages: []
}>()

const filtersOpen = ref(false)

const activeFilterCount = computed(() => {
    let count = 0
    if (props.selectedPlatforms.size > 0) count++
    if (props.selectedLanguages.size > 0) count++
    if (props.timeWindow !== "24") count++
    if (props.sorting.length > 0) count++
    if (props.perPage !== "12") count++
    return count
})
</script>

<template>
    <div class="space-y-3">
        <!-- Row 1: Search + mobile filter toggle -->
        <div class="flex items-center gap-2">
            <div class="relative flex-1">
                <Input
                    :model-value="searchQuery"
                    placeholder="Search repos, languages, topics..."
                    @update:model-value="emit('update:searchQuery', $event as string)"
                />
                <button
                    v-if="searchQuery"
                    class="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                    @click="emit('update:searchQuery', '')"
                >
                    <X class="h-4 w-4" />
                </button>
            </div>

            <Button
                variant="outline"
                class="md:hidden gap-1.5 shrink-0"
                @click="filtersOpen = !filtersOpen"
            >
                <SlidersHorizontal class="h-4 w-4" />
                <span>Filters</span>
                <span
                    v-if="activeFilterCount > 0"
                    class="flex h-4.5 w-4.5 items-center justify-center rounded-full bg-primary text-[10px] font-semibold text-primary-foreground"
                >
                    {{ activeFilterCount }}
                </span>
                <ChevronUp
                    class="h-3.5 w-3.5 text-muted-foreground transition-transform duration-200"
                    :class="{ 'rotate-180': !filtersOpen }"
                />
            </Button>
        </div>

        <!-- Desktop controls (md+) -->
        <div class="hidden md:flex md:items-center md:justify-between">
            <FilterControl
                :time-window="timeWindow"
                :all-platforms="allPlatforms"
                :all-languages="allLanguages"
                :selected-platforms="selectedPlatforms"
                :selected-languages="selectedLanguages"
                :favorite-platforms="favoritePlatforms"
                :favorite-languages="favoriteLanguages"
                @update:time-window="emit('update:timeWindow', $event)"
                @toggle-platform="emit('togglePlatform', $event)"
                @toggle-language="emit('toggleLanguage', $event)"
                @toggle-favorite-platform="emit('toggleFavoritePlatform', $event)"
                @toggle-favorite-language="emit('toggleFavoriteLanguage', $event)"
                @clear-platforms="emit('clearPlatforms')"
                @clear-languages="emit('clearLanguages')"
            />

            <DisplayControl
                :layout="layout"
                :per-page="perPage"
                :sorting="sorting"
                @update:layout="emit('update:layout', $event)"
                @update:per-page="emit('update:perPage', $event)"
                @update:sorting="emit('update:sorting', $event)"
            />
        </div>

        <!-- Mobile collapsible panel -->
        <div
            class="md:hidden overflow-hidden transition-all duration-200 ease-out"
            :class="filtersOpen ? 'max-h-[500px] opacity-100' : 'max-h-0 opacity-0'"
        >
            <div class="space-y-4 rounded-lg border border-border bg-card p-3">
                <!-- Content filters -->
                <div>
                    <span class="mb-2 block text-xs font-medium text-muted-foreground uppercase tracking-wider">
                        Filter by
                    </span>
                    <FilterControl
                        direction="grid"
                        :time-window="timeWindow"
                        :all-platforms="allPlatforms"
                        :all-languages="allLanguages"
                        :selected-platforms="selectedPlatforms"
                        :selected-languages="selectedLanguages"
                        :favorite-platforms="favoritePlatforms"
                        :favorite-languages="favoriteLanguages"
                        @update:time-window="emit('update:timeWindow', $event)"
                        @toggle-platform="emit('togglePlatform', $event)"
                        @toggle-language="emit('toggleLanguage', $event)"
                        @toggle-favorite-platform="emit('toggleFavoritePlatform', $event)"
                        @toggle-favorite-language="emit('toggleFavoriteLanguage', $event)"
                        @clear-platforms="emit('clearPlatforms')"
                        @clear-languages="emit('clearLanguages')"
                    />
                </div>

                <!-- Display controls -->
                <div>
                    <span class="mb-2 block text-xs font-medium text-muted-foreground uppercase tracking-wider">
                        Display
                    </span>
                    <div class="grid grid-cols-2 gap-2">
                        <Select :model-value="timeWindow" @update:model-value="emit('update:timeWindow', $event as string)">
                            <SelectTrigger class="w-full">
                                <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                                <SelectItem value="6">Last 6 hours</SelectItem>
                                <SelectItem value="24">Last 24 hours</SelectItem>
                                <SelectItem value="72">Last 3 days</SelectItem>
                                <SelectItem value="168">Last 7 days</SelectItem>
                                <SelectItem value="720">Last 30 days</SelectItem>
                            </SelectContent>
                        </Select>

                        <Select :model-value="perPage" @update:model-value="emit('update:perPage', $event as string)">
                            <SelectTrigger class="w-full">
                                <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                                <SelectItem value="6">6 per page</SelectItem>
                                <SelectItem value="12">12 per page</SelectItem>
                                <SelectItem value="24">24 per page</SelectItem>
                                <SelectItem value="48">48 per page</SelectItem>
                            </SelectContent>
                        </Select>
                    </div>

                    <div class="mt-4">
                        <DisplayControl
                            compact
                            :layout="layout"
                            :per-page="perPage"
                            :sorting="sorting"
                            @update:layout="emit('update:layout', $event)"
                            @update:per-page="emit('update:perPage', $event)"
                            @update:sorting="emit('update:sorting', $event)"
                        />
                    </div>
                </div>
            </div>
        </div>
    </div>
</template>
