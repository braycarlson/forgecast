<script setup lang="ts">
import type { Column } from "@tanstack/vue-table"
import { Button } from "@/components/ui/button"
import { ArrowUp, ArrowDown, ArrowUpDown } from "lucide-vue-next"
import { computed } from "vue"

const props = defineProps<{
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    column: Column<any, unknown>
    label: string
    align?: "left" | "right" | "center"
}>()

const icon = computed(() => {
    const sorted = props.column.getIsSorted()
    if (sorted === "asc") return ArrowUp
    if (sorted === "desc") return ArrowDown
    return ArrowUpDown
})

const wrapperClass = computed(() => {
    if (props.align === "right") return "flex justify-end"
    if (props.align === "center") return "flex justify-center"
    return ""
})
</script>

<template>
    <div :class="wrapperClass">
        <Button
            variant="ghost"
            :class="[
                'cursor-pointer',
                align === 'left' ? '-ml-3' : '',
            ]"
            @click="column.toggleSorting(column.getIsSorted() === 'asc')"
        >
            <span v-if="align === 'center'" class="w-3.5" />
            {{ label }}
            <component :is="icon" class="ml-1 h-3.5 w-3.5" />
        </Button>
    </div>
</template>
