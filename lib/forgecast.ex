defmodule Forgecast do
    @moduledoc """
    Forgecast tracks trending repositories across GitHub, GitLab, and Codeberg.

    Uses GitHub's public event stream for real-time star/fork velocity,
    with search-based polling as a backfill for other platforms. Computes
    trending scores from event counts and snapshot deltas within a
    configurable time window.
    """

    @spec score(keyword()) :: map()
    defdelegate score(opts), to: Forgecast.Trending

    @spec available_filters() :: map()
    defdelegate available_filters(), to: Forgecast.Trending

    @spec list_repos(keyword()) :: [map()]
    defdelegate list_repos(opts), to: Forgecast.Trending

    @spec snapshots_for(integer() | binary()) :: [map()]
    defdelegate snapshots_for(repo_id), to: Forgecast.Trending

    @spec status() :: map()
    defdelegate status(), to: Forgecast.Trending

    @spec poller_status() :: [map()]
    defdelegate poller_status(), to: Forgecast.Poller.Worker, as: :all_statuses

    @spec event_poller_status() :: map()
    defdelegate event_poller_status(), to: Forgecast.Event.Poller, as: :status

    @spec enricher_status() :: map()
    defdelegate enricher_status(), to: Forgecast.Event.Enricher, as: :status

    @spec preferences(integer()) :: %{String.t() => term()}
    defdelegate preferences(user_id), to: Forgecast.Preferences, as: :all
end
