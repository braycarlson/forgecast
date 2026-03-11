defmodule Forgecast.Velocity do
    @moduledoc """
    Shared star velocity computation from snapshot pairs.
    Used by the image cache, poller scheduler, and enricher
    to determine refresh/check intervals based on activity.
    """

    alias Forgecast.Repo
    alias Forgecast.Schema.Snapshot

    import Ecto.Query

    @spec star_velocity(integer()) :: float()
    def star_velocity(repo_id) do
        snapshots =
            from(s in Snapshot,
                where: s.repo_id == ^repo_id,
                order_by: [desc: s.inserted_at],
                limit: 2
            )
            |> Repo.all()

        case snapshots do
            [latest, previous] ->
                hours =
                    NaiveDateTime.diff(latest.inserted_at, previous.inserted_at, :second)
                    / 3600.0

                if hours > 0,
                    do: (latest.stars - previous.stars) / hours,
                    else: 0.0

            _ ->
                0.0
        end
    end
end
