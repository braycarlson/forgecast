defmodule Forgecast.Velocity do
    @moduledoc """
    Shared star velocity computation from snapshot pairs.
    Used by the image cache, poller scheduler, and enricher
    to determine refresh/check intervals based on activity.
    """

    alias Forgecast.Repo

    @spec star_velocity(integer()) :: float()
    def star_velocity(repo_id) do
        case star_velocities([repo_id]) do
            %{^repo_id => v} -> v
            _ -> 0.0
        end
    end

    @spec star_velocities([integer()]) :: %{integer() => float()}
    def star_velocities([]), do: %{}

    def star_velocities(repo_ids) do
        sql = """
        SELECT r.id, s.stars, EXTRACT(EPOCH FROM s.inserted_at)::float8 AS ts
        FROM unnest($1::bigint[]) AS r(id)
        CROSS JOIN LATERAL (
            SELECT s.stars, s.inserted_at
            FROM snapshots s
            WHERE s.repo_id = r.id
            ORDER BY s.inserted_at DESC
            LIMIT 2
        ) s
        """

        case Repo.query(sql, [repo_ids]) do
            {:ok, %{rows: rows}} ->
                rows
                |> Enum.group_by(&Enum.at(&1, 0))
                |> Enum.map(fn {repo_id, entries} ->
                    case entries do
                        [[_, latest_stars, latest_ts], [_, prev_stars, prev_ts]] ->
                            hours = (latest_ts - prev_ts) / 3600.0

                            velocity =
                                if hours > 0,
                                    do: (latest_stars - prev_stars) / hours,
                                    else: 0.0

                            {repo_id, velocity}

                        _ ->
                            {repo_id, 0.0}
                    end
                end)
                |> Map.new()

            _ ->
                Map.new(repo_ids, &{&1, 0.0})
        end
    end
end
