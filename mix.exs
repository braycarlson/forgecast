defmodule Forgecast.MixProject do
    use Mix.Project

    def project do
        [
            app: :forgecast,
            version: "0.1.0",
            elixir: "~> 1.19.5",
            elixirc_paths: elixirc_paths(Mix.env()),
            start_permanent: Mix.env() == :prod,
            aliases: aliases(),
            deps: deps()
        ]
    end

    def application do
        [
            extra_applications: [:logger],
            mod: {Forgecast.Application, []}
        ]
    end

    defp elixirc_paths(:test), do: ["lib", "test/support"]
    defp elixirc_paths(_), do: ["lib"]

    defp aliases do
        [
            "ecto.reset": ["ecto.drop", "ecto.create", "ecto.migrate"]
        ]
    end

    defp deps do
        [
            {:jason, "~> 1.4.4"},
            {:req, "~> 0.5.17"},
            {:postgrex, "~> 0.22.0"},
            {:ecto_sql, "~> 3.13.5"},
            {:plug, "~> 1.19.1"},
            {:bandit, "~> 1.10.3"},
            {:cors_plug, "~> 3.0.3"},
            {:mox, "~> 1.2.0", only: :test}
        ]
    end
end
