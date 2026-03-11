defmodule Forgecast.Event.Pruner do
    @moduledoc """
    Periodically deletes events older than the maximum trending window
    to keep the events table bounded.
    """

    use GenServer
    require Logger

    alias Forgecast.Repo
    alias Forgecast.Schema.Event

    import Ecto.Query

    @prune_interval :timer.hours(1)
    @max_age_days 30

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
        cutoff =
            NaiveDateTime.utc_now()
            |> NaiveDateTime.add(-@max_age_days * 86_400)

        {count, _} =
            from(e in Event, where: e.occurred_at < ^cutoff)
            |> Repo.delete_all()

        if count > 0 do
            Logger.info("[Event.Pruner] Deleted #{count} events older than #{@max_age_days} days")
        end

        schedule(@prune_interval)
        {:noreply, state}
    end

    defp schedule(interval) do
        Process.send_after(self(), :prune, interval)
    end
end
