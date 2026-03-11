<script setup lang="ts">
import FilterDropdown from "@/components/FilterDropdown.vue"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { formatPlatform } from "@/types/repo"

defineProps<{
    timeWindow: string
    allPlatforms: string[]
    allLanguages: string[]
    selectedPlatforms: ReadonlySet<string>
    selectedLanguages: ReadonlySet<string>
    favoritePlatforms: ReadonlySet<string>
    favoriteLanguages: ReadonlySet<string>
    direction?: "row" | "grid"
}>()

const emit = defineEmits<{
    "update:timeWindow": [value: string]
    togglePlatform: [value: string]
    toggleLanguage: [value: string]
    toggleFavoritePlatform: [value: string]
    toggleFavoriteLanguage: [value: string]
    clearPlatforms: []
    clearLanguages: []
}>()
</script>

<template>
    <div :class="direction === 'grid' ? 'grid grid-cols-2 gap-2' : 'flex items-center gap-2'">
        <FilterDropdown
            label="Platforms"
            :options="allPlatforms"
            :selected="selectedPlatforms"
            :favorites="favoritePlatforms"
            :format-option="formatPlatform"
            :class="direction === 'grid' ? 'w-full' : 'sm:w-[160px]'"
            @toggle-selected="emit('togglePlatform', $event)"
            @toggle-favorite="emit('toggleFavoritePlatform', $event)"
            @clear="emit('clearPlatforms')"
        />

        <FilterDropdown
            label="Languages"
            :options="allLanguages"
            :selected="selectedLanguages"
            :favorites="favoriteLanguages"
            :class="direction === 'grid' ? 'w-full' : 'sm:w-[160px]'"
            @toggle-selected="emit('toggleLanguage', $event)"
            @toggle-favorite="emit('toggleFavoriteLanguage', $event)"
            @clear="emit('clearLanguages')"
        />

        <Select
            v-if="direction !== 'grid'"
            :model-value="timeWindow"
            @update:model-value="emit('update:timeWindow', $event as string)"
        >
            <SelectTrigger class="w-[140px]">
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
</template>
