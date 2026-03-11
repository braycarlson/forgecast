<script setup lang="ts">
import { ref, computed } from "vue"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Check, ChevronDown, Star } from "lucide-vue-next"

const props = withDefaults(defineProps<{
    label: string
    options: string[]
    selected: ReadonlySet<string>
    favorites: ReadonlySet<string>
    formatOption?: (value: string) => string
    class?: string
}>(), {
    formatOption: (v: string) => v,
})

const emit = defineEmits<{
    toggleSelected: [value: string]
    toggleFavorite: [value: string]
    clear: []
}>()

const open = ref(false)
const search = ref("")

const sorted = computed(() => {
    const favs = props.options.filter(o => props.favorites.has(o))
    const rest = props.options.filter(o => !props.favorites.has(o))
    const all = [...favs, ...rest]

    if (!search.value) return all
    const q = search.value.toLowerCase()
    return all.filter(o => o.toLowerCase().includes(q))
})

const displayLabel = computed(() => {
    if (props.selected.size === 0) return props.label
    if (props.selected.size === 1) return props.formatOption([...props.selected][0]!)
    return `${props.selected.size} selected`
})

function onOpenChange(value: boolean) {
    open.value = value
    if (!value) search.value = ""
}
</script>

<template>
    <Popover :open="open" @update:open="onOpenChange">
        <PopoverTrigger as-child>
            <Button
                variant="outline"
                class="w-full sm:w-[180px] justify-between"
                :class="props.class"
            >
                <span class="truncate">{{ displayLabel }}</span>
                <ChevronDown class="ml-2 h-4 w-4 shrink-0 opacity-50" />
            </Button>
        </PopoverTrigger>
        <PopoverContent class="z-50 w-(--reka-popover-trigger-width) bg-popover p-0" align="start">
            <div class="p-2">
                <Input
                    v-model="search"
                    placeholder="Search..."
                    class="h-8"
                />
            </div>

            <div class="max-h-[260px] overflow-y-auto">
                <div class="p-1">
                    <button
                        v-for="option in sorted"
                        :key="option"
                        class="flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-sm hover:bg-accent"
                        @click="emit('toggleSelected', option)"
                    >
                        <span class="flex h-4 w-4 shrink-0 items-center justify-center rounded-sm border border-border">
                            <Check v-if="selected.has(option)" class="h-3 w-3" />
                        </span>

                        <span class="flex-1 text-left">{{ formatOption(option) }}</span>

                        <Star
                            :fill="favorites.has(option) ? 'currentColor' : 'none'"
                            class="h-3.5 w-3.5 shrink-0 cursor-pointer hover:text-yellow-400"
                            :class="favorites.has(option) ? 'text-yellow-400' : 'text-muted-foreground/40'"
                            role="button"
                            tabindex="0"
                            @click.stop="emit('toggleFavorite', option)"
                            @keydown.enter.stop="emit('toggleFavorite', option)"
                        />
                    </button>

                    <div v-if="sorted.length === 0" class="px-2 py-4 text-center text-sm text-muted-foreground">
                        No results
                    </div>
                </div>
            </div>

            <div v-if="selected.size > 0" class="border-t border-border p-1">
                <button
                    class="w-full rounded-sm px-2 py-1.5 text-center text-sm text-muted-foreground hover:bg-accent"
                    @click="emit('clear')"
                >
                    Clear filters
                </button>
            </div>
        </PopoverContent>
    </Popover>
</template>
