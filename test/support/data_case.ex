defmodule Forgecast.DataCase do
    use ExUnit.CaseTemplate

    using do
        quote do
            alias Forgecast.Repo
            alias Forgecast.Schema.{Repository, Snapshot, Project}
            import Ecto.Query
            import Forgecast.DataCase
        end
    end

    setup tags do
        Forgecast.Trending.init_cache()
        Forgecast.Trending.invalidate_cache()

        pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Forgecast.Repo, shared: not tags[:async])
        on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
        :ok
    end

    def insert_repo!(attrs \\ %{}) do
        defaults = %{
            platform: "github",
            platform_id: "#{System.unique_integer([:positive])}",
            name: "owner/repo-#{System.unique_integer([:positive])}",
            owner: "owner",
            url: "https://github.com/owner/repo",
            last_seen_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        }

        {:ok, repo} =
            %Forgecast.Schema.Repository{}
            |> Forgecast.Schema.Repository.changeset(Map.merge(defaults, attrs))
            |> Forgecast.Repo.insert()

        repo
    end

    def insert_snapshot!(repo, attrs \\ %{}) do
        defaults = %{
            repo_id: repo.id,
            stars: 100,
            forks: 10,
            open_issues: 5
        }

        merged = Map.merge(defaults, attrs)
        {inserted_at, merged} = Map.pop(merged, :inserted_at)

        {:ok, snapshot} =
            %Forgecast.Schema.Snapshot{}
            |> Forgecast.Schema.Snapshot.changeset(merged)
            |> then(fn cs ->
                if inserted_at do
                    Ecto.Changeset.force_change(cs, :inserted_at, inserted_at)
                else
                    cs
                end
            end)
            |> Forgecast.Repo.insert()

        snapshot
    end
end
