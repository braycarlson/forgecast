defmodule Forgecast.Schema.Mirror do
    @moduledoc """
    Custom Ecto type that stores a list of maps as a JSONB column.
    Ecto's built-in `{:array, :map}` maps to Postgres `jsonb[]`,
    not a single JSONB column containing a JSON array.
    """

    use Ecto.Type

    @impl true
    def type, do: :jsonb

    @impl true
    def cast(data) when is_list(data), do: {:ok, data}
    def cast(_), do: :error

    @impl true
    def load(data) when is_list(data), do: {:ok, data}
    def load(data) when is_binary(data) do
        case Jason.decode(data) do
            {:ok, list} when is_list(list) -> {:ok, list}
            _ -> :error
        end
    end
    def load(nil), do: {:ok, []}
    def load(_), do: :error

    @impl true
    def dump(data) when is_list(data), do: {:ok, data}
    def dump(_), do: :error
end
