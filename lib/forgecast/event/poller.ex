defmodule Forgecast.Event.Poller do
    @moduledoc """
    Polls GitHub's public events endpoint for WatchEvent (star) and
    ForkEvent activity. Uses conditional requests (ETags) so that
    unchanged polls cost zero rate limit tokens.

    Parsed events are bulk-inserted into the events table. Repos
    not yet in the repos table get a skeleton row with enriched_at
    set to nil, queuing them for later enrichment.

    Maintains a bounded set of recently-seen event IDs to avoid
    re-inserting duplicates across overlapping polls.
    """

    use GenServer
    require Logger

    alias Forgecast.Platform.Header
    alias Forgecast.Repo
    alias Forgecast.Schema.{Event, Repository}

    import Ecto.Query

    @poll_interval :timer.seconds(5)
    @events_url "https://api.github.com/events"
    @per_page 100
    @event_types MapSet.new(["WatchEvent", "ForkEvent"])
    @seen_max 5_000

    @type t :: %__MODULE__{
        etag: String.t() | nil,
        poll_interval: non_neg_integer(),
        total_events: non_neg_integer(),
        total_repos_created: non_neg_integer(),
        last_poll_at: NaiveDateTime.t() | nil,
        seen_ids: MapSet.t()
    }

    defstruct [
        etag: nil,
        poll_interval: @poll_interval,
        total_events: 0,
        total_repos_created: 0,
        last_poll_at: nil,
        seen_ids: MapSet.new()
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
        schedule(@poll_interval)
        {:ok, %__MODULE__{}}
    end

    @impl true
    def handle_info(:poll, state) do
        state = do_poll(state)
        schedule(state.poll_interval)
        {:noreply, state}
    end

    @impl true
    def handle_call(:status, _from, state) do
        info = %{
            etag: state.etag,
            poll_interval: state.poll_interval,
            total_events: state.total_events,
            total_repos_created: state.total_repos_created,
            last_poll_at: state.last_poll_at,
            seen_ids_size: MapSet.size(state.seen_ids)
        }

        {:reply, info, state}
    end

    defp schedule(interval) do
        Process.send_after(self(), :poll, interval)
    end

    defp do_poll(state) do
        headers = build_headers(state.etag)

        case Req.get(@events_url, headers: headers, params: [per_page: @per_page]) do
            {:ok, %Req.Response{status: 200, headers: resp_headers, body: body}} ->
                new_etag = get_header(resp_headers, "etag")
                interval = parse_poll_interval(resp_headers)
                {event_count, repo_count, new_seen} = process_events(body, state.seen_ids)

                Logger.info("[Event.Poller] Processed #{event_count} events, created #{repo_count} skeleton repos")

                %{state |
                    etag: new_etag,
                    poll_interval: interval,
                    total_events: state.total_events + event_count,
                    total_repos_created: state.total_repos_created + repo_count,
                    last_poll_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
                    seen_ids: trim_seen(new_seen)
                }

            {:ok, %Req.Response{status: 304}} ->
                Logger.debug("[Event.Poller] 304 Not Modified (free)")
                %{state | last_poll_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)}

            {:ok, %Req.Response{status: status}} ->
                Logger.warning("[Event.Poller] Unexpected status #{status}")
                %{state | poll_interval: :timer.seconds(30)}

            {:error, reason} ->
                Logger.warning("[Event.Poller] Request failed: #{inspect(reason)}")
                %{state | poll_interval: :timer.seconds(30)}
        end
    end

    defp build_headers(nil), do: Header.github_headers()

    defp build_headers(etag) do
        [{"if-none-match", etag} | Header.github_headers()]
    end

    defp process_events(body, seen_ids) when is_list(body) do
        {relevant, new_seen} =
            body
            |> Enum.filter(fn event -> MapSet.member?(@event_types, event["type"]) end)
            |> Enum.reduce({[], seen_ids}, fn event, {acc, seen} ->
                event_id = event["id"]

                if event_id && MapSet.member?(seen, event_id) do
                    {acc, seen}
                else
                    case parse_event(event) do
                        nil ->
                            {acc, seen}

                        parsed ->
                            new_seen = if event_id, do: MapSet.put(seen, event_id), else: seen
                            {[parsed | acc], new_seen}
                    end
                end
            end)

        relevant = Enum.reverse(relevant)
        insert_events(relevant)
        repo_count = ensure_skeleton_repos(relevant)

        {length(relevant), repo_count, new_seen}
    end

    defp process_events(_, seen_ids), do: {0, 0, seen_ids}

    defp trim_seen(seen) do
        if MapSet.size(seen) > @seen_max do
            seen
            |> MapSet.to_list()
            |> Enum.take(-@seen_max)
            |> MapSet.new()
        else
            seen
        end
    end

    defp parse_event(%{"type" => type, "repo" => repo, "created_at" => created_at}) do
        mapped_type =
            case type do
                "WatchEvent" -> "star"
                "ForkEvent" -> "fork"
                _ -> nil
            end

        with event_type when not is_nil(event_type) <- mapped_type,
             {:ok, occurred_at, _} <- DateTime.from_iso8601(created_at) do
            repo_name = repo["name"] || ""
            owner = repo_name |> String.split("/") |> List.first() || ""

            %{
                platform: "github",
                platform_repo_id: to_string(repo["id"]),
                repo_name: repo_name,
                owner: owner,
                event_type: event_type,
                occurred_at: DateTime.to_naive(occurred_at)
            }
        else
            _ -> nil
        end
    end

    defp parse_event(_), do: nil

    defp insert_events([]), do: :ok

    defp insert_events(events) do
        entries =
            Enum.map(events, fn e ->
                %{
                    platform: e.platform,
                    platform_repo_id: e.platform_repo_id,
                    repo_name: e.repo_name,
                    event_type: e.event_type,
                    occurred_at: e.occurred_at
                }
            end)

        Repo.insert_all(Event, entries)
    end

    defp ensure_skeleton_repos([]), do: 0

    defp ensure_skeleton_repos(events) do
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        unique_events = Enum.uniq_by(events, & &1.platform_repo_id)
        platform_ids = Enum.map(unique_events, & &1.platform_repo_id)

        existing =
            from(r in Repository,
                where: r.platform == "github" and r.platform_id in ^platform_ids,
                select: r.platform_id
            )
            |> Repo.all()
            |> MapSet.new()

        entries =
            unique_events
            |> Enum.reject(fn e -> MapSet.member?(existing, e.platform_repo_id) end)
            |> Enum.map(fn e ->
                %{
                    platform: e.platform,
                    platform_id: e.platform_repo_id,
                    name: e.repo_name,
                    owner: e.owner,
                    url: "https://github.com/#{e.repo_name}",
                    topics: [],
                    stars: 0,
                    forks: 0,
                    open_issues: 0,
                    inserted_at: now,
                    updated_at: now
                }
            end)

        case entries do
            [] ->
                0

            _ ->
                {count, _} =
                    Repo.insert_all(Repository, entries,
                        on_conflict: :nothing,
                        conflict_target: [:platform, :platform_id]
                    )

                count
        end
    end

    defp parse_poll_interval(headers) do
        case get_header(headers, "x-poll-interval") do
            nil -> @poll_interval
            val ->
                case Integer.parse(val) do
                    {seconds, _} -> :timer.seconds(max(seconds, 1))
                    :error -> @poll_interval
                end
        end
    end

    defp get_header(headers, key) do
        case Map.get(headers, key) do
            [value | _] -> value
            _ -> nil
        end
    end
end
