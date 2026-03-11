<script setup lang="ts">
import type { Mirror } from "@/types/repo"
import { formatPlatform } from "@/types/repo"
import PlatformIcon from "@/components/icons/PlatformIcon.vue"

defineProps<{
    mirrors: Mirror[]
}>()
</script>

<template>
    <div v-if="mirrors.length > 0" class="flex items-center gap-1.5">
        <a
            v-for="mirror in mirrors"
            :key="mirror.platform"
            :href="mirror.url"
            target="_blank"
            rel="noopener noreferrer"
            :title="`View on ${formatPlatform(mirror.platform)}`"
            class="transition-opacity hover:opacity-100 opacity-60"
            @click.stop
        >
            <PlatformIcon :platform="mirror.platform" />
        </a>
    </div>
</template>
