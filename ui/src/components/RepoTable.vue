<script setup lang="ts">
import { h } from "vue"
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
import { Badge } from "@/components/ui/badge"
import { Star, GitFork } from "lucide-vue-next"
import MirrorLink from "@/components/MirrorLink.vue"
import SortableHeader from "@/components/table/SortableHeader.vue"
import RepoCell from "@/components/table/RepoCell.vue"
import StatCell from "@/components/table/StatCell.vue"
import VelocityCell from "@/components/table/VelocityCell.vue"
import type { Repo } from "@/types/repo"

const props = defineProps<{
    repos: Repo[]
    sorting: SortingState
}>()

const emit = defineEmits<{
    "update:sorting": [value: SortingState]
}>()

const columns: ColumnDef<Repo>[] = [
    {
        accessorKey: "name",
        header: ({ column }) => h(SortableHeader, { column, label: "Repository" }),
        cell: ({ row }) => h(RepoCell, { repo: row.original }),
    },
    {
        accessorKey: "language",
        header: ({ column }) => h(SortableHeader, { column, label: "Language" }),
        cell: ({ row }) => {
            const lang = row.getValue<string | null>("language")
            return lang
                ? h(Badge, { variant: "outline", class: "text-xs" }, () => lang)
                : h("span", { class: "text-muted-foreground" }, "—")
        },
    },
    {
        accessorKey: "stars",
        header: ({ column }) => h(SortableHeader, { column, label: "Stars", align: "right" }),
        cell: ({ row }) => h(StatCell, { value: row.getValue<number>("stars"), icon: Star }),
    },
    {
        accessorKey: "forks",
        header: ({ column }) => h(SortableHeader, { column, label: "Forks", align: "right" }),
        cell: ({ row }) => h(StatCell, { value: row.getValue<number>("forks"), icon: GitFork }),
    },
    {
        accessorKey: "star_velocity",
        header: ({ column }) => h(SortableHeader, { column, label: "Velocity", align: "right" }),
        cell: ({ row }) => h(VelocityCell, { velocity: row.getValue<number>("star_velocity") }),
    },
    {
        accessorKey: "platform",
        enableSorting: false,
        header: "Platform",
        cell: ({ row }) => {
            const repo = row.original
            return h(MirrorLink, {
                mirrors: [{ platform: repo.platform, url: repo.url }, ...(repo.mirrors ?? [])],
            })
        },
    },
]

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
    <div class="overflow-x-auto rounded-lg border border-border">
        <Table>
            <TableHeader>
                <TableRow v-for="headerGroup in table.getHeaderGroups()" :key="headerGroup.id">
                    <TableHead v-for="header in headerGroup.headers" :key="header.id">
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
                    <TableCell v-for="cell in row.getVisibleCells()" :key="cell.id">
                        <FlexRender
                            :render="cell.column.columnDef.cell"
                            :props="cell.getContext()"
                        />
                    </TableCell>
                </TableRow>
                <TableRow v-if="table.getRowModel().rows.length === 0">
                    <TableCell :colspan="columns.length" class="h-24 text-center text-muted-foreground">
                        No repositories match your filters.
                    </TableCell>
                </TableRow>
            </TableBody>
        </Table>
    </div>
</template>
