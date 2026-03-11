import Config

config :forgecast, Forgecast.Repo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "forgecast_test",
    port: 5433,
    pool: Ecto.Adapters.SQL.Sandbox

config :forgecast,
    env: :test

config :forgecast, :github,
    token: nil

config :logger, level: :warning
