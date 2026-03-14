<script setup lang="ts">
import { ref, computed } from "vue"
import type { SortingState } from "@tanstack/vue-table"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import SortDropdown from "@/components/SortDropdown.vue"
import FilterDropdown from "@/components/FilterDropdown.vue"
import { X, SlidersHorizontal, List, Grid2x2, TableProperties } from "lucide-vue-next"
import { formatPlatform } from "@/types/repo"

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
const mobileFiltersOpen = ref(false)

const filterCount = computed(() => {
    let count = 0
    if (props.selectedPlatforms.size > 0) count++
    if (props.timeWindow !== "24") count++
    if (props.sorting.length > 0) count++
    if (props.perPage !== "12") count++
    return count
})
</script>

<template>
    <div class="space-y-2 sm:space-y-0">
        <!-- Desktop: single row -->
        <div class="hidden sm:flex items-center gap-2">
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

            <FilterDropdown
                label="Languages"
                :options="allLanguages"
                :selected="selectedLanguages"
                :favorites="favoriteLanguages"
                @toggle-selected="emit('toggleLanguage', $event)"
                @toggle-favorite="emit('toggleFavoriteLanguage', $event)"
                @clear="emit('clearLanguages')"
            />

            <Popover :open="filtersOpen" @update:open="filtersOpen = $event">
                <PopoverTrigger as-child>
                    <Button variant="outline" class="gap-1.5 shrink-0">
                        <SlidersHorizontal class="h-4 w-4" />
                        Filters
                        <Badge
                            v-if="filterCount > 0"
                            variant="secondary"
                            class="h-5 min-w-5 px-1.5 text-[10px] font-semibold"
                        >
                            {{ filterCount }}
                        </Badge>
                    </Button>
                </PopoverTrigger>
                <PopoverContent class="w-[320px] p-0" align="end">
                    <div class="space-y-4 p-4">
                        <div>
                            <span class="mb-2 block text-xs font-medium text-muted-foreground uppercase tracking-wider">
                                Platform
                            </span>
                            <FilterDropdown
                                label="All platforms"
                                class="!w-full [&_button]:!w-full"
                                :options="allPlatforms"
                                :selected="selectedPlatforms"
                                :favorites="favoritePlatforms"
                                :format-option="formatPlatform"
                                @toggle-selected="emit('togglePlatform', $event)"
                                @toggle-favorite="emit('toggleFavoritePlatform', $event)"
                                @clear="emit('clearPlatforms')"
                            />
                        </div>

                        <div>
                            <span class="mb-2 block text-xs font-medium text-muted-foreground uppercase tracking-wider">
                                Time Window
                            </span>
                            <Select
                                :model-value="timeWindow"
                                @update:model-value="emit('update:timeWindow', $event as string)"
                            >
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
                        </div>

                        <div>
                            <span class="mb-2 block text-xs font-medium text-muted-foreground uppercase tracking-wider">
                                Sort
                            </span>
                            <SortDropdown
                                :sorting="sorting"
                                @update:sorting="emit('update:sorting', $event)"
                            />
                        </div>

                        <div>
                            <span class="mb-2 block text-xs font-medium text-muted-foreground uppercase tracking-wider">
                                Per Page
                            </span>
                            <Select
                                :model-value="perPage"
                                @update:model-value="emit('update:perPage', $event as string)"
                            >
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
                    </div>
                </PopoverContent>
            </Popover>

            <ToggleGroup
                type="single"
                :model-value="layout"
                @update:model-value="emit('update:layout', $event as string)"
            >
                <ToggleGroupItem value="grid" aria-label="Grid view" class="px-3">
                    <Grid2x2 class="h-4 w-4" />
                </ToggleGroupItem>
                <ToggleGroupItem value="list" aria-label="List view" class="px-3">
                    <List class="h-4 w-4" />
                </ToggleGroupItem>
                <ToggleGroupItem value="table" aria-label="Table view" class="px-3">
                    <TableProperties class="h-4 w-4" />
                </ToggleGroupItem>
            </ToggleGroup>
        </div>

        <!-- Mobile: search on its own row -->
        <div class="sm:hidden relative">
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

        <div class="sm:hidden flex items-center gap-2">
            <FilterDropdown
                label="Languages"
                class="flex-1 [&_button]:!w-full"
                :options="allLanguages"
                :selected="selectedLanguages"
                :favorites="favoriteLanguages"
                @toggle-selected="emit('toggleLanguage', $event)"
                @toggle-favorite="emit('toggleFavoriteLanguage', $event)"
                @clear="emit('clearLanguages')"
            />

            <Button
                variant="outline"
                class="gap-1.5 shrink-0"
                @click="mobileFiltersOpen = !mobileFiltersOpen"
            >
                <SlidersHorizontal class="h-4 w-4" />
                Filters
                <Badge
                    v-if="filterCount > 0"
                    variant="secondary"
                    class="h-5 min-w-5 px-1.5 text-[10px] font-semibold"
                >
                    {{ filterCount }}
                </Badge>
            </Button>

            <ToggleGroup
                type="single"
                :model-value="layout"
                @update:model-value="emit('update:layout', $event as string)"
            >
                <ToggleGroupItem value="grid" aria-label="Grid view" class="px-3">
                    <Grid2x2 class="h-4 w-4" />
                </ToggleGroupItem>
                <ToggleGroupItem value="list" aria-label="List view" class="px-3">
                    <List class="h-4 w-4" />
                </ToggleGroupItem>
                <ToggleGroupItem value="table" aria-label="Table view" class="px-3">
                    <TableProperties class="h-4 w-4" />
                </ToggleGroupItem>
            </ToggleGroup>
        </div>

        <!-- Mobile: collapsible filter panel -->
        <div
            class="sm:hidden overflow-hidden transition-all duration-200 ease-out"
            :class="mobileFiltersOpen ? 'max-h-[500px] opacity-100' : 'max-h-0 opacity-0'"
        >
            <div class="space-y-4 rounded-lg border border-border bg-card p-3">
                <div>
                    <span class="mb-2 block text-xs font-medium text-muted-foreground uppercase tracking-wider">
                        Platform
                    </span>
                    <FilterDropdown
                        label="All platforms"
                        class="!w-full [&_button]:!w-full"
                        :options="allPlatforms"
                        :selected="selectedPlatforms"
                        :favorites="favoritePlatforms"
                        :format-option="formatPlatform"
                        @toggle-selected="emit('togglePlatform', $event)"
                        @toggle-favorite="emit('toggleFavoritePlatform', $event)"
                        @clear="emit('clearPlatforms')"
                    />
                </div>

                <div>
                    <span class="mb-2 block text-xs font-medium text-muted-foreground uppercase tracking-wider">
                        Time Window
                    </span>
                    <Select
                        :model-value="timeWindow"
                        @update:model-value="emit('update:timeWindow', $event as string)"
                    >
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
                </div>

                <div>
                    <span class="mb-2 block text-xs font-medium text-muted-foreground uppercase tracking-wider">
                        Sort
                    </span>
                    <SortDropdown
                        :sorting="sorting"
                        @update:sorting="emit('update:sorting', $event)"
                    />
                </div>

                <div>
                    <span class="mb-2 block text-xs font-medium text-muted-foreground uppercase tracking-wider">
                        Per Page
                    </span>
                    <Select
                        :model-value="perPage"
                        @update:model-value="emit('update:perPage', $event as string)"
                    >
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
            </div>
        </div>
    </div>
</template>
