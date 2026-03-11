defmodule Forgecast.Trending do
    @moduledoc """
    Queries repos and computes trending scores based on event-stream
    velocity and snapshot deltas within a configurable time window.
    Delegates pure scoring math to `Forgecast.Scoring`.
    """

    alias Forgecast.Repo
    alias Forgecast.Schema.{Repository, Snapshot, Event}
    alias Forgecast.Scoring

    import Ecto.Query

    @cache_table :forgecast_trending_cache
    @cache_ttl_ms 30_000

    @spec init_cache() :: :ok
    def init_cache do
        if :ets.whereis(@cache_table) == :undefined do
            :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])
        end

        :ok
    end

    @spec invalidate_cache() :: :ok
    def invalidate_cache do
        if :ets.whereis(@cache_table) != :undefined do
            :ets.delete_all_objects(@cache_table)
        end

        :ok
    end

    @spec score(keyword()) :: map()
    def score(opts \\ []) do
        cache_key = :erlang.phash2(opts)

        case lookup_cache(cache_key) do
            {:ok, result} ->
                result

            :miss ->
                result = compute_score(opts)
                store_cache(cache_key, result)
                result
        end
    end

    @spec available_filters() :: map()
    def available_filters do
        platforms =
            Repo.all(from r in Repository, distinct: true, select: r.platform, order_by: r.platform)

        languages =
            Repo.all(
                from r in Repository,
                    where: not is_nil(r.language) and r.language != "",
                    distinct: true,
                    select: r.language,
                    order_by: r.language
            )

        %{platforms: platforms, languages: languages}
    end

    @spec list_repos(keyword()) :: [map()]
    def list_repos(opts \\ []) do
        platform = Keyword.get(opts, :platform)
        language = Keyword.get(opts, :language)

        query =
            from r in Repository,
                select: %{
                    id: r.id,
                    platform: r.platform,
                    name: r.name,
                    owner: r.owner,
                    description: r.description,
                    language: r.language,
                    url: r.url,
                    topics: r.topics,
                    stars: r.stars,
                    forks: r.forks,
                    open_issues: r.open_issues,
                    avatar_url: r.avatar_url,
                    og_image_url: r.og_image_url
                },
                order_by: [desc: r.stars],
                limit: 50

        query = if platform, do: where(query, [r], r.platform == ^platform), else: query
        query = if language, do: where(query, [r], r.language == ^language), else: query

        Repo.all(query)
    end

    @spec snapshots_for(integer() | binary()) :: [map()]
    def snapshots_for(repo_id) do
        Repo.all(
            from s in Snapshot,
                where: s.repo_id == ^repo_id,
                order_by: [asc: s.inserted_at],
                select: %{
                    stars: s.stars,
                    forks: s.forks,
                    open_issues: s.open_issues,
                    recorded_at: s.inserted_at
                }
        )
    end

    @spec status() :: map()
    def status do
        %{
            repos: Repo.aggregate(Repository, :count),
            snapshots: Repo.aggregate(Snapshot, :count),
            events: Repo.aggregate(Event, :count)
        }
    end

    # -- Private --

    defp lookup_cache(key) do
        if :ets.whereis(@cache_table) == :undefined do
            :miss
        else
            case :ets.lookup(@cache_table, key) do
                [{^key, result, expires_at}] ->
                    if System.monotonic_time(:millisecond) < expires_at do
                        {:ok, result}
                    else
                        :ets.delete(@cache_table, key)
                        :miss
                    end

                [] ->
                    :miss
            end
        end
    end

    defp store_cache(key, result) do
        if :ets.whereis(@cache_table) != :undefined do
            expires_at = System.monotonic_time(:millisecond) + @cache_ttl_ms
            :ets.insert(@cache_table, {key, result, expires_at})
        end
    end

    defp compute_score(opts) do
        stale_days = Application.get_env(:forgecast, :trending)[:stale_days] || 7

        platform = Keyword.get(opts, :platform)
        language = Keyword.get(opts, :language)
        search = Keyword.get(opts, :search)
        page = Keyword.get(opts, :page, 1)
        per_page = Keyword.get(opts, :per_page, 12)
        window_hours = Keyword.get(opts, :window, 24)
        sort = Keyword.get(opts, :sort)
        dir = Keyword.get(opts, :dir)

        cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -window_hours * 3600)
        stale_cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -stale_days * 86400)
        offset = (page - 1) * per_page

        base = base_repo_query(platform, language, search, stale_cutoff)
        event_counts = event_counts_query(cutoff)

        total =
            base
            |> select([r], count(r.id))
            |> Repo.one()

        scored =
            base
            |> join(:left, [r], first in subquery(window_boundary_query(cutoff, :asc)), on: first.repo_id == r.id)
            |> join(:left, [r, _], last in subquery(window_boundary_query(cutoff, :desc)), on: last.repo_id == r.id)
            |> join(:left, [r, _, _], ec in subquery(event_counts),
                on: ec.platform == r.platform and ec.platform_repo_id == r.platform_id)
            |> select([r, first, last, ec], %{
                id: r.id,
                platform: r.platform,
                name: r.name,
                owner: r.owner,
                description: r.description,
                language: r.language,
                url: r.url,
                topics: r.topics,
                avatar_url: r.avatar_url,
                og_image_url: r.og_image_url,
                og_image_cached: not is_nil(r.og_image_cached_at),
                inserted_at: r.inserted_at,
                stars: r.stars,
                forks: r.forks,
                open_issues: r.open_issues,
                first_stars: first.stars,
                last_stars: last.stars,
                first_forks: first.forks,
                last_forks: last.forks,
                first_at: first.inserted_at,
                last_at: last.inserted_at,
                event_stars: coalesce(ec.star_count, 0),
                event_forks: coalesce(ec.fork_count, 0)
            })
            |> Repo.all()
            |> Enum.map(&Scoring.attach_scores(&1, window_hours))
            |> Scoring.sort(sort, dir)

        items =
            scored
            |> Enum.drop(offset)
            |> Enum.take(per_page)

        mirrors = Forgecast.Mirror.for_repos(items)

        items =
            Enum.map(items, fn item ->
                item
                |> Map.put(:mirrors, Map.get(mirrors, item.id, []))
                |> Map.put(:og_image_url, if(item.og_image_cached, do: "/api/og-image/#{item.id}", else: nil))
            end)

        %{
            items: items,
            total: total,
            page: page,
            per_page: per_page,
            total_pages: max(ceil(total / per_page), 1)
        }
    end

    defp event_counts_query(cutoff) do
        from(e in Event,
            where: e.occurred_at >= ^cutoff,
            group_by: [e.platform, e.platform_repo_id],
            select: %{
                platform: e.platform,
                platform_repo_id: e.platform_repo_id,
                star_count: filter(count(e.id), e.event_type == "star"),
                fork_count: filter(count(e.id), e.event_type == "fork")
            }
        )
    end

    defp base_repo_query(platform, language, search, stale_cutoff) do
        query =
            from(r in Repository,
                where: is_nil(r.last_seen_at) or r.last_seen_at >= ^stale_cutoff
            )

        query = apply_filter(query, :platform, platform)
        query = apply_filter(query, :language, language)

        if search && search != "" do
            term = "%#{sanitize_like(search)}%" |> String.downcase()

            where(query, [r],
                fragment("lower(?) LIKE ? ESCAPE '~'", r.name, ^term) or
                fragment("lower(?) LIKE ? ESCAPE '~'", r.description, ^term) or
                fragment("lower(?) LIKE ? ESCAPE '~'", r.language, ^term) or
                fragment("EXISTS (SELECT 1 FROM unnest(?) t WHERE lower(t) LIKE ? ESCAPE '~')", r.topics, ^term)
            )
        else
            query
        end
    end

    defp apply_filter(query, _field, nil), do: query
    defp apply_filter(query, _field, ""), do: query

    defp apply_filter(query, :platform, value) do
        case split_filter(value) do
            [single] -> where(query, [r], r.platform == ^single)
            many -> where(query, [r], r.platform in ^many)
        end
    end

    defp apply_filter(query, :language, value) do
        case split_filter(value) do
            [single] -> where(query, [r], r.language == ^single)
            many -> where(query, [r], r.language in ^many)
        end
    end

    defp window_boundary_query(cutoff, :asc) do
        inner =
            from s in Snapshot,
                where: s.inserted_at >= ^cutoff,
                group_by: s.repo_id,
                select: %{repo_id: s.repo_id, boundary_id: min(s.id)}

        from s in Snapshot,
            join: b in subquery(inner), on: s.id == b.boundary_id,
            select: %{
                repo_id: s.repo_id,
                stars: s.stars,
                forks: s.forks,
                inserted_at: s.inserted_at
            }
    end

    defp window_boundary_query(cutoff, :desc) do
        inner =
            from s in Snapshot,
                where: s.inserted_at >= ^cutoff,
                group_by: s.repo_id,
                select: %{repo_id: s.repo_id, boundary_id: max(s.id)}

        from s in Snapshot,
            join: b in subquery(inner), on: s.id == b.boundary_id,
            select: %{
                repo_id: s.repo_id,
                stars: s.stars,
                forks: s.forks,
                inserted_at: s.inserted_at
            }
    end

    defp split_filter(value) do
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
    end

    defp sanitize_like(term) do
        term
        |> String.replace("~", "~~")
        |> String.replace("%", "~%")
        |> String.replace("_", "~_")
    end
end
