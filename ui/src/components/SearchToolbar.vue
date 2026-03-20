<script setup lang="ts">
import { ref, computed } from "vue"
import type { SortingState } from "@tanstack/vue-table"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Sheet, SheetContent } from "@/components/ui/sheet"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import SortDropdown from "@/components/SortDropdown.vue"
import FilterDropdown from "@/components/FilterDropdown.vue"
import {
    X, SlidersHorizontal, List, Grid2x2, TableProperties,
    ChevronDown, ChevronLeft, ChevronRight, Check, Star,
    Globe, Clock, ArrowUpDown, Hash,
} from "lucide-vue-next"
import { formatPlatform } from "@/types/repo"

type Layout = "list" | "grid" | "table"
type MobileSheet = null | "languages" | "filters" | "layout" | "platform" | "time-window" | "sort" | "per-page"

const SHEET_CLASS = "h-[70dvh] rounded-t-xl flex flex-col gap-0 p-0"

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
const activeSheet = ref<MobileSheet>(null)
const mobileLanguageSearch = ref("")
const mobilePlatformSearch = ref("")

const filterCount = computed(() => {
    let count = 0
    if (props.selectedPlatforms.size > 0) count++
    if (props.timeWindow !== "24") count++
    if (props.sorting.length > 0) count++
    if (props.perPage !== "12") count++
    return count
})

const languageDisplayLabel = computed(() => {
    if (props.selectedLanguages.size === 0) return "Languages"
    if (props.selectedLanguages.size === 1) return [...props.selectedLanguages][0]!
    return `${props.selectedLanguages.size} selected`
})

const platformDisplayLabel = computed(() => {
    if (props.selectedPlatforms.size === 0) return "All platforms"
    if (props.selectedPlatforms.size === 1) return formatPlatform([...props.selectedPlatforms][0]!)
    return `${props.selectedPlatforms.size} selected`
})

const timeWindowLabel = computed(() => {
    const labels: Record<string, string> = {
        "6": "Last 6 hours",
        "24": "Last 24 hours",
        "72": "Last 3 days",
        "168": "Last 7 days",
        "720": "Last 30 days",
    }
    return labels[props.timeWindow] ?? "Last 24 hours"
})

const sortLabel = computed(() => {
    const first = props.sorting[0]
    if (!first) return "Default"
    const labels: Record<string, string> = {
        stars: "Stars",
        forks: "Forks",
        star_velocity: "Velocity",
        name: "Name",
        language: "Language",
    }
    const direction = first.desc ? "desc" : "asc"
    return `${labels[first.id] ?? first.id} (${direction})`
})

const perPageLabel = computed(() => `${props.perPage} per page`)

const layoutLabel = computed(() => {
    const labels: Record<string, string> = { grid: "Grid", list: "List", table: "Table" }
    return labels[props.layout] ?? "Grid"
})

const layoutOptions = [
    { value: "grid", label: "Grid", icon: Grid2x2 },
    { value: "list", label: "List", icon: List },
    { value: "table", label: "Table", icon: TableProperties },
]

const sortOptions: { key: string; label: string; defaultDesc: boolean }[] = [
    { key: "stars", label: "Stars", defaultDesc: true },
    { key: "forks", label: "Forks", defaultDesc: true },
    { key: "star_velocity", label: "Velocity", defaultDesc: true },
    { key: "name", label: "Name", defaultDesc: false },
    { key: "language", label: "Language", defaultDesc: false },
]

const timeWindowOptions = [
    { value: "6", label: "Last 6 hours" },
    { value: "24", label: "Last 24 hours" },
    { value: "72", label: "Last 3 days" },
    { value: "168", label: "Last 7 days" },
    { value: "720", label: "Last 30 days" },
]

const perPageOptions = [
    { value: "6", label: "6 per page" },
    { value: "12", label: "12 per page" },
    { value: "24", label: "24 per page" },
    { value: "48", label: "48 per page" },
]

