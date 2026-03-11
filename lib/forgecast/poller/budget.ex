defmodule Forgecast.Poller.Budget do
    @moduledoc """
    Hard per-platform hourly request cap. Acts as a circuit breaker
    to prevent runaway polling regardless of adaptive pacer behavior.

    Tracks requests in a rolling one-hour window and rejects calls
    once the platform's budget is exhausted.
    """

    use GenServer

    @window_seconds 3600
    @default_limit 100

    @type t :: %__MODULE__{
        counts: %{optional(String.t()) => non_neg_integer()},
        window_start: integer(),
        limits: %{optional(String.t()) => non_neg_integer()}
    }

    defstruct counts: %{}, window_start: 0, limits: %{}

    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts \\ []) do
        name = Keyword.get(opts, :name, __MODULE__)
        GenServer.start_link(__MODULE__, opts, name: name)
    end

    @spec request(String.t()) :: :ok | {:exhausted, non_neg_integer()}
    def request(platform) do
        GenServer.call(__MODULE__, {:request, platform})
    end

    @spec status() :: map()
    def status do
        GenServer.call(__MODULE__, :status)
    end

    @impl true
    def init(opts) do
        limits = Keyword.get(opts, :limits, %{})

        state = %__MODULE__{
            counts: %{},
            window_start: System.os_time(:second),
            limits: limits
        }

        {:ok, state}
    end

    @impl true
    def handle_call({:request, platform}, _from, state) do
        state = maybe_reset_window(state)
        limit = Map.get(state.limits, platform, @default_limit)
        count = Map.get(state.counts, platform, 0)

        if count < limit do
            counts = Map.put(state.counts, platform, count + 1)
            {:reply, :ok, %{state | counts: counts}}
        else
            seconds_left = @window_seconds - (System.os_time(:second) - state.window_start)
            {:reply, {:exhausted, max(seconds_left, 1)}, state}
        end
    end

    def handle_call(:status, _from, state) do
        state = maybe_reset_window(state)

        info =
            state.limits
            |> Enum.map(fn {platform, limit} ->
                count = Map.get(state.counts, platform, 0)

                {platform, %{
                    used: count,
                    limit: limit,
                    remaining: limit - count
                }}
            end)
            |> Map.new()

        {:reply, info, state}
    end

    defp maybe_reset_window(state) do
        now = System.os_time(:second)
        elapsed = now - state.window_start

        if elapsed >= @window_seconds do
            %{state | counts: %{}, window_start: now}
        else
            state
        end
    end
end
