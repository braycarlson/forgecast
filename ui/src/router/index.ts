import { createRouter, createWebHistory } from "vue-router"

const router = createRouter({
    history: createWebHistory(),
    routes: [
        {
            path: "/",
            name: "trending",
            component: () => import("@/views/TrendingView.vue"),
        },
    ],
})

export default router