function sortedFilterOptions(
    all: string[],
    selected: ReadonlySet<string>,
    favorites: ReadonlySet<string>,
    search: string,
): string[] {
    const favSelected = all.filter(o => favorites.has(o) && selected.has(o))
    const favUnselected = all.filter(o => favorites.has(o) && !selected.has(o))
    const sel = all.filter(o => !favorites.has(o) && selected.has(o))
    const rest = all.filter(o => !favorites.has(o) && !selected.has(o))
    const combined = [...favSelected, ...favUnselected, ...sel, ...rest]

    if (!search) return combined
    const q = search.toLowerCase()
    return combined.filter(o => o.toLowerCase().includes(q))
}

const sortedMobileLanguages = computed(() =>
    sortedFilterOptions(
        props.allLanguages,
        props.selectedLanguages,
        props.favoriteLanguages,
        mobileLanguageSearch.value,
    )
)

const sortedMobilePlatforms = computed(() =>
    sortedFilterOptions(
        props.allPlatforms,
        props.selectedPlatforms,
        props.favoritePlatforms,
        mobilePlatformSearch.value,
    )
)

function openSheet(sheet: MobileSheet) {
    activeSheet.value = sheet
    mobileLanguageSearch.value = ""
    mobilePlatformSearch.value = ""
}

function closeSheet() {
    activeSheet.value = null
    mobileLanguageSearch.value = ""
    mobilePlatformSearch.value = ""
}

function backToFilters() {
    mobilePlatformSearch.value = ""
    activeSheet.value = "filters"
}

