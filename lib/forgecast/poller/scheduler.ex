defmodule Forgecast.Poller.Scheduler do
    @moduledoc """
    Decides whether the next poll cycle should discover new repos
    or monitor existing ones, and selects the appropriate target.

    The discovery-to-monitoring ratio shifts dynamically based on
    how many repos the platform already tracks. Early on, almost
    all budget goes to discovery. Once a baseline is established,
    the balance shifts toward keeping existing data fresh. At
    maturity (1000+ repos), discovery drops to 15% of budget.

    Accepts a cached repo count to avoid querying the database on
    every poll tick.
    """

    alias Forgecast.Repo
    alias Forgecast.Schema.Repository
    alias Forgecast.Velocity

    import Ecto.Query

    @initial_threshold 100
    @mature_threshold 1000
    @initial_discovery_ratio 0.9
    @normal_discovery_ratio 0.3
    @mature_discovery_ratio 0.15

    @type task ::
        {:discover, String.t(), Forgecast.Poller.Strategy.t()}
        | {:monitor, Repository.t()}

    @spec next_task(String.t(), [String.t()], non_neg_integer(), non_neg_integer(), non_neg_integer()) :: task()
    def next_task(platform, languages, language_index, strategy_index, repo_count) do
        ratio =
            cond do
                repo_count < @initial_threshold -> @initial_discovery_ratio
                repo_count < @mature_threshold -> @normal_discovery_ratio
                true -> @mature_discovery_ratio
            end

        if :rand.uniform() < ratio do
            pick_discovery(languages, language_index, strategy_index)
        else
            case pick_monitor(platform) do
                nil -> pick_discovery(languages, language_index, strategy_index)
                task -> task
            end
        end
    end

    @spec count_platform_repos(String.t()) :: non_neg_integer()
    def count_platform_repos(platform) do
        Repo.aggregate(
            from(r in Repository, where: r.platform == ^platform),
            :count
        )
    end

    @spec compute_check_interval(Repository.t()) :: non_neg_integer()
    def compute_check_interval(repo) do
        velocity = Velocity.star_velocity(repo.id)

        cond do
            velocity > 10.0 -> 1_800
            velocity > 1.0 -> 7_200
            velocity > 0.1 -> 21_600
            true -> 86_400
        end
    end

    @spec update_next_check(Repository.t(), non_neg_integer()) ::
        {:ok, Repository.t()} | {:error, Ecto.Changeset.t()}
    def update_next_check(repo, interval_seconds) do
        next_at =
            NaiveDateTime.utc_now()
            |> NaiveDateTime.add(interval_seconds)
            |> NaiveDateTime.truncate(:second)

        repo
        |> Ecto.Changeset.change(%{next_check_at: next_at})
        |> Repo.update()
    end

    defp pick_discovery(languages, language_index, strategy_index) do
        language = Enum.at(languages, rem(language_index, length(languages)))
        strategy = Forgecast.Poller.Strategy.at(strategy_index)
        {:discover, language, strategy}
    end

    defp pick_monitor(platform) do
        now = NaiveDateTime.utc_now()

        case Repo.one(
            from r in Repository,
                where: r.platform == ^platform,
                where: not is_nil(r.next_check_at),
                where: r.next_check_at <= ^now,
                order_by: [asc: r.next_check_at],
                limit: 1
        ) do
            nil -> nil
            repo -> {:monitor, repo}
        end
    end
end
