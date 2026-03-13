defmodule Forgecast.Event.Enricher do
    @moduledoc """
    Picks unenriched repos (those discovered via the event stream but
    not yet fully fetched) and fills in their details from the GitHub
    GraphQL API. Prioritizes repos with the most recent event activity
    so the hottest repos get enriched first.

    After enrichment, takes a snapshot and sets enriched_at so the
    repo won't be picked again. Processes up to @batch_size repos
    per cycle in a single GraphQL request, consuming only 1 rate
    limit point regardless of batch size.

    Skips repos that the search poller has already fully ingested
    (detected by having a non-nil last_seen_at set by the ingester)
    to avoid burning an API call on data we already have.

    Also fetches the 10 most recent stargazer timestamps per repo
    within the same GraphQL call (no extra cost) to provide granular
    velocity data for scoring.
    """

    use GenServer
    require Logger

    alias Forgecast.Platform.Header
    alias Forgecast.Repo
    alias Forgecast.Schema.{Repository, Snapshot, Event}

    import Ecto.Query

    @check_interval :timer.seconds(15)
    @batch_size 40
    @min_events 2
    @graphql_url "https://api.github.com/graphql"
    @event_lookback_days 7

    @type t :: %__MODULE__{
        total_enriched: non_neg_integer(),
        total_skipped: non_neg_integer(),
        last_enriched_at: NaiveDateTime.t() | nil
    }

    defstruct [
        total_enriched: 0,
        total_skipped: 0,
        last_enriched_at: nil
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
        schedule(@check_interval)
        {:ok, %__MODULE__{}}
    end

    @impl true
    def handle_info(:enrich, state) do
        state = do_enrich_batch(state)
        schedule(@check_interval)
        {:noreply, state}
    end

    @impl true
    def handle_call(:status, _from, state) do
        {:reply, Map.from_struct(state), state}
    end

    defp schedule(interval) do
        Process.send_after(self(), :enrich, interval)
    end

    defp do_enrich_batch(state) do
        candidates = pick_candidates(@batch_size)

        if candidates == [] do
            state
        else
            {already_fresh, need_fetch} =
                Enum.split_with(candidates, fn repo ->
                    repo.last_seen_at != nil and repo.stars > 0
                end)

            Enum.each(already_fresh, fn repo ->
                mark_enriched(repo)
                Logger.debug("[Event.Enricher] Skipped #{repo.name} (already ingested)")
            end)

            skipped_count = length(already_fresh)
            enriched_count = enrich_via_graphql(need_fetch)

            if enriched_count > 0 do
                Forgecast.Trending.invalidate_cache()
            end

            %{state |
                total_enriched: state.total_enriched + enriched_count,
                total_skipped: state.total_skipped + skipped_count,
                last_enriched_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
            }
        end
    end

    defp enrich_via_graphql([]), do: 0

    defp enrich_via_graphql(repos) do
        case build_and_execute_query(repos) do
            {:ok, data} ->
                apply_batch_results(repos, data)

            {:error, reason} ->
                Logger.warning("[Event.Enricher] GraphQL batch failed: #{inspect(reason)}, falling back to marking enriched")
                Enum.each(repos, &mark_enriched/1)
                0
        end
    end

    defp build_and_execute_query(repos) do
        # Build aliased GraphQL query: repo0: repository(owner:"x", name:"y") { ... }
        fragments =
            repos
            |> Enum.with_index()
            |> Enum.map(fn {repo, idx} ->
                [owner, name] =
                    case String.split(repo.name, "/", parts: 2) do
                        [o, n] -> [o, n]
                        _ -> [repo.owner, repo.name]
                    end

                """
                repo#{idx}: repository(owner: "#{escape_graphql(owner)}", name: "#{escape_graphql(name)}") {
                    databaseId
                    description
                    primaryLanguage { name }
                    repositoryTopics(first: 20) { nodes { topic { name } } }
                    stargazerCount
                    forkCount
                    issues(states: OPEN) { totalCount }
                    owner { avatarUrl login }
                    name
                    openGraphImageUrl
                    stargazers(last: 10, orderBy: {field: STARRED_AT, direction: ASC}) {
                        edges { starredAt }
                    }
                }
                """
            end)
            |> Enum.join("\n")

        query = "query { #{fragments} }"

        case Req.post(@graphql_url,
            json: %{"query" => query},
            headers: Header.github_graphql_headers()
        ) do
            {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
                {:ok, data}

            {:ok, %Req.Response{status: 200, body: %{"errors" => errors} = body}} ->
                # GraphQL can return partial data with errors
                case body["data"] do
                    nil -> {:error, {:graphql_errors, errors}}
                    data -> {:ok, data}
                end

            {:ok, %Req.Response{status: status, body: body}} ->
                {:error, {:unexpected_status, status, body}}

            {:error, reason} ->
                {:error, reason}
        end
    end

    defp apply_batch_results(repos, data) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        repos
        |> Enum.with_index()
        |> Enum.count(fn {repo, idx} ->
            key = "repo#{idx}"

            case Map.get(data, key) do
                nil ->
                    Logger.warning("[Event.Enricher] No data for #{repo.name}, marking enriched")
                    mark_enriched(repo)
                    false

                body ->
                    apply_enrichment(repo, body, now)
                    Logger.info("[Event.Enricher] Enriched #{repo.name}")
                    true
            end
        end)
    end

    defp apply_enrichment(repo, body, now) do
        stars = body["stargazerCount"] || 0
        forks = body["forkCount"] || 0
        open_issues = get_in(body, ["issues", "totalCount"]) || 0
        language = get_in(body, ["primaryLanguage", "name"])
        owner_login = get_in(body, ["owner", "login"]) || ""
        repo_name = body["name"] || ""

        topics =
            body
            |> get_in(["repositoryTopics", "nodes"])
            |> List.wrap()
            |> Enum.map(&get_in(&1, ["topic", "name"]))
            |> Enum.reject(&is_nil/1)

        og_url =
            if owner_login != "" and repo_name != "" do
                "https://opengraph.githubassets.com/1/#{owner_login}/#{repo_name}"
            end

        star_velocity = compute_stargazer_velocity(body)
        now_naive = DateTime.to_naive(now)

        attrs = %{
            description: body["description"],
            language: language,
            topics: topics,
            avatar_url: get_in(body, ["owner", "avatarUrl"]),
            og_image_url: og_url,
            stars: stars,
            forks: forks,
            open_issues: open_issues,
            last_seen_at: now_naive,
            enriched_at: now_naive,
            next_check_at: NaiveDateTime.add(now_naive, enrichment_check_interval(star_velocity))
        }

        repo
        |> Repository.changeset(attrs)
        |> Repo.update()

        %Snapshot{}
        |> Snapshot.changeset(%{
            repo_id: repo.id,
            stars: stars,
            forks: forks,
            open_issues: open_issues
        })
        |> Repo.insert()
    end

    defp compute_stargazer_velocity(body) do
        edges =
            body
            |> get_in(["stargazers", "edges"])
            |> List.wrap()

        timestamps =
            edges
            |> Enum.map(fn edge ->
                case DateTime.from_iso8601(edge["starredAt"] || "") do
                    {:ok, dt, _} -> DateTime.to_unix(dt)
                    _ -> nil
                end
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.sort()

        case timestamps do
            [] -> 0.0
            [_single] -> 0.0
            ts ->
                span_hours = (List.last(ts) - List.first(ts)) / 3600.0

                if span_hours > 0 do
                    (length(ts) - 1) / span_hours
                else
                    0.0
                end
        end
    end

    defp enrichment_check_interval(velocity) do
        cond do
            velocity > 10.0 -> 1_800
            velocity > 1.0 -> 3_600
            velocity > 0.1 -> 7_200
            true -> 14_400
        end
    end

    defp mark_enriched(repo) do
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        repo
        |> Ecto.Changeset.change(%{enriched_at: now})
        |> Repo.update()
    end

    defp pick_candidates(limit) do
        # Only look at events from the last @event_lookback_days to
        # avoid scanning compressed chunks in the events hypertable.
        event_cutoff =
            NaiveDateTime.utc_now()
            |> NaiveDateTime.add(-@event_lookback_days * 86_400)

        # Uses the integer repo_id FK for an efficient join
        event_counts =
            from(e in Event,
                where: e.platform == "github" and not is_nil(e.repo_id),
                where: e.occurred_at >= ^event_cutoff,
                group_by: e.repo_id,
                having: count(e.id) >= ^@min_events,
                select: %{repo_id: e.repo_id, count: count(e.id)}
            )

        from(r in Repository,
            join: ec in subquery(event_counts),
                on: r.id == ec.repo_id,
            where: is_nil(r.enriched_at),
            order_by: [desc: ec.count],
            limit: ^limit
        )
        |> Repo.all()
    end

    defp escape_graphql(str) do
        str
        |> String.replace("\\", "\\\\")
        |> String.replace("\"", "\\\"")
    end
end
