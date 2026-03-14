defmodule Forgecast.Trending do
    @moduledoc """
    Serves trending data from precomputed scores stored on the
    repos table. All filtering, sorting, and pagination happens
    in Postgres using indexed columns, making queries O(log n)
    regardless of table size.

    Scores are maintained by `Forgecast.Scoring.Worker` on a
    background schedule. This module only reads.

    Supports keyset (cursor) pagination for efficient deep paging.
    When a `cursor` is provided, OFFSET is bypassed entirely and
    the query uses a row-value comparison against the indexed sort
    column plus the ID tiebreaker. Falls back to OFFSET pagination
    when no cursor is given for backward compatibility.
    """

    alias Forgecast.Repo
    alias Forgecast.Schema.{Repository, Snapshot}

    import Ecto.Query

    @cache_table :forgecast_trending_cache
    @cache_ttl_ms 30_000
    @filters_cache_key :__available_filters__
    @filters_ttl_ms 300_000
    @search_count_cap 10_000

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
        case lookup_cache(@filters_cache_key) do
            {:ok, result} ->
                result

            :miss ->
                result = fetch_available_filters()
                store_cache(@filters_cache_key, result, @filters_ttl_ms)
                result
        end
    end

    @spec list_repos(keyword()) :: [map()]
    def list_repos(opts \\ []) do
        platform = Keyword.get(opts, :platform)
        language = Keyword.get(opts, :language)

        query =
            from r in Repository,
                where: r.active == true,
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

    @spec snapshots_for(integer() | binary(), keyword()) :: [map()]
    def snapshots_for(repo_id, opts \\ []) do
        limit = Keyword.get(opts, :limit, 1000)

        Repo.all(
            from s in Snapshot,
                where: s.repo_id == ^repo_id,
                order_by: [asc: s.inserted_at],
                limit: ^limit,
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
            repos: estimated_count("repos"),
            snapshots: estimated_count("snapshots"),
            events: estimated_count("events")
        }
    end

    # -- Private --

    defp estimated_count(table) do
        case Repo.query("SELECT estimated_row_count($1)", [table]) do
            {:ok, %{rows: [[count]]}} -> count
            _ -> 0
        end
    end

    defp fetch_available_filters do
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

    defp store_cache(key, result, ttl \\ @cache_ttl_ms) do
        if :ets.whereis(@cache_table) != :undefined do
            expires_at = System.monotonic_time(:millisecond) + ttl
            :ets.insert(@cache_table, {key, result, expires_at})
        end
    end

    defp compute_score(opts) do
        platform = Keyword.get(opts, :platform)
        language = Keyword.get(opts, :language)
        search = Keyword.get(opts, :search)
        cursor = Keyword.get(opts, :cursor)
        page = Keyword.get(opts, :page, 1)
        per_page = Keyword.get(opts, :per_page, 12)
        sort = Keyword.get(opts, :sort)
        dir = Keyword.get(opts, :dir)

        filtered? = not is_nil(platform) or not is_nil(language)
        searching? = is_binary(search) and search != ""

        base = base_query(platform, language, search)
        total = count_results(base, searching?, filtered?)
        {sort_field, sort_dir} = resolve_sort(sort, dir)
        decoded_cursor = decode_cursor(cursor)

        items_query =
            base
            |> apply_cursor(decoded_cursor, sort_field, sort_dir)
            |> apply_sort_with_tiebreaker(sort_field, sort_dir)

        items_query =
            if decoded_cursor do
                limit(items_query, ^(per_page + 1))
            else
                offset = (page - 1) * per_page

                items_query
                |> offset(^offset)
                |> limit(^(per_page + 1))
            end

        items =
            items_query
            |> select([r], %{
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
                stars: r.stars,
                forks: r.forks,
                open_issues: r.open_issues,
                score: r.score,
                star_velocity: r.star_velocity,
                fork_velocity: r.fork_velocity,
                mirrors: r.mirrors
            })
            |> Repo.all()

        has_more = length(items) > per_page
        items = Enum.take(items, per_page)

        next_cursor =
            if has_more and items != [] do
                encode_cursor(List.last(items), sort_field)
            end

        items =
            Enum.map(items, fn item ->
                Map.put(item, :og_image_url, if(item.og_image_cached, do: "/api/og-image/#{item.id}", else: nil))
            end)

        %{
            items: items,
            total: total,
            page: page,
            per_page: per_page,
            total_pages: max(ceil(total / per_page), 1),
            next_cursor: next_cursor,
            has_more: has_more
        }
    end

    defp base_query(platform, language, search) do
        query = from(r in Repository, where: r.active == true)

        query = apply_filter(query, :platform, platform)
        query = apply_filter(query, :language, language)
        apply_search(query, search)
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

    defp apply_search(query, nil), do: query
    defp apply_search(query, ""), do: query

    defp apply_search(query, search) do
        term = String.downcase(search)
        like_term = "%#{sanitize_like(term)}%"

        where(query, [r],
            fragment(
                """
                (lower(?) || ' ' ||
                 coalesce(lower(?), '') || ' ' ||
                 coalesce(lower(?), '') || ' ' ||
                 coalesce(lower(immutable_array_to_string(?, ' ')), ''))
                LIKE ? ESCAPE '~'
                """,
                r.name, r.description, r.language, r.topics, ^like_term
            )
        )
    end

    # -- Sorting --

    defp resolve_sort(nil, _), do: {:score, :desc}
    defp resolve_sort(:score, nil), do: {:score, :desc}
    defp resolve_sort(:score, dir), do: {:score, dir}
    defp resolve_sort(:stars, nil), do: {:stars, :desc}
    defp resolve_sort(:stars, dir), do: {:stars, dir}
    defp resolve_sort(:forks, nil), do: {:forks, :desc}
    defp resolve_sort(:forks, dir), do: {:forks, dir}
    defp resolve_sort(:star_velocity, nil), do: {:star_velocity, :desc}
    defp resolve_sort(:star_velocity, dir), do: {:star_velocity, dir}
    defp resolve_sort(:name, nil), do: {:name, :asc}
    defp resolve_sort(:name, dir), do: {:name, dir}
    defp resolve_sort(:language, nil), do: {:language, :asc}
    defp resolve_sort(:language, dir), do: {:language, dir}
    defp resolve_sort(_, _), do: {:score, :desc}

    defp apply_sort_with_tiebreaker(query, field, :desc) do
        order_by(query, [r], [{:desc, field(r, ^field)}, {:desc, r.id}])
    end

    defp apply_sort_with_tiebreaker(query, field, :asc) do
        order_by(query, [r], [{:asc, field(r, ^field)}, {:asc, r.id}])
    end

    # -- Cursor pagination --

    defp apply_cursor(query, nil, _field, _dir), do: query

    defp apply_cursor(query, {cursor_value, cursor_id}, field, :desc) do
        where(query, [r],
            fragment("(?, ?) < (?, ?)",
                field(r, ^field), r.id,
                ^cursor_value, ^cursor_id
            )
        )
    end

    defp apply_cursor(query, {cursor_value, cursor_id}, field, :asc) do
        where(query, [r],
            fragment("(?, ?) > (?, ?)",
                field(r, ^field), r.id,
                ^cursor_value, ^cursor_id
            )
        )
    end

    defp encode_cursor(item, sort_field) do
        %{v: Map.get(item, sort_field), id: item.id}
        |> Jason.encode!()
        |> Base.url_encode64(padding: false)
    end

    defp decode_cursor(nil), do: nil
    defp decode_cursor(""), do: nil

    defp decode_cursor(encoded) do
        with {:ok, json} <- Base.url_decode64(encoded, padding: false),
             {:ok, %{"v" => value, "id" => id}} <- Jason.decode(json) do
            {value, id}
        else
            _ -> nil
        end
    end

    # -- Counting --

    # Active search: use a bounded count to cap scan cost.
    defp count_results(query, true = _searching?, _filtered?) do
        bounded =
            from(sub in subquery(from(r in query, select: r.id, limit: ^(@search_count_cap + 1))),
                select: count()
            )

        min(Repo.one(bounded), @search_count_cap)
    end

    # No search, but filtered by platform/language: exact count
    # is cheap on the partial indexes covering those columns.
    defp count_results(query, false, true = _filtered?) do
        Repo.one(from(r in query, select: count(r.id)))
    end

    # Unfiltered, no search: use pg_class estimate to avoid a
    # full index scan on millions of active rows.
    defp count_results(_query, false, false) do
        case Repo.query(
            "SELECT GREATEST(reltuples::bigint, 0) FROM pg_class WHERE relname = 'repos'",
            []
        ) do
            {:ok, %{rows: [[count]]}} -> count
            _ -> 0
        end
    end

    # -- Helpers --

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
