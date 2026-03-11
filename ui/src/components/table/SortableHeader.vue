<script setup lang="ts">
import type { Column } from "@tanstack/vue-table"
import { Button } from "@/components/ui/button"
import { ArrowUp, ArrowDown, ArrowUpDown } from "lucide-vue-next"
import { computed } from "vue"

const props = defineProps<{
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    column: Column<any, unknown>
    label: string
    align?: "left" | "right"
}>()

const icon = computed(() => {
    const sorted = props.column.getIsSorted()
    if (sorted === "asc") return ArrowUp
    if (sorted === "desc") return ArrowDown
    return ArrowUpDown
})
</script>

<template>
    <div :class="align === 'right' ? 'text-right' : ''">
        <Button
            variant="ghost"
            :class="align === 'right' ? '-mr-4 cursor-pointer' : '-ml-3 cursor-pointer'"
            @click="column.toggleSorting(column.getIsSorted() === 'asc')"
        >
            {{ label }}
            <component :is="icon" class="ml-2 h-3.5 w-3.5" />
        </Button>
    </div>
</template>