function onSortSelect(key: string, defaultDesc: boolean) {
    const current = props.sorting[0]
    if (current?.id === key) {
        emit("update:sorting", [{ id: key, desc: !current.desc }])
    } else {
        emit("update:sorting", [{ id: key, desc: defaultDesc }])
    }
}
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

        <!-- Mobile: search -->
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

        <!-- Mobile: toolbar row -->
        <div class="sm:hidden flex items-center gap-2">
            <Button
                variant="outline"
                class="flex-1 min-w-0 justify-between"
                @click="openSheet('languages')"
            >
                <span class="truncate">{{ languageDisplayLabel }}</span>
                <ChevronDown class="ml-2 h-4 w-4 shrink-0 opacity-50" />
            </Button>

            <Button
                variant="outline"
                class="gap-1.5 shrink-0"
                @click="openSheet('filters')"
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
        </div>

        <!-- Mobile: Languages sheet -->
        <Sheet :open="activeSheet === 'languages'" @update:open="v => { if (!v) closeSheet() }">
            <SheetContent side="bottom" :class="SHEET_CLASS">
                <div class="flex shrink-0 items-center justify-between px-6 pt-6 pb-4">
                    <span class="w-10" />
                    <h3 class="text-base font-semibold">Languages</h3>
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="closeSheet()"
                    >
                        <X class="h-4 w-4 text-muted-foreground" />
                    </button>
                </div>

                <div class="flex-1 overflow-hidden flex flex-col px-6">
                    <div class="shrink-0 pb-4">
                        <div class="relative">
                            <Input
                                :model-value="mobileLanguageSearch"
                                placeholder="Search languages..."
                                class="h-10 pr-9"
                                @input="mobileLanguageSearch = ($event.target as HTMLInputElement).value"
                            />
                            <button
                                v-if="mobileLanguageSearch"
                                class="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                                @click="mobileLanguageSearch = ''"
                            >
                                <X class="h-4 w-4" />
                            </button>
                        </div>
                    </div>

                    <div class="flex-1 overflow-y-auto -mx-2">
                        <div class="px-2 pb-2">
                            <button
                                v-for="option in sortedMobileLanguages"
                                :key="option"
                                class="flex w-full items-center gap-3 rounded-lg px-3 py-3 text-sm hover:bg-accent active:bg-accent transition-colors"
                                @click="emit('toggleLanguage', option)"
                            >
                                <span class="flex h-5 w-5 shrink-0 items-center justify-center rounded border border-border">
                                    <Check v-if="selectedLanguages.has(option)" class="h-3.5 w-3.5" />
                                </span>

                                <span class="flex-1 text-left">{{ option }}</span>

                                <Star
                                    :fill="favoriteLanguages.has(option) ? 'currentColor' : 'none'"
                                    class="h-4 w-4 shrink-0 cursor-pointer hover:text-yellow-400"
                                    :class="favoriteLanguages.has(option) ? 'text-yellow-400' : 'text-muted-foreground/40'"
                                    role="button"
                                    tabindex="0"
                                    @click.stop="emit('toggleFavoriteLanguage', option)"
                                    @keydown.enter.stop="emit('toggleFavoriteLanguage', option)"
                                />
                            </button>

                            <div v-if="sortedMobileLanguages.length === 0" class="px-3 py-8 text-center text-sm text-muted-foreground">
                                No results
                            </div>
                        </div>
                    </div>

                    <div v-if="selectedLanguages.size > 0" class="shrink-0 border-t border-border pt-3 pb-1">
                        <Button
                            variant="outline"
                            class="w-full text-destructive border-destructive/30 hover:bg-destructive/10 hover:text-destructive"
                            @click="emit('clearLanguages')"
                        >
                            <X class="h-3.5 w-3.5" />
                            Clear filters
                        </Button>
                    </div>
                </div>

                <div class="shrink-0 px-6 pb-6 pt-4">
                    <Button class="w-full" @click="closeSheet()">
                        Done
                    </Button>
                </div>
            </SheetContent>
        </Sheet>

        <!-- Mobile: Filters menu sheet -->
        <Sheet :open="activeSheet === 'filters'" @update:open="v => { if (!v) closeSheet() }">
            <SheetContent side="bottom" :class="SHEET_CLASS">
                <div class="flex shrink-0 items-center justify-between px-6 pt-6 pb-4">
                    <span class="w-10" />
                    <h3 class="text-base font-semibold">Filters</h3>
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="closeSheet()"
                    >
                        <X class="h-4 w-4 text-muted-foreground" />
                    </button>
                </div>

                <div class="flex-1 overflow-y-auto px-6">
                    <div class="space-y-1">
                        <button
                            class="flex w-full items-center gap-4 rounded-lg px-4 py-4 hover:bg-accent active:bg-accent transition-colors"
                            @click="openSheet('layout')"
                        >
                            <Grid2x2 class="h-5 w-5 text-muted-foreground" />
                            <div class="flex-1 text-left">
                                <span class="text-sm font-medium">Layout</span>
                                <span class="block text-xs text-muted-foreground mt-0.5">{{ layoutLabel }}</span>
                            </div>
                            <ChevronRight class="h-4 w-4 text-muted-foreground" />
                        </button>

                        <button
                            class="flex w-full items-center gap-4 rounded-lg px-4 py-4 hover:bg-accent active:bg-accent transition-colors"
                            @click="openSheet('platform')"
                        >
                            <Globe class="h-5 w-5 text-muted-foreground" />
                            <div class="flex-1 text-left">
                                <span class="text-sm font-medium">Platform</span>
                                <span class="block text-xs text-muted-foreground mt-0.5">{{ platformDisplayLabel }}</span>
                            </div>
                            <ChevronRight class="h-4 w-4 text-muted-foreground" />
                        </button>

                        <button
                            class="flex w-full items-center gap-4 rounded-lg px-4 py-4 hover:bg-accent active:bg-accent transition-colors"
                            @click="openSheet('time-window')"
                        >
                            <Clock class="h-5 w-5 text-muted-foreground" />
                            <div class="flex-1 text-left">
                                <span class="text-sm font-medium">Time Window</span>
                                <span class="block text-xs text-muted-foreground mt-0.5">{{ timeWindowLabel }}</span>
                            </div>
                            <ChevronRight class="h-4 w-4 text-muted-foreground" />
                        </button>

                        <button
                            class="flex w-full items-center gap-4 rounded-lg px-4 py-4 hover:bg-accent active:bg-accent transition-colors"
                            @click="openSheet('sort')"
                        >
                            <ArrowUpDown class="h-5 w-5 text-muted-foreground" />
                            <div class="flex-1 text-left">
                                <span class="text-sm font-medium">Sort</span>
                                <span class="block text-xs text-muted-foreground mt-0.5">{{ sortLabel }}</span>
                            </div>
                            <ChevronRight class="h-4 w-4 text-muted-foreground" />
                        </button>

                        <button
                            class="flex w-full items-center gap-4 rounded-lg px-4 py-4 hover:bg-accent active:bg-accent transition-colors"
                            @click="openSheet('per-page')"
                        >
                            <Hash class="h-5 w-5 text-muted-foreground" />
                            <div class="flex-1 text-left">
                                <span class="text-sm font-medium">Per Page</span>
                                <span class="block text-xs text-muted-foreground mt-0.5">{{ perPageLabel }}</span>
                            </div>
                            <ChevronRight class="h-4 w-4 text-muted-foreground" />
                        </button>
                    </div>
                </div>

                <div class="shrink-0 px-6 pb-6 pt-4">
                    <Button class="w-full" @click="closeSheet()">
                        Done
                    </Button>
                </div>
            </SheetContent>
        </Sheet>

        <!-- Mobile: Platform sheet -->
        <Sheet :open="activeSheet === 'platform'" @update:open="v => { if (!v) closeSheet() }">
            <SheetContent side="bottom" :class="SHEET_CLASS">
                <div class="flex shrink-0 items-center justify-between px-6 pt-6 pb-4">
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="backToFilters()"
                    >
                        <ChevronLeft class="h-4 w-4 text-muted-foreground" />
                    </button>
                    <h3 class="text-base font-semibold">Platform</h3>
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="closeSheet()"
                    >
                        <X class="h-4 w-4 text-muted-foreground" />
                    </button>
                </div>

                <div class="flex-1 overflow-hidden flex flex-col px-6">
                    <div class="shrink-0 pb-4">
                        <div class="relative">
                            <Input
                                :model-value="mobilePlatformSearch"
                                placeholder="Search platforms..."
                                class="h-10 pr-9"
                                @input="mobilePlatformSearch = ($event.target as HTMLInputElement).value"
                            />
                            <button
                                v-if="mobilePlatformSearch"
                                class="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                                @click="mobilePlatformSearch = ''"
                            >
                                <X class="h-4 w-4" />
                            </button>
                        </div>
                    </div>

                    <div class="flex-1 overflow-y-auto -mx-2">
                        <div class="px-2 pb-2">
                            <button
                                v-for="option in sortedMobilePlatforms"
                                :key="option"
                                class="flex w-full items-center gap-3 rounded-lg px-3 py-3 text-sm hover:bg-accent active:bg-accent transition-colors"
                                @click="emit('togglePlatform', option)"
                            >
                                <span class="flex h-5 w-5 shrink-0 items-center justify-center rounded border border-border">
                                    <Check v-if="selectedPlatforms.has(option)" class="h-3.5 w-3.5" />
                                </span>

                                <span class="flex-1 text-left">{{ formatPlatform(option) }}</span>

                                <Star
                                    :fill="favoritePlatforms.has(option) ? 'currentColor' : 'none'"
                                    class="h-4 w-4 shrink-0 cursor-pointer hover:text-yellow-400"
                                    :class="favoritePlatforms.has(option) ? 'text-yellow-400' : 'text-muted-foreground/40'"
                                    role="button"
                                    tabindex="0"
                                    @click.stop="emit('toggleFavoritePlatform', option)"
                                    @keydown.enter.stop="emit('toggleFavoritePlatform', option)"
                                />
                            </button>

                            <div v-if="sortedMobilePlatforms.length === 0" class="px-3 py-8 text-center text-sm text-muted-foreground">
                                No results
                            </div>
                        </div>
                    </div>

                    <div v-if="selectedPlatforms.size > 0" class="shrink-0 border-t border-border pt-3 pb-1">
                        <Button
                            variant="outline"
                            class="w-full text-destructive border-destructive/30 hover:bg-destructive/10 hover:text-destructive"
                            @click="emit('clearPlatforms')"
                        >
                            <X class="h-3.5 w-3.5" />
                            Clear platforms
                        </Button>
                    </div>
                </div>

                <div class="shrink-0 px-6 pb-6 pt-4">
                    <Button class="w-full" @click="backToFilters()">
                        Done
                    </Button>
                </div>
            </SheetContent>
        </Sheet>

        <!-- Mobile: Time Window sheet -->
        <Sheet :open="activeSheet === 'time-window'" @update:open="v => { if (!v) closeSheet() }">
            <SheetContent side="bottom" :class="SHEET_CLASS">
                <div class="flex shrink-0 items-center justify-between px-6 pt-6 pb-4">
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="backToFilters()"
                    >
                        <ChevronLeft class="h-4 w-4 text-muted-foreground" />
                    </button>
                    <h3 class="text-base font-semibold">Time Window</h3>
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="closeSheet()"
                    >
                        <X class="h-4 w-4 text-muted-foreground" />
                    </button>
                </div>

                <div class="flex-1 overflow-y-auto px-6">
                    <div class="-mx-2 px-2 pb-2">
                        <button
                            v-for="option in timeWindowOptions"
                            :key="option.value"
                            class="flex w-full items-center gap-3 rounded-lg px-3 py-3.5 text-sm hover:bg-accent active:bg-accent transition-colors"
                            @click="emit('update:timeWindow', option.value)"
                        >
                            <Check
                                v-if="timeWindow === option.value"
                                class="h-4 w-4 text-primary"
                            />
                            <span v-else class="h-4 w-4" />
                            <span :class="timeWindow === option.value ? 'font-medium text-foreground' : 'text-muted-foreground'">
                                {{ option.label }}
                            </span>
                        </button>
                    </div>
                </div>

                <div class="shrink-0 px-6 pb-6 pt-4">
                    <Button class="w-full" @click="backToFilters()">
                        Done
                    </Button>
                </div>
            </SheetContent>
        </Sheet>

        <!-- Mobile: Sort sheet -->
        <Sheet :open="activeSheet === 'sort'" @update:open="v => { if (!v) closeSheet() }">
            <SheetContent side="bottom" :class="SHEET_CLASS">
                <div class="flex shrink-0 items-center justify-between px-6 pt-6 pb-4">
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="backToFilters()"
                    >
                        <ChevronLeft class="h-4 w-4 text-muted-foreground" />
                    </button>
                    <h3 class="text-base font-semibold">Sort</h3>
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="closeSheet()"
                    >
                        <X class="h-4 w-4 text-muted-foreground" />
                    </button>
                </div>

                <div class="flex-1 overflow-y-auto px-6">
                    <div class="-mx-2 px-2 pb-2">
                        <button
                            v-for="option in sortOptions"
                            :key="option.key"
                            class="flex w-full items-center justify-between rounded-lg px-3 py-3.5 text-sm hover:bg-accent active:bg-accent transition-colors"
                            @click="onSortSelect(option.key, option.defaultDesc)"
                        >
                            <span class="flex items-center gap-3">
                                <Check
                                    v-if="sorting[0]?.id === option.key"
                                    class="h-4 w-4 text-primary"
                                />
                                <span v-else class="h-4 w-4" />
                                <span :class="sorting[0]?.id === option.key ? 'font-medium text-foreground' : 'text-muted-foreground'">
                                    {{ option.label }}
                                </span>
                            </span>
                            <span v-if="sorting[0]?.id === option.key" class="text-xs text-muted-foreground">
                                {{ sorting[0]?.desc ? "Descending" : "Ascending" }}
                            </span>
                        </button>
                    </div>
                    <p class="px-3 pt-2 pb-2 text-xs text-muted-foreground">
                        Tap again to toggle direction.
                    </p>
                </div>

                <div class="shrink-0 px-6 pb-6 pt-4">
                    <Button class="w-full" @click="backToFilters()">
                        Done
                    </Button>
                </div>
            </SheetContent>
        </Sheet>

        <!-- Mobile: Layout sheet -->
        <Sheet :open="activeSheet === 'layout'" @update:open="v => { if (!v) closeSheet() }">
            <SheetContent side="bottom" :class="SHEET_CLASS">
                <div class="flex shrink-0 items-center justify-between px-6 pt-6 pb-4">
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="backToFilters()"
                    >
                        <ChevronLeft class="h-4 w-4 text-muted-foreground" />
                    </button>
                    <h3 class="text-base font-semibold">Layout</h3>
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="closeSheet()"
                    >
                        <X class="h-4 w-4 text-muted-foreground" />
                    </button>
                </div>

                <div class="flex-1 overflow-y-auto px-6">
                    <div class="-mx-2 px-2 pb-2">
                        <button
                            v-for="option in layoutOptions"
                            :key="option.value"
                            class="flex w-full items-center gap-3 rounded-lg px-3 py-3.5 text-sm hover:bg-accent active:bg-accent transition-colors"
                            @click="emit('update:layout', option.value)"
                        >
                            <Check
                                v-if="layout === option.value"
                                class="h-4 w-4 text-primary"
                            />
                            <span v-else class="h-4 w-4" />
                            <component :is="option.icon" class="h-4 w-4 text-muted-foreground" />
                            <span :class="layout === option.value ? 'font-medium text-foreground' : 'text-muted-foreground'">
                                {{ option.label }}
                            </span>
                        </button>
                    </div>
                </div>

                <div class="shrink-0 px-6 pb-6 pt-4">
                    <Button class="w-full" @click="backToFilters()">
                        Done
                    </Button>
                </div>
            </SheetContent>
        </Sheet>

        <!-- Mobile: Per Page sheet -->
        <Sheet :open="activeSheet === 'per-page'" @update:open="v => { if (!v) closeSheet() }">
            <SheetContent side="bottom" :class="SHEET_CLASS">
                <div class="flex shrink-0 items-center justify-between px-6 pt-6 pb-4">
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="backToFilters()"
                    >
                        <ChevronLeft class="h-4 w-4 text-muted-foreground" />
                    </button>
                    <h3 class="text-base font-semibold">Per Page</h3>
                    <button
                        class="flex h-10 w-10 items-center justify-center rounded-full hover:bg-accent transition-colors"
                        @click="closeSheet()"
                    >
                        <X class="h-4 w-4 text-muted-foreground" />
                    </button>
                </div>

                <div class="flex-1 overflow-y-auto px-6">
                    <div class="-mx-2 px-2 pb-2">
                        <button
                            v-for="option in perPageOptions"
                            :key="option.value"
                            class="flex w-full items-center gap-3 rounded-lg px-3 py-3.5 text-sm hover:bg-accent active:bg-accent transition-colors"
                            @click="emit('update:perPage', option.value)"
                        >
                            <Check
                                v-if="perPage === option.value"
                                class="h-4 w-4 text-primary"
                            />
                            <span v-else class="h-4 w-4" />
                            <span :class="perPage === option.value ? 'font-medium text-foreground' : 'text-muted-foreground'">
                                {{ option.label }}
                            </span>
                        </button>
                    </div>
                </div>

                <div class="shrink-0 px-6 pb-6 pt-4">
                    <Button class="w-full" @click="backToFilters()">
                        Done
                    </Button>
                </div>
            </SheetContent>
        </Sheet>
    </div>
</template>
