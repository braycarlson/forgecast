<script setup lang="ts">
import { ref, computed } from "vue"
import type { SortingState } from "@tanstack/vue-table"
import { Button } from "@/components/ui/button"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { ArrowUpDown, ArrowUp, ArrowDown, Check } from "lucide-vue-next"

const props = defineProps<{
    sorting: SortingState
}>()

const emit = defineEmits<{
    "update:sorting": [value: SortingState]
}>()

const open = ref(false)

const options: { key: string; label: string; defaultDesc: boolean }[] = [
    { key: "stars", label: "Stars", defaultDesc: true },
    { key: "forks", label: "Forks", defaultDesc: true },
    { key: "star_velocity", label: "Velocity", defaultDesc: true },
    { key: "name", label: "Name", defaultDesc: false },
    { key: "language", label: "Language", defaultDesc: false },
]

const activeField = computed(() => props.sorting[0]?.id ?? null)
const activeDesc = computed(() => props.sorting[0]?.desc ?? true)

function onSelect(key: string, defaultDesc: boolean) {
    if (activeField.value === key) {
        emit("update:sorting", [{ id: key, desc: !activeDesc.value }])
    } else {
        emit("update:sorting", [{ id: key, desc: defaultDesc }])
        open.value = false
    }
}
</script>

<template>
    <Popover :open="open" @update:open="open = $event">
        <PopoverTrigger as-child>
            <Button variant="outline" class="w-full justify-between gap-2">
                <span class="flex items-center gap-2">
                    <ArrowUpDown class="h-4 w-4" />
                    <span>Sort</span>
                </span>
            </Button>
        </PopoverTrigger>
        <PopoverContent class="z-50 w-(--reka-popover-trigger-width) bg-popover p-1" align="start">
            <button
                v-for="option in options"
                :key="option.key"
                class="flex w-full items-center justify-between rounded-sm px-2 py-1.5 text-sm hover:bg-accent"
                @click="onSelect(option.key, option.defaultDesc)"
            >
                <span class="flex items-center gap-2">
                    <Check
                        v-if="activeField === option.key"
                        class="h-3.5 w-3.5"
                    />
                    <span v-else class="h-3.5 w-3.5" />
                    {{ option.label }}
                </span>
                <ArrowDown v-if="activeField === option.key && activeDesc" class="h-3.5 w-3.5 text-muted-foreground" />
                <ArrowUp v-else-if="activeField === option.key && !activeDesc" class="h-3.5 w-3.5 text-muted-foreground" />
            </button>
        </PopoverContent>
    </Popover>
</template>
