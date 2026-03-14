<script setup lang="ts">
import { ref, computed, nextTick } from "vue"
import { Card } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Star, GitFork, TrendingUp } from "lucide-vue-next"
import MirrorLink from "@/components/MirrorLink.vue"
import TopicBadge from "@/components/TopicBadge.vue"
import type { Repo } from "@/types/repo"
import { formatNumber, formatVelocity, bannerGradient, resolveOgImageUrl, allPlatformLinks, LANGUAGE_COLORS } from "@/types/repo"

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
const languageColor = computed(() => LANGUAGE_COLORS[props.repo.language ?? ""] ?? "#6b7280")

function checkTruncation() {
    nextTick(() => {
        const el = descriptionRef.value
        if (el) {
            overflows.value = isList.value
                ? el.scrollWidth > el.clientWidth
                : el.scrollHeight > el.clientHeight
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
        class="group flex w-full no-underline"
    >
        <!-- Grid Layout -->
        <Card
            v-if="!isList"
            class="repo-card flex w-full flex-col gap-0 overflow-hidden py-0 transition-all duration-300"
            :class="ready ? 'opacity-100' : 'opacity-0'"
        >
            <div class="relative shrink-0 overflow-hidden aspect-[2/1]">
                <div
                    class="absolute inset-0 flex items-end p-4"
                    :style="{ background: bannerGradient(repo) }"
                >
                    <div
                        class="banner-dots absolute inset-0"
                        :style="{ '--dot-color': languageColor }"
                    />

                    <span
                        v-if="!showOgImage || !ogLoaded"
                        class="relative z-10 text-lg font-semibold text-foreground/80"
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

                <div
                    v-if="formatVelocity(repo.star_velocity)"
                    class="absolute top-3 right-3 z-10 flex items-center gap-1 rounded-full bg-green-500/15 px-2.5 py-1 text-xs font-medium text-green-400 backdrop-blur-sm ring-1 ring-green-400/20"
                >
                    <TrendingUp class="h-3 w-3" />
                    {{ formatVelocity(repo.star_velocity) }}
                </div>
            </div>

            <div class="flex min-w-0 flex-1 flex-col p-4 pb-0">
                <div class="flex-1 space-y-2">
                    <div class="flex items-center justify-between gap-2">
                        <div class="flex items-center gap-2.5 min-w-0">
                            <div v-if="repo.avatar_url" class="relative h-7 w-7 shrink-0">
                                <div
                                    class="absolute inset-0 rounded-full bg-muted animate-pulse"
                                    :class="{ 'hidden': avatarLoaded }"
                                />
                                <img
                                    :src="repo.avatar_url"
                                    :alt="repo.owner"
                                    loading="lazy"
                                    class="h-7 w-7 rounded-full ring-1 ring-border/50 transition-opacity duration-200"
                                    :class="avatarLoaded ? 'opacity-100' : 'opacity-0'"
                                    @load="avatarLoaded = true"
                                />
                            </div>
                            <div class="min-w-0">
                                <span class="block truncate text-[15px] font-semibold text-foreground group-hover:text-primary transition-colors duration-200">
                                    {{ repo.name }}
                                </span>
                                <span class="block truncate text-xs text-muted-foreground/70">
                                    {{ repo.owner }}
                                </span>
                            </div>
                        </div>
                        <MirrorLink :mirrors="platforms" />
                    </div>

                    <div v-if="repo.description" class="pt-1">
                        <p
                            ref="descriptionRef"
                            class="text-[13px] leading-relaxed text-muted-foreground transition-all duration-200"
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
                    <p v-else class="text-[13px] text-muted-foreground/50 italic">
                        No description
                    </p>

                    <div class="min-h-[28px]">
                        <TopicBadge v-if="repo.topics.length > 0" :topics="repo.topics" :max="4" />
                    </div>
                </div>
            </div>

            <div class="mt-auto flex items-center gap-4 border-t border-border/50 px-4 py-3 text-[13px] text-muted-foreground">
                <span v-if="repo.language" class="flex items-center gap-1.5">
                    <span
                        class="h-2.5 w-2.5 shrink-0 rounded-full"
                        :style="{ backgroundColor: languageColor }"
                    />
                    {{ repo.language }}
                </span>
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
                    class="ml-auto flex items-center gap-1 rounded-full bg-green-500/10 px-2.5 py-1 text-xs font-medium text-green-400 ring-1 ring-green-400/20"
                >
                    <TrendingUp class="h-3 w-3" />
                    {{ formatVelocity(repo.star_velocity) }}
                </span>
                <span
                    v-else
                    class="ml-auto flex items-center gap-1 rounded-full bg-muted/50 px-2.5 py-1 text-xs text-muted-foreground/40 ring-1 ring-border/30"
                >
                    <TrendingUp class="h-3 w-3" />
                    —
                </span>
            </div>
        </Card>

        <!-- List Layout -->
        <Card
            v-else
            class="repo-card relative flex w-full flex-col gap-0 overflow-hidden py-0 transition-all duration-300"
        >
            <div class="absolute top-4 right-4">
                <MirrorLink :mirrors="platforms" />
            </div>

            <div class="flex min-w-0 items-start gap-3.5 p-4 pb-0 pr-12 sm:gap-4">
                <img
                    v-if="repo.avatar_url"
                    :src="repo.avatar_url"
                    :alt="repo.owner"
                    class="h-10 w-10 shrink-0 rounded-full ring-1 ring-border/50 mt-0.5"
                />

                <div class="min-w-0 flex-1 space-y-2.5">
                    <div>
                        <span class="truncate block font-semibold text-foreground group-hover:text-primary transition-colors duration-200">
                            {{ repo.owner }}<span class="text-muted-foreground/50">/</span>{{ repo.name }}
                        </span>

                        <div v-if="repo.description" class="mt-1">
                            <p
                                ref="descriptionRef"
                                class="text-[13px] leading-relaxed text-muted-foreground"
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

                    <div v-if="repo.topics.length > 0">
                        <TopicBadge :topics="repo.topics" :max="6" />
                    </div>
                </div>
            </div>

            <div class="flex items-center gap-4 border-t border-border/50 mx-4 mt-3.5 py-3 text-[13px] text-muted-foreground">
                <span v-if="repo.language" class="flex items-center gap-1.5">
                    <span
                        class="h-2.5 w-2.5 shrink-0 rounded-full"
                        :style="{ backgroundColor: languageColor }"
                    />
                    {{ repo.language }}
                </span>
                <span class="flex items-center gap-1 tabular-nums">
                    <Star class="h-3.5 w-3.5" />
                    {{ formatNumber(repo.stars) }}
                </span>
                <span class="flex items-center gap-1 tabular-nums">
                    <GitFork class="h-3.5 w-3.5" />
                    {{ formatNumber(repo.forks) }}
                </span>
                <span
                    v-if="formatVelocity(repo.star_velocity)"
                    class="ml-auto flex items-center gap-1 rounded-full bg-green-500/10 px-2.5 py-1 text-xs font-medium text-green-400 ring-1 ring-green-400/20"
                >
                    <TrendingUp class="h-3 w-3" />
                    {{ formatVelocity(repo.star_velocity) }}
                </span>
                <span
                    v-else
                    class="ml-auto flex items-center gap-1 rounded-full bg-muted/50 px-2.5 py-1 text-xs text-muted-foreground/40 ring-1 ring-border/30"
                >
                    <TrendingUp class="h-3 w-3" />
                    —
                </span>
            </div>
        </Card>
    </a>
</template>

<style scoped>
.repo-card {
    border-color: oklch(0.26 0.03 275 / 50%);
    background: linear-gradient(
        180deg,
        var(--card) 0%,
        oklch(from var(--card) l c h / 80%) 100%
    );
}

.repo-card:hover {
    border-color: oklch(0.68 0.22 275 / 40%);
    box-shadow:
        0 0 0 1px oklch(0.68 0.22 275 / 8%),
        0 4px 24px -4px oklch(0.68 0.22 275 / 12%);
}

.banner-dots {
    background-image: radial-gradient(circle, color-mix(in srgb, var(--dot-color) 30%, transparent) 1px, transparent 1px);
    background-size: 20px 20px;
    mask-image: radial-gradient(ellipse 70% 80% at 30% 50%, black 0%, transparent 100%);
    -webkit-mask-image: radial-gradient(ellipse 70% 80% at 30% 50%, black 0%, transparent 100%);
}
</style>
