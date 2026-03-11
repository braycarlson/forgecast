import Config

config :forgecast,
    ecto_repos: [Forgecast.Repo]

config :forgecast, Forgecast.Repo,
    migration_source: "migrations"

config :forgecast, :server,
    port: 4000,
    cors_origins: ["http://localhost:5173"]

config :forgecast, :poller,
    platforms: [
        {Forgecast.Platform.Github, "github"},
        {Forgecast.Platform.Codeberg, "codeberg"},
        {Forgecast.Platform.Gitlab, "gitlab"}
    ],
    languages: [
        "python", "rust", "go", "elixir", "typescript", "javascript",
        "zig", "c", "cpp", "java", "ruby", "swift", "kotlin", "c-sharp",
        "lua", "haskell", "scala", "dart", "php", "r"
    ],
    budget: %{
        # GitHub: authenticated token gives 5k/hr REST, 5k pts/hr GraphQL.
        # Event stream + ETags on search handle most discovery cheaply.
        # 200/hr leaves plenty of headroom for monitoring hot repos.
        "github" => 200,
        # GitLab/Codeberg: no event stream, but ETags on search/fetch
        # mean most stable queries return 304 at zero cost.
        "gitlab" => 80,
        "codeberg" => 80
    }

config :forgecast, :trending,
    stale_days: 7,
    max_per_page: 100

config :forgecast, :og_image_dir, Path.expand("../priv/og_images", __DIR__)

# Console: info and above only (no Ecto query spam).
# File handler is added at runtime in application.ex.
config :logger, level: :debug
config :logger, :default_handler, level: :info

if File.exists?("config/#{config_env()}.exs") do
    import_config "#{config_env()}.exs"
end
