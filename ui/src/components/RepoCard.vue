<script setup lang="ts">
import { ref, computed, nextTick } from "vue"
import { Card } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Star, GitFork, TrendingUp } from "lucide-vue-next"
import MirrorLink from "@/components/MirrorLink.vue"
import TopicBadge from "@/components/TopicBadge.vue"
import type { Repo } from "@/types/repo"
import { formatNumber, formatVelocity, bannerGradient, resolveOgImageUrl, allPlatformLinks } from "@/types/repo"

const props = defineProps<{
    repo: Repo
    showOgImage: boolean
    layout?: "list" | "grid"
}>()

const emit = defineEmits<{
    imageError: [repoId: number]
}>()

const ogLoaded = ref(false)
const avatarLoaded = ref(false)
const expanded = ref(false)
const descriptionRef = ref<HTMLParagraphElement | null>(null)
const overflows = ref(false)

const ready = computed(() => isList.value || !props.showOgImage || ogLoaded.value)
const resolvedOgUrl = computed(() => resolveOgImageUrl(props.repo.og_image_url))
const platforms = computed(() => allPlatformLinks(props.repo))
const isList = computed(() => props.layout === "list")

function checkTruncation() {
    nextTick(() => {
        const el = descriptionRef.value
        if (el) {
            overflows.value = el.scrollHeight > el.clientHeight
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
    <a
        :href="repo.url"
        target="_blank"
        rel="noopener noreferrer"
        class="flex w-full no-underline"
    >
        <Card
            class="flex w-full gap-0 overflow-hidden py-0 transition-[colors,opacity] duration-300 hover:border-primary"
            :class="[
                ready ? 'opacity-100' : 'opacity-0',
                isList ? 'flex-col sm:flex-row sm:items-stretch' : 'flex-col',
            ]"
        >
            <!-- Image -->
            <div
                v-if="!isList"
                class="relative shrink-0 overflow-hidden aspect-[2/1]"
            >
                <div
                    class="absolute inset-0 flex items-end p-4"
                    :style="{ background: bannerGradient(repo) }"
                >
                    <span
                        v-if="!showOgImage || !ogLoaded"
                        class="text-lg font-semibold text-foreground/80"
                    >
                        {{ repo.name }}
                    </span>
                </div>
                <img
                    v-if="showOgImage && resolvedOgUrl"
                    :src="resolvedOgUrl"
                    :alt="repo.name"
                    loading="lazy"
                    class="absolute inset-0 h-full w-full object-cover transition-opacity duration-300"
                    :class="ogLoaded ? 'opacity-100' : 'opacity-0'"
                    @load="ogLoaded = true"
                    @error="emit('imageError', repo.id)"
                />
            </div>

            <!-- Content -->
            <div
                class="flex min-w-0 flex-1 flex-col justify-between p-4"
                :class="isList ? 'py-4 sm:pl-6' : 'pt-3 pb-5'"
            >
                <div class="space-y-1.5">
                    <div class="flex items-center justify-between">
                        <div class="flex items-center gap-2.5 overflow-hidden">
                            <div v-if="repo.avatar_url" class="relative h-7 w-7 shrink-0">
                                <div
                                    class="absolute inset-0 rounded-full bg-muted animate-pulse"
                                    :class="{ 'hidden': avatarLoaded }"
                                />
                                <img
                                    :src="repo.avatar_url"
                                    :alt="repo.owner"
                                    loading="lazy"
                                    class="h-7 w-7 rounded-full transition-opacity duration-200"
                                    :class="avatarLoaded ? 'opacity-100' : 'opacity-0'"
                                    @load="avatarLoaded = true"
                                />
                            </div>
                            <span class="truncate text-base font-semibold text-primary">
                                {{ repo.name }}
                            </span>
                        </div>
                        <MirrorLink :mirrors="platforms" />
                    </div>

                    <div v-if="repo.description">
                        <p
                            ref="descriptionRef"
                            class="text-sm text-muted-foreground transition-all duration-200"
                            :class="expanded ? '' : 'line-clamp-2'"
                            @vue:mounted="checkTruncation"
                        >
                            {{ repo.description }}
                        </p>
                        <button
                            v-if="overflows || expanded"
                            class="mt-0.5 text-xs text-primary/70 hover:text-primary transition-colors"
                            @click="toggleExpanded"
                        >
                            {{ expanded ? "Show less" : "Show more" }}
                        </button>
                    </div>
                    <p v-else class="text-sm text-muted-foreground">
                        No description
                    </p>

                    <div class="pt-1.5 min-h-[28px]">
                        <TopicBadge v-if="repo.topics.length > 0" :topics="repo.topics" :max="isList ? 6 : 4" />
                    </div>
                </div>

                <div class="mt-6 flex items-center gap-3 text-sm text-muted-foreground">
                    <Badge v-if="repo.language" variant="outline">
                        {{ repo.language }}
                    </Badge>
                    <span class="flex items-center gap-1">
                        <Star class="h-3.5 w-3.5" />
                        {{ formatNumber(repo.stars) }}
                    </span>
                    <span class="flex items-center gap-1">
                        <GitFork class="h-3.5 w-3.5" />
                        {{ formatNumber(repo.forks) }}
                    </span>
                    <span
                        v-if="formatVelocity(repo.star_velocity)"
                        class="flex items-center gap-1 text-green-400"
                    >
                        <TrendingUp class="h-3.5 w-3.5" />
                        {{ formatVelocity(repo.star_velocity) }}
                    </span>
                </div>
            </div>
        </Card>
    </a>
</template>
