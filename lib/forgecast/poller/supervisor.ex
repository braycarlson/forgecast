defmodule Forgecast.Poller.Supervisor do
    @moduledoc """
    Supervises the budget limiter and per-platform polling workers.
    """

    use Supervisor

    @spec start_link(keyword()) :: Supervisor.on_start()
    def start_link(opts \\ []) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(_opts) do
        config = Application.get_env(:forgecast, :poller, [])
        platforms = Keyword.get(config, :platforms, [])
        languages = Keyword.get(config, :languages, [])
        budgets = Keyword.get(config, :budget, %{})

        workers =
            Enum.map(platforms, fn {module, name} ->
                Supervisor.child_spec(
                    {Forgecast.Poller.Worker,
                        module: module,
                        platform: name,
                        languages: languages},
                    id: {Forgecast.Poller.Worker, name}
                )
            end)

        children = [{Forgecast.Poller.Budget, limits: budgets} | workers]

        Supervisor.init(children, strategy: :one_for_one)
    end
end
