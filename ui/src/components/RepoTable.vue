<script setup lang="ts">
import { h, ref, onMounted, onUnmounted } from "vue"
import type { ColumnDef, SortingState } from "@tanstack/vue-table"
import {
    FlexRender,
    getCoreRowModel,
    useVueTable,
} from "@tanstack/vue-table"
import {
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow,
} from "@/components/ui/table"
import { Star, GitFork, TrendingUp, ExternalLink } from "lucide-vue-next"
import SortableHeader from "@/components/table/SortableHeader.vue"
import MirrorLink from "@/components/MirrorLink.vue"
import type { Repo } from "@/types/repo"
import { formatNumber, formatVelocity, LANGUAGE_COLORS, allPlatformLinks } from "@/types/repo"

const props = defineProps<{
    repos: Repo[]
    sorting: SortingState
}>()

const emit = defineEmits<{
    "update:sorting": [value: SortingState]
}>()

const columns: ColumnDef<Repo>[] = [
    {
        id: "name",
        accessorKey: "name",
        meta: { class: "pl-4 sm:pl-6" },
        header: ({ column }) => h(SortableHeader, { column, label: "Repository" }),
        cell: ({ row }) => {
            const repo = row.original

            return h("div", { class: "flex items-start gap-3 py-1" }, [
                repo.avatar_url
                    ? h("img", {
                        src: repo.avatar_url,
                        alt: repo.owner,
                        class: "h-6 w-6 shrink-0 rounded-full mt-0.5",
                    })
                    : null,
                h("div", { class: "min-w-0" }, [
                    h("a", {
                        href: repo.url,
                        target: "_blank",
                        rel: "noopener noreferrer",
                        class: "flex items-center gap-1 font-medium text-primary hover:underline",
                    }, [
                        h("span", { class: "truncate" }, repo.name),
                        h(ExternalLink, { class: "h-2.5 w-2.5 shrink-0 opacity-50" }),
                    ]),
                    repo.description
                        ? h("p", {
                            class: "text-[11px] text-muted-foreground/70 leading-relaxed truncate max-w-md",
                        }, repo.description)
                        : null,
                ]),
            ])
        },
    },
    {
        id: "language",
        accessorKey: "language",
        meta: { class: "text-center" },
        header: ({ column }) => h(SortableHeader, { column, label: "Language", align: "center" }),
        cell: ({ row }) => {
            const lang = row.getValue<string | null>("language")
            if (!lang) return h("span", { class: "text-muted-foreground/40" }, "—")
            const color = LANGUAGE_COLORS[lang] ?? "#6b7280"
            return h("div", { class: "flex items-center justify-center gap-2 text-xs" }, [
                h("span", {
                    class: "h-2 w-2 shrink-0 rounded-full",
                    style: { backgroundColor: color },
                }),
                lang,
            ])
        },
    },
    {
        id: "stars",
        accessorKey: "stars",
        meta: { class: "text-center" },
        header: ({ column }) => h(SortableHeader, { column, label: "Stars", align: "center" }),
        cell: ({ row }) => {
            return h("div", { class: "flex items-center justify-center gap-1.5 tabular-nums" }, [
                h(Star, { class: "h-3 w-3 text-muted-foreground" }),
                formatNumber(row.getValue<number>("stars")),
            ])
        },
    },
    {
        id: "forks",
        accessorKey: "forks",
        meta: { class: "text-center" },
        header: ({ column }) => h(SortableHeader, { column, label: "Forks", align: "center" }),
        cell: ({ row }) => {
            return h("div", { class: "flex items-center justify-center gap-1.5 tabular-nums" }, [
                h(GitFork, { class: "h-3 w-3 text-muted-foreground" }),
                formatNumber(row.getValue<number>("forks")),
            ])
        },
    },
    {
        id: "star_velocity",
        accessorKey: "star_velocity",
        meta: { class: "text-center" },
        header: ({ column }) => h(SortableHeader, { column, label: "Velocity", align: "center" }),
        cell: ({ row }) => {
            const velocity = row.getValue<number>("star_velocity")
            const formatted = formatVelocity(velocity)
            if (formatted) {
                return h("div", { class: "flex justify-center" }, [
                    h("span", {
                        class: "inline-flex items-center gap-1 rounded-full bg-green-500/10 px-2 py-0.5 text-[11px] font-medium text-green-400 ring-1 ring-green-400/20",
                    }, [
                        h(TrendingUp, { class: "h-2.5 w-2.5" }),
                        formatted,
                    ]),
                ])
            }
            return h("div", { class: "flex justify-center" }, [
                h("span", {
                    class: "inline-flex items-center gap-1 rounded-full bg-muted/50 px-2 py-0.5 text-[11px] text-muted-foreground/40 ring-1 ring-border/30",
                }, [
                    h(TrendingUp, { class: "h-2.5 w-2.5" }),
                    "—",
                ]),
            ])
        },
    },
    {
        id: "platform",
        accessorKey: "platform",
        meta: { class: "text-center pr-4 sm:pr-6" },
        header: ({ column }) => h(SortableHeader, { column, label: "Platform", align: "center" }),
        cell: ({ row }) => {
            const repo = row.original
            return h("div", { class: "flex justify-center" }, [
                h(MirrorLink, {
                    mirrors: allPlatformLinks(repo),
                }),
            ])
        },
    },
]

