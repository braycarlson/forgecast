<script setup lang="ts">
import { computed } from "vue"
import { Database, Globe, Code } from "lucide-vue-next"
import { formatNumber } from "@/types/repo"

const props = defineProps<{
    totalItems: number
    platforms: string[]
    languages: string[]
    timeWindow: string
    loading: boolean
}>()

const stats = computed(() => [
    {
        icon: Database,
        value: formatNumber(props.totalItems),
        label: "repos",
    },
    {
        icon: Globe,
        value: props.platforms.length.toString(),
        label: props.platforms.length === 1 ? "platform" : "platforms",
    },
    {
        icon: Code,
        value: props.languages.length.toString(),
        label: "languages",
    },
])
</script>

<template>
    <div class="relative overflow-hidden rounded-xl border border-border bg-card">
        <!-- Ambient glows -->
        <div class="pointer-events-none absolute -top-20 right-12 h-56 w-56 rounded-full bg-primary/8 blur-3xl" />
        <div class="pointer-events-none absolute -bottom-24 -left-12 h-44 w-44 rounded-full bg-chart-5/8 blur-3xl" />
        <div class="pointer-events-none absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 h-32 w-64 rounded-full bg-chart-2/5 blur-3xl" />

        <!-- Subtle grid pattern -->
        <div class="pointer-events-none absolute inset-0 opacity-[0.03] grid-pattern" />

        <div class="relative px-5 py-6 sm:px-8 sm:py-10">
            <div>
                <h1 class="header-gradient-text text-2xl font-bold tracking-tight leading-snug sm:text-4xl">
                    Discover what's trending
                </h1>

                <p class="mt-1.5 max-w-md text-sm text-muted-foreground/80">
                    Real-time trending repositories across GitHub, GitLab, and Codeberg.
                </p>
            </div>

            <!-- Stat pills -->
            <div
                v-if="!loading"
                class="mt-4 flex items-center gap-1.5 sm:gap-2"
            >
                <div
                    v-for="stat in stats"
                    :key="stat.label"
                    class="flex items-center rounded-lg border border-border bg-background/60 px-2 py-1 text-xs backdrop-blur-sm sm:px-3 sm:py-2 sm:text-sm"
                >
                    <component :is="stat.icon" class="mr-1.5 h-3 w-3 shrink-0 text-primary/60 sm:h-3.5 sm:w-3.5" />
                    <span class="font-semibold text-foreground">{{ stat.value }}</span>
                    <span class="ml-1 text-muted-foreground">{{ stat.label }}</span>
                </div>
            </div>
        </div>

        <!-- Bottom accent line -->
        <div class="header-accent" />
    </div>
</template>

<style scoped>
.header-gradient-text {
    background: linear-gradient(
        135deg,
        oklch(0.68 0.22 275) 0%,
        oklch(0.65 0.20 300) 40%,
        oklch(0.70 0.16 310) 100%
    );
    background-clip: text;
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
}

.grid-pattern {
    background-image: radial-gradient(circle, currentColor 1px, transparent 1px);
    background-size: 24px 24px;
}
</style>
