export interface Mirror {
    platform: string
    url: string
}

export interface Repo {
    id: number
    platform: string
    name: string
    owner: string
    description: string | null
    language: string | null
    url: string
    topics: string[]
    stars: number
    forks: number
    open_issues: number
    avatar_url: string | null
    og_image_url: string | null
    score: number
    star_velocity: number
    fork_velocity: number
    mirrors: Mirror[]
}

export const LANGUAGE_COLORS: Readonly<Record<string, string>> = {
    Python: "#3572A5",
    Rust: "#dea584",
    Go: "#00ADD8",
    Elixir: "#6e4a7e",
    TypeScript: "#3178c6",
    JavaScript: "#f1e05a",
    Zig: "#ec915c",
    C: "#555555",
    "C++": "#f34b7d",
    Java: "#b07219",
    Ruby: "#701516",
    Swift: "#F05138",
}

const PLATFORM_NAMES: Readonly<Record<string, string>> = {
    github: "GitHub",
    gitlab: "GitLab",
    codeberg: "Codeberg",
}

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:4000/api"

export function formatPlatform(platform: string): string {
    return PLATFORM_NAMES[platform.toLowerCase()] ?? platform
}

export function formatNumber(n: number): string {
    if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, "") + "k"
    return n.toString()
}

export function formatVelocity(v: number): string {
    if (v === 0) return ""
    if (v >= 1) return `+${v.toFixed(1)}/hr`
    const perDay = v * 24
    if (perDay >= 1) return `+${perDay.toFixed(1)}/day`
    return ""
}

export function bannerGradient(repo: Repo): string {
    const color = LANGUAGE_COLORS[repo.language ?? ""] ?? "#30363d"
    return `linear-gradient(135deg, ${color}33 0%, ${color}11 100%)`
}

export function resolveOgImageUrl(url: string | null): string | null {
    if (!url) return null
    if (url.startsWith("http")) return url
    return `${API_URL.replace(/\/api\/?$/, "")}${url}`
}

export function allPlatformLinks(repo: Repo): Mirror[] {
    return [
        { platform: repo.platform, url: repo.url },
        ...(repo.mirrors ?? []),
    ]
}
