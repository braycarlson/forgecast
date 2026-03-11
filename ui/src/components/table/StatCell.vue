<script setup lang="ts">
import type { Component } from "vue"
import { formatNumber } from "@/types/repo"

defineProps<{
    value: number
    icon: Component
}>()
</script>

<template>
    <div class="flex items-center justify-end gap-1">
        <component :is="icon" class="h-3.5 w-3.5 text-muted-foreground" />
        {{ formatNumber(value) }}
    </div>
</template>
