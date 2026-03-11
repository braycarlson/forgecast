defmodule Forgecast.Image.Worker do
    @moduledoc """
    Background worker that periodically downloads and caches OG images
    for repos that need them. Rate-limits outbound requests to avoid
    triggering GitHub's 429 responses, and backs off exponentially
    when rate limited.

    Filters out repos whose images already exist on disk before
    downloading, handling crash recovery gracefully. Dormant repos
    (zero star velocity) with existing cached images are skipped
    entirely to avoid unnecessary downloads.
    """

    use GenServer
    require Logger

    alias Forgecast.Image.Cache

    @check_interval :timer.minutes(5)
    @download_delay :timer.seconds(1)
    @batch_size 25
    @max_backoff :timer.minutes(30)

    @type t :: %__MODULE__{
        total_cached: non_neg_integer(),
        total_not_modified: non_neg_integer(),
        total_skipped: non_neg_integer(),
        total_failed: non_neg_integer(),
        total_rate_limited: non_neg_integer(),
        error_streak: non_neg_integer(),
        last_run_at: NaiveDateTime.t() | nil
    }

    defstruct [
        total_cached: 0,
        total_not_modified: 0,
        total_skipped: 0,
        total_failed: 0,
        total_rate_limited: 0,
        error_streak: 0,
        last_run_at: nil
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
        Cache.ensure_storage_dir()
        Cache.init_etag_cache()
        schedule(:timer.seconds(30))
        {:ok, %__MODULE__{}}
    end

    @impl true
    def handle_info(:run, state) do
        state = process_batch(state)
        {:noreply, state}
    end

    @impl true
    def handle_call(:status, _from, state) do
        {:reply, Map.from_struct(state), state}
    end

    defp process_batch(state) do
        repos = Cache.repos_needing_cache(@batch_size)

        # Filter out repos that already have the file on disk (crash recovery)
        repos =
            Enum.reject(repos, fn repo ->
                path = Cache.image_path(repo.owner, repo.name)

                if File.exists?(path) do
                    Cache.mark_cached(repo.id)
                    true
                else
                    false
                end
            end)

        if repos == [] do
            schedule(@check_interval)
            state
        else
            Logger.info("[Image.Worker] Processing #{length(repos)} images")

            {cached, not_modified, skipped, failed, rate_limited, streak} =
                Enum.reduce_while(repos, {0, 0, 0, 0, 0, state.error_streak}, fn repo, {c, nm, sk, f, rl, streak} ->
                    case Cache.download_and_cache(repo) do
                        :ok ->
                            Process.sleep(@download_delay)
                            {:cont, {c + 1, nm, sk, f, rl, 0}}

                        :not_modified ->
                            Process.sleep(div(@download_delay, 2))
                            {:cont, {c, nm + 1, sk, f, rl, 0}}

                        :skipped ->
                            {:cont, {c, nm, sk + 1, f, rl, 0}}

                        {:error, {:http_status, 429}} ->
                            new_streak = streak + 1
                            Logger.warning("[Image.Worker] Rate limited (streak: #{new_streak}), stopping batch")
                            {:halt, {c, nm, sk, f, rl + 1, new_streak}}

                        {:error, _} ->
                            Process.sleep(@download_delay)
                            {:cont, {c, nm, sk, f + 1, rl, streak}}
                    end
                end)

            Logger.info("[Image.Worker] Batch complete: #{cached} cached, #{not_modified} unchanged, #{skipped} skipped, #{failed} failed, #{rate_limited} rate limited")

            delay =
                if rate_limited > 0 do
                    backoff = exponential_backoff(streak)
                    Logger.info("[Image.Worker] Backing off for #{div(backoff, 1000)}s")
                    backoff
                else
                    @check_interval
                end

            schedule(delay)

            %{state |
                total_cached: state.total_cached + cached,
                total_not_modified: state.total_not_modified + not_modified,
                total_skipped: state.total_skipped + skipped,
                total_failed: state.total_failed + failed,
                total_rate_limited: state.total_rate_limited + rate_limited,
                error_streak: streak,
                last_run_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
            }
        end
    end

    defp exponential_backoff(streak) do
        capped = min(streak, 5)
        delay = :timer.minutes(1) * Integer.pow(2, capped)
        min(delay, @max_backoff)
    end

    defp schedule(interval) do
        Process.send_after(self(), :run, interval)
    end
end
