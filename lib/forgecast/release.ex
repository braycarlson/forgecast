defmodule Forgecast.Release do
    @moduledoc """
    Release tasks that can be run without Mix, used for
    running migrations inside Docker containers.

    Usage:
        bin/forgecast eval "Forgecast.Release.migrate()"
        bin/forgecast eval "Forgecast.Release.create_and_migrate()"
    """

    @app :forgecast

    @spec create_and_migrate() :: :ok
    def create_and_migrate do
        load_app()

        for repo <- repos() do
            create_repo(repo)
            {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
        end

        :ok
    end

    @spec migrate() :: :ok
    def migrate do
        load_app()

        for repo <- repos() do
            {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
        end

        :ok
    end

    @spec rollback(module(), integer()) :: :ok
    def rollback(repo, version) do
        load_app()
        {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
        :ok
    end

    defp create_repo(repo) do
        case repo.__adapter__().storage_up(repo.config()) do
            :ok -> :ok
            {:error, :already_up} -> :ok
            {:error, reason} -> raise "Could not create database: #{inspect(reason)}"
        end
    end

    defp repos do
        Application.fetch_env!(@app, :ecto_repos)
    end

    defp load_app do
        Application.load(@app)
    end
end
