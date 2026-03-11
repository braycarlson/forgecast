<script setup lang="ts">
import { ref, computed } from "vue"
import { Badge } from "@/components/ui/badge"

const props = withDefaults(defineProps<{
    topics: string[]
    max?: number
}>(), {
    max: 5,
})

const expanded = ref(false)

const visible = computed(() => {
    if (expanded.value) return props.topics
    return props.topics.slice(0, props.max)
})

const remaining = computed(() => props.topics.length - props.max)
</script>

<template>
    <div v-if="topics.length > 0" class="flex flex-wrap items-center gap-1.5">
        <Badge
            v-for="topic in visible"
            :key="topic"
            variant="secondary"
            class="text-[11px] font-normal px-2 py-0"
        >
            {{ topic }}
        </Badge>
        <button
            v-if="remaining > 0 && !expanded"
            class="text-[11px] text-muted-foreground hover:text-foreground transition-colors"
            @click.prevent.stop="expanded = true"
        >
            +{{ remaining }} more
        </button>
        <button
            v-if="expanded && remaining > 0"
            class="text-[11px] text-muted-foreground hover:text-foreground transition-colors"
            @click.prevent.stop="expanded = false"
        >
            show less
        </button>
    </div>
</template>
