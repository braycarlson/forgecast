defmodule Forgecast.Poller.Worker do
    @moduledoc """
    Per-platform polling worker that alternates between discovery
    and monitoring cycles based on the scheduler's allocation.

    Discovery cycles rotate through language/strategy combinations
    to surface new repos. Monitoring cycles re-fetch individual repos
    whose `next_check_at` has elapsed, updating snapshots and
    rescheduling based on observed velocity.

    Strategy parameters (page limits, cooldowns, star thresholds)
    are read from the active strategy struct, which is driven by
    the configured profile (see `Forgecast.Poller.Strategy`).

    Adaptive pacing consumes a fraction of the platform's rate budget
    derived from the rate-limit headers. Exponential backoff kicks in
    on errors, and a hard budget cap prevents runaway requests.

    Caches the platform repo count and refreshes it every
    @repo_count_refresh_cycles poll cycles to avoid hitting the
    database on every tick.

    Tracks pagination state per language/strategy pair so that
    successive discovery cycles page through results instead of
    re-fetching page 1 repeatedly.

    Enforces a cooldown per language/strategy pair after a full
    page cycle completes, so stable result sets (e.g. top_starred
    on Codeberg) aren't re-fetched until the cooldown expires.
    """

    use GenServer
    require Logger

    alias Forgecast.Poller.{Budget, Scheduler, Strategy}

    @default_interval :timer.seconds(10)
    @max_backoff :timer.minutes(5)
    @budget_fraction 0.8
    @repo_count_refresh_cycles 20
    @max_page_hashes 500

    @type t :: %__MODULE__{
        module: module(),
        platform: String.t(),
        languages: [String.t()],
        task_ref: reference() | nil,
        language_index: non_neg_integer(),
        strategy_index: non_neg_integer(),
        total_ingested: non_neg_integer(),
        total_discovered: non_neg_integer(),
        total_monitored: non_neg_integer(),
        total_skipped: non_neg_integer(),
        total_not_modified: non_neg_integer(),
        error_streak: non_neg_integer(),
        rate_limit: %{remaining: integer() | nil, reset_at: integer() | nil},
        repo_count: non_neg_integer(),
        cycles_since_count: non_neg_integer(),
        page_state: %{optional({String.t(), atom()}) => non_neg_integer()},
        cooldowns: %{optional({String.t(), atom()}) => integer()},
        page_hashes: %{optional({String.t(), atom(), non_neg_integer()}) => binary()}
    }

    defstruct [
        :module,
        :platform,
        :languages,
        :task_ref,
        language_index: 0,
        strategy_index: 0,
        total_ingested: 0,
        total_discovered: 0,
        total_monitored: 0,
        total_skipped: 0,
        total_not_modified: 0,
        error_streak: 0,
        rate_limit: %{remaining: nil, reset_at: nil},
        repo_count: 0,
        cycles_since_count: 0,
        page_state: %{},
        cooldowns: %{},
        page_hashes: %{}
    ]

    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) do
        platform = Keyword.fetch!(opts, :platform)
        GenServer.start_link(__MODULE__, opts, name: via(platform))
    end

    @spec status(String.t()) :: map()
    def status(platform) do
        GenServer.call(via(platform), :status)
    end

    @spec all_statuses() :: [map()]
    def all_statuses do
        config = Application.get_env(:forgecast, :poller, [])
        platforms = Keyword.get(config, :platforms, [])

        Enum.map(platforms, fn {_module, name} ->
            status(name)
        end)
    end

    defp via(platform) do
        {:via, Registry, {Forgecast.Poller.Registry, platform}}
    end

    @impl true
    def init(opts) do
        state = %__MODULE__{
            module: Keyword.fetch!(opts, :module),
            platform: Keyword.fetch!(opts, :platform),
            languages: Keyword.fetch!(opts, :languages)
        }

        schedule(:timer.seconds(1))
        {:ok, state}
    end

    @impl true
    def handle_info(:poll, %{task_ref: ref} = state) when is_reference(ref) do
        {:noreply, state}
    end

    def handle_info(:poll, state) do
        state = maybe_refresh_repo_count(state)

        case Budget.request(state.platform) do
            {:exhausted, seconds} ->
                Logger.warning("[Poller/#{state.platform}] Budget exhausted, waiting #{seconds}s")
                schedule(seconds * 1000)
                {:noreply, state}

            :ok ->
                dispatch(state)
        end
    end

    def handle_info({ref, {:discover, result, page_key, page, strategy}}, %{task_ref: ref} = state) do
        Process.demonitor(ref, [:flush])
        state = %{state | task_ref: nil}

        state =
            case result do
                {:ok, repos, rate_info} ->
                    handle_discovery_success(state, repos, rate_info, page_key, page, strategy)

                {:not_modified, rate_info} ->
                    handle_discovery_not_modified(state, rate_info, page_key, strategy)

                {:rate_limited, rate_info} ->
                    handle_rate_limit(state, rate_info)

                {:error, reason} ->
                    handle_error(state, reason)
            end

        {:noreply, state}
    end

    def handle_info({ref, {:monitor, result, repo}}, %{task_ref: ref} = state) do
        Process.demonitor(ref, [:flush])
        state = %{state | task_ref: nil}

        state =
            case result do
                {:ok, result_data, rate_info} ->
                    handle_monitor_success(state, result_data, rate_info, repo)

                {:not_modified, rate_info} ->
                    handle_monitor_not_modified(state, rate_info, repo)

                {:rate_limited, rate_info} ->
                    handle_rate_limit(state, rate_info)

                {:error, reason} ->
                    handle_monitor_error(state, reason, repo)
            end

        {:noreply, state}
    end

    def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
        Logger.warning("[Poller/#{state.platform}] Task crashed: #{inspect(reason)}")

        state =
            %{state | task_ref: nil}
            |> Map.update!(:error_streak, &(&1 + 1))
            |> schedule_backoff()

        {:noreply, state}
    end

    def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
        {:noreply, state}
    end

    @impl true
    def handle_call(:status, _from, state) do
        info = %{
            platform: state.platform,
            profile: Strategy.profile(),
            current_language: Enum.at(state.languages, state.language_index),
            current_strategy: Strategy.at(state.strategy_index).type,
            language_index: state.language_index,
            strategy_index: state.strategy_index,
            total_ingested: state.total_ingested,
            total_discovered: state.total_discovered,
            total_monitored: state.total_monitored,
            total_skipped: state.total_skipped,
            total_not_modified: state.total_not_modified,
            error_streak: state.error_streak,
            rate_limit: state.rate_limit,
            busy: state.task_ref != nil
        }

        {:reply, info, state}
    end

    defp maybe_refresh_repo_count(%{cycles_since_count: n} = state)
         when n >= @repo_count_refresh_cycles do
        count = Scheduler.count_platform_repos(state.platform)
        %{state | repo_count: count, cycles_since_count: 0}
    end

    defp maybe_refresh_repo_count(state) do
        %{state | cycles_since_count: state.cycles_since_count + 1}
    end

    defp dispatch(state) do
        task = Scheduler.next_task(
            state.platform,
            state.languages,
            state.language_index,
            state.strategy_index,
            state.repo_count
        )

        case task do
            {:discover, language, strategy} ->
                page_key = {language, strategy.type}

                if on_cooldown?(state, page_key) do
                    Logger.debug("[Poller/#{state.platform}] Skipping #{language}/#{strategy.type} (cooldown)")

                    state =
                        state
                        |> Map.update!(:total_skipped, &(&1 + 1))
                        |> advance_discovery()

                    schedule(@default_interval)
                    {:noreply, state}
                else
                    page = Map.get(state.page_state, page_key, 1)

                    Logger.info("[Poller/#{state.platform}] Discovering #{language} (#{strategy.type}) page #{page}")

                    ref =
                        Task.Supervisor.async_nolink(Forgecast.TaskSupervisor, fn ->
                            {:discover, state.module.search(language, strategy: strategy, page: page), page_key, page, strategy}
                        end)

                    {:noreply, %{state | task_ref: ref.ref}}
                end

            {:monitor, repo} ->
                Logger.info("[Poller/#{state.platform}] Monitoring #{repo.name}")

                ref =
                    Task.Supervisor.async_nolink(Forgecast.TaskSupervisor, fn ->
                        {:monitor, state.module.fetch(repo), repo}
                    end)

                {:noreply, %{state | task_ref: ref.ref}}
        end
    end

    defp on_cooldown?(state, page_key) do
        case Map.get(state.cooldowns, page_key) do
            nil -> false
            expires_at -> System.monotonic_time(:millisecond) < expires_at
        end
    end

    defp set_cooldown(state, page_key, cooldown_ms) do
        expires_at = System.monotonic_time(:millisecond) + cooldown_ms
        %{state | cooldowns: Map.put(state.cooldowns, page_key, expires_at)}
    end

    defp hash_results(repos) do
        repos
        |> Enum.map(fn r -> r.platform_id end)
        |> Enum.sort()
        |> :erlang.term_to_binary()
        |> then(&:crypto.hash(:sha256, &1))
    end

    defp trim_page_hashes(hashes) when map_size(hashes) > @max_page_hashes do
        hashes
        |> Enum.take(@max_page_hashes)
        |> Map.new()
    end

    defp trim_page_hashes(hashes), do: hashes

    defp handle_discovery_success(state, repos, rate_info, page_key, page, strategy) do
        {language, strategy_type} = page_key
        hash_key = {language, strategy_type, page}
        current_hash = hash_results(repos)
        previous_hash = Map.get(state.page_hashes, hash_key)

        {count, state} =
            if previous_hash == current_hash do
                Logger.debug("[Poller/#{state.platform}] Unchanged results for #{language} (#{strategy_type}) page #{page}, skipping ingestion")
                {0, state}
            else
                results = Forgecast.Ingester.ingest(repos)
                ingested = Enum.count(results, &match?({:ok, _}, &1))
                updated_hashes =
                    state.page_hashes
                    |> Map.put(hash_key, current_hash)
                    |> trim_page_hashes()

                {ingested, %{state | page_hashes: updated_hashes}}
            end

        Logger.info("[Poller/#{state.platform}] Discovered #{count} repos for #{language} (#{strategy_type}) page #{page}")

        {new_page, state} =
            if length(repos) >= 25 and page < strategy.page_limit do
                {page + 1, state}
            else
                {1, set_cooldown(state, page_key, strategy.cooldown_ms)}
            end

        page_state = Map.put(state.page_state, page_key, new_page)

        state
        |> Map.merge(%{
            error_streak: 0,
            total_ingested: state.total_ingested + count,
            total_discovered: state.total_discovered + count,
            rate_limit: safe_rate_info(rate_info),
            page_state: page_state
        })
        |> advance_discovery()
        |> schedule_adaptive()
    end

    defp handle_discovery_not_modified(state, rate_info, page_key, strategy) do
        {language, strategy_type} = page_key
        Logger.debug("[Poller/#{state.platform}] Search not modified for #{language} (#{strategy_type}), starting cooldown")

        state
        |> set_cooldown(page_key, strategy.cooldown_ms)
        |> Map.merge(%{
            error_streak: 0,
            total_not_modified: state.total_not_modified + 1,
            rate_limit: safe_rate_info(rate_info)
        })
        |> advance_discovery()
        |> schedule_adaptive()
    end

    defp handle_monitor_success(state, result_data, rate_info, repo) do
        Forgecast.Ingester.ingest([result_data])
        interval = Scheduler.compute_check_interval(repo)
        Scheduler.update_next_check(repo, interval)
        Logger.info("[Poller/#{state.platform}] Monitored #{repo.name}, next in #{div(interval, 60)}m")

        state
        |> Map.merge(%{
            error_streak: 0,
            total_ingested: state.total_ingested + 1,
            total_monitored: state.total_monitored + 1,
            rate_limit: safe_rate_info(rate_info)
        })
        |> schedule_adaptive()
    end

    defp handle_monitor_not_modified(state, rate_info, repo) do
        current_interval = Scheduler.compute_check_interval(repo)
        extended = min(current_interval * 2, 86_400)
        Scheduler.update_next_check(repo, extended)
        Logger.debug("[Poller/#{state.platform}] Not modified #{repo.name}, next in #{div(extended, 60)}m")

        state
        |> Map.merge(%{
            error_streak: 0,
            total_monitored: state.total_monitored + 1,
            total_not_modified: state.total_not_modified + 1,
            rate_limit: safe_rate_info(rate_info)
        })
        |> schedule_adaptive()
    end

    defp handle_rate_limit(state, rate_info) do
        Logger.warning("[Poller/#{state.platform}] Rate limited")

        state
        |> Map.put(:rate_limit, safe_rate_info(rate_info))
        |> schedule_until_reset()
    end

    defp handle_error(state, reason) do
        Logger.warning("[Poller/#{state.platform}] Error: #{inspect(reason)}")

        state
        |> Map.update!(:error_streak, &(&1 + 1))
        |> schedule_backoff()
    end

    defp handle_monitor_error(state, reason, repo) do
        Logger.warning("[Poller/#{state.platform}] Monitor failed #{repo.name}: #{inspect(reason)}")
        Scheduler.update_next_check(repo, 3600)

        state
        |> Map.update!(:error_streak, &(&1 + 1))
        |> schedule_backoff()
    end

    defp advance_discovery(state) do
        new_lang = rem(state.language_index + 1, length(state.languages))

        new_strat =
            if new_lang == 0,
                do: rem(state.strategy_index + 1, Strategy.count()),
                else: state.strategy_index

        %{state | language_index: new_lang, strategy_index: new_strat}
    end

    defp safe_rate_info(nil), do: %{remaining: nil, reset_at: nil}

    defp safe_rate_info(info) do
        %{
            remaining: Map.get(info, :remaining),
            reset_at: Map.get(info, :reset_at)
        }
    end

    defp schedule_adaptive(state) do
        delay = adaptive_delay(state.rate_limit)
        schedule(delay)
        state
    end

    defp schedule_until_reset(state) do
        delay =
            case state.rate_limit do
                %{reset_at: reset_at} when is_integer(reset_at) ->
                    seconds = max(reset_at - System.os_time(:second), 1)
                    seconds * 1000

                _ ->
                    :timer.minutes(1)
            end

        Logger.info("[Poller/#{state.platform}] Sleeping #{div(delay, 1000)}s for reset")
        schedule(delay)
        state
    end

    defp schedule_backoff(state) do
        delay = exponential_backoff(state.error_streak)
        Logger.info("[Poller/#{state.platform}] Backoff #{div(delay, 1000)}s (streak: #{state.error_streak})")
        schedule(delay)
        state
    end

    defp adaptive_delay(%{remaining: remaining, reset_at: reset_at})
         when is_integer(remaining) and remaining > 0 and is_integer(reset_at) do
        seconds_left = max(reset_at - System.os_time(:second), 1)
        ideal = seconds_left / (remaining * @budget_fraction)
        trunc(ideal * 1000) |> max(500)
    end

    defp adaptive_delay(_), do: @default_interval

    defp exponential_backoff(streak) do
        capped = min(streak, 6)
        delay = @default_interval * Integer.pow(2, capped)
        min(delay, @max_backoff)
    end

    defp schedule(interval) do
        Process.send_after(self(), :poll, interval)
    end
end
