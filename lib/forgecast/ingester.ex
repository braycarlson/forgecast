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

    After upserting repos, precomputes cross-platform mirror links
    for the affected canonical names so the trending read path
    never needs to join across the full table.

    Chunks large batches to stay within PostgreSQL's 65535 parameter
    limit on prepared statements.
    """

    alias Forgecast.Repo
    alias Forgecast.Schema.{Repository, Snapshot}
    alias Forgecast.Platform.Result

    @default_check_delay 3600
    @min_snapshot_interval_seconds 3600
    @min_snapshot_star_delta 5
    @snapshot_star_delta_ratio 0.001
    @max_repo_batch 2000
    @max_snapshot_batch 5000

    @spec ingest([Result.t()]) :: [{:ok, Repository.t()} | {:error, Ecto.Changeset.t()}]
    def ingest([]), do: []

    def ingest(results) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        now_naive = DateTime.to_naive(now)
        now_epoch = DateTime.to_unix(now)
        default_check = NaiveDateTime.add(now_naive, @default_check_delay)

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
                    last_seen_at: now_naive,
                    next_check_at: default_check,
                    inserted_at: now_naive,
                    updated_at: now_naive
                }
            end)

        upserted =
            entries
            |> Enum.chunk_every(@max_repo_batch)
            |> Enum.flat_map(fn batch ->
                {_count, rows} =
                    Repo.insert_all(Repository, batch,
                        on_conflict: {:replace, [
                            :name, :owner, :description, :language, :url, :topics,
                            :avatar_url, :og_image_url, :stars, :forks, :open_issues,
                            :last_seen_at, :updated_at
                        ]},
                        conflict_target: [:platform, :platform_id],
                        returning: [:id, :platform, :platform_id, :name, :owner]
                    )

                rows
            end)

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

                            {stars, forks, issues, recorded_epoch} ->
                                changed? = stars != result.stars or forks != result.forks or issues != result.open_issues
                                age = now_epoch - trunc(recorded_epoch)
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
            snapshot_entries
            |> Enum.chunk_every(@max_snapshot_batch)
            |> Enum.each(fn batch ->
                Repo.insert_all(Snapshot, batch)
            end)

            Forgecast.Trending.invalidate_cache()
        end

        update_mirrors(upserted)

        Enum.map(upserted, fn repo -> {:ok, repo} end)
    end

    defp update_mirrors(upserted) do
        canonicals =
            upserted
            |> Enum.map(fn repo -> Forgecast.Mirror.canonical(repo.owner, repo.name) end)
            |> Enum.uniq()

        Forgecast.Mirror.refresh_for_canonicals(canonicals)
    end

    defp snapshot_delta_threshold(stars) when is_integer(stars) do
        max(@min_snapshot_star_delta, trunc(stars * @snapshot_star_delta_ratio))
    end

    defp snapshot_delta_threshold(_), do: @min_snapshot_star_delta

    defp presence(nil), do: nil
    defp presence(""), do: nil
    defp presence(value), do: value

    # Uses a LATERAL join to grab exactly one snapshot per repo via
    # a single index seek on (repo_id, inserted_at DESC), avoiding
    # the GROUP BY + self-join that scales poorly at millions of rows.
    defp fetch_latest_snapshots([]), do: %{}

    defp fetch_latest_snapshots(repo_ids) do
        sql = """
        SELECT r.id, s.stars, s.forks, s.open_issues,
               EXTRACT(EPOCH FROM s.inserted_at)::float8 AS ts
        FROM unnest($1::bigint[]) AS r(id)
        CROSS JOIN LATERAL (
            SELECT s.stars, s.forks, s.open_issues, s.inserted_at
            FROM snapshots s
            WHERE s.repo_id = r.id
            ORDER BY s.inserted_at DESC
            LIMIT 1
        ) s
        """

        case Repo.query(sql, [repo_ids]) do
            {:ok, %{rows: rows}} ->
                rows
                |> Enum.map(fn [repo_id, stars, forks, issues, ts] ->
                    {repo_id, {stars, forks, issues, ts}}
                end)
                |> Map.new()

            _ ->
                %{}
        end
    end
end
