defmodule Forgecast.Poller.Registry do
    @moduledoc """
    Process registry for per-platform polling workers.
    """

    def child_spec(_opts) do
        Registry.child_spec(keys: :unique, name: __MODULE__)
    end
end
