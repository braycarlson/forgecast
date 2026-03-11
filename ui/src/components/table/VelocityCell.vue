<script setup lang="ts">
import { TrendingUp } from "lucide-vue-next"
import { formatVelocity } from "@/types/repo"

defineProps<{
    velocity: number
}>()
</script>

<template>
    <div v-if="formatVelocity(velocity)" class="flex items-center justify-end gap-1 text-green-400">
        <TrendingUp class="h-3.5 w-3.5" />
        {{ formatVelocity(velocity) }}
    </div>
    <span v-else class="text-right block text-muted-foreground">—</span>
</template>
