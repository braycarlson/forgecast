defmodule Forgecast.Auth.SessionPruner do
    @moduledoc """
    Periodically deletes expired sessions to keep the sessions
    table bounded.
    """

    use GenServer
    require Logger

    @prune_interval :timer.hours(6)

    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(_opts) do
        schedule(@prune_interval)
        {:ok, %{}}
    end

    @impl true
    def handle_info(:prune, state) do
        count = Forgecast.Auth.cleanup_expired_sessions()

        if count > 0 do
            Logger.info("[Auth.SessionPruner] Deleted #{count} expired sessions")
        end

        schedule(@prune_interval)
        {:noreply, state}
    end

    defp schedule(interval) do
        Process.send_after(self(), :prune, interval)
    end
end
