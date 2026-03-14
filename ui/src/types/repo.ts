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
    "ABAP": "#E8274B",
    "ActionScript": "#882B0F",
    "Ada": "#02f88c",
    "Agda": "#315665",
    "Assembly": "#6E4C13",
    "Astro": "#ff5a03",
    "Ballerina": "#FF5000",
    "Batchfile": "#C1F12E",
    "Bicep": "#519aba",
    "C": "#555555",
    "C#": "#178600",
    "C++": "#f34b7d",
    "Clojure": "#db5855",
    "CMake": "#DA3434",
    "COBOL": "#005ca5",
    "CoffeeScript": "#244776",
    "Crystal": "#000100",
    "CSS": "#563d7c",
    "Cuda": "#3A4E3A",
    "D": "#ba595e",
    "Dart": "#00B4AB",
    "Delphi": "#E3F171",
    "Dockerfile": "#384d54",
    "Elixir": "#6e4a7e",
    "Elm": "#60B5CC",
    "Emacs Lisp": "#c065db",
    "Erlang": "#B83998",
    "F#": "#b845fc",
    "Fortran": "#4d41b1",
    "GDScript": "#355570",
    "Gleam": "#ffaff3",
    "Go": "#00ADD8",
    "Groovy": "#4298b8",
    "Hack": "#878787",
    "Haskell": "#5e5086",
    "HCL": "#844FBA",
    "HTML": "#e34c26",
    "Haxe": "#df7900",
    "Java": "#b07219",
    "JavaScript": "#f1e05a",
    "JSON": "#292929",
    "Julia": "#a270ba",
    "Jupyter Notebook": "#DA5B0B",
    "Just": "#384d54",
    "Kotlin": "#A97BFF",
    "LaTeX": "#3D6117",
    "Lua": "#000080",
    "Makefile": "#427819",
    "Markdown": "#083fa1",
    "MATLAB": "#e16737",
    "MDX": "#fcb32c",
    "Mojo": "#ff4c1f",
    "Nim": "#ffc200",
    "Nix": "#7e7eff",
    "Nushell": "#4E9906",
    "Objective-C": "#438eff",
    "OCaml": "#ef7a08",
    "Odin": "#60AFFE",
    "Pascal": "#E3F171",
    "Perl": "#0298c3",
    "PHP": "#4F5D95",
    "PLpgSQL": "#336790",
    "PowerShell": "#012456",
    "Prolog": "#74283c",
    "Protobuf": "#4a6f8a",
    "Python": "#3572A5",
    "R": "#198CE7",
    "Racket": "#3c5caa",
    "Raku": "#0000fb",
    "Ruby": "#701516",
    "Rust": "#dea584",
    "Sass": "#a53b70",
    "Scala": "#c22d40",
    "Scheme": "#1e4aec",
    "SCSS": "#c6538c",
    "Shell": "#89e051",
    "Solidity": "#AA6746",
    "SQL": "#e38c00",
    "Starlark": "#76d275",
    "Svelte": "#ff3e00",
    "Swift": "#F05138",
    "Tcl": "#e4cc98",
    "Terraform": "#7b42bc",
    "TeX": "#3D6117",
    "TOML": "#9c4221",
    "TypeScript": "#3178c6",
    "V": "#4f87c4",
    "Vala": "#a56de2",
    "Vim Script": "#199f4b",
    "Vue": "#41b883",
    "WebAssembly": "#04133b",
    "YAML": "#cb171e",
    "Zig": "#ec915c",
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
    if (n >= 1_000_000) return (n / 1_000_000).toFixed(1).replace(/\.0$/, "") + "M"
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
