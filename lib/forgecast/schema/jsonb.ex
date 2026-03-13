defmodule Forgecast.Schema.Jsonb do
    @moduledoc """
    Custom Ecto type that stores any JSON-encodable value in a JSONB
    column. Unlike Ecto's built-in `:map` type, this accepts lists,
    scalars, and maps — matching the flexibility of JSONB itself.
    """

    use Ecto.Type

    @impl true
    def type, do: :jsonb

    @impl true
    def cast(data), do: {:ok, data}

    @impl true
    def load(data), do: {:ok, data}

    @impl true
    def dump(data)
        when is_map(data)
        or is_list(data)
        or is_binary(data)
        or is_number(data)
        or is_boolean(data)
        or is_nil(data),
        do: {:ok, data}

    def dump(_), do: :error
end
