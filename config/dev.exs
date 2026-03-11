import Config

config :forgecast, Forgecast.Repo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "forgecast_dev",
    port: 5433,
    show_sensitive_data_on_connection_error: true

config :forgecast, :og_image_dir, Path.expand("../priv/og_images", __DIR__)
