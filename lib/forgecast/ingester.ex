defmodule Forgecast.Ingester do
    @moduledoc """
    Upserts repos from platform results and records snapshots when metrics change.

    Sets a default `next_check_at` on newly discovered repos so they enter
    the monitoring queue. Existing repos preserve their scheduled check time
    on re-discovery thanks to the conflict replacement list excluding it.

    Uses batched insert_all for both repos and snapshots to minimize
    database round-trips. Only invalidates the trending cache when
    snapshots are actually inserted.

    Snapshot delta thresholds scale with total stars: for repos with
    10k+ stars, a change of 5 is noise and gets suppressed. The
    threshold is max(5, 0.1% of total stars).
    """

    alias Forgecast.Repo
    alias Forgecast.Schema.{Repository, Snapshot}
    alias Forgecast.Platform.Result

    import Ecto.Query

    @default_check_delay 3600
    @min_snapshot_interval_seconds 3600
    @min_snapshot_star_delta 5
    @snapshot_star_delta_ratio 0.001

    @spec ingest([Result.t()]) :: [{:ok, Repository.t()} | {:error, Ecto.Changeset.t()}]
    def ingest([]), do: []

    def ingest(results) do
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        default_check = NaiveDateTime.add(now, @default_check_delay)

        entries =
            Enum.map(results, fn result ->
                %{
                    platform: result.platform,
                    platform_id: result.platform_id,
                    name: result.name,
                    owner: result.owner,
                    description: result.description,
                    language: presence(result.language),
                    url: result.url,
                    topics: result.topics || [],
                    avatar_url: result.avatar_url,
                    og_image_url: result.og_image_url,
                    stars: result.stars,
                    forks: result.forks,
                    open_issues: result.open_issues,
                    last_seen_at: now,
                    next_check_at: default_check,
                    inserted_at: now,
                    updated_at: now
                }
            end)

        {_count, upserted} =
            Repo.insert_all(Repository, entries,
                on_conflict: {:replace, [
                    :name, :owner, :description, :language, :url, :topics,
                    :avatar_url, :og_image_url, :stars, :forks, :open_issues,
                    :last_seen_at, :updated_at
                ]},
                conflict_target: [:platform, :platform_id],
                returning: [:id, :platform, :platform_id]
            )

        repo_ids = Enum.map(upserted, & &1.id)
        latest_by_repo = fetch_latest_snapshots(repo_ids)

        result_by_key =
            results
            |> Enum.map(fn r -> {{r.platform, r.platform_id}, r} end)
            |> Map.new()

        snapshot_entries =
            upserted
            |> Enum.flat_map(fn repo ->
                key = {repo.platform, repo.platform_id}
                result = Map.get(result_by_key, key)

                if result do
                    latest = Map.get(latest_by_repo, repo.id)

                    should_snapshot? =
                        case latest do
                            nil ->
                                true

                            {stars, forks, issues, recorded_at} ->
                                changed? = stars != result.stars or forks != result.forks or issues != result.open_issues
                                age = NaiveDateTime.diff(now, recorded_at, :second)
                                star_delta = abs(result.stars - stars)
                                min_delta = snapshot_delta_threshold(stars)

                                cond do
                                    not changed? -> false
                                    age < @min_snapshot_interval_seconds and star_delta < min_delta -> false
                                    true -> true
                                end
                        end

                    if should_snapshot? do
                        [%{
                            repo_id: repo.id,
                            stars: result.stars,
                            forks: result.forks,
                            open_issues: result.open_issues,
                            inserted_at: now
                        }]
                    else
                        []
                    end
                else
                    []
                end
            end)

        if snapshot_entries != [] do
            Repo.insert_all(Snapshot, snapshot_entries)
            Forgecast.Trending.invalidate_cache()
        end

        Enum.map(upserted, fn repo -> {:ok, repo} end)
    end

    defp snapshot_delta_threshold(stars) when is_integer(stars) do
        max(@min_snapshot_star_delta, trunc(stars * @snapshot_star_delta_ratio))
    end

    defp snapshot_delta_threshold(_), do: @min_snapshot_star_delta

    defp presence(nil), do: nil
    defp presence(""), do: nil
    defp presence(value), do: value

    defp fetch_latest_snapshots([]), do: %{}

    defp fetch_latest_snapshots(repo_ids) do
        latest_ids =
            from(s in Snapshot,
                where: s.repo_id in ^repo_ids,
                group_by: s.repo_id,
                select: %{repo_id: s.repo_id, max_id: max(s.id)}
            )

        Repo.all(
            from s in Snapshot,
                join: l in subquery(latest_ids),
                    on: s.id == l.max_id,
                select: {s.repo_id, {s.stars, s.forks, s.open_issues, s.inserted_at}}
        )
        |> Map.new()
    end
end
