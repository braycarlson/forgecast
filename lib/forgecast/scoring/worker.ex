defmodule Forgecast.Scoring.Worker do
    @moduledoc """
    Background worker that precomputes trending scores for all repos.

    Runs on a configurable interval (default 30s), processing repos
    in batches to avoid locking the database. Scores are computed
    from event-stream velocity, snapshot deltas, base star count,
    and recency.

    The API reads directly from the indexed score column, making
    trending queries O(log n) regardless of table size.

    Also maintains the `active` flag on repos: repos whose
    last_seen_at is older than the stale cutoff are marked
    inactive so the trending query can filter on an indexed
    boolean instead of computing the cutoff on every read.

    Incremental scoring: only repos with new events or snapshots
    since the last run are rescored on the fast 30s cycle. A full
    rescore of all active repos runs every @full_rescore_cycles
    iterations as a catch-all.
    """

    use GenServer
    require Logger

    alias Forgecast.Repo
    alias Forgecast.Schema.{Repository, Snapshot, Event}

    import Ecto.Query

    @score_interval :timer.seconds(30)
    @batch_size 1000
    @window_hours 24
    @active_sync_interval 10
    @full_rescore_cycles 120

    @type t :: %__MODULE__{
        total_scored: non_neg_integer(),
        last_run_at: NaiveDateTime.t() | nil,
        last_duration_ms: non_neg_integer(),
        cycles: non_neg_integer()
    }

    defstruct [
        total_scored: 0,
        last_run_at: nil,
        last_duration_ms: 0,
        cycles: 0
    ]

    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @spec status() :: map()
    def status do
        GenServer.call(__MODULE__, :status)
    end

    @impl true
    def init(_opts) do
        schedule(:timer.seconds(5))
        {:ok, %__MODULE__{}}
    end

    @impl true
    def handle_info(:score, state) do
        start = System.monotonic_time(:millisecond)

        if rem(state.cycles, @active_sync_interval) == 0 do
            sync_active_flags()
        end

        full_rescore? = rem(state.cycles, @full_rescore_cycles) == 0

        count =
            if full_rescore? do
                recompute_all_scores()
            else
                recompute_changed_scores(state.last_run_at)
            end

        duration = System.monotonic_time(:millisecond) - start

        if count > 0 do
            Logger.info("[Scoring.Worker] Scored #{count} repos in #{duration}ms (full=#{full_rescore?})")
            Forgecast.Trending.invalidate_cache()
        end

        schedule(@score_interval)

        {:noreply, %{state |
            total_scored: state.total_scored + count,
            last_run_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
            last_duration_ms: duration,
            cycles: state.cycles + 1
        }}
    end

    @impl true
    def handle_call(:status, _from, state) do
        {:reply, Map.from_struct(state), state}
    end

    defp schedule(interval) do
        Process.send_after(self(), :score, interval)
    end

    defp sync_active_flags do
        stale_days = Application.get_env(:forgecast, :trending)[:stale_days] || 7
        stale_cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -stale_days * 86_400)

        {deactivated, _} =
            from(r in Repository,
                where: r.active == true,
                where: not is_nil(r.last_seen_at),
                where: r.last_seen_at < ^stale_cutoff
            )
            |> Repo.update_all(set: [active: false])

        {reactivated, _} =
            from(r in Repository,
                where: r.active == false,
                where: is_nil(r.last_seen_at) or r.last_seen_at >= ^stale_cutoff
            )
            |> Repo.update_all(set: [active: true])

        if deactivated > 0 or reactivated > 0 do
            Logger.info("[Scoring.Worker] Active flags: #{deactivated} deactivated, #{reactivated} reactivated")
        end
    end

    defp recompute_changed_scores(nil) do
        # First run, no last_run_at — do a full rescore
        recompute_all_scores()
    end

    defp recompute_changed_scores(since) do
        repo_ids = repos_with_activity_since(since)

        if repo_ids == [] do
            0
        else
            now = NaiveDateTime.utc_now()
            score_repo_ids(repo_ids, now)
        end
    end

    defp repos_with_activity_since(since) do
        event_ids =
            from(e in Event,
                where: e.occurred_at >= ^since,
                where: not is_nil(e.repo_id),
                distinct: true,
                select: e.repo_id
            )
            |> Repo.all()

        snapshot_ids =
            from(s in Snapshot,
                where: s.inserted_at >= ^since,
                distinct: true,
                select: s.repo_id
            )
            |> Repo.all()

        (event_ids ++ snapshot_ids) |> Enum.uniq()
    end

    defp score_repo_ids(repo_ids, now) do
        repo_ids
        |> Enum.chunk_every(@batch_size)
        |> Enum.reduce(0, fn batch, acc ->
            count = score_batch(batch, now)
            acc + count
        end)
    end

    # Iterates through all active repo IDs using keyset pagination
    # instead of a long-lived streaming transaction. Each batch is
    # independent and idempotent, so no wrapping transaction is needed.
    defp recompute_all_scores do
        now = NaiveDateTime.utc_now()

        Stream.unfold(0, fn last_id ->
            batch =
                from(r in Repository,
                    where: r.active == true and r.id > ^last_id,
                    select: r.id,
                    order_by: r.id,
                    limit: ^@batch_size
                )
                |> Repo.all()

            case batch do
                [] -> nil
                ids -> {ids, List.last(ids)}
            end
        end)
        |> Enum.reduce(0, fn batch, acc ->
            count = score_batch(batch, now)
            acc + count
        end)
    end

    defp score_batch(repo_ids, now) do
        event_counts = fetch_event_counts(repo_ids)
        snapshot_deltas = fetch_snapshot_deltas(repo_ids)
        repo_data = fetch_repo_data(repo_ids)

        updates =
            repo_ids
            |> Enum.map(fn id ->
                repo = Map.get(repo_data, id)
                ec = Map.get(event_counts, id, %{stars: 0, forks: 0})
                sd = Map.get(snapshot_deltas, id)

                if repo do
                    compute_and_build_update(repo, ec, sd, now)
                end
            end)
            |> Enum.reject(&is_nil/1)

        bulk_update_scores(updates, now)

        length(updates)
    end

    defp fetch_event_counts(repo_ids) do
        cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -@window_hours * 3600)

        from(e in Event,
            where: e.repo_id in ^repo_ids,
            where: e.occurred_at >= ^cutoff,
            group_by: e.repo_id,
            select: {e.repo_id, %{
                stars: filter(count(e.id), e.event_type == "star"),
                forks: filter(count(e.id), e.event_type == "fork")
            }}
        )
        |> Repo.all()
        |> Map.new()
    end

    # Uses LATERAL joins to grab only the first and last snapshot per
    # repo within the scoring window. Each LATERAL does a single index
    # seek on (repo_id, inserted_at), reading exactly one row per repo
    # instead of materializing every snapshot in the window.
    defp fetch_snapshot_deltas(repo_ids) do
        cutoff = DateTime.add(DateTime.utc_now(), -@window_hours * 3600) |> DateTime.truncate(:second)

        sql = """
        SELECT
            r.id,
            first_s.stars,
            first_s.forks,
            EXTRACT(EPOCH FROM first_s.inserted_at)::float8,
            last_s.stars,
            last_s.forks,
            EXTRACT(EPOCH FROM last_s.inserted_at)::float8
        FROM unnest($1::bigint[]) AS r(id)
        CROSS JOIN LATERAL (
            SELECT s.stars, s.forks, s.inserted_at
            FROM snapshots s
            WHERE s.repo_id = r.id AND s.inserted_at >= $2
            ORDER BY s.inserted_at ASC
            LIMIT 1
        ) first_s
        CROSS JOIN LATERAL (
            SELECT s.stars, s.forks, s.inserted_at
            FROM snapshots s
            WHERE s.repo_id = r.id AND s.inserted_at >= $2
            ORDER BY s.inserted_at DESC
            LIMIT 1
        ) last_s
        """

        case Repo.query(sql, [repo_ids, cutoff]) do
            {:ok, %{rows: rows}} ->
                rows
                |> Enum.map(fn [repo_id, fs, ff, fa, ls, lf, la] ->
                    {repo_id, %{
                        first: %{stars: fs, forks: ff, at: fa},
                        last: %{stars: ls, forks: lf, at: la}
                    }}
                end)
                |> Map.new()

            _ ->
                %{}
        end
    end

    defp fetch_repo_data(repo_ids) do
        from(r in Repository,
            where: r.id in ^repo_ids,
            select: {r.id, %{
                id: r.id,
                stars: r.stars,
                platform: r.platform,
                platform_id: r.platform_id,
                inserted_at: r.inserted_at
            }}
        )
        |> Repo.all()
        |> Map.new()
    end

    defp compute_and_build_update(repo, event_counts, snapshot_delta, now) do
        ev_sv = event_counts.stars / max(@window_hours, 1)
        ev_fv = event_counts.forks / max(@window_hours, 1)

        {snap_sv, snap_fv} =
            case snapshot_delta do
                nil ->
                    {0.0, 0.0}

                %{first: first, last: last} ->
                    hours = (last.at - first.at) / 3600.0

                    if hours > 0 do
                        {(last.stars - first.stars) / hours, (last.forks - first.forks) / hours}
                    else
                        {0.0, 0.0}
                    end
            end

        sv = max(ev_sv, snap_sv) |> max(0.0)
        fv = max(ev_fv, snap_fv) |> max(0.0)

        stars = repo.stars
        base = if stars > 0, do: :math.log2(stars), else: 0.0

        days_old =
            case repo.inserted_at do
                nil -> 0
                at -> div(NaiveDateTime.diff(now, at, :second), 86_400)
            end

        recency = max(0.0, 5.0 - days_old * 0.05)
        score = sv * 10.0 + fv * 5.0 + base + recency

        {repo.id, score, sv, fv}
    end

    defp bulk_update_scores([], _now), do: :ok

    defp bulk_update_scores(updates, now) do
        score_updated_at = NaiveDateTime.truncate(now, :second)

        {params, placeholders} =
            updates
            |> Enum.with_index()
            |> Enum.reduce({[], []}, fn {{id, score, sv, fv}, idx}, {params_acc, frag_acc} ->
                base = idx * 4
                placeholder = "($#{base + 1}::bigint, $#{base + 2}::float8, $#{base + 3}::float8, $#{base + 4}::float8)"
                {params_acc ++ [id, score, sv, fv], [placeholder | frag_acc]}
            end)

        values_sql = placeholders |> Enum.reverse() |> Enum.join(", ")

        sql = """
        UPDATE repos AS r
        SET score = v.score,
            star_velocity = v.star_velocity,
            fork_velocity = v.fork_velocity,
            score_updated_at = $#{length(params) + 1}
        FROM (VALUES #{values_sql}) AS v(id, score, star_velocity, fork_velocity)
        WHERE r.id = v.id
        """

        Repo.query!(sql, params ++ [score_updated_at])
    end
end
