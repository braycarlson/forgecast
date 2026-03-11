<script setup lang="ts">
import { useAuth } from "@/composables/useAuth"
import { Button } from "@/components/ui/button"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { LogOut } from "lucide-vue-next"
import { ref } from "vue"

const { user, loading, login, logout } = useAuth()
const open = ref(false)

async function handleLogout() {
    open.value = false
    await logout()
}
</script>

<template>
    <div v-if="!loading">
        <Button
            v-if="!user"
            variant="outline"
            size="sm"
            class="gap-2"
            @click="login"
        >
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12" />
            </svg>
            Sign in
        </Button>

        <Popover v-else :open="open" @update:open="open = $event">
            <PopoverTrigger as-child>
                <button class="flex items-center gap-2 rounded-full transition-opacity hover:opacity-80">
                    <img
                        v-if="user.avatar_url"
                        :src="user.avatar_url"
                        :alt="user.username"
                        class="h-8 w-8 rounded-full border border-border"
                    />
                    <span
                        v-else
                        class="flex h-8 w-8 items-center justify-center rounded-full border border-border bg-muted text-sm font-medium"
                    >
                        {{ user.username.charAt(0).toUpperCase() }}
                    </span>
                </button>
            </PopoverTrigger>
            <PopoverContent class="w-[200px] p-2" align="end">
                <div class="px-2 py-1.5 text-sm">
                    <p class="font-medium text-foreground">{{ user.display_name || user.username }}</p>
                    <p class="text-xs text-muted-foreground">@{{ user.username }}</p>
                </div>
                <div class="my-1 h-px bg-border" />
                <button
                    class="flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-sm text-muted-foreground hover:bg-accent hover:text-foreground"
                    @click="handleLogout"
                >
                    <LogOut class="h-4 w-4" />
                    Sign out
                </button>
            </PopoverContent>
        </Popover>
    </div>
</template>
