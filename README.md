<p align="center">
    <a href="https://forgecast.io">
        <img src="assets/forgecast.svg" alt="Forgecast" width="120" />
    </a>
    <br>
    <a href="https://forgecast.io">
        <img src="assets/title.svg" alt="Forgecast" width="320" />
    </a>
    <br><br>
    Track trending repositories across GitHub, GitLab, and Codeberg in real time.
</p>

---

Forgecast surfaces repositories gaining traction right now. It combines live event streams with search-based polling across three platforms, computing star and fork velocity on a rolling window so you can see what's trending — not just what's already popular.

## Features

- **Multi-platform** - GitHub, GitLab, and Codeberg from a single interface, with automatic cross-platform mirror detection.
- **Real-time velocity** - Star and fork rates updated every 30 seconds, distinguishing actively rising repos from historically popular ones.
- **Search and filter** - Filter by platform, language, or free-text search. Sort by score, stars, velocity, or name.
- **Cursor pagination** - Efficient deep paging across millions of repositories.
- **OG image previews** - Cached preview images with velocity-aware refresh intervals.
- **GitHub OAuth** - Sign in to save favorite languages, filters, and display preferences.

## Stack

| Layer | Technology |
|-------|-----------|
| Backend | Elixir, Bandit, Ecto |
| Database | PostgreSQL + TimescaleDB |
| Frontend | Vue + Vite |
| Deployment | Fly.io |

## Requirements

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose
- [just](https://github.com/casey/just)

For local development without Docker:

- Elixir 1.19+
- PostgreSQL 17 with [TimescaleDB](https://docs.timescale.com/)
- [Bun](https://bun.sh/)

## Getting Started

```bash
git clone https://github.com/braycarlson/forgecast.git
cd forgecast
just docker-reset
```
## Environment Variables

| Variable | Description |
|----------|-------------|
| `GITHUB_TOKEN` | GitHub personal access token for API polling |
| `GITHUB_OAUTH_CLIENT_ID` | GitHub OAuth app client ID |
| `GITHUB_OAUTH_CLIENT_SECRET` | GitHub OAuth app client secret |
| `GITHUB_OAUTH_REDIRECT_URI` | OAuth callback URL |
| `POLLER` | Set to `false` to disable all background polling |

## License

MIT
