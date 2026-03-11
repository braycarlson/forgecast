<script setup lang="ts">
import { ref, nextTick } from "vue"
import { ExternalLink } from "lucide-vue-next"
import type { Repo } from "@/types/repo"

defineProps<{
    repo: Repo
}>()

const expanded = ref(false)
const overflows = ref(false)
const descriptionRef = ref<HTMLParagraphElement | null>(null)

function checkTruncation() {
    nextTick(() => {
        const el = descriptionRef.value
        if (el) {
            overflows.value = el.scrollWidth > el.clientWidth
        }
    })
}

function toggleExpanded(event: Event) {
    event.preventDefault()
    event.stopPropagation()
    expanded.value = !expanded.value
}
</script>

<template>
    <div class="flex items-start gap-2">
        <img
            v-if="repo.avatar_url"
            :src="repo.avatar_url"
            :alt="repo.owner"
            class="h-5 w-5 shrink-0 rounded-full mt-0.5"
        />
        <div class="min-w-0">
            <a
                :href="repo.url"
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center gap-1 font-medium text-primary hover:underline"
            >
                <span class="truncate">{{ repo.owner }}/{{ repo.name }}</span>
                <ExternalLink class="h-3 w-3 shrink-0 opacity-50" />
            </a>
            <div v-if="repo.description">
                <p
                    ref="descriptionRef"
                    class="text-xs text-muted-foreground max-w-md"
                    :class="expanded ? 'whitespace-normal' : 'truncate'"
                    @vue:mounted="checkTruncation"
                >
                    {{ repo.description }}
                </p>
                <button
                    v-if="overflows || expanded"
                    class="text-xs text-primary/70 hover:text-primary transition-colors"
                    @click="toggleExpanded"
                >
                    {{ expanded ? "Show less" : "Show more" }}
                </button>
            </div>
        </div>
    </div>
</template>