const scrollRef = ref<HTMLDivElement | null>(null)
const isDragging = ref(false)
let startX = 0
let scrollLeft = 0

function onMouseDown(e: MouseEvent) {
    const el = scrollRef.value
    if (!el || el.scrollWidth <= el.clientWidth) return
    isDragging.value = true
    startX = e.pageX - el.offsetLeft
    scrollLeft = el.scrollLeft
    el.style.cursor = "grabbing"
    el.style.userSelect = "none"
}

function onMouseMove(e: MouseEvent) {
    if (!isDragging.value) return
    const el = scrollRef.value
    if (!el) return
    e.preventDefault()
    const x = e.pageX - el.offsetLeft
    el.scrollLeft = scrollLeft - (x - startX)
}

function onMouseUp() {
    if (!isDragging.value) return
    isDragging.value = false
    const el = scrollRef.value
    if (el) {
        el.style.cursor = ""
        el.style.userSelect = ""
    }
}

onMounted(() => {
    document.addEventListener("mousemove", onMouseMove)
    document.addEventListener("mouseup", onMouseUp)
})

onUnmounted(() => {
    document.removeEventListener("mousemove", onMouseMove)
    document.removeEventListener("mouseup", onMouseUp)
})

const table = useVueTable({
    get data() { return props.repos },
    get columns() { return columns },
    state: {
        get sorting() { return props.sorting },
    },
    onSortingChange: (updater) => {
        const next = typeof updater === "function" ? updater(props.sorting) : updater
        emit("update:sorting", next)
    },
    getCoreRowModel: getCoreRowModel(),
    manualSorting: true,
    manualPagination: true,
})
</script>

<template>
    <div
        ref="scrollRef"
        class="overflow-x-auto rounded-lg border border-border text-xs cursor-grab"
        @mousedown="onMouseDown"
    >
        <Table class="min-w-[700px] sm:min-w-0 w-full">
            <TableHeader>
                <TableRow v-for="headerGroup in table.getHeaderGroups()" :key="headerGroup.id">
                    <TableHead
                        v-for="header in headerGroup.headers"
                        :key="header.id"
                        :class="(header.column.columnDef.meta as Record<string, string>)?.class"
                    >
                        <FlexRender
                            v-if="!header.isPlaceholder"
                            :render="header.column.columnDef.header"
                            :props="header.getContext()"
                        />
                    </TableHead>
                </TableRow>
            </TableHeader>
            <TableBody>
                <TableRow
                    v-for="row in table.getRowModel().rows"
                    :key="row.id"
                    class="transition-colors hover:bg-muted/30"
                >
                    <TableCell
                        v-for="cell in row.getVisibleCells()"
                        :key="cell.id"
                        :class="[
                            'py-2.5',
                            (cell.column.columnDef.meta as Record<string, string>)?.class,
                        ]"
                    >
                        <FlexRender
                            :render="cell.column.columnDef.cell"
                            :props="cell.getContext()"
                        />
                    </TableCell>
                </TableRow>
                <TableRow v-if="table.getRowModel().rows.length === 0">
                    <TableCell :colspan="columns.length" class="h-24 px-6 text-center text-muted-foreground">
                        No repositories match your filters.
                    </TableCell>
                </TableRow>
            </TableBody>
        </Table>
    </div>
</template>
