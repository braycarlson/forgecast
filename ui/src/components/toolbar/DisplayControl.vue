<script setup lang="ts">
import type { SortingState } from "@tanstack/vue-table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Separator } from "@/components/ui/separator"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import SortDropdown from "@/components/SortDropdown.vue"
import { List, Grid2x2, TableProperties } from "lucide-vue-next"

type Layout = "list" | "grid" | "table"

defineProps<{
    layout: Layout
    perPage: string
    sorting: SortingState
    compact?: boolean
}>()

const emit = defineEmits<{
    "update:layout": [value: string | undefined]
    "update:perPage": [value: string]
    "update:sorting": [value: SortingState]
}>()
</script>

<template>
    <div :class="compact ? 'flex items-center justify-between' : 'flex items-center gap-2'">
        <SortDropdown
            :sorting="sorting"
            @update:sorting="emit('update:sorting', $event)"
        />

        <Select
            v-if="!compact"
            :model-value="perPage"
            @update:model-value="emit('update:perPage', $event as string)"
        >
            <SelectTrigger class="w-[125px]">
                <SelectValue />
            </SelectTrigger>
            <SelectContent>
                <SelectItem value="6">6 per page</SelectItem>
                <SelectItem value="12">12 per page</SelectItem>
                <SelectItem value="24">24 per page</SelectItem>
                <SelectItem value="48">48 per page</SelectItem>
            </SelectContent>
        </Select>

        <Separator v-if="!compact" orientation="vertical" class="h-5" />

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
</template>
