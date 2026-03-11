import Config

if url = System.get_env("DATABASE_URL") do
    config :forgecast, Forgecast.Repo,
        url: url,
        pool_size: String.to_integer(System.get_env("POOL_SIZE", "2")),
        socket_options: if(System.get_env("FLY_APP_NAME"), do: [:inet6], else: [])
end

if host = System.get_env("DB_HOST") do
    config :forgecast, Forgecast.Repo, hostname: host
end

config :forgecast, :og_image_dir, System.get_env("OG_IMAGE_DIR", "/data/og_images")

if config_env() == :prod do
    config :forgecast, :github,
        token: System.get_env("GITHUB_TOKEN")

    config :forgecast, :github_oauth,
        client_id: System.get_env("GITHUB_OAUTH_CLIENT_ID"),
        client_secret: System.get_env("GITHUB_OAUTH_CLIENT_SECRET"),
        redirect_uri: System.get_env(
            "GITHUB_OAUTH_REDIRECT_URI",
            "https://forgecast.fly.dev/api/auth/github/callback"
        )

    cors_origins =
        "CORS_ORIGINS"
        |> System.get_env("http://localhost:5173")
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)

    config :forgecast, :server,
        port: String.to_integer(System.get_env("PORT", "4000")),
        secure_cookies: true,
        cors_origins: cors_origins
end

if config_env() == :dev do
    config :forgecast, :github_oauth,
        client_id: System.get_env("GITHUB_OAUTH_CLIENT_ID"),
        client_secret: System.get_env("GITHUB_OAUTH_CLIENT_SECRET"),
        redirect_uri: System.get_env(
            "GITHUB_OAUTH_REDIRECT_URI",
            "http://localhost:3000/api/auth/github/callback"
        )
end
