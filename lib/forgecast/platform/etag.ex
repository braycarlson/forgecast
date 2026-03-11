defmodule Forgecast.Platform.ETag do
    @moduledoc """
    Shared ETag cache backed by ETS. Provides conditional request
    header generation and ETag storage for any platform or subsystem
    that uses conditional HTTP requests.
    """

    @spec init(atom()) :: :ok
    def init(table) do
        if :ets.whereis(table) == :undefined do
            :ets.new(table, [:set, :public, :named_table])
        end

        :ok
    end

    @spec conditional_headers(atom(), term(), [{String.t(), String.t()}]) ::
        [{String.t(), String.t()}]
    def conditional_headers(table, key, base_headers) do
        case :ets.whereis(table) do
            :undefined ->
                base_headers

            _ ->
                case :ets.lookup(table, key) do
                    [{_, etag}] ->
                        [{"if-none-match", etag} | base_headers]

                    [] ->
                        base_headers
                end
        end
    end

    @spec store_etag(atom(), term(), map()) :: :ok
    def store_etag(table, key, resp_headers) do
        if :ets.whereis(table) != :undefined do
            case Map.get(resp_headers, "etag") do
                [etag | _] -> :ets.insert(table, {key, etag})
                _ -> :ok
            end
        end

        :ok
    end
end
